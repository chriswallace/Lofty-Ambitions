#include "CDesktop.h"
#include <SDL3/SDL.h>
#include <math.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#define STBI_ONLY_PNG
#define STB_IMAGE_IMPLEMENTATION
#include "../../Vendor/stb/stb_image.h"
#define STB_TRUETYPE_IMPLEMENTATION
#include "../../Vendor/stb/stb_truetype.h"
#define STBI_WRITE_NO_STDIO
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../../Vendor/stb/stb_image_write.h"

#define IMAGE_COUNT 96
#define TEXT_COUNT 256
#define IMAGE_BUDGET (256u * 1024u * 1024u)
#define TEXT_BUDGET (32u * 1024u * 1024u)
typedef struct { char *key; SDL_Texture *texture; int w,h,px,bold; unsigned color; Uint64 used; size_t bytes; } Cache;
typedef struct FileResult { char *path; struct FileResult *next; } FileResult;
/* The queue owns one reference; each outstanding dialog owns another. A dialog
 * can outlive the window without calling into freed desktop/session storage. */
typedef struct { SDL_Mutex *mutex; int references; bool alive; FileResult *head,*tail; } DialogQueue;
typedef struct { DialogQueue *queue; char *default_path; } DialogRequest;
struct LTDesktop {
    SDL_Window *window; SDL_Renderer *renderer;
    Cache images[IMAGE_COUNT],texts[TEXT_COUNT];
    Uint64 frame; float density; char *event_text;
    unsigned char *font_data[2]; stbtt_fontinfo font[2];
    DialogQueue *dialogs;
};
static float coord(float x) { return isfinite(x) ? fmaxf(-1000000,fminf(x,1000000)) : 0; }
static float extent(float x) { return isfinite(x) ? fmaxf(0,fminf(x,1000000)) : 0; }
static void color(SDL_Renderer *r,unsigned c) { SDL_SetRenderDrawColor(r,c>>24,(c>>16)&255,(c>>8)&255,c&255); }
static void free_cache(Cache *c) { SDL_DestroyTexture(c->texture); SDL_free(c->key); memset(c,0,sizeof(*c)); }
static Cache *slot(Cache *cache,int count,size_t budget,size_t needed) {
    size_t used=0; for(int i=0;i<count;i++) used+=cache[i].bytes;
    while(used+needed>budget) {
        Cache *old=NULL; for(int i=0;i<count;i++) if(cache[i].key&&(!old||cache[i].used<old->used)) old=&cache[i];
        if(!old) break; used-=old->bytes; free_cache(old);
    }
    Cache *old=&cache[0];
    for(int i=0;i<count;i++) { if(!cache[i].key) return &cache[i]; if(cache[i].used<old->used) old=&cache[i]; }
    free_cache(old); return old;
}
static SDL_Texture *texture(LTDesktop *d,unsigned char *pixels,int w,int h,bool smooth) {
    SDL_Surface *s=SDL_CreateSurfaceFrom(w,h,SDL_PIXELFORMAT_RGBA32,pixels,w*4);
    if(!s) return NULL;
    SDL_Texture *t=SDL_CreateTextureFromSurface(d->renderer,s); SDL_DestroySurface(s);
    if(t) { SDL_SetTextureBlendMode(t,SDL_BLENDMODE_BLEND); SDL_SetTextureScaleMode(t,smooth?SDL_SCALEMODE_LINEAR:SDL_SCALEMODE_NEAREST); }
    return t;
}
static bool load_font(LTDesktop *d,int bold) {
    const char *override=SDL_getenv(bold?"LOFTY_FONT_BOLD":"LOFTY_FONT");
    const char *paths[5]={override,NULL,NULL,NULL,NULL};
#ifdef _WIN32
    char windows_font[1024],windows_fallback[1024];
    const char *windows=SDL_getenv("WINDIR"); if(!windows) windows="C:\\Windows";
    SDL_snprintf(windows_font,sizeof(windows_font),"%s\\Fonts\\%s",windows,bold?"segoeuib.ttf":"segoeui.ttf");
    SDL_snprintf(windows_fallback,sizeof(windows_fallback),"%s\\Fonts\\%s",windows,bold?"arialbd.ttf":"arial.ttf");
    paths[1]=windows_font; paths[2]=windows_fallback;
#elif defined(__APPLE__)
    paths[1]=bold?"/System/Library/Fonts/Supplemental/Arial Bold.ttf":"/System/Library/Fonts/Supplemental/Arial.ttf";
    paths[2]=bold?"/Library/Fonts/Arial Bold.ttf":"/Library/Fonts/Arial.ttf";
#else
    paths[1]=bold?"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf":"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
#endif
    for(int i=0;i<5;i++) if(paths[i]) {
        size_t n=0; unsigned char *data=SDL_LoadFile(paths[i],&n);
        if(!data) continue;
        if(n>=12&&stbtt_InitFont(&d->font[bold],data,0)) { d->font_data[bold]=data; return true; }
        SDL_free(data);
    }
    return SDL_SetError("No system TrueType font found. Set LOFTY_FONT and LOFTY_FONT_BOLD to installed TTF paths.");
}
static void queue_free(DialogQueue *q) {
    FileResult *p=q->head; while(p) { FileResult *next=p->next; SDL_free(p->path); SDL_free(p); p=next; }
    SDL_DestroyMutex(q->mutex); SDL_free(q);
}
static void SDLCALL dialog_done(void *userdata,const char *const *files,int filter) {
    (void)filter; DialogRequest *request=userdata; DialogQueue *q=request->queue;
    FileResult *result=SDL_calloc(1,sizeof(*result));
    if(result) result->path=SDL_strdup(files&&files[0]?files[0]:"");
    SDL_LockMutex(q->mutex);
    if(result&&result->path&&q->alive) {
        if(q->tail) q->tail->next=result; else q->head=result; q->tail=result; result=NULL;
    }
    bool release=--q->references==0;
    SDL_UnlockMutex(q->mutex);
    if(result) { SDL_free(result->path); SDL_free(result); }
    SDL_free(request->default_path); SDL_free(request);
    if(release) queue_free(q);
}
LTDesktop *lt_create(const char *title,int width,int height) {
    if(width<1||height<1) { SDL_SetError("Window dimensions must be positive"); return NULL; }
    if(!SDL_InitSubSystem(SDL_INIT_VIDEO)) return NULL;
    LTDesktop *d=SDL_calloc(1,sizeof(*d));
    if(!d) { SDL_QuitSubSystem(SDL_INIT_VIDEO); return NULL; }
    d->density=1;
    d->window=SDL_CreateWindow(title?title:"Lofty Ambitions",width,height,SDL_WINDOW_RESIZABLE|SDL_WINDOW_HIGH_PIXEL_DENSITY);
    if(d->window) { SDL_SetWindowMinimumSize(d->window,1080,650); d->renderer=SDL_CreateRenderer(d->window,NULL); }
    if(!d->renderer) goto fail;
    SDL_SetRenderVSync(d->renderer,1); SDL_SetRenderDrawBlendMode(d->renderer,SDL_BLENDMODE_BLEND);
    d->dialogs=SDL_calloc(1,sizeof(*d->dialogs));
    if(!d->dialogs) goto fail;
    d->dialogs->mutex=SDL_CreateMutex();
    if(!d->dialogs->mutex) goto fail;
    d->dialogs->references=1; d->dialogs->alive=true;
    if(!load_font(d,0)||!load_font(d,1)) goto fail;
    if(!SDL_StartTextInput(d->window)) goto fail;
    SDL_ClearError(); return d;
fail: {
    char error[1024]; SDL_strlcpy(error,SDL_GetError(),sizeof(error));
    lt_destroy(d); SDL_SetError("Desktop initialization failed: %s",error[0]?error:"out of memory"); return NULL;
}}
void lt_destroy(LTDesktop *d) {
    if(!d) return;
    if(d->dialogs) {
        DialogQueue *q=d->dialogs; bool release=true;
        if(q->mutex) { SDL_LockMutex(q->mutex); q->alive=false; release=--q->references==0; SDL_UnlockMutex(q->mutex); }
        if(release) queue_free(q);
    }
    for(int i=0;i<IMAGE_COUNT;i++) free_cache(&d->images[i]);
    for(int i=0;i<TEXT_COUNT;i++) free_cache(&d->texts[i]);
    SDL_free(d->font_data[0]); SDL_free(d->font_data[1]); SDL_free(d->event_text);
    SDL_DestroyRenderer(d->renderer); SDL_DestroyWindow(d->window); SDL_free(d); SDL_QuitSubSystem(SDL_INIT_VIDEO);
}
static int mods(SDL_Keymod m) { return ((m&SDL_KMOD_SHIFT)?1:0)|((m&SDL_KMOD_CTRL)?2:0)|((m&SDL_KMOD_ALT)?4:0)|((m&SDL_KMOD_GUI)?8:0); }
static int key(SDL_Keycode k) {
    if(k>=65&&k<=90) return (int)k+32;
    if(k<128) return (int)k;
    switch(k) { case SDLK_UP:return 1001; case SDLK_DOWN:return 1002; case SDLK_LEFT:return 1003; case SDLK_RIGHT:return 1004; default:return 0; }
}
bool lt_poll(LTDesktop *d,LTEvent *out) {
    if(!d||!out) return false;
    SDL_free(d->event_text); d->event_text=NULL; memset(out,0,sizeof(*out));
    DialogQueue *q=d->dialogs; SDL_LockMutex(q->mutex);
    FileResult *result=q->head; if(result) { q->head=result->next; if(!q->head) q->tail=NULL; }
    SDL_UnlockMutex(q->mutex);
    if(result) { d->event_text=result->path; SDL_free(result); out->type=9; out->text=d->event_text; return true; }
    SDL_Event e;
    while(SDL_PollEvent(&e)) {
        out->mods=mods(SDL_GetModState());
        switch(e.type) {
        case SDL_EVENT_QUIT: case SDL_EVENT_WINDOW_CLOSE_REQUESTED: out->type=1; break;
        case SDL_EVENT_MOUSE_BUTTON_DOWN: case SDL_EVENT_MOUSE_BUTTON_UP:
            out->type=e.type==SDL_EVENT_MOUSE_BUTTON_DOWN?2:3; out->x=e.button.x; out->y=e.button.y; out->button=e.button.button; break;
        case SDL_EVENT_MOUSE_MOTION: out->type=4; out->x=e.motion.x; out->y=e.motion.y; out->dx=e.motion.xrel; out->dy=e.motion.yrel; break;
        case SDL_EVENT_MOUSE_WHEEL: {
            float sign=e.wheel.direction==SDL_MOUSEWHEEL_FLIPPED?-1:1;
            out->type=5; out->x=e.wheel.mouse_x; out->y=e.wheel.mouse_y; out->dx=e.wheel.x*sign; out->dy=e.wheel.y*sign; break; }
        case SDL_EVENT_KEY_DOWN: out->type=6; out->key=key(e.key.key); out->mods=mods(e.key.mod); break;
        case SDL_EVENT_TEXT_INPUT: d->event_text=SDL_strdup(e.text.text); out->type=7; out->text=d->event_text; break;
        case SDL_EVENT_WINDOW_RESIZED: case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
            out->type=8; { int w,h; lt_size(d,&w,&h); out->x=(float)w; out->y=(float)h; } break;
        default: continue;
        }
        return true;
    }
    return false;
}
void lt_size(LTDesktop *d,int *w,int *h) { if(d) SDL_GetWindowSize(d->window,w,h); else { if(w)*w=0; if(h)*h=0; } }
void lt_begin(LTDesktop *d,unsigned c) {
    if(!d) return; int w,h,pw,ph; SDL_GetWindowSize(d->window,&w,&h); SDL_GetRenderOutputSize(d->renderer,&pw,&ph);
    if(w>0&&h>0&&pw>0&&ph>0) { d->density=(float)ph/h; SDL_SetRenderScale(d->renderer,(float)pw/w,(float)ph/h); }
    d->frame++; SDL_SetRenderClipRect(d->renderer,NULL); color(d->renderer,c); SDL_RenderClear(d->renderer);
}
void lt_rect(LTDesktop *d,float x,float y,float w,float h,unsigned c) {
    if(!d||w<=0||h<=0) return; SDL_FRect r={coord(x),coord(y),extent(w),extent(h)}; color(d->renderer,c); SDL_RenderFillRect(d->renderer,&r);
}
void lt_line(LTDesktop *d,float x,float y,float x2,float y2,unsigned c) { if(d) { color(d->renderer,c); SDL_RenderLine(d->renderer,coord(x),coord(y),coord(x2),coord(y2)); } }
void lt_image(LTDesktop *d,const char *path,float sx,float sy,float sw,float sh,float x,float y,float w,float h,int flip,unsigned char alpha) {
    if(!d||!path||!*path||w<=0||h<=0) return;
    Cache *c=NULL; for(int i=0;i<IMAGE_COUNT;i++) if(d->images[i].key&&!strcmp(d->images[i].key,path)) { c=&d->images[i]; break; }
    if(!c) {
        size_t n=0; unsigned char *data=SDL_LoadFile(path,&n),*pixels=NULL; int iw=0,ih=0,channels;
        if(data&&n<=INT_MAX) pixels=stbi_load_from_memory(data,(int)n,&iw,&ih,&channels,4); SDL_free(data);
        size_t bytes=(size_t)iw*ih*4;
        if(pixels&&(iw>16384||ih>16384||bytes>IMAGE_BUDGET)) { stbi_image_free(pixels); pixels=NULL; SDL_SetError("Image exceeds desktop texture budget: %s",path); }
        c=slot(d->images,IMAGE_COUNT,IMAGE_BUDGET,pixels?bytes:0); c->key=SDL_strdup(path); c->w=iw; c->h=ih;
        if(pixels) { c->texture=texture(d,pixels,iw,ih,false); c->bytes=c->texture?bytes:0; stbi_image_free(pixels); }
        else if(data==NULL) SDL_SetError("Unable to load PNG: %s",path);
    }
    c->used=d->frame; if(!c->texture) return;
    if(sw<=0||sh<=0) { sx=sy=0; sw=(float)c->w; sh=(float)c->h; }
    SDL_FRect src={coord(sx),coord(sy),extent(sw),extent(sh)},dst={coord(x),coord(y),extent(w),extent(h)};
    SDL_SetTextureAlphaMod(c->texture,alpha);
    SDL_RenderTextureRotated(d->renderer,c->texture,&src,&dst,0,NULL,(flip&1)?SDL_FLIP_HORIZONTAL:SDL_FLIP_NONE);
}
void lt_pixels(LTDesktop *d,const char *key,const unsigned char *pixels,int pw,int ph,float x,float y,float w,float h,unsigned char alpha) {
    if(!d||!key||!*key||!pixels||pw<1||ph<1||pw>16384||ph>16384||w<=0||h<=0)return;
    size_t bytes=(size_t)pw*ph*4; if(bytes>IMAGE_BUDGET)return;
    /* Prefix dynamic keys so a procedural name cannot alias a PNG pathname. */
    size_t length=SDL_strlen(key); if(length>4096)return;
    char *cache_key=SDL_malloc(length+9); if(!cache_key)return;
    SDL_snprintf(cache_key,length+9,"pixels:%s",key);
    Cache *c=NULL; for(int i=0;i<IMAGE_COUNT;i++) if(d->images[i].key&&!strcmp(d->images[i].key,cache_key)) { c=&d->images[i];break; }
    if(!c) {
        unsigned char *straight=SDL_malloc(bytes); if(!straight) { SDL_free(cache_key);return; }
        for(size_t i=0;i<bytes;i+=4) {
            unsigned a=pixels[i+3]; straight[i+3]=(unsigned char)a;
            for(int j=0;j<3;j++)straight[i+j]=a?(unsigned char)SDL_min(255,((unsigned)pixels[i+j]*255+a/2)/a):0;
        }
        c=slot(d->images,IMAGE_COUNT,IMAGE_BUDGET,bytes); c->key=cache_key;cache_key=NULL;
        c->texture=texture(d,straight,pw,ph,false);c->w=pw;c->h=ph;c->bytes=c->texture?bytes:0;SDL_free(straight);
    }
    SDL_free(cache_key);c->used=d->frame;if(!c->texture)return;
    SDL_FRect dst={coord(x),coord(y),extent(w),extent(h)};SDL_SetTextureAlphaMod(c->texture,alpha);SDL_RenderTexture(d->renderer,c->texture,NULL,&dst);
}
/* Decode Unicode scalar values without reading beyond the terminating NUL. */
static int utf8(const char **text) {
    const unsigned char *p=(const unsigned char *)*text; unsigned c=*p++; int n=0;
    if(c<128) { *text=(const char *)p; return (int)c; }
    if(c>=0xC2&&c<=0xDF) { c&=31;n=1; } else if(c>=0xE0&&c<=0xEF) { c&=15;n=2; } else if(c>=0xF0&&c<=0xF4) { c&=7;n=3; } else { *text=(const char *)p;return 0xFFFD; }
    int length=n; for(int i=0;i<n;i++) { if((*p&0xC0)!=0x80) { *text=(const char *)p; return 0xFFFD; } c=(c<<6)|(*p++&63); }
    *text=(const char *)p;
    if(c>0x10FFFF||(c>=0xD800&&c<=0xDFFF)||(length==1&&c<128)||(length==2&&c<2048)||(length==3&&c<65536)) return 0xFFFD;
    return (int)c;
}
static int glyph(stbtt_fontinfo *font,int cp) { return stbtt_FindGlyphIndex(font,cp)?cp:'?'; }
static Cache *text_cache(LTDesktop *d,const char *text,int px,unsigned rgba,int bold) {
    for(int i=0;i<TEXT_COUNT;i++) { Cache *c=&d->texts[i]; if(c->key&&c->px==px&&c->color==rgba&&c->bold==bold&&!strcmp(c->key,text)) return c; }
    stbtt_fontinfo *font=&d->font[bold]; float scale=stbtt_ScaleForPixelHeight(font,(float)px);
    int ascent,descent,gap; stbtt_GetFontVMetrics(font,&ascent,&descent,&gap);
    int line=(int)ceilf((ascent-descent+gap)*scale),baseline=(int)ceilf(ascent*scale),w=1,h=line+2;
    float pen=2,maxpen=0; int previous=0;
    const char *p=text;
    while(*p) { int cp=utf8(&p); if(cp=='\n') { maxpen=fmaxf(maxpen,pen); pen=2; h+=line; previous=0; continue; } cp=glyph(font,cp); int advance; stbtt_GetCodepointHMetrics(font,cp,&advance,NULL); if(previous)pen+=stbtt_GetCodepointKernAdvance(font,previous,cp)*scale; pen+=advance*scale; previous=cp; }
    w=(int)ceilf(fmaxf(maxpen,pen))+px;
    if(w>8192||h>4096||w<1||h<1||(size_t)w*h*4>TEXT_BUDGET) { SDL_SetError("Text exceeds desktop texture budget"); return NULL; }
    unsigned char *pixels=SDL_calloc((size_t)w*h,4); if(!pixels) return NULL;
    pen=2; int y=baseline; previous=0; p=text;
    while(*p) {
        int cp=utf8(&p); if(cp=='\n') { pen=2;y+=line;previous=0;continue; } cp=glyph(font,cp);
        if(previous)pen+=stbtt_GetCodepointKernAdvance(font,previous,cp)*scale;
        int bw,bh,ox,oy,advance; unsigned char *bitmap=stbtt_GetCodepointBitmap(font,scale,scale,cp,&bw,&bh,&ox,&oy);
        for(int by=0;by<bh;by++) for(int bx=0;bx<bw;bx++) { int tx=(int)floorf(pen)+ox+bx,ty=y+oy+by; if(tx>=0&&tx<w&&ty>=0&&ty<h) { unsigned char *pixel=pixels+((size_t)ty*w+tx)*4; unsigned a=(unsigned)bitmap[by*bw+bx]*(rgba&255)/255; pixel[0]=rgba>>24;pixel[1]=(rgba>>16)&255;pixel[2]=(rgba>>8)&255; if(a>pixel[3])pixel[3]=(unsigned char)a; } }
        stbtt_FreeBitmap(bitmap,NULL); stbtt_GetCodepointHMetrics(font,cp,&advance,NULL); pen+=advance*scale;previous=cp;
    }
    Cache *c=slot(d->texts,TEXT_COUNT,TEXT_BUDGET,(size_t)w*h*4); c->texture=texture(d,pixels,w,h,true); SDL_free(pixels);
    if(!c->texture)return NULL;
    c->key=SDL_strdup(text);c->w=w;c->h=h;c->px=px;c->bold=bold;c->color=rgba;c->bytes=(size_t)w*h*4; return c;
}
void lt_text(LTDesktop *d,const char *text,float x,float y,float size,unsigned rgba,int bold) {
    if(!d||!text||!*text||!isfinite(size)||size<=0||strlen(text)>4096) return;
    float density=fmaxf(1,fminf(d->density,4)); int px=(int)ceilf(fminf(size,128)*density); if(px<1)px=1;
    Cache *c=text_cache(d,text,px,rgba,bold!=0); if(!c)return; c->used=d->frame;
    SDL_FRect dst={coord(x)-2/density,coord(y),c->w/density,c->h/density}; SDL_RenderTexture(d->renderer,c->texture,NULL,&dst);
}
void lt_clip(LTDesktop *d,float x,float y,float w,float h) { if(d) { SDL_Rect r={(int)coord(x),(int)coord(y),(int)extent(w),(int)extent(h)}; SDL_SetRenderClipRect(d->renderer,w<0?NULL:&r); } }
void lt_present(LTDesktop *d) { if(d)SDL_RenderPresent(d->renderer); }
double lt_time(void) { return SDL_GetTicksNS()/1000000000.0; }
void lt_delay(int ms) { if(ms>0)SDL_Delay((Uint32)ms); }
typedef struct { SDL_IOStream *io; bool ok; } PNGOutput;
static void png_write(void *context,void *data,int size) { PNGOutput *out=context; if(out->ok&&SDL_WriteIO(out->io,data,(size_t)size)!=(size_t)size)out->ok=false; }
bool lt_capture(LTDesktop *d,const char *path) {
    if(!d||!path||!*path)return false;
    SDL_Surface *raw=SDL_RenderReadPixels(d->renderer,NULL); if(!raw)return false;
    SDL_Surface *surface=SDL_ConvertSurface(raw,SDL_PIXELFORMAT_RGBA32); SDL_DestroySurface(raw); if(!surface)return false;
    PNGOutput out={SDL_IOFromFile(path,"wb"),true};
    if(!out.io) { SDL_DestroySurface(surface);return false; }
    bool ok=stbi_write_png_to_func(png_write,&out,surface->w,surface->h,4,surface->pixels,surface->pitch)!=0;
    ok=SDL_CloseIO(out.io)&&ok&&out.ok; SDL_DestroySurface(surface); return ok;
}
void lt_file_dialog(LTDesktop *d,int save,const char *path) {
    if(!d)return; DialogRequest *r=SDL_calloc(1,sizeof(*r)); if(!r)return;
    r->queue=d->dialogs;r->default_path=path?SDL_strdup(path):NULL;
    SDL_LockMutex(r->queue->mutex); r->queue->references++; SDL_UnlockMutex(r->queue->mutex);
    static const SDL_DialogFileFilter filters[]={{"Lofty Ambitions saves","loftyambitions"},{"JSON saves","json"},{"All files","*"}};
    if(save) SDL_ShowSaveFileDialog(dialog_done,r,d->window,filters,3,r->default_path);
    else SDL_ShowOpenFileDialog(dialog_done,r,d->window,filters,3,r->default_path,false);
}
const char *lt_error(void) { return SDL_GetError(); }

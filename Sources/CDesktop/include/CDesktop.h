#ifndef LOFTY_CDESKTOP_H
#define LOFTY_CDESKTOP_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LTDesktop LTDesktop;
typedef struct LTEvent {
    int type;
    float x, y, dx, dy;
    int button, key, mods;
    const char *text;
} LTEvent;
/* All calls on the main thread. Text remains valid until the next lt_poll.
 * Event types: 1 quit, 2 mouseDown, 3 mouseUp, 4 motion, 5 wheel,
 * 6 keyDown, 7 textInput, 8 resize, 9 fileResult (empty text on cancellation).
 * Keys: lowercase ASCII; 1001 up, 1002 down, 1003 left, 1004 right.
 * Modifier bits: 1 shift, 2 control, 4 alt, 8 command/gui.
 * Coordinates and font sizes are logical window units. Colors are RRGGBBAA.
 */
LTDesktop *lt_create(const char *title, int width, int height);
void lt_destroy(LTDesktop *desktop);
bool lt_poll(LTDesktop *desktop, LTEvent *event);
void lt_size(LTDesktop *desktop, int *width, int *height);
/* Native window coordinates before application UI scaling. */
void lt_window_size(LTDesktop *desktop, int *width, int *height);
float lt_content_scale(LTDesktop *desktop);
void lt_set_ui_scale(LTDesktop *desktop, float scale);
void lt_maximize(LTDesktop *desktop);
void lt_restore(LTDesktop *desktop);
typedef struct LTCacheStats {
    unsigned long long png_decodes, dynamic_uploads;
    int images, dynamic_images;
} LTCacheStats;
void lt_cache_stats(LTDesktop *desktop, LTCacheStats *stats);
void lt_begin(LTDesktop *desktop, unsigned rgba);
void lt_rect(LTDesktop *desktop, float x, float y, float w, float h, unsigned rgba);
void lt_line(LTDesktop *desktop, float x1, float y1, float x2, float y2, unsigned rgba);
void lt_image(LTDesktop *desktop, const char *png, float sx, float sy, float sw, float sh, float x, float y, float w, float h, int flip, unsigned char alpha);
/* Cached dynamic image. A key identifies immutable premultiplied RGBA8 pixels. */
/* Draw an existing dynamic texture without regenerating or uploading pixels. */
bool lt_cached_pixels(LTDesktop *desktop, const char *key, float x, float y, float w, float h, unsigned char alpha);
void lt_pixels(LTDesktop *desktop, const char *key, const unsigned char *premultiplied_rgba, int pixel_width, int pixel_height, float x, float y, float w, float h, unsigned char alpha);
void lt_text(LTDesktop *desktop, const char *text, float x, float y, float size, unsigned rgba, int bold);
void lt_clip(LTDesktop *desktop, float x, float y, float w, float h);
void lt_present(LTDesktop *desktop);
double lt_time(void);
void lt_delay(int ms);
/* Capture after drawing and BEFORE lt_present. */
bool lt_capture(LTDesktop *desktop, const char *png);
void lt_file_dialog(LTDesktop *desktop, int save, const char *default_path);
const char *lt_error(void);
#ifdef __cplusplus
}
#endif
#endif

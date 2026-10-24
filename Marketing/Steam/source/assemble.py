"""Rebuild the promotional edit from captured gameplay and original key art."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess, math, wave, json
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'source'
FF='/opt/homebrew/bin/ffmpeg'
FONT='/System/Library/Fonts/Supplemental/Arial Black.ttf'
REG='/System/Library/Fonts/Supplemental/Arial.ttf'
CREAM='#fff1d2'; CORAL='#ff725e'; TEAL='#6be5ce'; NAVY='#101e35'

def run(args):
    subprocess.run([FF,'-y','-hide_banner','-loglevel','error',*map(str,args)],check=True)

def font(size,bold=True):return ImageFont.truetype(FONT if bold else REG,size)

def overlay(index,lines,sub):
    im=Image.new('RGBA',(1920,1080))
    # Graphic title treatment is separate from the unaltered gameplay screenshots.
    strip=Image.new('RGBA',(820,1080)); px=strip.load()
    for x in range(820):
        alpha=int(245 if x<490 else 245*(1-(x-490)/330)**1.5)
        for y in range(1080):px[x,y]=(16,30,53,alpha)
    im.alpha_composite(strip)
    d=ImageDraw.Draw(im)
    d.rectangle((64,61,111,69),fill=CORAL)
    d.text((64,92),'LOFTY AMBITIONS',font=font(23),fill=CREAM)
    d.text((64,141),'BUILD / MANAGE / THRIVE',font=font(17,False),fill=TEAL)
    for n,line in enumerate(lines):
        f=font(72)
        while d.textbbox((0,0),line,font=f)[2]>535:f=font(f.size-1)
        d.text((60,335+n*88),line,font=f,fill=CORAL if n==len(lines)-1 else CREAM,stroke_width=0)
    y=370+len(lines)*88
    for line in sub.split('\n'):
        d.text((64,y),line,font=font(24,False),fill='#d4dfdf');y+=34
    d.text((64,929),f'{index+1:02d}  /  07',font=font(20),fill=TEAL)
    for k in range(7):d.rectangle((64+k*66,982,116+k*66,987),fill=CORAL if k==index else '#526176')
    d.rounded_rectangle((1614,38,1878,80),radius=21,fill=(16,30,53,215))
    d.text((1641,49),'IN-GAME FOOTAGE',font=font(17),fill=CREAM)
    im.save(SRC/f'overlay-{index}.png')

def soundtrack():
    sr=48000;duration=32;n=sr*duration
    out=np.zeros((n,2),np.float64);rng=np.random.default_rng(20261024)
    def put(signal,start,pan=0):
        i=int(start*sr);end=min(n,i+len(signal))
        if i<0 or i>=n:return
        signal=signal[:end-i]
        out[i:end,0]+=signal*math.sqrt((1-pan)/2)
        out[i:end,1]+=signal*math.sqrt((1+pan)/2)
    def tone(midi,duration,amp=.1,kind='pluck'):
        t=np.arange(int(sr*duration))/sr;f=440*2**((midi-69)/12)
        env=np.minimum(t/.007,1)*np.exp(-t*(7 if kind=='pluck' else 3))
        env*=np.minimum((duration-t)/.03,1)
        if kind=='bass':s=np.sin(2*np.pi*f*t)+.22*np.sin(4*np.pi*f*t)
        else:s=np.sin(2*np.pi*f*t)+.3*np.sin(4*np.pi*f*t)+.12*np.sin(6*np.pi*f*t)
        return s*env*amp
    # 120 BPM. Bright major-seventh harmony, syncopated bass, arcade arpeggios.
    chords=[[48,52,55,59],[55,59,62,66],[57,60,64,67],[53,57,60,64]]
    for bar in range(16):
        start=bar*2;ch=chords[(bar//2)%4]
        for note in ch:put(tone(note+12,1.9,.055),start,(-.45 if note%2 else .45))
        for b in range(4):
            beat=start+b*.5
            t=np.arange(int(sr*.28))/sr
            kick=np.sin(2*np.pi*(48*t+9*(1-np.exp(-t*38))))*np.exp(-t*18)*.48
            put(kick,beat)
            put(tone(ch[0]-12,.3,.29,'bass'),beat+.0)
            if b in [1,3]:
                t=np.arange(int(sr*.16))/sr
                noise=rng.standard_normal(len(t));noise=np.r_[noise[0],np.diff(noise)]
                put((noise*.09+np.sin(2*np.pi*185*t)*.12)*np.exp(-t*28),beat)
        for step in range(8):
            t=np.arange(int(sr*.06))/sr;noise=rng.standard_normal(len(t))
            put(noise*np.exp(-t*75)*.055,start+step*.25,(-.25 if step%2 else .25))
            if bar>=2:
                note=ch[[0,2,1,3,2,1,3,2][step]]+24
                put(tone(note,.22,.075),start+step*.25,math.sin(step)*.4)
        if bar>=4:
            melody=[7,12,14,16,14,12,7,9]
            for step in range(4):put(tone(ch[0]+24+melody[(bar+step)%8],.32,.07),start+.125+step*.5,-.1)
    # Short construction blips and transitions, written for this edit.
    for time in [4,8,12,16,20,24,28]:
        t=np.arange(int(sr*.18))/sr
        put(np.sin(2*np.pi*(600*t+2400*t*t))*np.exp(-t*23)*.13,time)
    for time in np.arange(4.25,7.8,.35):put(tone(84,.09,.11),time,.2)
    t=np.arange(int(sr*.5))/sr
    put(rng.standard_normal(len(t))*np.linspace(0,.08,len(t)),27.5)
    out=np.tanh(out*1.15)
    out*=np.minimum(np.arange(n)/sr/.03,1)[:,None]
    out*=np.minimum((duration-np.arange(n)/sr)/.65,1)[:,None]
    out*=.84/max(np.max(np.abs(out)),.84)
    with wave.open(str(SRC/'skyline-spark-original.wav'),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(sr);w.writeframes((out*32767).astype('<i2').tobytes())

def assets():
    # Only format conversions here: full artwork is retained in source/.
    landscape=SRC/'key-art-landscape.png';portrait=SRC/'key-art-portrait.png'
    for name,w,h,path in [('main',1232,706,landscape),('header',920,430,landscape),('vertical',748,896,portrait)]:
        run(['-i',path,'-vf',f'scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h}','-frames:v','1',ROOT/'capsules'/f'{name}-{w}x{h}.png'])
    run(['-i',landscape,'-vf','crop=790:298:0:283,scale=462:174','-frames:v','1',ROOT/'capsules/small-462x174.png'])

def videos():
    scenes=sorted(SRC.glob('0[1-7]-*.mp4'))
    assert len(scenes)==7,scenes
    copy=[(['A WHOLE','CITY.','ONE TOWER.'],'Your neighborhood.\nOn a whole new level.'),
          (['START SMALL.','BUILD BIG.'],'Stack rooms. Add floors.\nWatch your ambitions rise.'),
          (['LITTLE ROOMS.','BIG STORIES.'],'Homes, work, ramen, play.\nLife fills every floor.'),
          (['KEEP LIFE','MOVING.'],'Connect the floors.\nKeep the elevators flowing.'),
          (['GO BELOW.','GROW BEYOND.'],'Take your neighborhood\nunderground.'),
          (['A LITTLE','CHAOS.'],'Noisy guests. Sudden fires.\nYou are in charge.'),
          (['DREAM','IN FLOORS.'],'From your first lobby\nto your own city landmark.')]
    edited=[]
    for i,(scene,(lines,sub)) in enumerate(zip(scenes,copy)):
        overlay(i,lines,sub)
        dest=SRC/f'edit-{i}.mp4';edited.append(dest)
        if '--refresh-emergency' in sys.argv and i != 5:
            continue
        vf="[1:v]format=rgba,fade=t=in:st=0:d=0.18:alpha=1[title];[0:v][title]overlay=x='-28*max(0,(0.28-t)/0.28)':y=0:shortest=1,drawbox=x=0:y=1072:w='iw':h=8:color=0xff725e:t=fill,fade=t=in:st=0:d=0.08[v]"
        run(['-i',scene,'-loop','1','-i',SRC/f'overlay-{i}.png','-filter_complex',vf,'-map','[v]','-t','4','-r','30','-c:v','libx264','-preset','fast','-crf','17','-pix_fmt','yuv420p',dest])
        print('Edited',scene.stem,flush=True)
    # A slow illustrated reveal, with drifting pixel sparks and a clean closing line.
    d=Image.new('RGBA',(1920,1080));draw=ImageDraw.Draw(d)
    draw.rectangle((0,946,1920,1080),fill=(16,30,53,235))
    text='BUILD YOUR NEIGHBORHOOD IN THE SKY.'
    draw.text((960,992),text,font=font(34),fill=CREAM,anchor='mm')
    draw.text((960,1040),'LOFTY AMBITIONS  /  TOWER MANAGEMENT',font=font(17,False),fill=TEAL,anchor='mm')
    d.save(SRC/'end-overlay.png')
    end=SRC/'edit-7.mp4';edited.append(end)
    spark=''
    for i in range(14):
        x=850+(i*83)%1000;y=150+(i*147)%730
        spark+=f",drawbox=x={x}:y={y}:w=4:h=4:color=0xffdf8c@0.65:t=fill:enable='lt(mod(t+{i*.11:.2f},1.8),0.45)'"
    vf=f"[0:v]scale=2112:1188,zoompan=z='1.02+0.00035*on':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=120:s=1920x1080:fps=30{spark}[art];[art][1:v]overlay=0:0,fade=t=in:st=0:d=0.15,fade=t=out:st=3.7:d=0.3[v]"
    run(['-i',SRC/'key-art-landscape.png','-loop','1','-i',SRC/'end-overlay.png','-filter_complex',vf,'-map','[v]','-t','4','-r','30','-c:v','libx264','-preset','fast','-crf','17','-pix_fmt','yuv420p',end])
    (SRC/'concat.txt').write_text(''.join(f"file '{p.name}'\n" for p in edited))
    run(['-f','concat','-safe','0','-i',SRC/'concat.txt','-i',SRC/'skyline-spark-original.wav','-map','0:v','-map','1:a','-c:v','libx264','-preset','slow','-b:v','12M','-maxrate','18M','-bufsize','24M','-pix_fmt','yuv420p','-c:a','aac','-b:a','320k','-ar','48000','-movflags','+faststart','-t','32',ROOT/'video/Lofty-Ambitions-Gameplay-Trailer-1080p.mp4'])
    # 12-second teaser: construction, chaos, title reveal.
    (SRC/'teaser-concat.txt').write_text(''.join(f"file 'edit-{i}.mp4'\n" for i in [1,5,7]))
    run(['-f','concat','-safe','0','-i',SRC/'teaser-concat.txt','-ss','20','-i',SRC/'skyline-spark-original.wav','-map','0:v','-map','1:a','-c:v','libx264','-preset','slow','-b:v','10M','-pix_fmt','yuv420p','-c:a','aac','-b:a','320k','-af','afade=t=out:st=11.5:d=0.5','-movflags','+faststart','-t','12',ROOT/'video/Lofty-Ambitions-Teaser-1080p.mp4'])
    for index,name in [(1,'build-it-up'),(2,'little-lives'),(5,'pleasant-chaos')]:
        # Ping-pong motion loops without a jump at the repeat boundary.
        width=480 if index==2 else 600
        run(['-t','3','-i',scenes[index],'-filter_complex',f'[0:v]fps=10,scale={width}:-1:flags=lanczos,split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1:a=0,split[c][d];[c]palettegen=max_colors=128[p];[d][p]paletteuse=dither=bayer:bayer_scale=4','-loop','0',ROOT/f'loops/{name}.gif'])
    # Concept-only motion asset; gameplay is presented separately in the trailer.
    run(['-loop','1','-i',SRC/'key-art-landscape.png','-i',SRC/'skyline-spark-original.wav','-vf',"scale=2112:1188,zoompan=z='1.0+0.0003*on':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1920x1080:fps=30"+spark,'-t','8','-c:v','libx264','-b:v','10M','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-af','afade=t=out:st=7.5:d=0.5','-movflags','+faststart',ROOT/'video/Lofty-Ambitions-Concept-Reveal-1080p.mp4'])

if __name__=='__main__':
    import sys
    assets();soundtrack()
    if '--assets-only' not in sys.argv:videos()
    print('Promo edit complete.',flush=True)

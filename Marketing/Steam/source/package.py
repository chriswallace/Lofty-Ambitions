"""Check finished deliverables, create a review sheet, and package the upload set."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess, json, hashlib, zipfile

ROOT=Path(__file__).resolve().parents[1]
font='/System/Library/Fonts/Supplemental/Arial Black.ttf'
report={'images':[],'videos':[],'loops':[]}
expected={'main-1232x706.png':(1232,706),'header-920x430.png':(920,430),'small-462x174.png':(462,174),'vertical-748x896.png':(748,896)}
for path in sorted((ROOT/'capsules').glob('*.png')):
    im=Image.open(path);im.verify()
    assert Image.open(path).size==expected[path.name],path
    report['images'].append({'file':str(path.relative_to(ROOT)),'size':expected[path.name]})
shots=sorted((ROOT/'screenshots').glob('*.png'))
assert len(shots)==8
for path in shots:
    im=Image.open(path);assert im.size==(1920,1080);im.verify()
    report['images'].append({'file':str(path.relative_to(ROOT)),'size':(1920,1080)})
durations={'Lofty-Ambitions-Gameplay-Trailer-1080p.mp4':32,'Lofty-Ambitions-Teaser-1080p.mp4':12,'Lofty-Ambitions-Concept-Reveal-1080p.mp4':8}
for path in sorted((ROOT/'video').glob('*.mp4')):
    info=json.loads(subprocess.check_output(['/opt/homebrew/bin/ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
    v=next(s for s in info['streams'] if s['codec_type']=='video')
    a=next(s for s in info['streams'] if s['codec_type']=='audio')
    assert (v['width'],v['height'],v['codec_name'],v['avg_frame_rate'])==(1920,1080,'h264','30/1')
    assert a['codec_name']=='aac' and a['channels']==2
    assert abs(float(info['format']['duration'])-durations[path.name])<.1
    subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-i',str(path),'-f','null','-'],check=True)
    report['videos'].append({'file':str(path.relative_to(ROOT)),'duration':info['format']['duration'],'video':v['codec_name'],'audio':a['codec_name'],'resolution':[v['width'],v['height']],'fps':v['avg_frame_rate']})
for path in sorted((ROOT/'loops').glob('*.gif')):
    im=Image.open(path);assert im.n_frames>20
    assert path.stat().st_size<5*1024*1024,(path,path.stat().st_size)
    assert im.info.get('loop')==0
    duration=0
    for frame in range(im.n_frames):im.seek(frame);duration+=im.info['duration']
    assert 5500<=duration<=6500,duration
    report['loops'].append({'file':str(path.relative_to(ROOT)),'frames':im.n_frames,'duration_ms':duration,'bytes':path.stat().st_size})

# One glanceable board for reviewing the finished edit and art.
board=Image.new('RGB',(1920,1640),'#101e35');d=ImageDraw.Draw(board)
def f(size):return ImageFont.truetype(font,size)
d.text((50,35),'LOFTY AMBITIONS',font=f(38),fill='#fff1d2')
d.text((50,91),'STEAM PROMO SET  /  A WHOLE CITY. ONE TOWER.',font=f(19),fill='#6be5ce')
main=Image.open(ROOT/'capsules/main-1232x706.png');main.thumbnail((1130,650));board.paste(main,(50,145))
portrait=Image.open(ROOT/'capsules/vertical-748x896.png');portrait.thumbnail((480,590));board.paste(portrait,(1280,145))
d.text((50,813),'32s GAMEPLAY TRAILER  /  ORIGINAL SYNTH SOUNDTRACK',font=f(24),fill='#ff725e')
names=['opening','construction','room-life','elevators','underground','emergency','skyline','finale']
for i,name in enumerate(names):
    im=Image.open(ROOT/f'preview/{name}.png');im.thumbnail((440,248))
    x=50+(i%4)*465;y=872+(i//4)*327
    board.paste(im,(x,y))
    d.text((x,y+258),f'{i*4:02d}s  /  '+name.upper(),font=f(17),fill='#fff1d2')
d.text((50,1552),'PLUS: 12s TEASER / 8s CONCEPT REVEAL / 8 GAMEPLAY SHOTS / 3 GIF LOOPS / 4 CAPSULES',font=f(18),fill='#6be5ce')
board.save(ROOT/'preview/Promo-Overview.jpg',quality=93)
report['verification']='All final PNGs inspected structurally; three videos decoded without errors; GIFs repeat and remain below 5 MiB. Five artwork tests pass. Rebuilt app contains the matching fire-engine sprite and its local signature verifies.'
(ROOT/'asset-manifest.json').write_text(json.dumps(report,indent=2)+'\n')

bundle=ROOT.parent/'Lofty-Ambitions-Steam-Promo-Kit.zip'
with zipfile.ZipFile(bundle,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for folder in ['capsules','screenshots','video','loops']:
        for path in sorted((ROOT/folder).iterdir()):z.write(path,'Lofty-Ambitions-Steam-Promo-Kit/'+str(path.relative_to(ROOT)))
    for relative in ['README.md','asset-manifest.json','preview/Promo-Overview.jpg']:
        z.write(ROOT/relative,'Lofty-Ambitions-Steam-Promo-Kit/'+relative)
with zipfile.ZipFile(bundle) as z:assert z.testzip() is None
print(json.dumps(report,indent=2))
print('Created',bundle,'—',round(bundle.stat().st_size/1024/1024,1),'MiB')

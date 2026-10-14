from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np, wave, json
ROOT=Path(__file__).resolve().parent.parent
frames=sorted((ROOT/'.tesseract-work/frames').glob('*.png'))
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',18)
for lo,hi,name in [(0,28,'Reference-Opening'),(26,56,'Reference-Icons'),(54,82,'Reference-Ending')]:
    selected=frames[lo:hi]
    out=Image.new('RGB',(1440,((len(selected)+3)//4)*290),'#252525');d=ImageDraw.Draw(out)
    for j,f in enumerate(selected):
        im=Image.open(f).resize((360,270));x=(j%4)*360;y=(j//4)*290
        out.paste(im,(x,y));d.text((x+8,y+271),f'{(int(f.stem)-1)/4+.125:.3f}s',font=font,fill='white')
    out.save(ROOT/'Previews'/f'{name}.jpg')
with wave.open(str(ROOT/'.tesseract-work/original-audio.wav')) as w:
    sr=w.getframerate();n=w.getnchannels();a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).reshape(-1,n)/32768
im=Image.new('RGB',(1600,500),'#17191c');d=ImageDraw.Draw(im)
for c in range(n):
    y0=70+c*190;d.text((15,y0-40),f'Original audio — channel {c+1}',font=font,fill='white')
    for x in range(60,1560):
        st=int((x-60)/1500*len(a));en=max(st+1,int((x-59)/1500*len(a)))
        p=float(np.max(abs(a[st:en,c])));d.line((x,y0+70-p*65,x,y0+70+p*65),fill='#77d8c5')
    for t in range(21):
        x=60+t/ (len(a)/sr)*1500;d.line((x,y0,x,y0+140),fill='#30363e');d.text((x,y0+145),str(t),font=font,fill='#cccccc')
im.save(ROOT/'Previews/Original-Audio-Waveform.png')
print('Reference sheets and audio waveform ready')

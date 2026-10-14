from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent.parent
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',18)
for folder,start,fps,step,chunk in [('orbit-frames',6.35,24,1,16),('carousel-frames',9.25,12,1,12),('scatter-frames',11.95,12,1,12)]:
    frames=sorted((ROOT/'.tesseract-work'/folder).glob('*.png'))[::step]
    for offset in range(0,len(frames),chunk):
        fs=frames[offset:offset+chunk];im=Image.new('RGB',(1440,((len(fs)+3)//4)*294),'#252525');d=ImageDraw.Draw(im)
        for j,f in enumerate(fs):
            x=j%4*360;y=j//4*294;im.paste(Image.open(f).resize((360,270)),(x,y));d.text((x+8,y+273),f'{start+(int(f.stem)-.5)/fps:.3f}s / frame {f.stem}',font=font,fill='white')
        im.save(ROOT/'Previews'/f'Dense-{folder}-{offset//chunk+1}.jpg')
print('Dense reference strips ready')

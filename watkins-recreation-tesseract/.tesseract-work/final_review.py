from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess
ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'.tesseract-work';out=WORK/'final-review';out.mkdir(exist_ok=True)
source=Path('/Users/akhilkonduru/Library/CloudStorage/OneDrive-Personal/CDownloads/Jordan_Watkins_-_i_d_love_to_see_AI_try_and_recreate_this_AyD9nu.mp4')
video=ROOT/'Watkins-Recreation.mp4'
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',19)
def frame(p,t,target):
 subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-y','-ss',str(t),'-i',str(p),'-frames:v','1','-vf','scale=1440:1080',str(target)],check=True)
 return Image.open(target).convert('RGB')
times=[.15,.5,.9,1.6,2.4,3.6,4.4,5.8,6.7,7.38,7.8,8.7,9.6,10.2,10.82,11.5,12.18,12.52,13.35,14.4,16.1,16.7,17.7,19.9]
strip=Image.new('RGB',(1440,6*300),(20,20,18));d=ImageDraw.Draw(strip)
for i,t in enumerate(times):
 im=frame(video,t,out/f'final-{t}.png');x=i%4*360;y=i//4*300;strip.paste(im.resize((360,270)),(x,y));d.text((x+10,y+275),f'{t:.3f}s',font=font,fill='white')
strip.save(ROOT/'Previews/Recreation-Filmstrip.png')
for page,ts in enumerate([[6.7,7.15,7.38,7.8,8.28,9.6],[10.82,12.18,12.52,12.8,13.10,13.35]]):
 sheet=Image.new('RGB',(1440,3*300),(20,20,18));d=ImageDraw.Draw(sheet)
 for i,t in enumerate(ts):
  for j,p in enumerate([source,video]):
   im=frame(p,t,out/f'compare-{page}-{i}-{j}.png');x=(i%2*2+j)*360;y=i//2*300;sheet.paste(im.resize((360,270)),(x,y));d.text((x+10,y+275),('Reference' if j==0 else 'Recreated')+f' · {t:.3f}s',font=font,fill='white')
 sheet.save(ROOT/f'Previews/Orbit-Comparison-{page+1}.jpg',quality=94)
frame(video,7.375,ROOT/'Previews/Poster.png')
print('Final filmstrip, poster, and paired orbital comparisons saved.')

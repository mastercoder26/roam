from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np,json
ROOT=Path(__file__).resolve().parent.parent
sprites=json.load(open(ROOT/'.tesseract-work/native-sprites.json'))
rng=np.random.default_rng(4)
templates={}
for name,s in sprites.items():
    w,h=s['grid'];colors=[];points=[]
    for p in s['parts']:
        cmds=p['commands']
        for i in range(0,len(cmds),5):
            x0,y0=cmds[i]['x'],cmds[i]['y'];x1,y1=cmds[i+2]['x'],cmds[i+2]['y']
            # Inner samples reflect the traced sprite's solid color cells.
            points.append([(x0+x1)/400,(y0+y1)/400]);colors.append(np.array(p['color'][:3])*255)
    points=np.array(points);colors=np.array(colors)
    picks=rng.choice(len(points),min(60,len(points)),replace=False)
    templates[name]=(points[picks],colors[picks])
gridx,gridy=np.meshgrid(np.arange(8,354,4),np.arange(8,264,4));centers=np.stack([gridx.ravel(),gridy.ravel()],1)
times=[i for i in range(26,34)]+[38,39,40,43,44,49,50,51,52,53,54,55]
tracks={name:[] for name in sprites}
for idx in times:
    arr=np.asarray(Image.open(ROOT/'.tesseract-work/frames'/f'{idx:03d}.png').resize((360,270))).astype(np.float32)
    for name,(pts,col) in templates.items():
        best=None
        for width in [15,20,27,35,46,60,78,100,126]:
            coords=centers[:,None,:]+pts[None,:,:]*width
            coords=np.round(coords).astype(int)
            valid=(coords[:,:,0].min(1)>=0)&(coords[:,:,0].max(1)<360)&(coords[:,:,1].min(1)>=0)&(coords[:,:,1].max(1)<270)
            cand=centers[valid];coords=coords[valid]
            got=arr[coords[:,:,1],coords[:,:,0]]
            error=np.minimum((got-col[None,:,:])**2,16000).mean((1,2))
            j=int(np.argmin(error));v=float(error[j])
            if best is None or v<best[0]:best=(v,cand[j],width)
        val,center,width=best
        # Refine one coarse solution locally, including size.
        gx,gy=np.meshgrid(np.arange(center[0]-4,center[0]+5),np.arange(center[1]-4,center[1]+5));cs=np.stack([gx.ravel(),gy.ravel()],1)
        for ww in np.linspace(width*.88,width*1.12,7):
            co=np.round(cs[:,None,:]+pts[None,:,:]*ww).astype(int);co[:,:,0]=co[:,:,0].clip(0,359);co[:,:,1]=co[:,:,1].clip(0,269)
            got=arr[co[:,:,1],co[:,:,0]];err=np.minimum((got-col[None,:,:])**2,16000).mean((1,2));j=int(np.argmin(err))
            if err[j]<val:val=float(err[j]);best=(val,cs[j],ww)
        val,center,width=best
        tracks[name].append({'time':round((idx-1)*.25+.125,3),'x':int(center[0])*4,'y':int(center[1])*4,'width':round(width*4,2),'error':round(val,2)})
    print(idx,flush=True)
json.dump(tracks,open(ROOT/'.tesseract-work/tracks.json','w'),indent=2)
sheet=Image.new('RGB',(1440,6*290),'#202020');d=ImageDraw.Draw(sheet)
for j,idx in enumerate(times):
    im=Image.open(ROOT/'.tesseract-work/frames'/f'{idx:03d}.png').resize((360,270));dd=ImageDraw.Draw(im)
    for name,items in tracks.items():
        p=items[j];x=p['x']/4;y=p['y']/4;dd.ellipse((x-4,y-4,x+4,y+4),outline='red',width=1);dd.text((x+4,y),name,fill='red')
    x=(j%4)*360;y=(j//4)*290;sheet.paste(im,(x,y));d.text((x+8,y+273),f'{(idx-1)*.25+.125:.3f}',fill='white')
sheet.save(ROOT/'Previews/Tracking-Review.jpg')

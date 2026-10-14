from pathlib import Path
from collections import deque
from PIL import Image, ImageDraw
import numpy as np, json
ROOT=Path(__file__).resolve().parent.parent
# Sample artwork from the supplied clip; trace it into native color paths.
specs={
 'record':(52,(523,88,677,234),48),
 'book':(52,(639,381,776,470),48),
 'camera':(50,(804,146,1008,284),64),
 'controller':(52,(1185,738,1413,889),48),
 'cap':(52,(782,436,940,555),48),
 'coin':(52,(1022,514,1188,699),32),
 'cash':(52,(178,872,400,1026),48),
 'heart':(65,(566,422,874,671),16),
 'clapper':(50,(257,379,448,579),48),
 'skateboard':(50,(309,234,546,388),48),
 'plant':(50,(278,548,480,784),40),
 'cat':(50,(925,242,1125,432),40),
}
out={};sheet=Image.new('RGB',(960,720),'#dfdfdf');draw=ImageDraw.Draw(sheet)
for i,(name,(frame,box,size)) in enumerate(specs.items()):
    original=Image.open(ROOT/'.tesseract-work/frames'/f'{frame:03d}.png').crop(box)
    w,h=original.size;cw=size;ch=round(size*h/w)
    im=original.resize((cw,ch),Image.Resampling.BOX);arr=np.asarray(im).astype(np.float32)
    sat=arr.max(2)-arr.min(2)
    background=(arr.min(2)>115)&(sat<39)
    visited=np.zeros((ch,cw),bool);q=deque()
    for x in range(cw):q.append((x,0));q.append((x,ch-1))
    for y in range(ch):q.append((0,y));q.append((cw-1,y))
    while q:
        x,y=q.popleft()
        if x<0 or y<0 or x>=cw or y>=ch or visited[y,x] or not background[y,x]:continue
        visited[y,x]=True;q.extend([(x-1,y),(x+1,y),(x,y-1),(x,y+1)])
    # Remove neighboring artwork from crowded wheel samples with authored outlines.
    if name in ['plant','clapper','cat','skateboard','controller','cap']:
        poly={
         'plant':[(0,80),(58,80),(70,20),(130,0),(163,6),(161,76),(192,70),(202,96),(160,143),(170,157),(160,236),(39,236),(25,146),(52,137),(0,107)],
         'clapper':[(5,55),(169,0),(178,0),(178,70),(20,75),(190,95),(190,200),(7,200)],
         'cat':[(0,148),(52,91),(42,30),(56,0),(72,20),(123,20),(158,0),(169,6),(174,112),(154,135),(136,147),(136,180),(105,188),(86,160),(47,146),(30,172)],
         'skateboard':[(0,83),(148,0),(225,0),(225,65),(170,111),(173,143),(142,143),(142,120),(115,136),(106,154),(75,154),(75,134),(39,137),(0,118)],
         'controller':[(12,0),(48,0),(54,10),(143,10),(150,0),(193,0),(227,34),(228,118),(205,144),(169,146),(144,111),(73,109),(46,143),(11,145),(0,116),(0,37)],
         'cap':[(0,85),(28,57),(38,24),(70,6),(92,7),(95,11),(118,17),(143,41),(147,89),(107,77),(87,101),(53,116),(16,106),(1,98)]
        }[name]
        m=Image.new('L',(cw,ch));md=ImageDraw.Draw(m);md.polygon([(x*cw/w,y*ch/h) for x,y in poly],fill=255)
        if name in ['controller','cap']:visited = np.asarray(m)==0
        else:visited |= np.asarray(m)==0
    # Palette grouping keeps individual colors editable while reducing grain noise.
    quant=im.quantize(colors=14,method=Image.Quantize.MEDIANCUT)
    idx=np.asarray(quant);palette=np.array(quant.getpalette()).reshape(-1,3)
    parts=[]
    for c in sorted(set(idx[~visited].ravel().tolist())):
        mask=(idx==c)&~visited;commands=[]
        for y in range(ch):
            xs=np.flatnonzero(mask[y]);j=0
            while j<len(xs):
                start=int(xs[j]);end=start+1;j+=1
                while j<len(xs) and xs[j]==end:end+=1;j+=1
                x0=start/cw*200-100;x1=end/cw*200-100
                y0=y/cw*200-h/w*100;y1=(y+1)/cw*200-h/w*100
                commands += [{'type':'moveTo','x':x0,'y':y0},{'type':'lineTo','x':x1,'y':y0},{'type':'lineTo','x':x1,'y':y1},{'type':'lineTo','x':x0,'y':y1},{'type':'close'}]
        if commands:parts.append({'color':[*[round(float(x)/255,4) for x in palette[c]],1],'commands':commands})
    out[name]={'parts':parts,'aspect':h/w,'sourceFrame':frame,'sourceBox':box,'grid':[cw,ch]}
    x=(i%4)*240;y=(i//4)*240
    draw.text((x+8,y+6),name,fill='black');sheet.paste(original.resize((min(w,210),min(h,175))),(x+10,y+30))
    draw.text((x+8,y+215),f'{len(parts)} editable color paths',fill='black')
json.dump(out,open(ROOT/'.tesseract-work/native-sprites.json','w'))
sheet.save(ROOT/'Previews/Sprite-Sources.jpg')
print({k:len(v['parts']) for k,v in out.items()})

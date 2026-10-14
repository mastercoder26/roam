from pathlib import Path
import json, math, random, copy
ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'.tesseract-work'
sprites=json.load(open(WORK/'native-sprites.json'))
doc=json.load(open(WORK/'imported.json'))
doc['dimensions']={'width':1440,'height':1080};doc['duration']=20.459
doc['composition']['name']='Watkins — editable recreation'
doc['composition']['motionBlur']={'enabled':True,'samplesPerFrame':8,'shutterAngle':140,'shutterPhase':-70,'adaptiveSampleLimit':16}
layers=[];entries=[];next_id=0
def ident():
    global next_id
    next_id+=1;return next_id
def ms(t):return round(t*1000)
def transform(x=0,y=0,scale=100,rotation=0,anchor=(0,0)):
    return {'anchorPoint':list(anchor),'position':[x,y],'scale':[scale,scale],'rotation':rotation,'opacity':100}
def playback(start,end,source=0):
    d=ms(end-start)
    return {'type':'windowed','inputRange':{'start':ms(start),'duration':d},'mapping':{'type':'linear','input':{'start':ms(start),'duration':d},'output':{'start':ms(source),'duration':d}},'inputOffsetMs':0}
def base(kind,name,start,end,x=0,y=0):
    return {'type':kind,'id':ident(),'name':name,'blendMode':'normal','activeRange':{'start':ms(start),'duration':ms(end-start)},'transform':transform(x,y)}
def kf(layer,prop,keys,start=0,kind='float',ease='linear'):
    kk=[]
    for j,(t,v) in enumerate(keys):
        kk.append({'id':f'{layer["id"]}-{prop}-{j}','layerTime':ms(t-start),'value':{'type':kind,'value':v},'easing':{'type':ease}})
    entries.append({'target':{'kind':'layer','layerId':layer['id'],'propertyType':prop},'animator':{'type':'keyframes','enabled':True,'keyframes':kk}})
def expr(layer,prop,code):
    entries[:] = [e for e in entries if not (e['target']['layerId']==layer['id'] and e['target']['propertyType']==prop)]
    entries.append({'target':{'kind':'layer','layerId':layer['id'],'propertyType':prop},'animator':{'type':'jsScript','layerTimeJsCode':code}})
def effect(layer,typ,**params):
    layer.setdefault('effects',[]).append({'id':ident(),'effect':{'type':typ,**params}})
GRAIN_WGSL='''
struct VertexInput { @location(0) position:vec2<f32>, @location(1) tex_coords:vec2<f32>, @location(2) color:vec4<f32> };
struct VertexOutput { @builtin(position) clip_position:vec4<f32>, @location(0) tex_coords:vec2<f32> };
@vertex fn vs_main(i:VertexInput)->VertexOutput { var o:VertexOutput; o.clip_position=vec4<f32>(i.position,0.,1.);o.tex_coords=i.tex_coords;return o; }
struct Params { animationTime:f32, amount:f32, _pad0:f32, _pad1:f32 };
@group(0) @binding(0) var tex:texture_2d<f32>;
@group(0) @binding(1) var samp:sampler;
@group(0) @binding(2) var<uniform> p:Params;
@fragment fn fs_main(i:VertexOutput)->@location(0) vec4<f32> {
let c=textureSample(tex,samp,i.tex_coords);let px=floor(i.tex_coords*vec2<f32>(textureDimensions(tex)));
let grain=fract(sin(dot(px,vec2<f32>(12.9898,78.233))+floor(p.animationTime*24.)*19.17)*43758.5453)-0.5;
return vec4<f32>(clamp(c.rgb+vec3<f32>(grain*p.amount*c.a),vec3<f32>(0.),vec3<f32>(c.a)),c.a);
}'''
def grain(layer,amount=.038):
    effect(layer,'customShader',name='Monochrome film grain',description='Fine neutral grain matching the reference, independently adjustable.',wgsl=GRAIN_WGSL,params=[{'name':'animationTime','description':'Local render clock in seconds','min':0,'max':21,'default':0},{'name':'amount','description':'Neutral grain amplitude','min':0,'max':.15,'default':amount}])
def rect(name,start,end,x,y,w,h,color):
    l=base('Rect',name,start,end,x,y);l['rect']={'size':[w,h],'fillColor':color};return l
def fill(c):return {'paint':{'type':'solid','color':c},'fillRule':'nonZeroWinding','blendMode':'normal','opacity':100}
def shape(name,start,end,commands,color=None,stroke=None,width=2,x=0,y=0):
    l=base('Shape',name,start,end,x,y);l['shape']={'path':{'commands':commands},'fills':[] if color is None else [fill(color)],'strokes':[]}
    if stroke:l['shape']['strokes']=[{'paint':{'type':'solid','color':stroke},'width':width,'cap':'round','join':'round','miterLimit':4,'blendMode':'normal','opacity':100}]
    return l
def text(name,content,start,end,x,y,size,color=(.08,.055,.04,1),center=False):
    l=base('Text',name,start,end,x,y)
    l['sourceText']={'text':content,'fontFamily':'Helvetica','fontStyle':'Bold','fontSize':size,'fillColor':list(color),'strokeWidth':0,'justification':'center' if center else 'left','tracking':-1}
    return l
def group(name,start,end,children,x=0,y=0,scale=100,rotation=0):
    return {'type':'Group','id':ident(),'name':name,'blendMode':'normal','playback':playback(start,end),'transform':transform(x,y,scale,rotation),'layers':children}
def icon(name,start,end,x,y,width,rotation=0):
    parts=[shape(f'{name} • color {i+1}',0,end-start,p['commands'],p['color']) for i,p in enumerate(sprites[name]['parts'])]
    g=group(f'{name.title()} • editable pixel art',start,end,parts,x,y,width/2,rotation)
    return g
def pose(layer,poses,start):
    for prop,col in [('positionX',1),('positionY',2),('scaleX',3),('scaleY',3),('rotation',4)]:
        kf(layer,prop,[(p[0],p[col] if col!=3 else p[col]/2) for p in poses],start)
def M(x,y):return {'type':'moveTo','x':x,'y':y}
def L(x,y):return {'type':'lineTo','x':x,'y':y}
def C(a,b,c,d,x,y):return {'type':'cubicTo','c1x':a,'c1y':b,'c2x':c,'c2y':d,'x':x,'y':y}
def ellipse(rx,ry):
    return [M(rx,0),C(rx,ry*.552,rx*.552,ry,0,ry),C(-rx*.552,ry,-rx,ry*.552,-rx,0),C(-rx,-ry*.552,-rx*.552,-ry,0,-ry),C(rx*.552,-ry,rx,-ry*.552,rx,0),{'type':'close'}]
def star(name,start,end,x,y,sx,sy,color):
    cmds=[M(0,-sy),C(5,-sy*.12,sx*.1,-8,sx,0),C(sx*.1,8,5,sy*.12,0,sy),C(-5,sy*.12,-sx*.1,8,-sx,0),C(-sx*.1,-8,-5,-sy*.12,0,-sy),{'type':'close'}]
    return shape(name,start,end,cmds,color,x=x,y=y)
def scribble(name,start,end,x,y,scale=1,color=(.19,.08,.055,1),seed=1,width=3):
    r=random.Random(seed);cmds=[M(0,0)]
    for j in range(5):
        cmds.append(C(r.uniform(-55,55)*scale,r.uniform(-90,90)*scale,r.uniform(-90,90)*scale,r.uniform(-120,120)*scale,r.uniform(-110,110)*scale,r.uniform(-130,130)*scale))
    l=shape(name,start,end,cmds,stroke=color,width=width,x=x,y=y)
    kf(l,'rotation',[(start,-12),(end-0.02,35)],start);return l
def paper(name,start,end,strong=False,red=False):
    color=[.84,.845,.83,1] if not red else [.84,.02,.015,1]
    l=rect(name,start,end,0,0,1440,1080,color)
    grain(l,.042)
    if strong:effect(l,'vignette',amount=.72,radius=.64,feather=.8)
    return l
def black(name,start,end):
    l=rect(name,start,end,0,0,1440,1080,[.057,.058,.055,1]);grain(l,.025);return l
# Original mix, isolated from all image layers to prevent doubled sound.
layers.append({'type':'Audio','id':ident(),'name':'ORIGINAL AUDIO • unchanged stereo mix','source':{'assetId':'original-audio'},'sourceRange':{'start':0,'duration':20459},'sourceIntrinsicDuration':20459,'playback':playback(0,20.459),'volume':1,'captionsEnabled':False})
# Opening oversized type collapses into a sentence, then the iris/star reveal.
opening=text('Opening question • editable type','how',0,3.96,400,640,270)
kf(opening,'textContent',[(0,'how'),(.28,'how do'),(.7,'how do you communicate'),(1.0,'how do you communicate that'),(1.3,"how do you communicate that you're"),(1.55,"how do you communicate that you're going"),(1.8,"how do you communicate that you're going through"),(2.08,"how do you communicate that you're going through a change?")],0,'string','hold')
kf(opening,'fontSize',[(0,270),(.3,270),(.58,62),(.76,40.5)],0)
kf(opening,'positionX',[(0,400),(.3,-180),(.65,65),(.76,55)],0)
kf(opening,'positionY',[(0,640),(.35,640),(.76,550)],0)
layers.append(opening)
for s,e in [(0,.23),(.72,.98)]:
    for yy in [360,630] if s==0 else [495,572]:
        l=shape('Typographic registration guide',s,e,[M(0,yy),L(1440,yy)],stroke=[.17,.08,.055,1],width=2)
        l['shape']['strokes'][0]['dashes']=[20,25];layers.append(l)
for s,e,x,y,sc,seed in [(.30,.51,620,500,1.5,8),(.75,1.02,270,650,.9,2),(1.05,1.34,810,650,.8,4),(1.37,1.58,720,680,1.1,5),(2.1,2.7,1230,260,.45,3),(2.26,2.53,510,870,.65,1)]:
    layers.append(scribble('Opening handwritten gesture',s,e,x,y,sc,seed=seed))
# Native colored quatrefoil and the warm transition flare.
st=star('Cyan / blue iris star • editable curves',2.16,3.99,150,530,660,1400,[.015,.78,.84,1])
kf(st,'rotation',[(2.16,14),(2.6,24),(3.8,35)],2.16)
st['shape']['fills'][0]['paint']={'type':'gradient','gradientType':'linear','start':[-170,-100],'end':[350,100],'stops':[{'offset':0,'color':[.04,.07,.96,1]},{'offset':.62,'color':[.01,.85,.80,1]},{'offset':1,'color':[.09,.75,.80,1]}]}
kf(st,'opacity',[(2.16,100),(3.7,100),(3.82,0)],2.16)
effect(st,'gaussianBlur',blurriness=8);layers.append(st)
for name,x,y,w in [('book',760,355,82),('clapper',1040,350,87),('coin',900,665,94),('camera',1080,868,94)]:
    g=icon(name,2.10,3.34,x,y,w,15 if name=='clapper' else -10)
    kf(g,'scaleX',[(2.10,0),(2.24,w/2),(3.20,w/2),(3.34,0)],2.10);kf(g,'scaleY',[(2.10,0),(2.24,w/2),(3.20,w/2),(3.34,0)],2.10)
    layers.append(g)
flare=shape('Red change / lens flare',3.7,4.15,ellipse(270,280),[.82,.025,.01,1],x=435,y=530)
effect(flare,'gaussianBlur',blurriness=100);kf(flare,'opacity',[(3.7,0),(3.84,90),(4.15,0)],3.7);layers.append(flare)
layers.append(paper('Paper • opening',0,3.82,False))
layers.append(paper('Paper • iris vignette',2.13,3.82,True))
layers.append(rect('Yellow opening flash',.065,.21,0,0,1440,1080,[.91,.67,.035,1]))
# Original human footage remains native video; words are independently editable.
for name,s,e in [('Thermal profile / live profile',3.82,6.50),('Thermal hand performance',13.74,16.02)]:
    l={'type':'Video','id':ident(),'name':name+' • source footage','blendMode':'normal','source':{'assetId':'thermal-people','fit':'contain'},'sourceRange':{'start':ms(s),'duration':ms(e-s)},'sourceIntrinsicDuration':20395,'playback':playback(s,e,s),'transform':transform(),'volume':0}
    layers.append(l)
for s,e,content in [(3.99,5.29,'you dont.'),(5.29,5.48,'you'),(5.48,5.71,'you just'),(5.71,5.97,'you just show'),(5.97,6.31,'you just show it.')]:
    layers.append(text('Profile phrase • '+content,content,s,e,205,557,39,[.94,.94,.9,1] if s<5.99 else [.10,.08,.07,1]))
for s,e,content in [(13.81,14.15,'through'),(14.15,16.02,'through ones')]:layers.append(text('Hand / left phrase',content,s,e,207,556,39,[.94,.94,.9,1]))
for s,e,content in [(14.3,14.48,'own'),(14.48,15.82,'own ability'),(15.82,16.02,'own ability to')]:layers.append(text('Hand / right phrase',content,s,e,936,556,39,[.94,.94,.9,1]))
# Poses measured from the supplied reference. Width is on-canvas pixels.
names=['skateboard','record','book','camera','cat','coin','controller','cap','heart','cash','plant','clapper']
wheelA={
 'skateboard':[(6.52,970,620,390,0),(6.68,1050,620,360,0),(6.9,485,400,180,0),(7.15,460,380,180,0),(7.4,460,375,175,0),(7.65,470,380,170,0),(7.9,492,388,170,0),(8.24,600,368,173,0)],
 'record':[(6.52,710,700,450,0),(6.68,760,650,450,0),(6.9,535,295,180,0),(7.15,579,290,174,0),(7.4,595,290,170,0),(7.65,620,290,174,0),(7.9,637,290,170,0),(8.24,720,311,180,0)],
 'book':[(6.52,350,630,360,0),(6.68,390,670,330,0),(6.9,690,240,170,0),(7.15,720,285,173,0),(7.4,750,290,165,0),(7.65,768,297,174,0),(7.9,780,305,170,0),(8.24,863,330,180,0)],
 'camera':[(6.52,290,535,240,0),(6.68,330,535,240,0),(6.9,850,237,170,0),(7.15,852,290,184,0),(7.4,875,298,185,0),(7.65,870,319,185,0),(7.9,873,319,184,0),(8.24,965,368,180,0)],
 'cat':[(6.52,410,440,175,0),(6.68,390,460,175,0),(6.9,1000,265,155,0),(7.15,978,340,160,0),(7.4,1000,338,170,0),(7.65,1002,345,175,0),(7.9,1002,356,170,0),(8.24,1075,421,180,0)],
 'coin':[(6.52,470,380,175,0),(6.68,470,390,170,0),(6.9,1085,295,170,0),(7.15,1120,416,180,0),(7.4,1120,427,214,0),(7.65,1120,437,190,0),(7.9,1120,439,186,0),(8.24,1160,495,206,0)],
 'controller':[(6.52,585,350,180,0),(6.68,590,355,180,0),(6.9,1210,320,195,0),(7.15,1160,515,206,0),(7.4,1170,533,254,0),(7.65,1170,555,225,0),(7.9,1170,553,226,0),(8.24,1140,612,265,0)],
 'cap':[(6.52,725,330,180,0),(6.68,725,335,180,0),(6.9,1230,430,205,0),(7.15,1080,642,249,0),(7.4,1130,640,285,0),(7.65,1140,676,267,0),(7.9,1130,679,276,0),(8.24,1007,699,328,0)],
 'heart':[(6.52,865,300,195,0),(6.68,865,337,194,0),(6.9,1120,555,380,0),(7.15,899,685,407,0),(7.4,851,760,412,0),(7.65,883,756,430,0),(7.9,890,748,411,0),(8.24,741,673,414,0)],
 'cash':[(6.52,975,325,205,0),(6.68,1000,363,196,0),(6.9,904,650,438,0),(7.15,606,673,379,0),(7.4,598,691,349,0),(7.65,572,690,373,0),(7.9,588,675,339,0),(8.24,530,588,304,0)],
 'plant':[(6.52,1120,330,170,0),(6.68,1115,360,169,0),(6.9,650,661,316,0),(7.15,348,596,285,0),(7.4,350,526,285,0),(7.65,350,513,283,0),(7.9,375,499,254,0),(8.24,468,498,258,0)],
 'clapper':[(6.52,1200,440,210,0),(6.68,1215,450,207,0),(6.9,470,591,295,0),(7.15,387,463,237,0),(7.4,382,457,226,0),(7.65,402,421,227,0),(7.9,433,411,222,0),(8.24,471,420,198,0)]
}
for name in names:
    poses=wheelA[name];g=icon(name,6.5,8.27,*poses[0][1:4],poses[0][4]);pose(g,poses,6.5);layers.append(g)
layers.append(paper('Paper • first icon orbit',6.5,8.27))
# Fast foreshortened icon carousel sections (independent transforms).
for start,end,shift in [(9.30,10.02,0),(10.55,11.02,680)]:
    for i,name in enumerate(names):
        # Sequence across a depth-flattened oval; foreground enlarges as it passes.
        phase=i*math.tau/12
        g=icon(name,start,end,720,545,160)
        code=f'var t=input.time.seconds;var a={phase}+t*3.0+{shift/300};'
        expr(g,'positionX',code+'return 720+500*Math.cos(a);')
        expr(g,'positionY',code+'return 545+65*Math.sin(a);')
        expr(g,'scaleX',code+'return 48+82*(Math.sin(a)+1)/2;')
        expr(g,'scaleY',code+'return 48+82*(Math.sin(a)+1)/2;')
        layers.append(g)
    layers.append(paper('Paper • horizontal carousel',start,end))
# Three black feature beats: action, intention, curiosity.
for name,label,s,e,width in [('camera','action.',8.27,9.30,346),('book','intention.',10.02,10.55,430),('record','curiosity.',11.02,12.00,342)]:
    g=icon(name,s,e,430,535,width)
    kf(g,'rotation',[(s,-12),(s+.20,0),(e-.10,12)],s)
    if name=='camera':
        kf(g,'scaleX',[(s,170),(s+.23,170),(s+.55,70),(s+.7,210),(e-.01,250)],s)
        kf(g,'scaleY',[(s,170),(s+.23,170),(s+.55,240),(s+.7,80),(e-.01,35)],s)
    if name=='record':expr(g,'rotation','return input.time.seconds*150;')
    layers.append(g)
    layers.append(text(label+' • editable label',label,s+.14,e,850 if name=='camera' else 840,560,55,[.95,.95,.9,1]))
    cursor=rect('Typing caret',s+.16,e,1210,515,9,57,[.95,.95,.9,1]);expr(cursor,'opacity','return Math.floor(input.time.seconds*7)%2?0:100;');layers.append(cursor)
    if name=='camera':
        q=star('Red camera flash • curves',s,e,565,360,170,340,[.95,.015,.015,1]);kf(q,'rotation',[(s,5),(e-.01,30)],s);layers.append(q)
    if name=='book':
        ribbon=shape('Intention • red ribbon',s,e,[M(0,800),C(400,450,750,600,1440,-120),L(1440,-40),C(690,700,430,600,0,900),{'type':'close'}],[.94,.01,.01,1]);layers.append(ribbon)
    if name=='record':
        for j,(x,y,sz,r) in enumerate([(590,280,220,10),(680,800,200,-15),(970,810,150,-25)]):
            # Draw the notes as native curves to avoid unsupported font glyphs.
            commands=ellipse(20,14)+[M(18,0),L(18,-100),L(75,-113),L(75,-17),L(66,-17),L(66,-84),L(27,-75),L(27,0),{'type':'close'}]
            n=shape('Editable red music note',s+.2+j*.12,e,commands,[.94,.025,.02,1],x=x,y=y)
            n['transform']['scale']=[sz/150*100,sz/150*100];n['transform']['rotation']=r;layers.append(n)
    layers.append(black('Charcoal • '+label,s,e))
# Return to a circular orbit, followed by the independent scatter.
order=['record','book','camera','cat','coin','controller','cap','heart','cash','plant','clapper','skateboard']
scatter={'record':(595,154,135),'book':(715,425,140),'camera':(950,345,124),'cat':(1110,745,160),'coin':(1130,619,164),'controller':(1310,822,219),'cap':(880,495,159),'heart':(539,621,142),'cash':(295,949,219),'plant':(230,480,159),'clapper':(145,480,191),'skateboard':(460,490,155)}
for i,name in enumerate(order):
    angle=-2.02+i*math.tau/12;x=720+427*math.cos(angle);y=540+395*math.sin(angle)
    w=190 if name not in ['heart','cash','cap','clapper','plant'] else 230
    tx,ty,tw=scatter[name]
    poses=[(12.00,x,y,w,0),(12.37,x,y,w,0),(12.66,tx,ty,tw,0),(13.30,tx+(i%3-1)*35,ty+(i%2)*22,tw,0),(13.74,tx+(i%3-1)*75,ty+(i%2)*38,tw,0)]
    g=icon(name,12.00,13.74,x,y,w);pose(g,poses,12);layers.append(g)
layers.append(paper('Paper • final orbit / scatter',12,13.74,True))
# Ink swooshes and marks, each native and adjustable.
for j,(s,e,x,y) in enumerate([(6.6,7.35,850,420),(7.2,7.65,750,190),(7.6,8.10,310,555),(8.0,8.26,750,560),(12.07,12.50,565,470),(12.58,13.05,960,700),(13.0,13.53,1200,595),(13.3,13.74,200,765)]):
    blob=shape('Ink smear • editable soft shape',s,e,[M(-30,-35),C(-65,-22,-44,35,-10,75),C(10,155,60,220,10,310),C(40,255,30,165,25,70),C(55,15,55,-30,-30,-35),{'type':'close'}],[.04,.035,.03,1],x=x,y=y)
    blob['shape']['fills'][0]['paint']={'type':'gradient','gradientType':'linear','start':[0,-35],'end':[0,310],'stops':[{'offset':0,'color':[.025,.02,.02,.94]},{'offset':.3,'color':[.03,.03,.03,.8]},{'offset':1,'color':[.03,.03,.03,0]}]}
    effect(blob,'gaussianBlur',blurriness=18)
    kf(blob,'positionY',[(s,y-170),(s+(e-s)*.5,y),(e-.01,y+140)],s)
    kf(blob,'scaleY',[(s,40),(s+(e-s)*.4,130),(e-.01,30)],s);layers.insert(1,blob)
for j,(s,e,x,y) in enumerate([(12.71,12.96,420,200),(12.78,13.04,800,225),(13.12,13.36,1110,880),(13.27,13.62,840,780)]):layers.insert(1,scribble('Ink handwriting / scatter',s,e,x,y,.95,seed=10+j,width=5))
# LOVE feature flash sequence: source assets recreated as native pixel paths.
for name,s,e,width in [('heart',16.02,16.30,310),('camera',16.30,16.52,260),('book',16.52,16.77,165),('record',16.77,17.25,255)]:
    g=icon(name,s,e,720,535,width)
    if name=='record':kf(g,'scaleX',[(s,10),(s+.12,width/2),(e-.01,width/2)],s);expr(g,'rotation','return input.time.seconds*155;')
    else:kf(g,'rotation',[(s,-12),(e-.01,12)],s)
    layers.append(g)
    if name=='heart':layers.append(paper('Love • pale flash',s,e))
    elif name=='book':layers.append(paper('Love • red flash',s,e,red=True))
    else:layers.append(black('Love • charcoal flash',s,e))
for i,ch in enumerate('LOVE'):
    s=16.02+i*.23
    love=text('LOVE • letter '+ch,ch,s,17.25,110+i*390,555,55,[.94,.94,.9,1]);layers.append(love)
    if i==0:kf(love,'fillColor',[(s,[.14,.08,.05,1]),(16.30,[.94,.94,.9,1])],s,'color','hold')
# Closing glyphs orbit gently, with a sparse four-corner arrangement.
dest=[(360,300),(920,300),(460,868),(1200,868)]
for i,ch in enumerate('VOLE'):
    x,y=dest[i];l=text('Closing editable glyph '+ch,ch,17.25,20.459,x,y,48,[.15,.06,.04,1],True)
    kf(l,'positionX',[(17.25,x+(i%2*2-1)*220),(18.00,x),(20.20,x)],17.25)
    kf(l,'positionY',[(17.25,y+(-1 if i<2 else 1)*120),(18.0,y),(20.20,y)],17.25)
    kf(l,'rotation',[(17.25,190-i*30),(18.0,95+i*15),(19.1,10),(20.15,0)],17.25)
    layers.append(l)
    for s,e in [(17.3,17.70),(19.45,19.70),(19.85,20.23)]:layers.append(scribble('Closing red loop • letter '+ch,s,e,x,y,.58,[.73,.14,.10,.6],seed=42+i,width=1.3))
for x,y in [(235,625),(730,350),(1070,415),(805,665)]:layers.append(shape('Closing separator dot',17.25,20.459,ellipse(4,4),[.14,.075,.05,1],x=x,y=y))
for j,(x,y) in enumerate([(200,330),(810,680),(1230,330)]):layers.append(scribble('Closing large ink flourish',17.25,17.62,x,y,2,[.12,.09,.06,.7],seed=53+j,width=8))
cat=icon('cat',20.25,20.459,860,560,440)
kf(cat,'scaleX',[(20.25,1),(20.34,200)],20.25);kf(cat,'scaleY',[(20.25,1),(20.34,200)],20.25);layers.append(cat)
layers.append(scribble('Final red flower loop',20.25,20.459,870,530,2,[.80,.08,.04,.9],seed=74,width=2))
layers.append(paper('Paper • closing glyphs',17.25,20.459))
# Sparse grain flecks, kept native to avoid a baked overlay.
rand=random.Random(17)
for j in range(24):
    x=rand.randrange(80,1360);y=rand.randrange(70,1010);r=rand.uniform(.8,2.6)
    l=shape('Editable paper / film speck',0,20.459,ellipse(r,r*1.7),[.23,.16,.11,.24],x=x,y=y)
    expr(l,'opacity',f'return Math.floor(input.time.seconds*8+{j})%11<3?45:0;')
    layers.insert(1,l)
# Layer order is frontmost-first. Keep graphics over footage and backgrounds.
exec((WORK/'refine.py').read_text())
front=[l for l in layers if l['type'] not in ['Video'] and not ('Paper •' in l['name'] or l['name'].startswith(('Charcoal •','Love •','Yellow opening')))]
videos=[l for l in layers if l['type']=='Video']
backs=[l for l in layers if ('Paper •' in l['name'] or l['name'].startswith(('Charcoal •','Love •','Yellow opening')))]
# More specific background windows appear above the general opening paper.
backs.sort(key=lambda l: l.get('activeRange',{}).get('start',0),reverse=True)
doc['composition']['layers']=front+videos+backs
doc['composition']['dynamics']={'entries':entries}
json.dump(doc,open(WORK/'editable.json','w'),indent=2)
def count(items):return sum(1+count(l.get('layers',[])) for l in items)
print(f'{count(doc["composition"]["layers"])} native layers; {len(entries)} animation tracks')

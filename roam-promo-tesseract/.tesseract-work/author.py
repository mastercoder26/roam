from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent.parent;W=ROOT/'.tesseract-work'
doc=json.load(open(W/'editable.json'))
doc['dimensions']={'width':1920,'height':1080};doc['duration']=24
doc['composition']['name']='Roam / A little more confidence'
layers=[];actions=[];counter=0
def ident():
 global counter
 counter+=1;return counter
def transform(x=0,y=0,s=100,a=(0,0)):
 return {'anchorPoint':list(a),'position':[x,y],'scale':[s,s],'rotation':0,'opacity':100}
def base(kind,name,start,end,x=0,y=0):
 return {'id':ident(),'type':kind,'name':name,'blendMode':'normal','activeRange':{'start':round(start*1000),'duration':round((end-start)*1000)},'transform':transform(x,y)}
def animate(l,prop,code):
 actions.append({'type':'setFxPropertyAnimator','compositionId':'main','property':{'layerId':l['id'],'propertyType':prop},'animator':{'type':'jsScript','layerTimeJsCode':code},'dependencies':[]})
def rise(l,y,duration=4,delay=0):
 animate(l,'positionY',f'var t=Math.max(0,input.time.seconds-{delay});var q=Math.max(0,Math.min(1,t/.65));var e=1-Math.pow(1-q,4);return {y}+(1-e)*48;')
 animate(l,'opacity',f'var t=input.time.seconds;return 100*Math.min(1,Math.max(0,(t-{delay})/.25))*Math.min(1,Math.max(0,({duration}-t)/.20));')
def text(words,x,y,size,start,end,color='#18203b',style='Bold',width=820):
 l=base('Text',words.replace('\n',' / '),start,end,x,y)
 c=[int(color[i:i+2],16)/255 for i in (1,3,5)]+[1]
 l['sourceText']={'text':words,'fontFamily':'Avenir Next','fontStyle':style,'fontSize':size,'fillColor':c,'strokeWidth':0,'justification':'left','tracking':-1.2 if size>70 else 0,'leading':size*1.13,'boxText':True,'boxPosition':[0,0],'boxSize':[width,400]}
 layers.append(l);rise(l,y,end-start);return l
def rect(name,x,y,w,h,start,end,color,r=0):
 l=base('Rect',name,start,end,x,y);l['rect']={'size':[w,h],'fillColor':color,'roundness':r};layers.append(l);return l
def image(asset,name,x,y,scale,start,end,anchor=(0,0)):
 l=base('Image',name,start,end,x,y);l['source']={'assetId':asset,'fit':'contain'};l['transform']=transform(x,y,scale,anchor);layers.append(l);return l
def playback(start,dur):
 return {'type':'windowed','inputRange':{'start':round(start*1000),'duration':round(dur*1000)},'mapping':{'type':'linear','input':{'start':0,'duration':round(dur*1000)},'output':{'start':0,'duration':round(dur*1000)}},'inputOffsetMs':0}
def audio(asset,name,start,dur,total,volume):
 l={'type':'Audio','id':ident(),'name':name,'source':{'assetId':asset},'sourceRange':{'start':0,'duration':round(dur*1000)},'sourceIntrinsicDuration':round(total*1000),'playback':playback(start,dur),'volume':volume,'captionsEnabled':False};layers.append(l);return l

# Frontmost: a single directional wipe grammar, covering the object match cuts.
for at in [4,10,14,18]:
 l=rect('Roam blue scene wipe',-2300,0,2250,1080,at-.4,at+.4,[.192,.345,.831,1])
 animate(l,'positionX','var q=Math.max(0,Math.min(1,input.time.seconds/.8));var e=q*q*(3-2*q);return -2300+4300*e;')
# Quiet persistent brand signature.
image('wordmark','Roam brand signature',100,69,83,0,18)
# Compact headlines that say what the product does.
text('New driver.\nBig world.',105,314,108,0,4)
text('Meet Roam.',110,618,32,.35,4,color='#3158d4',style='Regular')
text('Know the road\nbefore you go.',105,305,95,4,10)
text('Plan routes. See the tricky parts.',110,593,31,4.4,10,color='#5f656b',style='Regular')
screen=image('route-ui','Actual Roam route-planning UI crop',1095,250,62,4.25,9.85)
screen['cornerRadius']=.10
screen['dropShadow']={'enabled':True,'color':[.08,.11,.18,.24],'blurRadius':38,'spreadRadius':0,'offset':[0,18],'blendMode':'normal'}
rise(screen,250,5.6)
animate(screen,'rotation','return -3+Math.sin(input.time.seconds*.6)*1.2;')
text('Practice.\nOne drive\nat a time.',105,272,94,10,14)
text('Record the drive. Learn from it.',110,656,30,10.35,14,color='#5f656b',style='Regular')
text('See how far\nyou’ve come.',105,310,96,14,18)
text('Your miles. Your progress.',110,610,32,14.35,18,color='#5f656b',style='Regular')
# Deliberately spacious end card, with the supplied exact logo.
logo=image('wordmark','Roam end-card wordmark',86,210,220,18,24)
rise(logo,210,6)
text('Build confidence.\nGo roam.',105,436,82,18.35,24)
text('Your driving journey starts here.',110,683,30,18.75,24,color='#5f656b',style='Regular')

# A full native procedural 3D scene behind each beat.
shader=(W/'world.wgsl').read_text()
shots=[(0,4,0),(4,10,1),(10,14,2),(14,18,3),(18,24,4)]
for start,end,shot in shots:
 l=base('Rect',f'3D miniature world / shot {shot+1}',start,end)
 l['rect']={'size':[1920,1080],'fillColor':[1,1,1,1]}
 l['effects']=[{'id':100+shot,'effect':{'type':'customShader','name':'RoamMiniatureWorld','description':'Lit solid car, tires, windows, roads, trees and growth pillars, modeled with signed distance geometry. Orthographic camera, contact shadows, restrained motion.','wgsl':shader,'params':[
 {'name':'animationTime','description':'Engine time in seconds.','min':0,'max':24,'default':0},
 {'name':'shot','description':'Scene selector: 0 hero, 1 route, 2 drive, 3 progress, 4 signoff.','min':0,'max':4,'default':shot},
 {'name':'camera','description':'Reserved camera control.','min':0,'max':10,'default':0},
 {'name':'start','description':'Scene in-point in seconds.','min':0,'max':24,'default':start}], 'textureInputs':[]}}]
 layers.append(l)

audio('music','Original electric keys and bass',0,24,24,.82)
audio('drums','Original swung drums',0,24,24,.80)
for t in [3.62,9.62,13.62,17.62]:audio('whoosh','Soft directional transition',t,.6,.6,.35)
for t in [14.25,14.47,14.69]:audio('pop','Progress pillar soft pop',t,.22,.22,.38)
audio('impact','Opening car accent',.12,.4,.4,.35)
doc['composition']['layers']=layers
json.dump(doc,open(W/'authored.json','w'),indent=2)
json.dump(actions,open(W/'animations.json','w'),indent=2)
print(f'Authored {len(layers)} editable layers and {len(actions)} motion controls.')

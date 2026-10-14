"""Frame-measured orbital poses, native ink ribbons and thermal impacts."""
# Executed by build.py in its authoring namespace.
def all_ids(l):
    return {l['id']} | set().union(*(all_ids(c) for c in l.get('layers',[])))
remove=set()
for l in layers:
    n=l['name'];s=l.get('playback',{}).get('inputRange',{}).get('start',-1)
    if n.startswith(('Ink smear','Ink handwriting')) or (l['type']=='Group' and s in [6500,9300,10550,12000]):remove|=all_ids(l)
layers[:]=[l for l in layers if l['id'] not in remove]
entries[:]=[e for e in entries if e['target']['layerId'] not in remove]

def interp(rows,t):
    if t<=rows[0][0]:return rows[0][1:]
    if t>=rows[-1][0]:return rows[-1][1:]
    for a,b in zip(rows,rows[1:]):
        if a[0]<=t<=b[0]:
            f=(t-a[0])/(b[0]-a[0]);return tuple(x+(y-x)*f for x,y in zip(a[1:],b[1:]))

HEAT_WGSL=GRAIN_WGSL.replace('amount:f32, _pad0:f32, _pad1:f32','amount:f32, hitTime:f32, strength:f32').replace(
    'return vec4<f32>(clamp(c.rgb+vec3<f32>(grain*p.amount*c.a),vec3<f32>(0.),vec3<f32>(c.a)),c.a);',
    '''let falloff=1.-.8*smoothstep(.08,.64,length(i.tex_coords-vec2<f32>(.5,.5)));
    let pulse=exp(-pow((p.animationTime-p.hitTime)/0.10,2.))*p.strength*falloff;
    let lum=dot(c.rgb,vec3<f32>(.299,.587,.114))/max(c.a,.001);
    let heat=vec3<f32>(.95,.40+.27*lum,.025)*c.a;
    let rgb=mix(c.rgb,heat,pulse)+vec3<f32>(grain*p.amount*c.a);
    return vec4<f32>(clamp(rgb,vec3<f32>(0.),vec3<f32>(c.a)),c.a);''')
def film_icon(g,hit=None):
    g['motionBlur']=True
    effect(g,'gaussianBlur',blurriness=.65)
    if hit is None:grain(g,.048)
    else:effect(g,'customShader',name='Warm ink impact',description='Frame-matched orange impact, with neutral film grain.',wgsl=HEAT_WGSL,params=[{'name':'animationTime','min':0,'max':21,'default':0},{'name':'amount','min':0,'max':.15,'default':.055},{'name':'hitTime','min':0,'max':21,'default':hit},{'name':'strength','min':0,'max':1,'default':.9}])
def native_scene(title,s,e,tracks,heats=None,blacken=None):
    # Depth order is determined from the measured on-screen size of each pose.
    sequence=sorted(tracks,key=lambda n:interp(tracks[n],(s+e)/2)[2],reverse=True)
    children=[]
    for name in sequence:
        rows=tracks[name];x,y,w,r=interp(rows,s)
        g=icon(name,0,e-s,x,y,w,r)
        times=sorted({s,e-0.0001}|{row[0] for row in rows if s<row[0]<e})
        pose(g,[(t-s,*interp(rows,t)) for t in times],0)
        film_icon(g,None if not heats or name not in heats else heats[name]-s)
        if blacken and name in blacken:
            at=blacken[name]-s
            for part in g['layers']:
                color=part['shape']['fills'][0]['paint']['color']
                keys=[(0,color)]+([(at-.04,color)] if at>.041 else [])+[(max(.001,at+.06),[.025,.024,.022,1]),(e-s,[.025,.024,.022,1])]
                kf(part,'fillColor',keys,0,'color')
            grain(g,.13)
            if name=='cash':
                ink=shape('Cash • rounded ink silhouette',max(0,at+.06),e-s,[M(-86,-32),C(-98,-32,-101,-17,-99,0),L(-85,34),C(-80,46,-67,48,-56,45),L(84,30),C(98,28,103,17,98,3),L(84,-31),C(80,-42,67,-45,54,-43),L(-86,-32),{'type':'close'}],[.025,.024,.022,1])
                ink['transform']['rotation']=24;effect(ink,'gaussianBlur',blurriness=3);grain(ink,.13);g['layers'].insert(0,ink)
        if blacken and name=='cat':kf(g,'opacity',[(0,0),(e-s,0)],0)
        children.append(g)
    scene=group(title,s,e,children);layers.append(scene)
    return scene

# The first quarter turn follows the actual source poses, rather than crossing the ring.
initial={
 'record':[(6.59,710,705,450,0),(6.67,295,525,280,0),(6.76,475,320,180,0)],
 'skateboard':[(6.59,1000,650,390,0),(6.67,470,670,330,0),(6.76,355,450,190,0)],
 'book':[(6.59,345,620,350,0),(6.67,310,385,200,0),(6.76,640,295,165,0)],
 'camera':[(6.59,290,470,235,0),(6.67,410,280,175,0),(6.76,800,275,175,0)],
 'cat':[(6.59,405,365,160,0),(6.67,600,250,155,0),(6.76,940,285,155,0)],
 'coin':[(6.59,490,300,165,0),(6.67,760,235,160,0),(6.76,1050,330,165,0)],
 'controller':[(6.59,635,275,170,0),(6.67,905,270,175,0),(6.76,1180,390,200,0)],
 'cap':[(6.59,780,265,175,0),(6.67,1080,340,185,0),(6.76,1210,515,230,0)],
 'heart':[(6.59,920,290,190,0),(6.67,1190,430,265,0),(6.76,1150,660,390,0)],
 'cash':[(6.59,1040,330,205,0),(6.67,1210,565,300,0),(6.76,895,715,435,0)],
 'plant':[(6.59,1150,375,200,0),(6.67,1120,690,335,0),(6.76,615,700,325,0)],
 'clapper':[(6.59,1210,495,265,0),(6.67,750,760,425,0),(6.76,380,600,300,0)]}
flatten={
 'record':(535,470,175),'book':(665,470,160),'camera':(790,460,180),'cat':(1280,565,280),
 'coin':(980,565,450),'controller':(630,555,360),'cap':(340,565,330),'heart':(320,515,190),
 'cash':(350,480,160),'plant':(420,475,125),'clapper':(465,475,130),'skateboard':(495,470,140)}
first={}
for n in names:
    stable=[(p[0]-.033,*p[1:]) for p in wheelA[n] if 6.9<=p[0]<=7.9]
    # Once the slow orbit completes it accelerates into an edge-on carousel.
    x,y,w=flatten[n]
    first[n]=initial[n]+stable+[(8.08,*interp(wheelA[n],8.20)),(8.30,x,y,w,0),(8.342,x-70,y,w,0)]
hits={'cap':7.17,'heart':7.38,'cash':7.59,'plant':7.84}
for s,e in [(6.59,6.70),(6.70,6.81),(6.81,8.10),(8.10,8.3417)]:native_scene('Orbit • upright icons / measured turn',s,e,first,hits)

# Overlapping near-edge-on carousels, with tiny rear icons and large foreground passes.
def carousel_tracks(s,e,second=False):
    rows={}
    for i,n in enumerate(order):
        a=-2.45+i*math.tau/12
        def projected(phase):
            theta=a+phase;depth=400*math.sin(theta);perspective=950/(950-depth)
            return (720+400*math.cos(theta)*perspective,535+10*math.sin(theta)*perspective,230*perspective,0)
        rows[n]=[(s,*projected(0)),(e,*projected(-.6 if not second else -1.2))]
    if not second:
        measured={
         'clapper':[(350,540,250),(220,520,140),(440,480,130)],
         'plant':[(520,540,300),(340,535,235),(360,490,130)],
         'cash':[(755,540,420),(540,540,370),(370,515,200)],
         'heart':[(980,540,410),(760,550,440),(480,545,205)],
         'cap':[(1230,550,290),(1030,550,350),(665,555,390)],
         'controller':[(1120,505,150),(1200,550,280),(920,545,360)],
         'coin':[(1020,495,110),(1270,535,180),(1150,550,450)],
         'cat':[(905,500,110),(1050,500,130),(1380,550,270)]}
        times=[s,s+.48,e-.035]
    else:
        measured={
         'heart':[(370,540,190),(170,535,160),(-160,535,100)],
         'cap':[(625,550,385),(270,545,325),(-50,540,200)],
         'controller':[(885,545,345),(445,540,320),(60,540,225)],
         'coin':[(1140,545,445),(725,550,465),(235,545,330)],
         'cat':[(1370,540,270),(1040,550,290),(440,545,230)],
         'camera':[(990,490,150),(1290,545,290),(725,545,430)],
         'book':[(825,495,125),(1210,510,165),(1100,550,420)],
         'record':[(700,495,120),(1140,495,145),(1450,550,350)]}
        times=[s,s+.26,e-.015]
    for n,values in measured.items():rows[n]=[(t,*v,0) for t,v in zip(times,values)]
    return rows
for s,e,second in [(9.1758,9.8849,False),(10.5522,11.0527,True)]:
    tracks=carousel_tracks(s,e,second)
    split=s+(e-s)*.7
    native_scene('Carousel • foreground pass',s,split,tracks)
    native_scene('Carousel • accelerated turn',split,e,tracks)

# Near-circular return, very fast diagonal turn, then individual scatter.
final={}
diagonal={'plant':(700,125,165),'clapper':(915,170,180),'skateboard':(1010,400,225),'record':(1065,495,210),'book':(970,720,170),'camera':(890,805,235),'cat':(890,975,185),'coin':(510,885,200),'controller':(435,690,220),'cap':(455,430,195),'heart':(440,260,210),'cash':(580,255,205)}
for i,n in enumerate(order):
    a=-2.02+i*math.tau/12
    x=720+427*math.cos(a);y=540+395*math.sin(a);w=190 if n not in ['heart','cash','cap','clapper','plant'] else 215
    def tilted(theta):
        xx=430*math.cos(theta);yy=90*math.sin(theta);r=.62
        return (720+xx*math.cos(r)-yy*math.sin(r),530+xx*math.sin(r)+yy*math.cos(r),190+120*(math.sin(theta)+1)/2,0)
    tx,ty,tw=scatter[n]
    final[n]=[(11.9286,*tilted(a-.8)),(12.08,x,y,w,0),(12.34,x,y,w,0),(12.435,720+420*math.cos(a+.65),540+370*math.sin(a+.65),w,0),(12.495,*diagonal[n],0),(12.54,*diagonal[n],0),(12.593,tx,ty,tw,0),(13.50,tx,ty,tw,0),(13.8055,720+(i%3-1)*80,540+(i-5)*45,tw*.75,0)]
blacken={'heart':12.60,'skateboard':12.61,'coin':13.04,'cash':13.24}
native_scene('Orbit • circular return',11.9286,12.42,final)
native_scene('Orbit • diagonal whip turn',12.42,12.593,final)
native_scene('Scatter • ink changes artwork',12.593,13.8055,final,blacken=blacken)

# Ink is a series of editable native ribbons, sampled along a smooth measured flight.
def catmull(rows,t):
    if t<=rows[0][0]:return rows[0][1:]
    if t>=rows[-1][0]:return rows[-1][1:]
    for i,(a,b) in enumerate(zip(rows,rows[1:])):
        if a[0]<=t<=b[0]:
            f=(t-a[0])/(b[0]-a[0]);p0=rows[max(0,i-1)][1:];p1=a[1:];p2=b[1:];p3=rows[min(len(rows)-1,i+2)][1:]
            return tuple(.5*((2*v1)+(-v0+v2)*f+(2*v0-5*v1+4*v2-v3)*f*f+(-v0+3*v1-3*v2+v3)*f*f*f) for v0,v1,v2,v3 in zip(p0,p1,p2,p3))
def ink_flight(title,s,e,rows):
    parts=[];frames=math.ceil((e-s)*24)
    for frame in range(frames):
        t=s+frame/24;until=min(e-s,(frame+1)/24);local=frame/24
        hx,hy,r=catmull(rows,t);points=[]
        # The tail lengthens with velocity, then dissolves around held orbital poses.
        for j in range(13):points.append(catmull(rows,max(s,t-.145+j*.145/12))[:2])
        speed=math.hypot(points[-1][0]-points[0][0],points[-1][1]-points[0][1])
        if speed>38:
            left=[];right=[]
            for j,(x,y) in enumerate(points):
                before=points[max(0,j-1)];after=points[min(12,j+1)];dx=after[0]-before[0];dy=after[1]-before[1];length=max(1,math.hypot(dx,dy));width=2+r*.7*(j/12)**1.5
                left.append((x-dy/length*width,y+dx/length*width));right.append((x+dy/length*width,y-dx/length*width))
            cmds=[M(*left[0])]+[L(*p) for p in left[1:]]+[L(*p) for p in reversed(right)]+[{'type':'close'}]
            for j in range(12):
                quad=[M(*left[j]),L(*left[j+1]),L(*right[j+1]),L(*right[j]),{'type':'close'}]
                trail=shape(f'Trail / frame {frame+1} / fade {j+1}',local,until,quad,[.065,.063,.057,1])
                trail['transform']['opacity']=5+32*((j+1)/12)**1.5
                effect(trail,'gaussianBlur',blurriness=24);parts.append(trail)
        rng=random.Random(100+frame%4);cmd=[]
        vx=points[-1][0]-points[-2][0];vy=points[-1][1]-points[-2][1];angle=math.atan2(vy,vx)*180/math.pi
        for k in range(24):
            a=k*math.tau/24;rad=r*(1+rng.uniform(-.07,.07));x=math.cos(a)*rad*(1.25 if speed>50 else 1);y=math.sin(a)*rad*.73
            cmd.append(M(x,y) if not k else L(x,y))
        cmd.append({'type':'close'})
        head=shape(f'Ink orb / frame {frame+1}',local,until,cmd,[.018,.019,.017,1],x=hx,y=hy);head['transform']['rotation']=angle
        effect(head,'gaussianBlur',blurriness=10);grain(head,.17);parts.insert(0,head)
        if speed<50:
            halo=shape(f'Orb diffuse edge / frame {frame+1}',local,until,ellipse(r*1.35,r*1.15),[.045,.045,.04,1],x=hx,y=hy);halo['transform']['opacity']=30;effect(halo,'gaussianBlur',blurriness=26);parts.append(halo)
            hole=shape(f'Orb soft center / frame {frame+1}',local,until,ellipse(r*.30,r*.23),[.5,.5,.47,.40],x=hx,y=hy);effect(hole,'gaussianBlur',blurriness=5);parts.insert(0,hole)
    g=group(title,s,e,parts);layers.insert(1,g)

flight=[(7.00,700,450,19),(7.05,650,450,27),(7.09,730,70,25),(7.13,1110,165,28),(7.17,1070,550,32),(7.215,545,170,19),(7.25,800,75,26),(7.30,735,90,27),(7.34,740,115,34),(7.38,850,655,33),(7.425,730,95,23),(7.465,855,90,28),(7.505,420,90,28),(7.55,800,80,26),(7.59,585,630,33),(7.63,1080,155,21),(7.67,1000,135,20),(7.75,940,120,17),(7.795,1000,210,25),(7.84,380,450,30),(7.88,740,565,24),(7.94,735,555,28),(8.05,735,555,27),(8.20,735,545,20)]
ink_flight('Ink • curved orbital flight',7.00,8.27,flight)
ink_flight('Ink • circular return and scatter',11.95,13.70,[(11.95,650,525,22),(12.10,715,550,30),(12.32,735,540,27),(12.43,900,440,27),(12.52,1050,570,28),(12.59,570,630,30),(12.68,800,900,32),(12.76,550,620,31),(12.84,1300,170,26),(12.96,540,620,30),(13.035,1130,620,33),(13.10,690,785,23),(13.17,1100,780,28),(13.24,295,950,32),(13.30,390,180,25),(13.38,560,170,21),(13.53,510,175,22),(13.67,750,750,26)])

# Warm flashes and tiny impact rays happen on the matching icon poses.
for name,t in hits.items():
    x,y,w,_=interp(first[name],t)
    halo=shape('Impact • '+name,t-.04,t+.19,ellipse(w*.35,w*.30),[1,.52,.025,.6],x=x,y=y)
    effect(halo,'gaussianBlur',blurriness=28);kf(halo,'opacity',[(t-.04,0),(t,85),(t+.19,0)],t-.04);layers.append(halo)
    for j in range(4):
        a=(j*math.tau/4)+.35;xx=x+math.cos(a)*w*.54;yy=y+math.sin(a)*w*.44
        ray=shape('Impact ray • '+name,t,t+.11,[M(0,0),L(4,-w*.12),L(8,0),{'type':'close'}],[.91,.53,.02,1],x=xx,y=yy);ray['transform']['rotation']=a*180/math.pi+90;layers.insert(1,ray)

# Cut points measured directly from the original frame stream.
windows={'Paper • first icon orbit':(6.59,8.3417),'Paper • horizontal carousel':None,'Paper • final orbit / scatter':None,'Charcoal • action.':(8.3417,9.1758),'Charcoal • intention.':(9.8849,10.5522),'Charcoal • curiosity.':(11.0527,11.9286)}
layers[:]=[l for l in layers if l['name'] not in ['Paper • horizontal carousel','Paper • final orbit / scatter']]
for s,e in [(9.1758,9.8849),(10.5522,11.0527),(11.9286,12.593)]:layers.append(paper('Paper • measured orbit',s,e))
l=paper('Paper • scatter lens shading',12.593,13.8055)
LENS_WGSL=GRAIN_WGSL.replace('let rgb=', 'let rgb=').replace('return vec4<f32>(clamp(c.rgb+vec3<f32>(grain*p.amount*c.a),vec3<f32>(0.),vec3<f32>(c.a)),c.a);','''let radius=length((i.tex_coords-vec2<f32>(.50,.50))*vec2<f32>(1.25,1.));
let shade=1.-.52*smoothstep(.27,.76,radius);
return vec4<f32>(clamp(c.rgb*shade+vec3<f32>(grain*p.amount*c.a),vec3<f32>(0.),vec3<f32>(c.a)),c.a);''')
effect(l,'customShader',name='Soft film lens falloff',description='Bright center and soft dark corners, matched to the scatter frames.',wgsl=LENS_WGSL,params=[{'name':'animationTime','min':0,'max':21,'default':0},{'name':'amount','min':0,'max':.15,'default':.025}]);layers.append(l)
for l in layers:
    n=l['name']
    if n in windows and windows[n]:
        s,e=windows[n];l['activeRange']={'start':ms(s),'duration':ms(e-s)}
    if n.startswith('Thermal profile'):
        l['playback']=playback(3.7538,6.59,3.7538);l['sourceRange']={'start':3754,'duration':2836}
    if n.startswith('Thermal hand'):
        l['playback']=playback(13.8055,15.9326,13.8055);l['sourceRange']={'start':13806,'duration':2127}
    # Adjust the three native feature groups and their associated overlays together.
    r=l.get('activeRange');p=l.get('playback',{}).get('inputRange');start=(r or p or {}).get('start')
    correction={8270:(8.3417,9.1758),10020:(9.8849,10.5522),11020:(11.0527,11.9286),16020:(15.9326,16.2245),16300:(16.2245,16.5999),16520:(16.5999,16.8085),16770:(16.8085,17.2255)}
    if start in correction and not n.startswith('LOVE • letter'):
        s,e=correction[start]
        if l['type']=='Group':
            l['playback']=playback(s,e);film_icon(l)
            for child in l['layers']:child['activeRange']['duration']=ms(e-s)
        else:l['activeRange']={'start':ms(s),'duration':ms(e-s)}
    if r and l['type']=='Text' and ('action.' in n or 'intention.' in n or 'curiosity.' in n):
        s,e=next(v for k,v in [('action.',(8.3417,9.1758)),('intention.',(9.8849,10.5522)),('curiosity.',(11.0527,11.9286))] if k in n)
        l['activeRange']={'start':ms(s+.10),'duration':ms(e-s-.10)}
    if n=='Typing caret':
        s,e={8430:(8.3417,9.1758),10180:(9.8849,10.5522),11180:(11.0527,11.9286)}[start]
        l['activeRange']={'start':ms(s+.16),'duration':ms(e-s-.16)}
    if n=='Editable red music note':
        l['activeRange']={'start':r['start']+33,'duration':11929-r['start']-33}
    if n.startswith('LOVE • letter'):
        s={'L':15.9326,'O':16.2245,'V':16.5999,'E':16.8085}[n[-1]]
        l['activeRange']={'start':ms(s),'duration':17225-ms(s)}
    if n.startswith('Hand /') and r:
        r['duration']=min(r['duration'],15933-r['start'])
    if start==17250:
        if l['type']=='Group':l['playback']=playback(17.2255,20.459)
        else:l['activeRange']={'start':17225,'duration':r['start']+r['duration']-17225}
# Opening backgrounds must end at the footage cut; the star and flare already cover it.
for l in layers:
    if l['name'] in ['Paper • opening','Paper • iris vignette']:l['activeRange']['duration']=3754-l['activeRange']['start']
# The word starts before the hand transition, as in the source.
layers.append(text('Scatter / through • editable word','through',13.60,13.8055,207,556,39,[.10,.08,.07,1]))

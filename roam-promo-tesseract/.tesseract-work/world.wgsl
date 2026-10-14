struct VertexInput { @location(0) position: vec2<f32>, @location(1) tex_coords: vec2<f32>, @location(2) color: vec4<f32> };
struct VertexOutput { @builtin(position) clip_position: vec4<f32>, @location(0) tex_coords: vec2<f32> };
@vertex fn vs_main(v: VertexInput) -> VertexOutput { var o: VertexOutput; o.clip_position=vec4<f32>(v.position,0.,1.); o.tex_coords=v.tex_coords; return o; }
struct Params { animationTime: f32, shot: f32, camera: f32, start: f32 };
@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;
fn ease(t:f32)->f32 { let q=clamp(t,0.,1.);return q*q*(3.-2.*q); }
fn box(p:vec3<f32>,b:vec3<f32>,r:f32)->f32 { let q=abs(p)-b;return length(max(q,vec3<f32>(0.)))+min(max(q.x,max(q.y,q.z)),0.)-r; }
fn cylX(p:vec3<f32>,r:f32,h:f32)->f32 { let q=vec2<f32>(length(p.yz)-r,abs(p.x)-h);return min(max(q.x,q.y),0.)+length(max(q,vec2<f32>(0.))); }
fn cylY(p:vec3<f32>,r:f32,h:f32)->f32 { let q=vec2<f32>(length(p.xz)-r,abs(p.y)-h);return min(max(q.x,q.y),0.)+length(max(q,vec2<f32>(0.))); }
fn rot(p:vec3<f32>,a:f32)->vec3<f32> {return vec3<f32>(cos(a)*p.x-sin(a)*p.z,p.y,sin(a)*p.x+cos(a)*p.z);}
fn put(a:vec2<f32>,d:f32,id:f32)->vec2<f32> {if(d<a.x){return vec2<f32>(d,id);}return a;}
fn road(z:f32)->f32{return .65*sin(z*.62);}
fn car(p0:vec3<f32>,t:f32,hero:bool)->vec2<f32> {
 var p=p0; var sc=1.;
 if(hero){sc=1.65;p=rot(p-vec3<f32>(0.,.08,0.),-.55+.8*ease(t/3.5)+.05*sin(t*1.5));}
 else {let z=.35*sin(t*.75); p=rot(p-vec3<f32>(road(z)+.38,0.,z),-.25*cos(z*.62));}
 p=p/sc;
 p.y=p.y-.015*sin(t*3.);
 var d=vec2<f32>(box(p-vec3<f32>(0.,.51,0.),vec3<f32>(.55,.19,.96),.12),1.);
 d=put(d,box(p-vec3<f32>(0.,.89,-.14),vec3<f32>(.46,.23,.49),.11),2.);
 d=put(d,box(p-vec3<f32>(0.,1.15,-.14),vec3<f32>(.49,.035,.49),.065),1.);
 d=put(d,box(p-vec3<f32>(0.,.91,-.18),vec3<f32>(.535,.25,.033),.018),1.);
 let wp=vec3<f32>(abs(p.x)-.59,p.y-.30,abs(p.z)-.62);
 d=put(d,cylX(wp,.275,.115),3.);
 d=put(d,cylX(vec3<f32>(abs(p.x)-.717,p.y-.30,abs(p.z)-.62),.155,.014),4.);
 d=put(d,cylX(vec3<f32>(abs(p.x)-.735,p.y-.30,abs(p.z)-.62),.067,.02),1.);
 d=put(d,box(vec3<f32>(abs(p.x)-.37,p.y-.58,p.z-1.075),vec3<f32>(.13,.07,.012),.045),5.);
 d=put(d,box(vec3<f32>(abs(p.x)-.39,p.y-.55,p.z+1.075),vec3<f32>(.09,.065,.014),.025),6.);
 d=put(d,box(p-vec3<f32>(0.,.35,1.06),vec3<f32>(.40,.035,.035),.035),4.);
 d.x=d.x*sc;return d;
}
fn scene(p:vec3<f32>)->vec2<f32> {
 let t=params.animationTime-params.start;let shot=params.shot;
 let hero=shot<.5||shot>3.5;
 var d=vec2<f32>(p.y+.27,0.);
 if(hero){
  d=put(d,cylY(p-vec3<f32>(0.,-.14,0.),2.38,.16),7.);
 }else if(shot<2.5){
  d=put(d,box(p-vec3<f32>(0.,-.25,0.),vec3<f32>(2.75,.13,3.6),.10),7.);
  let q=vec3<f32>(p.x-road(p.z),p.y+.018,p.z);
  d=put(d,box(q,vec3<f32>(1.05,.015,3.5),.025),8.);
  let dz=abs(fract((p.z+t*1.3)/.95)-.5)*.95;
  d=put(d,max(box(vec3<f32>(p.x-road(p.z),p.y-.032,dz),vec3<f32>(.035,.008,.19),.013),abs(p.z)-3.45),5.);
  for(var i=0;i<4;i=i+1){
   let fi=f32(i);let side=select(-1.,1.,i%2==0);let z=(fi-1.5)*1.8;
   let center=vec3<f32>(side*2.08,0.,z);
   let growth=ease((t-.1*fi)/.8);
   let h=.6*growth;
   d=put(d,cylY(p-center-vec3<f32>(0.,h*.5,0.),.07,h*.5),9.);
   let top=p-center-vec3<f32>(0.,h+.34*growth,0.);
   d=put(d,(length(top/vec3<f32>(1.,1.25,1.))-.48*growth)*.8,10.);
  }
 }else{
  d=put(d,cylY(p-vec3<f32>(0.,-.14,0.),2.8,.16),7.);
  for(var i=0;i<3;i=i+1){
   let fi=f32(i);let h=(.5+fi*.50)*ease((t-.18*fi)/1.0);
   d=put(d,box(p-vec3<f32>((fi-1.)*1.13,h*.5,-.8),vec3<f32>(.39,h*.5,.40),.09),11.+fi);
  }
 }
 if(shot<2.5||hero){let c=car(p,t,hero);d=put(d,c.x,c.y);}
 return d;
}
fn normal(p:vec3<f32>)->vec3<f32>{let e=.003;return normalize(vec3<f32>(scene(p+vec3<f32>(e,0.,0.)).x-scene(p-vec3<f32>(e,0.,0.)).x,scene(p+vec3<f32>(0.,e,0.)).x-scene(p-vec3<f32>(0.,e,0.)).x,scene(p+vec3<f32>(0.,0.,e)).x-scene(p-vec3<f32>(0.,0.,e)).x));}
fn color(id:f32)->vec3<f32>{
 if(id<.5){return vec3<f32>(.951,.941,.914);}
 if(id<1.5){return vec3<f32>(.10,.26,.81);}
 if(id<2.5){return vec3<f32>(.055,.13,.22);}
 if(id<3.5){return vec3<f32>(.075,.086,.105);}
 if(id<4.5){return vec3<f32>(.80,.85,.87);}
 if(id<5.5){return vec3<f32>(1.,.95,.75);}
 if(id<6.5){return vec3<f32>(.92,.22,.13);}
 if(id<7.5){return vec3<f32>(.79,.86,.75);}
 if(id<8.5){return vec3<f32>(.34,.40,.49);}
 if(id<9.5){return vec3<f32>(.60,.35,.18);}
 if(id<10.5){return vec3<f32>(.28,.57,.36);}
 if(id<11.5){return vec3<f32>(.49,.65,.98);}
 if(id<12.5){return vec3<f32>(.23,.43,.90);}
 return vec3<f32>(.12,.30,.78);
}
@fragment fn fs_main(v:VertexOutput)->@location(0) vec4<f32>{
 let t=params.animationTime-params.start;
 let hero=params.shot<.5||params.shot>3.5;
 let center=select(.72,.70,hero);
 let frame=vec2<f32>((v.tex_coords.x-center)*1.7778,.56-v.tex_coords.y);
 let cam=rot(vec3<f32>(5.2,4.6,6.8),.11*sin(t*.43));
 let aim=vec3<f32>(0.,.35,0.);
 let forward=normalize(aim-cam);let right=normalize(cross(forward,vec3<f32>(0.,1.,0.)));let up=cross(right,forward);
 let span=select(9.3,7.2,hero)+.18*sin(t*.5);
 let ro=cam+span*(frame.x*right+frame.y*up);
 let rd=forward;
 var dist=0.;var hit=vec2<f32>(1.,0.);var found=false;
 for(var i=0;i<64;i=i+1){hit=scene(ro+rd*dist);if(hit.x<.004){found=true;break;}dist=dist+max(hit.x*.85,.003);if(dist>25.){break;}}
 var rgb=vec3<f32>(.951,.941,.914);
 if(found){
  let p=ro+rd*dist;let n=normal(p);let light=normalize(vec3<f32>(-3.,6.,4.));
  var shadow=1.;var sd=.03;
  for(var j=0;j<14;j=j+1){let h=scene(p+n*.013+light*sd).x;shadow=min(shadow,8.*h/sd);sd=sd+clamp(h,.05,.36);}
  shadow=clamp(shadow,.28,1.);
  let ambient=.60+.12*n.y;let diffuse=max(dot(n,light),0.)*.43*shadow;
  let occl=clamp(scene(p+n*.16).x/.16,.40,1.);
  let base=color(hit.y);
  let spec=pow(max(dot(reflect(-light,n),-rd),0.),42.)*.25*shadow;
  rgb=base*(ambient+diffuse)*(.80+.20*occl)+spec;
  if(hit.y<.5){rgb=mix(vec3<f32>(.951,.941,.914),rgb,.52);}
 }
 return vec4<f32>(clamp(rgb,vec3<f32>(0.),vec3<f32>(1.)),1.);
}

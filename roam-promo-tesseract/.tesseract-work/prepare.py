from pathlib import Path
import json, wave, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'.tesseract-work'
SR=48000; DUR=24; N=SR*DUR
rng=np.random.default_rng(71)
music=np.zeros((N,2)); drums=np.zeros((N,2))
def add(buf,sig,start,gain=1,pan=0):
    i=round(start*SR); n=min(len(sig),N-i)
    if i<0 or n<=0:return
    buf[i:i+n,0]+=sig[:n]*gain*np.sqrt((1-pan)/2)
    buf[i:i+n,1]+=sig[:n]*gain*np.sqrt((1+pan)/2)
def note(m,d,kind='keys'):
    t=np.arange(round(d*SR))/SR; f=440*2**((m-69)/12)
    if kind=='bass':
        s=np.sin(2*np.pi*f*t)+.30*np.sin(4*np.pi*f*t)+.12*np.sin(6*np.pi*f*t)
        e=(1-np.exp(-t*180))*np.exp(-t*4.0)
    else:
        s=np.sin(2*np.pi*f*t+1.3*np.sin(2*np.pi*f*2*t)*np.exp(-t*8))+.16*np.sin(2*np.pi*f*3*t)
        e=(1-np.exp(-t*260))*np.exp(-t*3.2)
    e*=np.minimum(1,(d-t)/.035)
    return s*e
chords=[[60,64,67,71],[57,60,64,67],[53,57,60,64],[55,59,62,69]]
roots=[36,33,29,31]
for bar in range(11):
    at=bar*2.; chord=chords[bar%4]; root=roots[bar%4]
    # Soft electric-key chord stabs, swung plucks and a nimble bass groove.
    for off,g in [(0,.10),(.75,.055),(1.5,.065)]:
        for j,m in enumerate(chord):add(music,note(m,1.1),at+off+j*.008,g,(j-1.5)*.21)
    for k,off in enumerate([0,.75,1.,1.75]):
        add(music,note(root+(12 if k==3 else 0),.5,'bass'),at+off,.29)
    if bar>=2:
        for k,off in enumerate([.25,.875,1.25,1.875]):
            add(music,note(chord[[2,1,3,1][k]]+12,.43),at+off,.075,(-.35 if k%2==0 else .35))
    for k in range(4):
        if bar==8 and k>=2:continue
        t=np.arange(round(.35*SR))/SR
        phase=2*np.pi*(49*t+29*(1-np.exp(-t*28))/28)
        kick=np.sin(phase)*np.exp(-t*15)+(rng.normal(0,1,len(t))*.035*np.exp(-t*200))
        add(drums,kick,at+k*.5,.48)
    for off in [.5,1.5]:
        t=np.arange(round(.22*SR))/SR; noise=rng.normal(0,1,len(t))
        hp=noise-np.convolve(noise,np.ones(11)/11,'same')
        sn=(hp*.42+np.sin(2*np.pi*180*t)*.13)*np.exp(-t*23)*(1-np.exp(-t*1000))
        add(drums,sn,at+off,.24,.10)
    for k in range(8):
        t=np.arange(round(.09*SR))/SR; noise=rng.normal(0,1,len(t))
        hp=noise-np.convolve(noise,np.ones(19)/19,'same')
        add(drums,hp*np.exp(-t*60),at+k*.25+(0.02 if k%2 else 0),.022 if k%2 else .016,(-.45 if k%2 else .45))
# A clear C-major ending at 22 s, with room for a natural release.
for j,m in enumerate([48,60,64,67,72]):add(music,note(m,2.),22+j*.025,.14,(j-2)*.15)
# Short stereo delays create space, without a washy pad.
for delay,gain in [(.1875,.15),(.375,.065)]:
    d=round(delay*SR);music[d:]+=music[:-d,::-1]*gain
for buf in [music,drums]:
    fade=np.minimum(1,np.arange(N)/(.015*SR))*np.minimum(1,(N-np.arange(N))/(.45*SR))
    buf*=fade[:,None]
def wav(path,buf):
    with wave.open(str(path),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(SR)
        w.writeframes((np.clip(buf,-1,1)*32767).astype('<i2').tobytes())
wav(WORK/'keys-bass.wav',music)
wav(WORK/'drums.wav',drums)
wav(WORK/'music-audition.wav',music+drums)
# Waveform view uses the same samples and explicit composition cue markers.
im=Image.new('RGB',(1600,470),'#171c2c');d=ImageDraw.Draw(im)
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',18)
for ch in range(2):
    y=125+ch*185; d.line((50,y,1550,y),fill='#46516e')
    for x in range(1500):
        a=int(x*N/1500);b=int((x+1)*N/1500);peak=np.max(np.abs((music+drums)[a:b,ch]));h=peak*160
        d.line((x+50,y-h,x+50,y+h),fill='#96b9fa')
for sec in [0,4,10,14,18,22,24]:
    x=50+sec/24*1500;d.line((x,45,x,420),fill='#e9c66a',width=2);d.text((x+4,425),f'{sec}s',font=font,fill='white')
d.text((50,12),'Roam / original instrumental / 120 BPM / picture cues',font=font,fill='white')
im.save(WORK/'checks/music-waveform.png')
# A faithful crop of supplied app UI, excluding the status bar, map and error.
app=Image.open(ROOT.parent/'ad/assets/app-route.png')
app.crop((48,215,1155,1135)).save(WORK/'route-ui.png')
json.dump({'bpm':120,'beatSeconds':.5,'phrases':[0,4,8,12,16,20],
 'pictureCues':[{'time':0,'event':'hero car + first proposition'}, {'time':4,'event':'route-planning UI'},
 {'time':10,'event':'practice road'}, {'time':14,'event':'progress pillars'},
 {'time':18,'event':'brand payoff'}, {'time':22,'event':'final resolving chord'}],
 'source':'Original locally composed keys, bass and drum stems; no sampled commercial recordings.'},open(WORK/'audio-map.json','w'),indent=2)
print('Prepared original music stems, waveform, and source UI crop.')

#!/usr/bin/env python3
"""Animated 9:16 Short: Boston's 1919 Great Molasses Flood.

An original two-second animated cold open shows the molasses wave first, followed
by a rewind and the historical story. Art, captions, soundtrack, foley and motion
are generated specifically for this Short.
"""
from __future__ import annotations
import math, os, subprocess
from pathlib import Path
import imageio_ffmpeg
import numpy as np
import scipy.io.wavfile as wavfile
import scipy.signal as signal
from scipy.ndimage import uniform_filter1d
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"shorts"/"molasses_flood_animated_short.mp4"
ART=ROOT/"shorts"/"molasses_flood_scenes"
AUDIO=ROOT/"shorts"/"molasses_flood_audio"
WORK=ROOT/".cache"/"molasses_render"
FONT=ROOT/"shorts"/"assets"/"fonts"
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
W,H,FPS,SR=1080,1920,30,44100
HOOK=2.0
REWIND=.18
VOICE_START=HOOK+REWIND
GAP=.10
OUTRO=1.45

IVORY=(248,246,238)
GOLD=(255,190,78)
AMBER=(198,103,37)
SYRUP=(74,34,20)
SYRUP_HI=(255,183,78)
CYAN=(139,228,220)
MINT=(101,239,190)
CORAL=(245,102,86)
SLATE=(177,193,207)

BEATS=[
 {"id":1,"audio":"vo_01.mp3","bg":"scene_02_tank.jpg","tag":("STREET LEVEL // 1919","25-FOOT WAVE",GOLD),"action":"tank",
  "phrases":[("January 15, 1919.",{"1919.":GOLD}),("A 25-foot wave slammed",{"25-foot":GOLD}),("into Boston's North End.",{}),("And it wasn't water.",{"water.":CYAN}),("It was molasses.",{"molasses.":GOLD})],
  "cam":(-.01,.01,.02,-.01,1.02,1.09)},
 {"id":2,"audio":"vo_02.mp3","bg":"scene_03_surge.jpg","tag":("THE BREACH","2 MILLION GALLONS",CORAL),"action":"surge",
  "phrases":[("A storage tank burst,",{"burst,":CORAL}),("unleashing more than",{}),("two million gallons of syrup",{"million":GOLD,"syrup":GOLD}),("in seconds.",{})],
  "cam":(0,.02,-.01,0,1.03,1.10)},
 {"id":3,"audio":"vo_03.mp3","bg":"scene_04_rescue.jpg","tag":("NORTH END","NO WAY OUT",GOLD),"action":"rescue",
  "phrases":[("The sticky surge swept",{}),("wagons aside, smashed",{"smashed":CORAL}),("buildings, and flooded homes",{"homes":GOLD}),("before people could get clear.",{})],
  "cam":(.015,.01,-.02,0,1.02,1.09)},
 {"id":4,"audio":"vo_04.mp3","bg":"scene_05_aftercare.jpg","tag":("HUMAN COST","21 DEAD // 150 INJURED",CORAL),"action":"aftermath",
  "phrases":[("21 people died.",{"21":CORAL,"died.":CORAL}),("Around 150 more",{"150":GOLD}),("were injured.",{"injured.":GOLD})],
  "cam":(0,.02,0,-.01,1.02,1.07)},
 {"id":5,"audio":"vo_05.mp3","bg":"scene_06_inquiry.jpg","tag":("THE INVESTIGATION","THIN STEEL. WEAK RIVETS.",MINT),"action":"inquiry",
  "phrases":[("Thin steel walls.",{"Thin":GOLD}),("Weak rivets.",{"rivets.":CORAL}),("The tank had leaked",{}),("before it burst.",{"burst.":CORAL})],
  "cam":(0,.01,0,-.01,1.02,1.08)},
 {"id":6,"audio":"vo_06.mp3","bg":"scene_07_court.jpg","tag":("SIX-YEAR COURT FIGHT","OWNER HELD LIABLE",GOLD),"action":"court",
  "phrases":[("A six-year court battle",{}),("held the tank's owner",{}),("responsible.",{"responsible.":GOLD}),("A landmark case",{ "landmark":MINT}),("for engineering accountability.",{"accountability.":MINT})],
  "cam":(0,.01,0,0,1.02,1.08)},
 {"id":7,"audio":"vo_07.mp3","bg":"scene_08_legacy.jpg","tag":("THE LASTING LESSON","SAFETY IS ENGINEERED",MINT),"action":"legacy",
  "phrases":[("Boston's sweetest cargo",{"sweetest":GOLD}),("left its darkest lesson.",{"darkest":CORAL}),("Safety cannot be",{"Safety":MINT}),("built on guesswork.",{"guesswork.":MINT})],
  "cam":(0,.015,0,-.01,1.00,1.07)},
]


def clamp(v,lo=0.0,hi=1.0): return max(lo,min(hi,v))
def smooth(v):
 v=clamp(v); return v*v*(3-2*v)
def syllable(w):
 w=''.join(c for c in w.lower() if c.isalpha() or c.isdigit())
 if not w: return 1.0
 if w.isdigit(): return max(2.0,len(w)*1.05)
 n=0; prev=False
 for c in w:
  isv=c in 'aeiouy'
  if isv and not prev:n+=1
  prev=isv
 if w.endswith('e') and n>1:n-=.5
 return max(1.0,float(n))

def tighten_pauses(x,sr):
 x=np.asarray(x,dtype=np.float32)
 if x.ndim>1:x=x.mean(axis=1)
 step=int(.01*sr); n=len(x)//step
 env=np.array([np.sqrt(np.mean(x[k*step:(k+1)*step]**2)+1e-12) for k in range(n)])
 active=np.where(env>.006)[0]
 if len(active):
  pad=int(.024*sr); x=x[max(0,active[0]*step-pad):min(len(x),(active[-1]+1)*step+pad)]
 n=len(x)//step; env=np.array([np.sqrt(np.mean(x[k*step:(k+1)*step]**2)+1e-12) for k in range(n)])
 quiet=env<.007; out=[]; k=0
 while k<n:
  if not quiet[k]:out.append(x[k*step:(k+1)*step]);k+=1;continue
  j=k
  while j<n and quiet[j]:j+=1
  if j-k>18:
   keep=7; half=keep//2
   out.extend([x[k*step:(k+half)*step],x[(j-half)*step:j*step]])
  else:out.append(x[k*step:j*step])
  k=j
 if n*step<len(x):out.append(x[n*step:])
 x=np.concatenate([a for a in out if len(a)]) if out else x
 fade=min(int(.012*sr),len(x)//4)
 if fade:x[:fade]*=np.linspace(0,1,fade);x[-fade:]*=np.linspace(1,0,fade)
 return x

def process_voice(path,idx):
 WORK.mkdir(parents=True,exist_ok=True)
 rawp=WORK/f"raw_{idx:02d}.wav"; tightp=WORK/f"tight_{idx:02d}.wav"; outp=WORK/f"voice_{idx:02d}.wav"
 subprocess.run([FFMPEG,"-y","-i",str(path),"-ar",str(SR),"-ac","1",str(rawp)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 sr,raw=wavfile.read(rawp); x=tighten_pauses(raw.astype(np.float32)/32768.0,sr)
 wavfile.write(tightp,sr,np.clip(x*32767,-32768,32767).astype(np.int16))
 af=("atempo=1.18,highpass=f=75,equalizer=f=220:t=q:w=1.2:g=1.2,"
     "equalizer=f=3600:t=q:w=1.3:g=1.8,acompressor=threshold=-19dB:ratio=2.4:attack=8:release=110:makeup=2dB,alimiter=limit=0.90")
 subprocess.run([FFMPEG,"-y","-i",str(tightp),"-af",af,"-ar",str(SR),"-ac","1",str(outp)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 sr,y=wavfile.read(outp); return y.astype(np.float32)/32768.0

def align_phrases(audio,phrases):
 dur=len(audio)/SR
 weights=np.array([sum(syllable(w) for w in p[0].split()) for p in phrases],dtype=float)
 targets=np.cumsum(weights)[:-1]/weights.sum()*dur
 hop=int(.01*SR); n=max(1,len(audio)//hop)
 rms=np.array([np.sqrt(np.mean(audio[k*hop:(k+1)*hop]**2)+1e-10) for k in range(n)])
 if n>5:rms=np.convolve(rms,np.ones(5)/5,mode='same')
 cuts=[0.0]
 for i,target in enumerate(targets):
  lo=max(cuts[-1]+.16,target-.20);hi=min(dur-.16*(len(phrases)-1-i),target+.20)
  a=max(0,int(lo/.01));b=min(n-1,int(hi/.01))
  if b>a:
   k=np.arange(a,b+1);cost=rms[a:b+1]/(rms.max()+1e-9)+.25*((k*.01-target)/.2)**2
   t=float(k[np.argmin(cost)]*.01)
  else:t=float(target)
  cuts.append(t)
 cuts.append(dur)
 return [(cuts[i],cuts[i+1],phrases[i][0],phrases[i][1]) for i in range(len(phrases))]

def prepare_audio():
 clips=[]
 for i,b in enumerate(BEATS):
  clip=process_voice(AUDIO/b["audio"],i+1);clips.append(clip)
  print(f"  Narration {i+1}: {len(clip)/SR:.2f}s",flush=True)
 cursor=VOICE_START; timeline=[]
 for b,clip in zip(BEATS,clips):
  item=dict(b);item["start"]=cursor;item["speech_end"]=cursor+len(clip)/SR;item["end"]=item["speech_end"]+GAP;item["clip"]=clip;item["caption_schedule"]=align_phrases(clip,b["phrases"])
  timeline.append(item);cursor=item["end"]
 total_s=cursor+OUTRO;nframes=int(round(total_s*FPS));ns=int(round(nframes*SR/FPS));vo=np.zeros(ns,dtype=np.float32)
 for b in timeline:
  i0=int(round(b["start"]*SR));i1=min(ns,i0+len(b["clip"]));vo[i0:i1]=b["clip"][:i1-i0]
 return vo,timeline,nframes,nframes/FPS

def fx(kind,dur,seed=0):
 n=max(1,int(dur*SR));t=np.arange(n,dtype=float)/SR;rng=np.random.default_rng(seed)
 if kind in ("sticky","whoosh"):
  noise=rng.standard_normal(n);sos=signal.butter(3,[120/(SR/2),2400/(SR/2)],btype='band',output='sos');x=signal.sosfilt(sos,noise)
  env=np.sin(np.pi*np.clip(t/max(dur,1e-4),0,1))**1.4
  if kind=="sticky":
   for f,a,d in [(75,.3,3.0),(145,.2,4.0),(320,.09,5.0)]:x+=a*np.sin(2*np.pi*f*t)*np.exp(-t*d)
  return (x*env*.19).astype(np.float32)
 if kind=="metal":
  f=970-550*np.clip(t/dur,0,1);phase=2*np.pi*np.cumsum(f)/SR
  return (np.sin(phase)*np.exp(-t*16)+.16*np.sin(2*np.pi*2100*t)*np.exp(-t*10)).astype(np.float32)
 if kind=="thump":
  f=66+38*np.exp(-t*16);phase=2*np.pi*np.cumsum(f)/SR
  return (np.tanh(1.7*np.sin(phase))*np.exp(-t*5)).astype(np.float32)
 if kind=="gavel":
  return (.6*np.sin(2*np.pi*(115-35*t/dur)*t)*np.exp(-t*13)+.2*np.sin(2*np.pi*870*t)*np.exp(-t*20)).astype(np.float32)
 return np.zeros(n,dtype=np.float32)

def build_mix(vo,timeline,total_s):
 n=len(vo);l=np.zeros(n,dtype=float);r=np.zeros(n,dtype=float)
 # Slow original minor-key score, opening in suspense and resolving into a warm, measured pulse.
 chord=[73.42,110,146.83,174.61]
 for si,start in enumerate(np.arange(0,total_s,5.4)):
  i0=int(start*SR);i1=min(n,i0+int(7.3*SR));tt=np.arange(i1-i0)/SR
  if i1<=i0:continue
  notes=chord if si%3==0 else ([65.41,98,130.81,164.81] if si%3==1 else [58.27,87.31,116.54,174.61])
  a=np.zeros_like(tt);b=np.zeros_like(tt)
  for j,f in enumerate(notes):
   a+=(np.sin(2*np.pi*f*tt+j*.22)+.14*np.sin(4*np.pi*f*tt+j*.5))/len(notes)
   b+=(np.sin(2*np.pi*f*1.0015*tt+j*.35)+.14*np.sin(4*np.pi*f*1.0015*tt+j*.7))/len(notes)
  env=np.minimum(1,tt/.6)*np.minimum(1,(len(tt)/SR-tt)/.8)
  vib=.72+.28*np.sin(2*np.pi*.13*tt+si*.5)
  l[i0:i1]+=a*env*vib*.085;r[i0:i1]+=b*env*vib*.085
 def add(sig,sec,pan=0,gain=.5):
  i0=max(0,int(sec*SR));i1=min(n,i0+len(sig));
  if i1<=i0:return
  p=(pan+1)*math.pi/4;l[i0:i1]+=sig[:i1-i0]*gain*math.cos(p);r[i0:i1]+=sig[:i1-i0]*gain*math.sin(p)
 # Cold-open foley: a metallic split, heavy sticky wave and short rewind swell.
 add(fx("whoosh",1.35,1919),.02,0,.75);add(fx("metal",.42,1),.30,-.15,.62);add(fx("sticky",1.10,2),.53,.15,.85);add(fx("whoosh",.27,3),1.78,0,.38)
 for i,b in enumerate(timeline):
  t=b["start"]
  if b["action"]=="tank":add(fx("metal",.55,20+i),t+1.5,-.2,.30)
  if b["action"]=="surge":add(fx("sticky",.8,30+i),t+.8,.1,.32)
  if b["action"]=="rescue":add(fx("whoosh",.65,40+i),t+1.3,-.2,.18)
  if b["action"]=="aftermath":add(fx("thump",.7,50+i),t+.6,0,.21)
  if b["action"]=="court":add(fx("gavel",.7,60+i),t+1.15,0,.37)
  if i:add(fx("whoosh",.22,70+i),t-.12,0,.16)
 # Voice-driven duck; mono VO is centered, score breathes beneath it.
 hop=int(.025*SR);env=uniform_filter1d(np.abs(vo),size=hop,mode='nearest');duck=1-.56*np.clip(env/.075,0,1)
 sw=int(.10*SR);duck=uniform_filter1d(duck,size=sw,mode='nearest')
 lm=l*duck+vo*.94;rm=r*duck+vo*.94
 fade=int(.18*SR);lm[:fade]*=np.linspace(0,1,fade);rm[:fade]*=np.linspace(0,1,fade);lm[-fade:]*=np.linspace(1,0,fade);rm[-fade:]*=np.linspace(1,0,fade)
 peak=max(float(np.max(np.abs(lm))),float(np.max(np.abs(rm))),1e-6)
 if peak>.92:lm=np.tanh(lm/peak*1.15)*.90;rm=np.tanh(rm/peak*1.15)*.90
 return np.clip(np.stack((lm,rm),axis=1)*32767,-32768,32767).astype(np.int16)

def load_bg(name):
 im=Image.open(ART/name).convert('RGB');iw,ih=im.size;sc=max((W+100)/iw,(H+180)/ih)
 return im.resize((int(iw*sc),int(ih*sc)),Image.Resampling.LANCZOS)

def camera(bg,u,cam):
 x0,y0,x1,y1,z0,z1=cam;q=smooth(u);z=z0+(z1-z0)*q;iw,ih=bg.size;cw,ch=W/z,H/z
 cx=iw*(.5+x0+(x1-x0)*q);cy=ih*(.5+y0+(y1-y0)*q)
 a=max(0,min(iw-cw,cx-cw/2));b=max(0,min(ih-ch,cy-ch/2))
 return bg.transform((W,H),Image.Transform.EXTENT,(a,b,a+cw,b+ch),resample=Image.Resampling.BILINEAR)

def draw_wave(frame,progress,phase=0,alpha=1.0,base=0.78):
 d=ImageDraw.Draw(frame,'RGBA');p=clamp(progress)
 top=H*(base-.44*smooth(p));pts=[]
 for x in range(-80,W+100,22):
  xx=x/W
  y=top+52*math.sin(xx*math.pi*3+phase)+26*math.sin(xx*math.pi*8-phase*1.4)+18*math.cos(xx*math.pi*13+phase*.7)
  pts.append((x,int(y)))
 poly=pts+[(W+100,H+100),(-80,H+100)]
 d.polygon(poly,fill=(72,34,22,int(225*alpha)))
 d.line(pts,fill=(255,192,101,int(245*alpha)),width=11,joint='curve')
 d.line([(x,y+19) for x,y in pts],fill=(187,94,39,int(210*alpha)),width=7,joint='curve')
 # Thick glossy rivulets along the crest.
 for k in range(5):
  shift=(phase*105+k*217)%(W+260)-130
  y=int(top+75+34*math.sin(shift/W*math.pi*4+phase))
  length=70+25*k
  d.line((shift,y,shift+length,y+12),fill=(255,207,121,int((95+25*k)*alpha)),width=max(2,7-k))

def draw_droplets(frame,t,seed=3,color=SYRUP_HI,count=30,area=(0,400,1080,1550),speed=320):
 d=ImageDraw.Draw(frame,'RGBA');rng=np.random.default_rng(seed);x0,y0,x1,y1=area
 for i in range(count):
  xx,yy,sz,ph=rng.random(4)
  x=int(x0+xx*(x1-x0)+math.sin(t*1.7+ph*8)*17)
  y=int(y0+((yy*(y1-y0)+t*speed*(.5+sz))%(y1-y0)))
  rad=2+int(sz*6);a=int(70+135*(.5+.5*math.sin(t*2.5+ph*5)))
  d.ellipse((x-rad,y-rad,x+rad,y+rad),fill=(*color,a))
  if i%5==0:d.ellipse((x-rad*.45,y-rad*.7,x+rad*.25,y-rad*.1),fill=(255,238,183,int(a*.8)))

def draw_hook(frame,t,fonts):
 d=ImageDraw.Draw(frame,'RGBA');progress=clamp(t/1.55)
 draw_wave(frame,.25+.78*progress,phase=t*2.8,alpha=.92,base=.92)
 draw_droplets(frame,t,seed=1919,count=32,area=(70,520,1020,1500),speed=210)
 if t<.42:
  d.rounded_rectangle((190,178,890,302),radius=22,fill=(8,13,22,200),outline=(255,255,255,70),width=2)
  d.text((540,239),"BOSTON // 1919",font=fonts['hook_small'],fill=GOLD,anchor='mm')
 elif t<1.78:
  d.rounded_rectangle((63,156,1017,420),radius=24,fill=(4,10,19,195),outline=(255,255,255,75),width=2)
  d.text((540,248),"A 25-FOOT WAVE.",font=fonts['hook'],fill=IVORY,anchor='mm',stroke_width=3,stroke_fill=(4,8,15,210))
  d.text((540,348),"NOT WATER. MOLASSES.",font=fonts['hook'],fill=GOLD,anchor='mm',stroke_width=3,stroke_fill=(4,8,15,210))
 d.rectangle((0,0,W,6),fill=(255,255,255,40));d.rectangle((0,0,int(W*t/HOOK),6),fill=GOLD)
 return frame

def split_lines(text,d,font,maxw=920):
 words=text.split();lines=[];cur=[]
 for w in words:
  s=' '.join(cur+[w])
  if cur and d.textbbox((0,0),s,font=font)[2]>maxw:lines.append(cur);cur=[w]
  else:cur.append(w)
 if cur:lines.append(cur)
 return lines

def draw_caption(frame,text,hl,font,alpha=1.0,ycenter=1450):
 d=ImageDraw.Draw(frame,'RGBA');lines=split_lines(text,d,font)
 heights=62; widths=[sum(d.textlength(w,font=font) for w in ln)+d.textlength(' ',font=font)*(len(ln)-1) for ln in lines]
 maxw=max(widths);cx=W/2;tot=heights*len(lines);padx,pady=32,18
 box=(int(cx-maxw/2-padx),int(ycenter-tot/2-pady),int(cx+maxw/2+padx),int(ycenter+tot/2+pady))
 d.rounded_rectangle(box,radius=22,fill=(5,10,18,int(210*alpha)),outline=(248,245,235,int(54*alpha)),width=2)
 for li,words in enumerate(lines):
  x=cx-widths[li]/2;y=ycenter-tot/2+li*heights-4
  for word in words:
   col=hl.get(word,hl.get(word.strip('.,!?;:'),IVORY))
   d.text((x+2,y+3),word,font=font,fill=(0,0,0,int(210*alpha)))
   d.text((x,y),word,font=font,fill=(*col,int(255*alpha)))
   x+=d.textlength(word,font=font)+d.textlength(' ',font=font)

def draw_hud(frame,beat,t,total,fonts):
 d=ImageDraw.Draw(frame,'RGBA');accent=beat['tag'][2]
 d.rectangle((0,0,W,5),fill=(255,255,255,45));d.rectangle((0,0,int(W*clamp(t/total)),5),fill=(*accent,235))
 local=t-beat['start'];a=smooth(min(1,local/.22))*smooth(min(1,(beat['end']-t)/.15))
 if a>.02:
  kicker,title,col=beat['tag'];x0,y0=58,138
  box1=d.textbbox((0,0),kicker,font=fonts['small']);box2=d.textbbox((0,0),title,font=fonts['tag'])
  bw=max(box1[2],box2[2])+52
  d.rounded_rectangle((x0,y0,x0+bw,y0+90),radius=15,fill=(5,12,21,int(208*a)),outline=(255,255,255,int(50*a)),width=2)
  d.rounded_rectangle((x0+12,y0+14,x0+19,y0+76),radius=3,fill=(*col,int(245*a)))
  d.text((x0+31,y0+10),kicker,font=fonts['small'],fill=(*SLATE,int(235*a)))
  d.text((x0+31,y0+38),title,font=fonts['tag'],fill=(*IVORY,int(255*a)))
  for p0,p1,txt,high in beat['caption_schedule']:
   if p0-.02<=local<=p1+.04:
    e=smooth(min(1,max(0,(local-p0+.03)/.09)))*smooth(min(1,max(0,(p1+.04-local)/.08)))
    draw_caption(frame,txt,high,fonts['caption'],e);break

def draw_action(frame,b,local,dur,fonts):
 d=ImageDraw.Draw(frame,'RGBA');u=clamp(local/max(dur,.01));act=b['action']
 if act=='tank':
  # The fracture line crawls down the riveted seam; sticky stream pulses at the breach.
  p=smooth(min(1,local/2.2));x=550+int(7*math.sin(local*3));y0=510;ystart=int(780-90*p)
  d.line((x,y0,x+int(5*math.sin(local*5)),ystart),fill=(255,186,95,220),width=5)
  d.polygon([(x-17,ystart),(x+18,ystart),(x+31,1260),(x-30,1260)],fill=(112,48,19,215))
  for k in range(4):
   yy=ystart+((local*280+k*125)%500)
   d.ellipse((x-9,yy,x+10,yy+44),fill=(192,92,34,230),outline=(255,191,97,200),width=2)
  draw_droplets(frame,local,seed=21,count=16,area=(250,450,850,1470),speed=115)
  if local<1.2:
   d.ellipse((x-90,ystart-28,x+90,ystart+35),outline=(255,188,95,int(160*(1-local/1.2))),width=4)
 elif act=='surge':
  p=smooth(min(1,local/max(2,dur*.48)));draw_wave(frame,p,phase=local*3.4,alpha=.9,base=.96)
  draw_droplets(frame,local,seed=33,count=45,area=(50,360,1030,1560),speed=260)
  # Loose boards and wheels streak sideways with the syrup.
  for i in range(9):
   x=int((i*151+local*230)%(W+100)-50);y=int(820+(i%4)*155+24*math.sin(local*3+i))
   d.line((x,y,x+65,y-12),fill=(174,108,66,220),width=8)
 elif act=='rescue':
  # Ripples spread around rescuers; lanterns sway; drifting amber droplets cross frame.
  for i in range(4):
   p=(local*.62+i*.23)%1;rad=int(30+360*p);a=int(125*(1-p))
   d.ellipse((540-rad,1190-rad*.24,540+rad,1190+rad*.24),outline=(227,166,96,a),width=4)
  draw_droplets(frame,local,seed=42,count=26,area=(100,350,980,1400),speed=85)
  for x,y,ph in [(210,850,0),(790,680,1),(505,975,2)]:
   q=.5+.5*math.sin(local*3+ph);d.ellipse((x-24-8*q,y-25-8*q,x+24+8*q,y+25+8*q),fill=(255,185,82,int(18+22*q)))
 elif act=='aftermath':
  # Stat card lands quietly; no graphic depictions of casualties.
  q=smooth(min(1,local/.7));d.rounded_rectangle((168,1120,912,1345),radius=24,fill=(6,13,22,int(218*q)),outline=(245,129,103,int(165*q)),width=2)
  d.text((230,1150),"21",font=fonts['stat'],fill=(255,120,104,int(255*q)))
  d.text((355,1180),"LIVES LOST",font=fonts['small'],fill=(247,240,227,int(245*q)))
  d.line((210,1245,870,1245),fill=(255,255,255,int(70*q)),width=2)
  d.text((228,1260),"150",font=fonts['stat_small'],fill=(255,197,92,int(255*q)))
  d.text((390,1282),"INJURED",font=fonts['small'],fill=(247,240,227,int(245*q)))
  draw_droplets(frame,local,seed=53,count=15,color=(160,100,52),area=(100,500,970,1180),speed=30)
 elif act=='inquiry':
  # A forensic reticle sweeps across the failed rivet and blueprint.
  x=int(240+620*smooth(u));y=int(1050+70*math.sin(local*1.2));r=int(82-24*smooth(min(1,local/1.1)))
  d.ellipse((x-r,y-r,x+r,y+r),outline=(90,245,201,190),width=3)
  for dx,dy in [(-r-18,0),(r+18,0),(0,-r-18),(0,r+18)]:d.line((x+dx*.65,y+dy*.65,x+dx,y+dy),fill=(90,245,201,210),width=3)
  d.line((x-r*.65,y,x+r*.65,y),fill=(90,245,201,75),width=2)
  if local>1.4:
   d.rounded_rectangle((600,1080,980,1175),radius=16,fill=(5,13,23,190),outline=(241,107,92,180),width=2)
   d.text((640,1107),"RIVET FAILURE",font=fonts['tag'],fill=CORAL)
 elif act=='court':
  q=smooth(min(1,max(0,(local-1.0)/.45)))
  # Animated gavel and LIABLE stamp fall into frame on the spoken verdict.
  y=int(480+q*410)
  d.line((650,y-110,795,y+34),fill=(109,66,45,255),width=36)
  d.rounded_rectangle((590,y-154,710,y-75),radius=18,fill=(143,98,64,255),outline=(255,218,158,240),width=3)
  if q>.72:
   d.rounded_rectangle((125,1010,955,1175),radius=18,fill=(88,23,17,210),outline=(255,137,95,220),width=4)
   d.text((540,1091),"LIABLE",font=fonts['liable'],fill=(255,222,171,255),anchor='mm',stroke_width=2,stroke_fill=(52,11,12,220))
  for i in range(8):
   x=160+i*110;y2=620+int(8*math.sin(local*3+i));d.line((x,y2,x+25,y2-20),fill=(255,214,145,90),width=2)
 elif act=='legacy':
  q=smooth(min(1,local/1.6));
  # Animated blueprint traces from the historic failure to present-day safety design.
  d.line((80,1050,80+830*q,1050),fill=(88,243,198,170),width=3)
  for i in range(5):
   x=int(145+i*170);yy=int(800+30*math.sin(local*1.2+i))
   d.ellipse((x-6,yy-6,x+6,yy+6),fill=(255,193,93,190))
  if local>.75:
   d.rounded_rectangle((126,1125,954,1240),radius=20,fill=(5,14,22,185),outline=(94,238,197,175),width=2)
   d.text((540,1182),"SAFETY IS ENGINEERED",font=fonts['tag'],fill=MINT,anchor='mm')


def draw_hook_transition(frame,t,bg_tank,fonts):
 u=clamp((t-HOOK)/REWIND);q=smooth(u)
 # Rewind streaks, then an amber wipe reveals the failing tank.
 d=ImageDraw.Draw(frame,'RGBA')
 for k in range(7):
  y=480+k*135;d.line((-120,y+q*35,W+100,y-80+q*35),fill=(255,188,89,int(120*(1-q))),width=4+(k%3))
 veil=int(215*(1-q));d.rectangle((0,0,W,H),fill=(74,34,20,veil))
 if q>.04:
  img=bg_tank.copy();d2=ImageDraw.Draw(img,'RGBA');d2.rectangle((0,0,W,H),fill=(0,0,0,int(95*(1-q))))
  return Image.blend(frame,img,q)
 return frame

def render_frame(t,total,timeline,bgs,fonts,idx):
 if t<HOOK:
  u=clamp(t/HOOK);frame=camera(bgs['scene_01_hook.jpg'],u,(0,.03,0,-.02,1.04,1.13));return draw_hook(frame,t,fonts)
 if t<VOICE_START:
  base=camera(bgs['scene_01_hook.jpg'],1,(0,.03,0,-.02,1.04,1.13));tank=camera(bgs['scene_02_tank.jpg'],0,BEATS[0]['cam']);return draw_hook_transition(base,t,tank,fonts)
 last=timeline[-1]['end']
 if t>=last:
  b=timeline[-1];local=t-last;frame=camera(bgs[b['bg']],1,b['cam']);draw_action(frame,b,local,OUTRO,fonts)
  d=ImageDraw.Draw(frame,'RGBA');d.rounded_rectangle((94,260,986,440),radius=25,fill=(5,13,22,198),outline=(103,239,194,145),width=2)
  d.text((540,350),"SAFETY IS ENGINEERED",font=fonts['hook'],fill=IVORY,anchor='mm');return frame
 beat=timeline[0]
 for b in timeline:
  if b['start']<=t<b['end']:beat=b;break
 local=t-beat['start'];u=clamp(local/max(.01,beat['end']-beat['start']))
 frame=camera(bgs[beat['bg']],u,beat['cam'])
 # Fine filmic motion, with impact tremor around the tank burst and courtroom gavel.
 if (beat['action']=='tank' and .8<local<1.3) or (beat['action']=='court' and 1.0<local<1.3):
  amt=7*math.exp(-abs(local-1.05)*12);dx=int(amt*math.sin(idx*2.3));dy=int(amt*math.cos(idx*2.7));tmp=Image.new('RGB',(W,H),(0,0,0));tmp.paste(frame,(dx,dy));frame=tmp
 draw_action(frame,beat,local,beat['end']-beat['start'],fonts);draw_hud(frame,beat,t,total,fonts)
 return frame

def load_fonts():
 return {"caption":ImageFont.truetype(str(FONT/'montserrat-latin-800-normal.woff'),50),
         "small":ImageFont.truetype(str(FONT/'space-grotesk-latin-700-normal.woff'),22),
         "tag":ImageFont.truetype(str(FONT/'bebas-neue-latin-400-normal.woff'),37),
         "hook":ImageFont.truetype(str(FONT/'bebas-neue-latin-400-normal.woff'),78),
         "hook_small":ImageFont.truetype(str(FONT/'space-grotesk-latin-700-normal.woff'),32),
         "stat":ImageFont.truetype(str(FONT/'bebas-neue-latin-400-normal.woff'),105),
         "stat_small":ImageFont.truetype(str(FONT/'bebas-neue-latin-400-normal.woff'),72),
         "liable":ImageFont.truetype(str(FONT/'bebas-neue-latin-400-normal.woff'),124)}

def main():
 WORK.mkdir(parents=True,exist_ok=True)
 print('1/4 Preparing voice tracks, timing, and animated cold open...',flush=True)
 vo,timeline,nframes,total=prepare_audio()
 for b in timeline:print(f"  Beat {b['id']}: {b['start']:.2f}-{b['end']:.2f}s | {b['tag'][1]}",flush=True)
 print(f"  Total {total:.2f}s, {nframes} frames",flush=True)
 print('2/4 Building original score and foley...',flush=True)
 mix=build_mix(vo,timeline,total);audio_path=WORK/'master_mix.wav';wavfile.write(audio_path,SR,mix)
 print('3/4 Loading original illustrations and type...',flush=True)
 names={b['bg'] for b in BEATS}|{'scene_01_hook.jpg'};bgs={n:load_bg(n) for n in names};fonts=load_fonts()
 ff_log=WORK/'encode.log';cmd=[FFMPEG,'-y','-f','rawvideo','-vcodec','rawvideo','-s',f'{W}x{H}','-pix_fmt','rgb24','-r',str(FPS),'-i','-',
  '-i',str(audio_path),'-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-profile:v','high','-c:a','aac','-b:a','192k','-movflags','+faststart','-shortest',str(OUT)]
 print('4/4 Rendering the animated Boston molasses story...',flush=True)
 with open(ff_log,'w') as log:
  proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stderr=log)
  try:
   for i in range(nframes):
    t=i/FPS;frame=render_frame(t,total,timeline,bgs,fonts,i);proc.stdin.write(frame.tobytes())
    if (i+1)%180==0 or i==nframes-1:print(f'  {i+1}/{nframes} frames ({100*(i+1)/nframes:.0f}%)',flush=True)
  finally:
   if proc.stdin:proc.stdin.close()
  ret=proc.wait()
 if ret:raise RuntimeError(f'FFmpeg failed ({ret}):\n{ff_log.read_text(errors="replace")[-2000:]}')
 print(f'SUCCESS: {OUT} ({OUT.stat().st_size/(1024*1024):.2f} MB)',flush=True)

if __name__=='__main__':main()

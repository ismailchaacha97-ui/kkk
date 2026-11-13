"""
MAROC MARRAKECH - MT4 port validation
====================================

The order-block engine of MT4/MAROC_MARRAKECH.mq4 is re-implemented here in
Python, bar by bar, exactly as written in MQL4 (shift based, closed bars,
state arrays).  It is compared against a faithful simulation of the original
Pine Script v5 logic on synthetic OHLCV data.

Both simulations start on the same bar and stop on the last CLOSED bar, so the
comparison is apples to apples.  Pine keeps an unbounded OB array while the MT4
indicator keeps only the newest "Number of OBs" entries, therefore the MT4 list
must be equal to the newest entries of the Pine list.

Run:  python3 validate_order_blocks.py
"""

import random

def make_bars(n=3000, seed=7):
    random.seed(seed)
    bars = []
    px = 1.1000
    for i in range(n):
        drift = random.gauss(0, 0.0009)
        o = px
        c = o + drift
        h = max(o, c) + abs(random.gauss(0, 0.0005))
        l = min(o, c) - abs(random.gauss(0, 0.0005))
        v = random.randint(50, 500)
        bars.append(dict(o=o, h=h, l=l, c=c, v=v, t=i))
        px = c
    return bars

def pine_run(bars, start_n, end_n, internal=5, ob_num=5, pos="Precise", overlap=True, mitigation="Absolute", filt="None", log=None):
    N=len(bars)
    H=[b['h'] for b in bars]; L=[b['l'] for b in bars]; C=[b['c'] for b in bars]
    O=[b['o'] for b in bars]; Vv=[b['v'] for b in bars]
    def pvh(n,k):
        p=n-k
        if p-k<0: return None
        mid=H[p]
        for i in range(p-k,p+k+1):
            if i!=p and H[i]>=mid: return None
        return mid
    def pvl(n,k):
        p=n-k
        if p-k<0: return None
        mid=L[p]
        for i in range(p-k,p+k+1):
            if i!=p and L[i]<=mid: return None
        return mid
    def posv(bull,i):
        if pos=="Full": return H[i] if bull else L[i]
        if pos=="Middle": return (O[i]+H[i]+L[i]+C[i])/4
        return (H[i]+L[i])/2
    def hlcc4(i): return (H[i]+L[i]+2*C[i])/4
    upP=[];upL=[];dnP=[];dnL=[]; itrend=0; hN=lN=None
    bull=[];bear=[]
    for n in range(start_n, end_n+1):
        k=internal
        iH=pvh(n,k); iL=pvl(n,k)
        sb=ss=False; txt=""
        if iH is not None: upP.insert(0,H[n-k]); upL.insert(0,H[n-k])
        if iL is not None: dnP.insert(0,L[n-k]); dnL.insert(0,L[n-k])
        if len(upP)>0 and len(dnL)>1 and C[n-1]<=upP[0]<C[n]:
            choch = itrend<0
            txt = "BOS" if not choch else ("CHoCH+" if dnL[0]>dnL[1] else "CHoCH")
            if filt=="None" or filt==txt: sb=True
            itrend=1; upP.clear()
        if len(dnP)>0 and len(upL)>1 and C[n-1]>=dnP[0]>C[n]:
            choch = itrend>0
            txt = "BOS" if not choch else ("CHoCH+" if upL[0]<upL[1] else "CHoCH")
            if filt=="None" or filt==txt: ss=True
            itrend=-1; dnP.clear()
        if iH is not None: hN=n-k
        if iL is not None: lN=n-k
        for isbull in (True,False):
            arr = bull if isbull else bear
            flag = sb if isbull else ss
            loc  = hN if isbull else lN
            if flag and loc is not None:
                d=n-loc
                if d>=1:
                    hs=[H[n-j] for j in range(d)]; ls=[L[n-j] for j in range(d)]
                    mMin=ls.index(min(ls)); mMax=hs.index(max(hs))
                    bU=n-(mMin+1); bD=n-(mMax+1)
                    rec={}
                    rec['dir']=(1 if C[bU]>O[bU] else -1) if isbull else (1 if C[bD]>O[bD] else -1)
                    if isbull: rec['top']=posv(True,bU); rec['btm']=min(ls); rec['left']=bars[n-mMin]['t']; rec['cV']=Vv[bU]
                    else:      rec['top']=max(hs); rec['btm']=posv(False,bD); rec['left']=bars[n-mMax]['t']; rec['cV']=Vv[bD]
                    rec['avg']=(rec['top']+rec['btm'])/2
                    if pos=="Precise":
                        if isbull:
                            if rec['avg']<min(C[bU],O[bU]) and rec['top']>hlcc4(bU):
                                rec['top']=rec['avg']; rec['avg']=(rec['top']+rec['btm'])/2
                        else:
                            cmpv=O[bD] if C[bU]<O[bU] else C[bD]
                            if rec['avg']>cmpv and rec['btm']<hlcc4(bD):
                                rec['btm']=rec['avg']; rec['avg']=(rec['top']+rec['btm'])/2
                    if log is not None: log.append((n,'B' if isbull else 'S',rec['left'],round(rec['top'],6),round(rec['btm'],6)))
                    if overlap and len(arr)>0:
                        if (rec['btm']<arr[0]['top']) if isbull else (rec['top']>arr[0]['btm']):
                            arr.pop(0)
                    arr.insert(0,rec)
            kept=[]
            for r in arr:
                pt = r['avg'] if mitigation=="Middle" else (r['btm'] if isbull else r['top'])
                if (C[n]<pt) if isbull else (C[n]>pt): continue
                kept.append(r)
            arr[:]=kept
    return bull,bear

def mql_run(bars, internal=5, ob_num=5, pos="Precise", overlap=True, mitigation="Absolute", filt="None", maxReplay=3000, log=None):
    N=len(bars)
    def H(s): return bars[N-1-s]['h']
    def L(s): return bars[N-1-s]['l']
    def C(s): return bars[N-1-s]['c']
    def O(s): return bars[N-1-s]['o']
    def Vv(s): return bars[N-1-s]['v']
    def T(s): return bars[N-1-s]['t']
    B=N
    def pvh(sh,k):
        p=sh+k
        if p+k>=B: return None
        mid=H(p)
        for i in range(p-k,p):
            if i<0 or H(i)>=mid: return None
        for j in range(p+1,p+k+1):
            if H(j)>=mid: return None
        return mid
    def pvl(sh,k):
        p=sh+k
        if p+k>=B: return None
        mid=L(p)
        for i in range(p-k,p):
            if i<0 or L(i)<=mid: return None
        for j in range(p+1,p+k+1):
            if L(j)<=mid: return None
        return mid
    def posv(sh,isbull):
        if pos=="Full": return H(sh) if isbull else L(sh)
        if pos=="Middle": return (O(sh)+H(sh)+L(sh)+C(sh))/4
        return (H(sh)+L(sh))/2
    def hlcc4(sh): return (H(sh)+L(sh)+2*C(sh))/4
    upP=[];upL=[];dnP=[];dnL=[]; itrend=0; lastHi=lastLo=None
    bull=[];bear=[]
    startSh=min(B-1-2*max(internal,10)-2, maxReplay, B-2)
    for sh in range(startSh,0,-1):
        k=internal
        iH=pvh(sh,k); iL=pvl(sh,k)
        sb=ss=False
        if iH is not None: upP.insert(0,iH); upL.insert(0,iH)
        if iL is not None: dnP.insert(0,iL); dnL.insert(0,iL)
        if len(upP)>0 and len(dnL)>1 and C(sh+1)<=upP[0]<C(sh):
            txt="BOS" if itrend>=0 else ("CHoCH+" if dnL[0]>dnL[1] else "CHoCH")
            if filt=="None" or filt==txt: sb=True
            itrend=1; upP.clear()
        if len(dnP)>0 and len(upL)>1 and C(sh+1)>=dnP[0]>C(sh):
            txt="BOS" if itrend<=0 else ("CHoCH+" if upL[0]<upL[1] else "CHoCH")
            if filt=="None" or filt==txt: ss=True
            itrend=-1; dnP.clear()
        if iH is not None: lastHi=T(sh+k)
        if iL is not None: lastLo=T(sh+k)
        for isbull in (True,False):
            arr = bull if isbull else bear
            flag = sb if isbull else ss
            loc = lastHi if isbull else lastLo
            if flag and loc is not None:
                locShift=(N-1)-loc
                wl=locShift-sh
                if wl>=1:
                    mMin=-1;mMax=-1;mn=None;mx=None
                    for j in range(wl):
                        s2=sh+j
                        if mMin<0 or L(s2)<mn: mn=L(s2); mMin=j
                        if mMax<0 or H(s2)>mx: mx=H(s2); mMax=j
                    shU=sh+mMin+1; shD=sh+mMax+1
                    rec={}
                    rec['dir']=(1 if C(shU)>O(shU) else -1) if isbull else (1 if C(shD)>O(shD) else -1)
                    if isbull: rec['top']=posv(shU,True); rec['btm']=mn; rec['left']=T(sh+mMin); rec['cV']=Vv(shU)
                    else:      rec['top']=mx; rec['btm']=posv(shD,False); rec['left']=T(sh+mMax); rec['cV']=Vv(shD)
                    rec['avg']=(rec['top']+rec['btm'])/2
                    if pos=="Precise":
                        if isbull:
                            if rec['avg']<min(C(shU),O(shU)) and rec['top']>hlcc4(shU):
                                rec['top']=rec['avg']; rec['avg']=(rec['top']+rec['btm'])/2
                        else:
                            cmpv=O(shD) if C(shU)<O(shU) else C(shD)
                            if rec['avg']>cmpv and rec['btm']<hlcc4(shD):
                                rec['btm']=rec['avg']; rec['avg']=(rec['top']+rec['btm'])/2
                    if log is not None: log.append((N-1-sh,'B' if isbull else 'S',rec['left'],round(rec['top'],6),round(rec['btm'],6)))
                    if overlap and len(arr)>0:
                        if (rec['btm']<arr[0]['top']) if isbull else (rec['top']>arr[0]['btm']):
                            arr.pop(0)
                    arr.insert(0,rec)
                    if len(arr)>ob_num: arr.pop()
            kept=[]
            for r in arr:
                pt = r['avg'] if mitigation=="Middle" else (r['btm'] if isbull else r['top'])
                if (C(sh)<pt) if isbull else (C(sh)>pt): continue
                kept.append(r)
            arr[:]=kept
    return bull,bear

# ------------------------------------------------------------------ matrix
def compare(pine, mql, ob_num_keys=('left','top','btm','avg','cV','dir')):
    pb, ps = pine
    mb, ms = mql
    if len(mb) > len(pb) or len(ms) > len(ps):
        return False
    for x, y in list(zip(pb[:len(mb)], mb)) + list(zip(ps[:len(ms)], ms)):
        for k in ob_num_keys:
            if abs(float(x[k]) - float(y[k])) > 1e-12:
                return False
    return True


def main():
    checks = fails = 0
    for seed in (1, 2, 3, 7, 42, 99):
        for nbars in (1200, 2500):
            bars = make_bars(nbars, seed)
            n = len(bars)
            start_sh = n - 1 - 2 * max(5, 10) - 2
            pine_start = n - 1 - start_sh
            for pos in ("Full", "Middle", "Accurate", "Precise"):
                for filt in ("None", "BOS", "CHoCH", "CHoCH+"):
                    for overlap in (True, False):
                        for mitig in ("Absolute", "Middle"):
                            pine = pine_run(bars, pine_start, n - 2, pos=pos,
                                            overlap=overlap, mitigation=mitig,
                                            filt=filt)
                            mql = mql_run(bars, pos=pos, overlap=overlap,
                                          mitigation=mitig, filt=filt)
                            checks += 1
                            if not compare(pine, mql):
                                fails += 1
                                print("MISMATCH", seed, nbars, pos, filt, overlap, mitig)
    print("%d/%d configurations identical" % (checks - fails, checks))
    return fails == 0


if __name__ == "__main__":
    raise SystemExit(0 if main() else 1)

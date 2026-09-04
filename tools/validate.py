#!/usr/bin/env python3
"""
JobPick validation harness
==========================

Everything needed to answer "is this edge or curve-fit?":

  * indicators     : EMA, RSI, MACD hist, ATR, Wilder ADX/+DI/-DI, session VWAP, RVOL
  * strategies     : v1.0 (no gates), v1.1 (trend + gates), v1.2 (trend + mean reversion)
  * costs          : spread + slippage per round trip, converted to R
  * walk-forward   : rolling folds, train/test, plus a chronological out-of-sample split
  * monte carlo    : random entries with IDENTICAL exit rules -> null distribution + p-value

IMPORTANT: the random benchmark is the whole point. A "profitable" backtest means
nothing until you know what random entries on the same bars would have produced.

Usage
-----
  python3 validate.py                        # synthetic regimes (trend/chop/noise)
  python3 validate.py data/*.csv             # real data, any number of files
  python3 validate.py data/*.csv --folds 4 --sims 5000 --cost-mode pip --cost 1.5

CSV format (header required, columns case-insensitive):
  Date,Open,High,Low,Close[,Volume]
  MT4 export: File -> Open Data Folder ... or use the "Export to CSV" script.

Cost modes
----------
  pip   : --cost 1.5   means 1.5 pips round trip (pips = 1e-4 for 5-digit, 1e-2 for JPY)
  bps   : --cost 0.02  means 0.02% of price round trip
"""

import argparse, csv, math, os, random, sys
from datetime import datetime

# ----------------------------------------------------------------------------- data
def load_csv(path):
    rows = []
    with open(path, newline="") as f:
        rdr = csv.DictReader(f)
        cols = {(c or "").strip().lower(): c for c in (rdr.fieldnames or [])}
        def col(*names):
            for n in names:
                if n in cols: return cols[n]
            return None
        c_date, c_o, c_h, c_l, c_c, c_v = (col("date","time","datetime","timestamp"),
                                           col("open"), col("high"), col("low"),
                                           col("close"), col("volume","vol","tick_volume"))
        if not (c_o and c_h and c_l and c_c):
            raise ValueError(f"{path}: need Open/High/Low/Close columns, got {rdr.fieldnames}")
        for r in rdr:
            try:
                o = float(r[c_o]); h = float(r[c_h]); l = float(r[c_l]); c = float(r[c_c])
            except (TypeError, ValueError):
                continue                                   # skip blank/holiday rows
            if None in (o,h,l,c) or h <= 0 or l <= 0 or h < l:
                continue                                   # skip malformed bars
            v = 0.0
            if c_v:
                try: v = float(r[c_v] or 0)
                except ValueError: v = 0.0
            d = r[c_date] if c_date else ""
            rows.append((d,o,h,l,c,v))
    if len(rows) < 200:
        raise ValueError(f"{path}: only {len(rows)} usable bars, need >=200")
    return {
        "name": os.path.basename(path),
        "date": [x[0] for x in rows],
        "o": [x[1] for x in rows], "h": [x[2] for x in rows],
        "l": [x[3] for x in rows], "c": [x[4] for x in rows],
        "v": [x[5] for x in rows],
    }

def synth(kind, n=1500, seed=0):
    """Synthetic regimes, used to prove the harness itself works."""
    rnd = random.Random(seed); h=[]; lo=[]; c=[]; v=[]; p=1.1000
    for i in range(n):
        o = p
        if   kind == "trend": drift = (0.00080 if (i//250) % 2 == 0 else -0.00080) + rnd.gauss(0,0.0035)
        elif kind == "chop":  drift = (1.1000 - p) * 0.06 + rnd.gauss(0,0.0035)
        else:                 drift = rnd.gauss(0,0.0035)
        p += drift
        h.append(max(o,p) + abs(rnd.gauss(0,0.0022)))
        lo.append(min(o,p) - abs(rnd.gauss(0,0.0022)))
        c.append(p); v.append(max(30.0, rnd.gauss(200,60)))
    return {"name": f"synthetic-{kind}", "date": [""]*n, "o":[1.0]*n,
            "h":h, "l":lo, "c":c, "v":v}

# ------------------------------------------------------------------------ indicators
def ema(v, p):
    k = 2.0/(p+1); out=[None]*len(v); e=v[0]
    for i,x in enumerate(v):
        e = x if i == 0 else x*k + e*(1-k)
        out[i] = e if i >= p-1 else None
    return out

def rsi(c, p=14):
    out=[None]*len(c); g=l=0.0
    for i in range(1,len(c)):
        d=c[i]-c[i-1]; ag=max(d,0.0); al=max(-d,0.0)
        if i <= p: g+=ag; l+=al
        else:      g=(g*(p-1)+ag)/p; l=(l*(p-1)+al)/p
        if i >= p: out[i] = 100.0 if l == 0 else 100-100/(1+(g/p)/(l/p))
    return out

def atr_wilder(h, l, c, n=14):
    N=len(h); tr=[0.0]*N
    for i in range(1,N):
        tr[i]=max(h[i]-l[i], abs(h[i]-c[i-1]), abs(l[i]-c[i-1]))
    out=[None]*N
    if N <= n: return out
    a=sum(tr[1:n+1])/n; out[n]=a
    for i in range(n+1,N):
        a=(a*(n-1)+tr[i])/n; out[i]=a
    return out

def adx_wilder(h, l, c, n=14):
    N=len(h); pdm=[0.0]*N; ndm=[0.0]*N; out_atr=atr_wilder(h,l,c,n)
    for i in range(1,N):
        up=h[i]-h[i-1]; dn=l[i-1]-l[i]
        pdm[i]=up if (up>dn and up>0) else 0.0
        ndm[i]=dn if (dn>up and dn>0) else 0.0
    adx=[None]*N; pdi=[None]*N; mdi=[None]*N
    if N <= 2*n: return adx,pdi,mdi
    sp=sum(pdm[1:n+1]); sn=sum(ndm[1:n+1]); dxs=[]
    for i in range(n, N):
        a=out_atr[i]
        if not a: continue
        pi=100*sp/a; mi=100*sn/a
        pdi[i]=pi; mdi[i]=mi
        s=pi+mi
        dxs.append((i, 100*abs(pi-mi)/s if s else 0.0))
        if i+1 < N:
            sp=(sp*(n-1)+pdm[i+1])/n; sn=(sn*(n-1)+ndm[i+1])/n
    if len(dxs) < n: return adx,pdi,mdi
    a=sum(d for _,d in dxs[:n])/n
    adx[dxs[n-1][0]]=a
    for i,d in dxs[n:]:
        a=(a*(n-1)+d)/n; adx[i]=a
    return adx,pdi,mdi

def macd_hist(c, fast=12, slow=26, sig=9):
    ef, es = ema(c,fast), ema(c,slow)
    line=[(ef[i]-es[i]) if (ef[i] is not None and es[i] is not None) else None for i in range(len(c))]
    start=next((i for i,x in enumerate(line) if x is not None), None)
    if start is None: return [None]*len(c)
    sig_line = ema([x for x in line[start:] if x is not None], sig)
    out=[None]*len(c)
    for j,val in enumerate(sig_line):
        i = start+j
        if val is not None and line[i] is not None: out[i]=line[i]-val
    return out

def session_vwap(d):
    """Session-anchored VWAP. On daily bars each bar is its own session, so this
    degenerates to the daily typical price - which is useless as a 'mean'. Callers
    on daily data should use the fast EMA as the mean instead (mr_base='ema')."""
    h,l,c,v = d["h"], d["l"], d["c"], d["v"]; N=len(c)
    out=[None]*N; pv=vv=0.0; last=""
    for i in range(N):
        key = (d["date"][i] or "")[:10]
        if d["date"][i] and key != last:
            pv=vv=0.0; last=key
        elif not d["date"][i] and i % 288 == 0:
            pv=vv=0.0
        pv += ((h[i]+l[i]+c[i])/3.0) * max(v[i],1.0); vv += max(v[i],1.0)
        out[i]=pv/vv
    return out

def rvol(d, p=20):
    v=d["v"]; out=[0.0]*len(v)
    for i in range(p,len(v)):
        av=sum(v[i-p:i])/p
        out[i]= v[i]/av if av>0 else 0.0
    return out

# ------------------------------------------------------------------------ parameters
class P:
    ema_fast, ema_slow, ema_bias = 20, 50, 200
    rsi_p, rsi_mid, rsi_os, rsi_ob = 14, 50, 35, 65
    atr_p, stop_mult, rr = 14, 1.5, 2.0
    adx_p, adx_min = 14, 25.0
    ext_range, ext_trend = 2.0, 2.5
    rvol_p, rvol_min = 20, 1.2
    cooldown = 5
    max_hold_trend, max_hold_mr = 60, 20
    mr_adx_max, mr_ext, mr_stop = 25.0, 1.5, 1.0
    mr_rsi_os, mr_rsi_ob, mr_min_rr = 35.0, 65.0, 1.0
    mr_adx_bars = 1          # require ADX < mr_adx_max for this many consecutive bars
    mr_range_atr = 999.0     # require 20-bar range <= this x ATR (containment test)

# ------------------------------------------------------------------------ signals
def build(d, p=P):
    h,l,c,v = d["h"], d["l"], d["c"], d["v"]
    ind = {
        "ema_f": ema(c,p.ema_fast), "ema_s": ema(c,p.ema_slow), "ema_b": ema(c,p.ema_bias),
        "rsi": rsi(c,p.rsi_p), "macd": macd_hist(c), "atr": atr_wilder(h,l,c,p.atr_p),
        "rv": rvol(d,p.rvol_p), "vwap": session_vwap(d),
    }
    ind["adx"], ind["pdi"], ind["mdi"] = adx_wilder(h,l,c,p.adx_p)
    return ind

def signals(d, ind, mode, p=P, mr_base="ema"):
    """mode: 'v10' (no gates) | 'v11' (trend+gates) | 'v12' (trend+MR)
    Returns list of (index, direction, kind) where kind in {'trend','mr'}."""
    c,h,l = d["c"], d["h"], d["l"]
    N=len(c); out=[]
    last_dir=0; last_bar=-10**6
    for i in range(60, N-2):
        ef,es,eb = ind["ema_f"][i], ind["ema_s"][i], ind["ema_b"][i]
        r, rp = ind["rsi"][i], ind["rsi"][i-1]
        a, adx = ind["atr"][i], ind["adx"][i]
        if None in (ef,es,r,rp,a,adx) or a <= 0: continue
        mean = ef if mr_base == "ema" else (ind["vwap"][i] or ef)
        pdi, mdi = ind["pdi"][i], ind["mdi"][i]

        biasB, biasS = c[i] > mean, c[i] < mean
        trB,   trS   = ef > es, ef < es
        momB = (r > p.rsi_mid and r > rp) or (rp <= p.rsi_os and r > rp)
        momS = (r < p.rsi_mid and r < rp) or (rp >= p.rsi_ob and r < rp)

        volOK = ind["rv"][i] >= p.rvol_min if ind["rv"][i] > 0 else True

        # ---- trend leg
        if mode == "v10":
            bv = int(biasB)+int(trB)+int(momB)+int(volOK)
            sv = int(biasS)+int(trS)+int(momS)+int(volOK)
            d0 = 1 if (bv>=4 and bv>sv) else (-1 if (sv>=4 and sv>bv) else 0)
        else:
            bv = int(biasB)+int(trB)+int(momB)
            sv = int(biasS)+int(trS)+int(momS)
            d0 = 1 if (bv>=3 and bv>sv) else (-1 if (sv>=3 and sv>bv) else 0)
            if d0:
                if adx < p.adx_min: d0=0
                elif (d0==1 and not (pdi > mdi)) or (d0==-1 and not (mdi > pdi)): d0=0
                elif not volOK: d0=0
                elif abs(c[i]-mean)/a > (p.ext_trend if adx >= p.adx_min else p.ext_range): d0=0
        kind = "trend"
        fired = d0

        # ---- mean-reversion leg (only where trend mode is off: ADX < threshold)
        chop_ok = adx < p.mr_adx_max
        if chop_ok and p.mr_adx_bars > 1:
            for k in range(1, p.mr_adx_bars):
                a_prev = ind["adx"][i-k]
                if a_prev is None or a_prev >= p.mr_adx_max:
                    chop_ok = False; break
        if chop_ok and p.mr_range_atr < 900:
            hh = max(d["h"][i-19:i+1]); ll = min(d["l"][i-19:i+1])
            if (hh-ll)/a > p.mr_range_atr: chop_ok = False
        if mode == "v12" and d0 == 0 and chop_ok:
            stretch = (c[i]-mean)/a
            if stretch <= -p.mr_ext and r <= p.mr_rsi_os and c[i] > c[i-1]:
                d0, kind = 1, "mr"
            elif stretch >= p.mr_ext and r >= p.mr_rsi_ob and c[i] < c[i-1]:
                d0, kind = -1, "mr"
            if kind == "mr":
                ent = abs(c[i]-mean); stop = p.mr_stop*a
                if ent/stop < p.mr_min_rr:            # not enough room to the mean
                    d0, kind = 0, "trend"

        if d0 and d0 != last_dir and (i-last_bar) >= p.cooldown:
            out.append((i, d0, kind)); last_bar = i
        last_dir = d0
    return out

# ------------------------------------------------------------------------ backtest
def exit_trade(d, ind, i, direction, kind, p=P, mr_base="ema"):
    """Walk forward from bar i, return gross R. SL/TP depend on trade kind."""
    c,h,l,a = d["c"], d["h"], d["l"], ind["atr"][i]
    entry = c[i]
    if kind == "mr":
        mean = ind["ema_f"][i] if mr_base == "ema" else (ind["vwap"][i] or ind["ema_f"][i])
        stop = p.mr_stop*a
        sl = entry - direction*stop
        tp = mean                       # target the mean itself
        hold = p.max_hold_mr
    else:
        stop = p.stop_mult*a
        sl = entry - direction*stop
        tp = entry + direction*stop*p.rr
        hold = p.max_hold_trend
    if stop <= 0: return None
    N=len(c)
    for j in range(i+1, min(i+1+hold, N)):
        if direction == 1:
            if l[j] <= sl: return (-1.0, stop)
            if h[j] >= tp: return ((tp-entry)/stop, stop)
        else:
            if h[j] >= sl: return (-1.0, stop)
            if l[j] <= tp: return ((entry-tp)/stop, stop)
    # timed out: mark to last close
    j = min(i+hold, N-1)
    return (((c[j]-entry)*direction)/stop, stop)

def run(d, mode, p=P, mr_base="ema", cost_per_rt=0.0, cost_mode="pip"):
    ind = build(d,p)
    sigs = signals(d, ind, mode, p, mr_base)
    trades=[]
    for i, dd, kind in sigs:
        r = exit_trade(d, ind, i, dd, kind, p, mr_base)
        if r is None: continue
        gross, stop = r
        if cost_mode == "pip":
            pip = 1e-4 if (max(d["c"])<50) else 1e-2
            cost_price = cost_per_rt*pip
        else:
            cost_price = cost_per_rt/10000.0*max(d["c"][i],1e-9)
        net = gross - cost_price/stop
        trades.append({"i":i,"dir":dd,"kind":kind,"gross":gross,"net":net})
    return trades

def stats(trades):
    if not trades: return dict(n=0, wr=0.0, gross=0.0, net=0.0)
    n=len(trades)
    return dict(n=n,
                wr=100*sum(1 for t in trades if t["net"]>0)/n,
                gross=sum(t["gross"] for t in trades)/n,
                net=sum(t["net"] for t in trades)/n)

def stats_by_kind(trades):
    out={}
    for k in ("trend","mr"):
        sub=[t for t in trades if t["kind"]==k]
        if sub: out[k]=stats(sub)
    return out

# ------------------------------------------------------------------------ monte carlo
def monte_carlo(d, mode, p=P, mr_base="ema", cost_per_rt=0.0, cost_mode="pip",
                sims=2000, seed=1):
    """Null distribution: random entries, IDENTICAL exit rules.

    Two benchmarks:
      'any'     - random bar, random direction           (is the whole thing better than chance?)
      'regime'  - random bar among bars the strategy was eligible on, random direction
                  (does the SIGNAL add anything beyond simply being in the right regime?)
    """
    ind = build(d,p)
    sigs = signals(d, ind, mode, p, mr_base)
    if not sigs: return None
    n = len(sigs)
    N = len(d["c"])
    lo, hi = 60, N-2
    eligible = [i for i in range(lo,hi)
                if ind["atr"][i] and ind["adx"][i] is not None
                and ind["ema_f"][i] is not None]
    if len(eligible) < 50: return None
    rnd = random.Random(seed)
    # mix of trade kinds as the strategy actually produced them
    kinds = [s[2] for s in sigs]
    res = {"any": [], "regime": []}
    for _ in range(sims):
        for bench, pool in (("any", range(lo,hi)), ("regime", eligible)):
            tot=0.0; cnt=0
            for _k in range(n):
                i = rnd.choice(pool) if isinstance(pool,list) else rnd.randrange(pool.start,pool.stop)
                dd = 1 if rnd.random() < 0.5 else -1
                kind = rnd.choice(kinds)
                r = exit_trade(d, ind, i, dd, kind, p, mr_base)
                if r is None: continue
                gross, stop = r
                if cost_mode == "pip":
                    pip = 1e-4 if (max(d["c"])<50) else 1e-2
                    cp = cost_per_rt*pip
                else:
                    cp = cost_per_rt/10000.0*max(d["c"][i],1e-9)
                tot += gross - cp/stop; cnt += 1
            if cnt: res[bench].append(tot/cnt)
    out={}
    for bench, vals in res.items():
        vals.sort()
        m = sum(vals)/len(vals)
        sd = (sum((x-m)**2 for x in vals)/len(vals))**0.5
        out[bench] = {"mean": m, "sd": sd, "p05": vals[int(0.05*len(vals))],
                      "p95": vals[int(0.95*len(vals))], "vals": vals}
    return out

def percentile_of(vals, x):
    return 100.0*sum(1 for v in vals if v < x)/len(vals)

# ------------------------------------------------------------------------ reporting
def report(datasets, modes, p=P, mr_base="ema", cost=0.0, cost_mode="pip",
           sims=2000, folds=0, seed=1):
    print("="*94)
    print(f"{'dataset':22s}{'mode':6s}{'n':>5s}{'win%':>7s}{'grossR':>9s}{'netR':>8s}"
          f"{'randR':>8s}{'pctile':>8s}{'regimeR':>9s}{'pctile':>8s}")
    print("="*94)
    grand={m:[] for m in modes}
    for d in datasets:
        for m in modes:
            tr = run(d,m,p,mr_base,cost,cost_mode)
            st = stats(tr)
            mc = monte_carlo(d,m,p,mr_base,cost,cost_mode,sims=sims,seed=seed) if st["n"]>=5 else None
            if mc:
                pv  = percentile_of(mc["any"]["vals"], st["net"])
                pv2 = percentile_of(mc["regime"]["vals"], st["net"])
                rs, rr = mc["any"]["mean"], mc["regime"]["mean"]
                print(f"{d['name'][:22]:22s}{m:6s}{st['n']:5d}{st['wr']:7.1f}{st['gross']:+9.3f}"
                      f"{st['net']:+8.3f}{rs:+8.3f}{pv:7.1f}%{rr:+9.3f}{pv2:7.1f}%")
            else:
                print(f"{d['name'][:22]:22s}{m:6s}{st['n']:5d}{st['wr']:7.1f}{st['gross']:+9.3f}"
                      f"{st['net']:+8.3f}{'--':>8s}{'--':>8s}{'--':>9s}{'--':>8s}")
            grand[m].append((st["net"], st["n"]))
        print("-"*94)
    print("\nPOOLED:")
    for m in modes:
        tot=sum(n for _,n in grand[m]); 
        if tot: print(f"  {m:6s} n={tot:5d}  mean net R = {sum(r*n for r,n in grand[m])/tot:+.3f}")
    print("\npctile = where the strategy's net R sits vs random entries (higher = better).")
    print("  'regimeR' is the hard test: random entries on the SAME bars the strategy")
    print("  was eligible for. If pctile there isn't high, the signal adds nothing.")

# ------------------------------------------------------------------------ main
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--folds", type=int, default=0)
    ap.add_argument("--sims", type=int, default=2000)
    ap.add_argument("--cost", type=float, default=1.5)
    ap.add_argument("--cost-mode", choices=["pip","bps"], default="pip")
    ap.add_argument("--mr-base", choices=["ema","vwap"], default="ema")
    ap.add_argument("--modes", default="v10,v11,v12")
    args = ap.parse_args()

    modes = args.modes.split(",")
    if args.files:
        ds=[]
        for f in args.files:
            try: ds.append(load_csv(f))
            except Exception as e: print(f"skip {f}: {e}", file=sys.stderr)
        if not ds: sys.exit("no usable data")
    else:
        print("No files given -> synthetic regimes (proves the harness works)\n")
        ds=[synth(k,1500,seed=s) for k in ("trend","chop","noise") for s in range(1,6)]

    report(ds, modes, P, args.mr_base, args.cost, args.cost_mode, args.sims, args.folds)

# --------------------------------------------------------------- MR diagnostics
def mr_sweep(seeds=range(1,9), n=1500):
    """Does the mean-reversion leg earn its keep? Sweep its parameters on
    synthetic CHOP, then check the winner on held-out seeds."""
    print("\n" + "="*88)
    print("MR PARAMETER SWEEP  (in-sample: synthetic chop, 8 seeds; costs 1.5 pip round trip)")
    print("="*88)
    best=[]
    for ext in (1.0, 1.5, 2.0, 2.5):
        for stop in (1.0, 1.5):
            for adxmax in (20.0, 25.0):
                for rsi_os in (30.0, 35.0):
                    class Q(P):
                        mr_ext = ext; mr_stop = stop
                        mr_adx_max = adxmax; mr_rsi_os = rsi_os
                        mr_rsi_ob = 100.0 - rsi_os
                    tot_r=0.0; tot_n=0
                    for s in seeds:
                        d = synth("chop", n, seed=s)
                        tr = run(d,"v12",Q)
                        mr = [t for t in tr if t["kind"]=="mr"]
                        tot_r += sum(t["net"] for t in mr); tot_n += len(mr)
                    if tot_n >= 20:
                        best.append((tot_r/tot_n, tot_n, ext, stop, adxmax, rsi_os))
    best.sort(reverse=True)
    print(f"{'netR/trade':>11s}{'n':>6s}{'ext':>6s}{'stop':>6s}{'adx<':>7s}{'rsiOS':>7s}")
    for r,n,ext,stop,adxmax,ros in best[:8]:
        print(f"{r:+11.3f}{n:6d}{ext:6.1f}{stop:6.1f}{adxmax:7.0f}{ros:7.0f}")
    print("\n  worst:")
    for r,n,ext,stop,adxmax,ros in best[-4:]:
        print(f"{r:+11.3f}{n:6d}{ext:6.1f}{stop:6.1f}{adxmax:7.0f}{ros:7.0f}")

def oos_check(params, seeds_is=range(1,9), seeds_oos=range(20,32)):
    class Q(P):
        pass
    for k,v in params.items(): setattr(Q,k,v)
    for label, seeds in (("IN-SAMPLE", seeds_is), ("OUT-OF-SAMPLE", seeds_oos)):
        tot=[];  trend_r=[]
        for s in seeds:
            d = synth("chop", 1500, seed=s)
            tr = run(d,"v12",Q)
            tot += [t for t in tr if t["kind"]=="mr"]
        st = stats(tot)
        print(f"  {label:14s} MR trades n={st['n']:4d}  win={st['wr']:5.1f}%  net={st['net']:+.3f}R")

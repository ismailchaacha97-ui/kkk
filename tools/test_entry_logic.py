"""Port of the entry-signal logic to validate behaviour."""
import random

def lineY(x1,y1,x2,y2,x):
    return y1 + (0.0 if x2==x1 else (y2-y1)/(x2-x1))*(x-x1)

def simulate(bars, sup_line, res_line, zone, one_signal=True,
             trend_filter=True, sup_rising=True, res_falling=True,
             want_pb=True, want_bo=True):
    """bars = list of (high, low, close). *_line = fn(i)->level or None."""
    long_armed = True; short_armed = True
    sigs = []
    prev_sup = prev_res = None
    for i,(h,l,c) in enumerate(bars):
        supNow = sup_line(i); resNow = res_line(i)

        pbL = want_pb and supNow is not None and l <= supNow+zone and c > supNow \
              and (not trend_filter or sup_rising)
        pbS = want_pb and resNow is not None and h >= resNow-zone and c < resNow \
              and (not trend_filter or res_falling)
        boL = want_bo and resNow is not None and prev_res is not None and \
              c > resNow and bars[i-1][2] <= prev_res
        boS = want_bo and supNow is not None and prev_sup is not None and \
              c < supNow and bars[i-1][2] >= prev_sup

        # re-arm (mirrors the Pine order: re-arm BEFORE evaluating signal)
        if supNow is None or c > supNow + zone*2: long_armed = True
        if resNow is None or c < resNow - zone*2: short_armed = True

        L = (pbL or boL) and (not one_signal or long_armed)
        S = (pbS or boS) and (not one_signal or short_armed)
        if L: long_armed = False
        if S: short_armed = False
        if L or S: sigs.append((i, 'L' if L else '', 'S' if S else ''))
        prev_sup, prev_res = supNow, resNow
    return sigs

print("=== ENTRY LOGIC TESTS ===")

# 1) Price drifting ALONG support: without dedup -> many signals, with -> few
n=40
sup = lambda i: 100.0
res = lambda i: 130.0
# every bar dips to the line and closes just above it
drift = [(101.0, 99.6, 100.4) for _ in range(n)]
raw = simulate(drift, sup, res, zone=0.5, one_signal=False)
ded = simulate(drift, sup, res, zone=0.5, one_signal=True)
print(f"  drift along support: no-dedup={len(raw)} signals, dedup={len(ded)} signals "
      f"-> {'PASS' if len(raw)>=n-2 and len(ded)<=2 else 'FAIL'}")

# 2) Genuine re-test: dip, leave the zone entirely, come back -> 2 signals
seq=[]
seq += [(101,99.6,100.4)]                 # touch #1
seq += [(106,105,105.5)]*5                # travel well clear (> zone*2)
seq += [(101,99.6,100.4)]                 # touch #2
sig = simulate(seq, sup, res, zone=0.5, one_signal=True)
print(f"  dip / leave / dip again -> {len(sig)} signals (expect 2): "
      f"{'PASS' if len(sig)==2 else 'FAIL'}")

# 3) Trend filter: falling support should block longs when filter is ON
falling = [(101,99.6,100.4)]
on  = simulate(falling, sup, res, 0.5, trend_filter=True,  sup_rising=False)
off = simulate(falling, sup, res, 0.5, trend_filter=False, sup_rising=False)
print(f"  falling support, filter ON={len(on)} OFF={len(off)} (expect 0 / 1): "
      f"{'PASS' if len(on)==0 and len(off)==1 else 'FAIL'}")

# 4) Close BELOW support must NOT be a long pullback (it's a breakdown)
below = [(101, 99.0, 99.2)]
sig = simulate(below, sup, res, 0.5)
longs = [s for s in sig if s[1]=='L']
print(f"  close below support -> long signals={len(longs)} (expect 0): "
      f"{'PASS' if len(longs)==0 else 'FAIL'}")

# 5) Breakout through resistance fires a long
bo = [(129,127,128.0), (133,129,131.0)]
sig = simulate(bo, sup, res, 0.5, want_pb=False, want_bo=True)
print(f"  close through resistance -> {sig} (expect one L at i=1): "
      f"{'PASS' if len(sig)==1 and sig[0][0]==1 and sig[0][1]=='L' else 'FAIL'}")

# 6) No line present -> no signals, no crash
none_line = lambda i: None
sig = simulate([(101,99,100)]*10, none_line, none_line, 0.5)
print(f"  na lines -> {len(sig)} signals (expect 0): {'PASS' if len(sig)==0 else 'FAIL'}")

# 7) Signals only fire when a line exists AND price interacts: random noise sanity
random.seed(4)
noise=[]
p=100.0
for i in range(500):
    p+=random.gauss(0,1)
    noise.append((p+abs(random.gauss(0,.5)), p-abs(random.gauss(0,.5)), p))
sig = simulate(noise, lambda i: 100.0, lambda i: 110.0, zone=0.5)
print(f"  500 random bars -> {len(sig)} signals (bounded, not per-bar): "
      f"{'PASS' if len(sig) < 120 else 'FAIL'}")

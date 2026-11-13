"""
M3K HL Sweep - MT4 port validation
==================================

1) Structure sweep  : Pine state machine vs the shift based MQL4 port.
2) MTF level offset : request.security(..., ta.highest(high, N)[1]) vs
                      iBarShift()/iHighest() with the "[1]" implemented as
                      start = formingShift + 1.

Run: python3 validate_hl_sweep.py
"""
import random


# ---------------------------------------------------------------- data
def make_bars(n=2000, seed=5, step_seconds=900):
    random.seed(seed)
    bars, px = [], 1.10
    for i in range(n):
        o = px
        c = o + random.gauss(0, 0.0012)
        h = max(o, c) + abs(random.gauss(0, 0.0006))
        l = min(o, c) - abs(random.gauss(0, 0.0006))
        bars.append(dict(o=o, h=h, l=l, c=c, t=i * step_seconds,
                         end=i * step_seconds))
        px = c
    return bars


# ---------------------------------------------------------------- sweeps
def pine_sweeps(bars, strength=35):
    H = [b['h'] for b in bars]
    L = [b['l'] for b in bars]
    C = [b['c'] for b in bars]
    n_bars = len(bars)

    def pv_high(n, k):
        p = n - k
        if p - k < 0:
            return None
        mid = H[p]
        for i in range(p - k, p):            # left : strictly lower
            if H[i] >= mid:
                return None
        for i in range(p + 1, p + k + 1):    # right : lower or equal
            if H[i] > mid:
                return None
        return mid

    def pv_low(n, k):
        p = n - k
        if p - k < 0:
            return None
        mid = L[p]
        for i in range(p - k, p):            # left : strictly higher
            if L[i] <= mid:
                return None
        for i in range(p + 1, p + k + 1):    # right : higher or equal
            if L[i] < mid:
                return None
        return mid

    o_h = o_h_i = l_a_h = l_a_h_i = None
    o_l = o_l_i = h_a_l = h_a_l_i = None
    out = []
    for n in range(n_bars):
        ph = pv_high(n, strength)
        pl = pv_low(n, strength)

        if ph is not None:
            o_h, o_h_i, l_a_h = ph, n - strength, None
        if pl is not None and o_h is not None and pl < o_h:
            l_a_h, l_a_h_i = pl, n - strength
        if l_a_h is not None and o_h is not None and H[n] > o_h and C[n] < o_h:
            out.append(('H', bars[o_h_i]['t'], o_h, bars[l_a_h_i]['t'], l_a_h,
                        bars[n]['t'], H[n]))
            o_h = None

        if pl is not None:
            o_l, o_l_i, h_a_l = pl, n - strength, None
        if ph is not None and o_l is not None and ph > o_l:
            h_a_l, h_a_l_i = ph, n - strength
        if h_a_l is not None and o_l is not None and L[n] < o_l and C[n] > o_l:
            out.append(('L', bars[o_l_i]['t'], o_l, bars[h_a_l_i]['t'], h_a_l,
                        bars[n]['t'], L[n]))
            o_l = None
    return out


def mql_sweeps(bars, strength=35, replay=3000):
    N = len(bars)          # shift s  ->  bars[N-1-s]
    def H(s): return bars[N - 1 - s]['h']
    def L(s): return bars[N - 1 - s]['l']
    def C(s): return bars[N - 1 - s]['c']
    def T(s): return bars[N - 1 - s]['t']

    def pv_high(sh, k):
        p = sh + k
        if p + k >= N:
            return None
        mid = H(p)
        for i in range(p - k, p):
            if i < 0 or H(i) >= mid:
                return None
        for j in range(p + 1, p + k + 1):
            if H(j) > mid:
                return None
        return mid

    def pv_low(sh, k):
        p = sh + k
        if p + k >= N:
            return None
        mid = L(p)
        for i in range(p - k, p):
            if i < 0 or L(i) <= mid:
                return None
        for j in range(p + 1, p + k + 1):
            if L(j) < mid:
                return None
        return mid

    o_h = o_h_t = l_a_h = l_a_h_t = None
    o_l = o_l_t = h_a_l = h_a_l_t = None
    out = []
    start = min(N - 1 - (2 * strength + 2), replay, N - 2)
    for sh in range(start, 0, -1):
        ph = pv_high(sh, strength)
        pl = pv_low(sh, strength)
        pvT = T(sh + strength) if sh + strength < N else 0

        if ph is not None:
            o_h, o_h_t, l_a_h = ph, pvT, None
        if pl is not None and o_h is not None and pl < o_h:
            l_a_h, l_a_h_t = pl, pvT
        if l_a_h is not None and o_h is not None and H(sh) > o_h and C(sh) < o_h:
            out.append(('H', o_h_t, o_h, l_a_h_t, l_a_h, T(sh), H(sh)))
            o_h = None

        if pl is not None:
            o_l, o_l_t, h_a_l = pl, pvT, None
        if ph is not None and o_l is not None and ph > o_l:
            h_a_l, h_a_l_t = ph, pvT
        if h_a_l is not None and o_l is not None and L(sh) < o_l and C(sh) > o_l:
            out.append(('L', o_l_t, o_l, h_a_l_t, h_a_l, T(sh), L(sh)))
            o_l = None
    return out


# ---------------------------------------------------------------- MTF levels
def aggregate(bars, factor):
    """group `factor` consecutive bars into one higher timeframe bar
    (the trailing, still forming group is kept too, like MT4 does)"""
    ht = []
    for i in range(0, len(bars), factor):
        g = bars[i:i + factor]
        ht.append(dict(t=g[0]['t'], o=g[0]['o'], h=max(b['h'] for b in g),
                       l=min(b['l'] for b in g), c=g[-1]['c'],
                       end=g[-1]['t']))
    return ht


def pine_level(chart_bars, tf_bars, n, lookback, is_high):
    """ta.highest(high, lookback)[1] of the higher timeframe, as Pine sees it
    on chart bar n  ->  max over the `lookback` COMPLETED tf bars"""
    t_close = chart_bars[n]['t'] + 900          # close of the chart bar
    # last completed tf bar = the last one whose close <= t_close
    done = [b for b in tf_bars if b['end'] + 900 <= t_close]
    if len(done) < lookback:
        return None
    window = done[-lookback:]
    return max(b['h'] for b in window) if is_high else min(b['l'] for b in window)


def mql_level(chart_bars, tf_bars, n, lookback, is_high):
    """iBarShift(tf, tClose) + 1  then  iHighest / iLowest"""
    t_close = chart_bars[n]['t'] + 900
    # iBarShift : index of the tf bar containing t_close (0 = newest)
    forming = None
    for idx, b in enumerate(reversed(tf_bars)):
        if b['t'] <= t_close:
            forming = idx
            break
    if forming is None:
        return None
    start = forming + 1
    # collect shifts start .. start+lookback-1
    vals = []
    for s in range(start, start + lookback):
        if s >= len(tf_bars):
            break
        b = tf_bars[len(tf_bars) - 1 - s]
        vals.append(b['h'] if is_high else b['l'])
    if len(vals) < lookback:
        return None
    return max(vals) if is_high else min(vals)


# ---------------------------------------------------------------- signal filter
def filter_check(n_bars=400, window=3, trials=40):
    """gLastSweep* keeps the last sweep at or before the signal bar.
    MQL4 works with shifts (0 = newest), the reference with bar indexes.
    Both must accept exactly the same (sweep, signal) pairs."""
    import random as rnd
    for _ in range(trials):
        N = n_bars
        sweeps = sorted(rnd.sample(range(2, N - 2), rnd.randint(3, 25)))
        sigs = sorted(rnd.sample(range(2, N - 2), rnd.randint(3, 25)))
        for w in (0, 1, 3, 10):
            # reference : last sweep at or before the signal, within w bars
            ref = set()
            for sg in sigs:
                prev = [x for x in sweeps if x <= sg]
                if not prev:
                    continue
                if sg - prev[-1] <= w:
                    ref.add(sg)
            # MQL4 : shift arithmetic
            mql = set()
            last_t = None
            for i in range(N):                      # chronological replay
                if i in sweeps:
                    last_t = i
                if i not in sigs:
                    continue
                if last_t is None:
                    continue
                sw3 = N - 1 - last_t
                sh = N - 1 - i
                dist = sw3 - sh
                if 0 <= dist <= w:
                    mql.add(i)
            if ref != mql:
                return False
    return True


# ---------------------------------------------------------------- run
def main():
    ok = True

    print("== structure sweep ==")
    for seed in (1, 2, 3, 7):
        bars = make_bars(1500, seed)
        p = pine_sweeps(bars)
        m = mql_sweeps(bars)
        same = len(p) == len(m) and all(
            a[0] == b[0] and a[1] == b[1] and abs(a[2] - b[2]) < 1e-12 and
            a[3] == b[3] and abs(a[4] - b[4]) < 1e-12 and a[5] == b[5]
            for a, b in zip(p, m))
        print("  seed %-2d pine=%3d mql=%3d  %s" % (seed, len(p), len(m), "MATCH" if same else "DIFF"))
        ok = ok and same

    print("== MTF level offset (W / D / 4H / 1H / 15M) ==")
    bars15 = make_bars(2000, 11, 900)
    tf = {
        "15M": bars15,
        "H1": aggregate(bars15, 4),
        "H4": aggregate(bars15, 16),
        "D1": aggregate(bars15, 96),
    }
    checks = bad = 0
    for name, tfb in tf.items():
        for n in (700, 1200, 1600, 1998):
            for look in (20, 100):
                for hi in (True, False):
                    t_close = bars15[n]['t'] + 900
                    done = [b for b in tfb if b['end'] + 900 <= t_close]
                    if len(done) < look:
                        continue      # not enough higher timeframe history
                    p = pine_level(bars15, tfb, n, look, hi)
                    m = mql_level(bars15, tfb, n, look, hi)
                    if p is None and m is None:
                        continue          # not enough history on that TF
                    checks += 1
                    if p is None or m is None or abs(p - m) > 1e-12:
                        bad += 1
                        if bad <= 3:
                            print("   DIFF", name, "bar", n, "look", look, "high", hi, p, m)
    print("  %d/%d levels identical" % (checks - bad, checks))
    ok = ok and bad == 0

    print("== signal + sweep filter ==")
    f = filter_check()
    print("  shift arithmetic == bar arithmetic :", "MATCH" if f else "DIFF")
    ok = ok and f

    print("\nRESULT:", "ALL MATCH" if ok else "DIFFERENCES FOUND")
    return ok


if __name__ == "__main__":
    raise SystemExit(0 if main() else 1)

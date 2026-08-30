#!/usr/bin/env python3
"""Backtest engine for FVG_Cascade.mq4 - faithful Python port of the MQL4 logic.

Input : M1 OHLC bars (bid, like an MT4 chart) built from Dukascopy ticks
        by build_m1.py -> backtest/data/EURUSD_M1_*.csv.gz
Output: backtest/trades.csv + summary stats printed (report by make_report.py)

The replay evaluates the cascade at every CLOSED M1 candle, exactly like the
indicator does live:

  Step 1  H1   bias      : latest invalidated H1 FVG decides the bias
                           (bearish FVG invalidated -> bullish bias, and vice versa)
  Step 2  M30  IFVG zone : opposite-side FVG inverted by a close becomes the
                           trade zone; wait for the tap (M1 granularity)
  Step 3  M5   swing     : fractal low (buy) / high (sell) after the tap
  Step 4  M1   trigger   : opposite-side M1 FVG invalidated by a close -> signal
                           entry = close of the trigger candle, SL/TP per inputs
"""
import os, bisect, heapq
from collections import defaultdict
import numpy as np
import pandas as pd

PIP = 1e-4
POINT = 1e-5

# ------------- indicator defaults (must match FVG_Cascade.mq4) -------------
BIAS_WIN_BARS       = 24      # H1 bars
BIAS_MAX_AGE_BARS   = 36      # H1 bars
BIAS_MIN_EVENTS     = 1
ZONE_MAX_AGE_BARS   = 96      # M30 bars
MIN_ZONE_PTS        = 0.0
MAX_ZONE_PTS        = 0.0
SWING_STRENGTH      = 2       # M5 bars each side
SETUP_TIMEOUT_MIN   = 240
MAX_TRADES_PER_ZONE = 1
COOLDOWN_MIN        = 10
SL_MODE             = 'swing'   # 'swing' | 'zone' | 'fvg'
SL_BUFFER_PTS       = 10        # points
TP_MODE             = 'rr'
RR                  = 2.0
TP_PTS              = 200.0
TF_BIAS, TF_ZONE, TF_SWING = 60, 30, 5      # minutes

# -----------------------------------------------------------------------------
def floor_tf(t, minutes):
    return (t // (minutes * 60)) * (minutes * 60)

def load_m1(files):
    frames = [pd.read_csv(f) for f in files]
    df = pd.concat(frames, ignore_index=True)
    df['t'] = pd.to_datetime(df['time']).values.astype('datetime64[s]').astype('int64')
    return df.sort_values('t').reset_index(drop=True)

def aggregate(m1, minutes):
    """aggregate M1 -> higher TF exactly like MT4 builds H1/M30/M5 from M1."""
    b = (m1['t'].values // (minutes * 60)) * (minutes * 60)
    df = m1.assign(b=b).groupby('b', sort=True).agg(
        o=('o', 'first'), h=('h', 'max'), l=('l', 'min'), c=('c', 'last'))
    df = df.reset_index().rename(columns={'b': 't'})
    return df

# -----------------------------------------------------------------------------
class FVG:
    __slots__ = ('created', 'dir', 'top', 'bottom', 't_mit', 't_inv', 't_break')

def build_fvgs(bars, minutes):
    """All 3-candle FVGs of a TF with their event times (first touch, first
    close-beyond = invalidation, post-inversion break), computed to the end of
    data with heap sweeps (O(n log n)). Filtering events by `<= t` reconstructs
    the exact state at any past t - same semantics as the MQL4 per-bar scans.
    Arrays are chronological: index i older than i+1; a triplet is (i, i+1, i+2)
    with i+2 the newest candle, FVG confirmed at the CLOSE of candle i+2."""
    t = bars['t'].values; h = bars['h'].values
    l = bars['l'].values; c = bars['c'].values
    n = len(t)
    tfsec = minutes * 60
    fvgs = []
    for i in range(n - 2):                       # i = oldest candle of the triplet
        if l[i + 2] > h[i]:                      # bullish FVG: gap between A.high and C.low
            f = FVG(); f.dir = 1; f.bottom = h[i]; f.top = l[i + 2]
        elif h[i + 2] < l[i]:                    # bearish FVG
            f = FVG(); f.dir = -1; f.bottom = h[i + 2]; f.top = l[i]
        else:
            continue
        f.created = t[i + 2]                     # exists from close of the 3rd candle
        f.t_mit = 0; f.t_inv = 0; f.t_break = 0
        fvgs.append(f)
    # chronological sweep of events
    idx, seq = 0, 0
    bull_mit, bull_inv = [], []       # bullish: touch low<=top ; invalid close<bottom
    bear_mit, bear_inv = [], []       # bearish: touch high>=bottom ; invalid close>top
    # after inversion the FVG becomes an IFVG on the OPPOSITE side:
    brk_bear = []                     # bull FVG inverted -> bearish resistance, break close>top
    brk_bull = []                     # bear FVG inverted -> bullish support,    break close<bottom
    for i in range(n):
        ti, hi, lo, ci = t[i], h[i], l[i], c[i]
        while idx < len(fvgs) and fvgs[idx].created + tfsec <= ti:
            f = fvgs[idx]; idx += 1
            if f.dir > 0:
                heapq.heappush(bull_mit, (-f.top, seq, f))
                heapq.heappush(bull_inv, (-f.bottom, seq, f))
            else:
                heapq.heappush(bear_mit, (f.bottom, seq, f))
                heapq.heappush(bear_inv, (f.top, seq, f))
            seq += 1
        while bull_mit and -bull_mit[0][0] >= lo:          # top >= low  -> touched
            _, _, f = heapq.heappop(bull_mit)
            if f.t_mit == 0: f.t_mit = ti
        while bull_inv and -bull_inv[0][0] > ci:           # bottom > close -> invalidated
            _, _, f = heapq.heappop(bull_inv)
            if f.t_inv == 0:
                f.t_inv = ti
                heapq.heappush(brk_bear, (f.top, seq, f)); seq += 1
        while bear_mit and bear_mit[0][0] <= hi:           # bottom <= high -> touched
            _, _, f = heapq.heappop(bear_mit)
            if f.t_mit == 0: f.t_mit = ti
        while bear_inv and bear_inv[0][0] < ci:            # top < close -> invalidated
            _, _, f = heapq.heappop(bear_inv)
            if f.t_inv == 0:
                f.t_inv = ti
                heapq.heappush(brk_bull, (-f.bottom, seq, f)); seq += 1
        while brk_bear and brk_bear[0][0] < ci:            # top < close -> broken
            _, _, f = heapq.heappop(brk_bear)
            if f.t_break == 0: f.t_break = ti
        while brk_bull and -brk_bull[0][0] > ci:           # bottom > close -> broken
            _, _, f = heapq.heappop(brk_bull)
            if f.t_break == 0: f.t_break = ti
    return fvgs

def build_pivots(m5, strength):
    """M5 fractal pivots + confirmation time. Strictness mirrors the MQL4:
    a newer equal low is OK, an older equal low kills the pivot."""
    t = m5['t'].values; h = m5['h'].values; l = m5['l'].values
    n = len(t)
    lo_t, lo_p, lo_c, hi_t, hi_p, hi_c = [], [], [], [], [], []
    for s in range(strength, n - strength):
        isLo = isHi = True
        for j in range(1, strength + 1):
            if l[s] > l[s + j] or l[s] >= l[s - j]: isLo = False   # s+j newer, s-j older
            if h[s] < h[s + j] or h[s] <= h[s - j]: isHi = False
            if not isLo and not isHi: break
        if isLo:
            lo_t.append(t[s]); lo_p.append(l[s]); lo_c.append(t[s + strength] + 5 * 60)
        if isHi:
            hi_t.append(t[s]); hi_p.append(h[s]); hi_c.append(t[s + strength] + 5 * 60)
    return (np.array(lo_t, dtype=np.int64), np.array(lo_p),
            np.array(lo_c, dtype=np.int64),
            np.array(hi_t, dtype=np.int64), np.array(hi_p),
            np.array(hi_c, dtype=np.int64))

# -----------------------------------------------------------------------------
class Backtester:
    def __init__(self, m1):
        self.t = m1['t'].values.astype(np.int64)
        self.o = m1['o'].values; self.h = m1['h'].values
        self.l = m1['l'].values; self.c = m1['c'].values
        self.spread = m1['spread'].values
        self.n = len(self.t)

        self.m5 = aggregate(m1, 5)
        self.m30 = aggregate(m1, 30)
        self.h1 = aggregate(m1, 60)
        self.m5_t = self.m5['t'].values; self.m5_c = self.m5['c'].values

        self.h1_fvgs = build_fvgs(self.h1, TF_BIAS)
        self.m30_fvgs = build_fvgs(self.m30, TF_ZONE)
        self.m1_fvgs = build_fvgs(m1, 1)

        # bias events (invalidated H1 FVGs) sorted by event time
        ev = [(f.t_inv, f.dir) for f in self.h1_fvgs if f.t_inv > 0]
        ev.sort()
        self.bias_ev_t = np.array([e[0] for e in ev], dtype=np.int64)
        self.bias_ev_dir = np.array([e[1] for e in ev], dtype=np.int64)

        (self.plo_t, self.plo_p, self.plo_c,
         self.phi_t, self.phi_p, self.phi_c) = build_pivots(self.m5, SWING_STRENGTH)

        # M1 trigger FVGs by direction, sorted by created
        self.trig_bear = sorted([f for f in self.m1_fvgs if f.dir < 0], key=lambda f: f.created)
        self.trig_bull = sorted([f for f in self.m1_fvgs if f.dir > 0], key=lambda f: f.created)
        self.trig_bear_t = [f.created for f in self.trig_bear]
        self.trig_bull_t = [f.created for f in self.trig_bull]

        # zones = inverted M30 FVGs, sorted by inversion time
        self.zones = sorted([f for f in self.m30_fvgs if f.t_inv > 0], key=lambda f: f.t_inv)
        self.zone_tinv = [z.t_inv for z in self.zones]

        self.tap_cache = {}
        self.sb_cache = {}

    def ibar(self, arr_t, tm):
        i = bisect.bisect_right(arr_t, tm) - 1
        return i if i >= 0 else 0

    def first_touch_m1(self, z, bias):
        """first M1 bar strictly after the invalidating M30 candle touched the
        zone (buy: low <= top ; sell: high >= bottom); window bounded to the
        zone's relevant lifetime (age <= ~50h)."""
        start = z.t_inv + TF_ZONE * 60
        i0 = bisect.bisect_left(self.t, start)
        i1 = min(self.n, bisect.bisect_right(self.t, z.t_inv + 50 * 3600))
        if bias > 0:
            for i in range(i0, i1):
                if self.l[i] <= z.top: return self.t[i]
        else:
            for i in range(i0, i1):
                if self.h[i] >= z.bottom: return self.t[i]
        return 0

    def swing_break_time(self, tap, zTop, zBottom, bias):
        """first M5 bar (open time) whose CLOSE is beyond the protective side
        of the zone, starting at the M5 bar containing the tap (MQL4
        ZoneBrokenSwing). Only the window where a setup can still live matters."""
        i = self.ibar(self.m5_t, tap)
        end = min(len(self.m5_t), i + 60)
        for k in range(i, end):
            ci = self.m5_c[k]
            if bias > 0 and ci < zBottom: return int(self.m5_t[k])
            if bias < 0 and ci > zTop:    return int(self.m5_t[k])
        return 0

    # --------------------------------------------------------------------------
    def run(self, verbose=True):
        consumed = defaultdict(int)
        fired = set()
        last_sig_trig_t = None
        signals = []
        month = ''

        win_sec = BIAS_WIN_BARS * 3600
        maxage_bias = BIAS_MAX_AGE_BARS * 3600
        zmaxage = ZONE_MAX_AGE_BARS * TF_ZONE * 60
        timeout = SETUP_TIMEOUT_MIN * 60
        cooldown = COOLDOWN_MIN * 60

        zptr = 0                 # zones older than the window
        next_recalc = 0          # when to re-run zone selection
        sel_zi, sel_tap, last_bias = -1, 0, None

        for i in range(self.n):
            t = int(self.t[i])

            if verbose:
                mo = str(pd.Timestamp(t, unit='s'))[:7]
                if mo != month:
                    month = mo
                    print('  ... %s  (%d signals)' % (mo, len(signals)))

            # ---------------- STEP 1: bias (latest invalidated H1 FVG) --------
            k = bisect.bisect_right(self.bias_ev_t, t) - 1
            bias = 0
            if k >= 0:
                evT = int(self.bias_ev_t[k])
                if t - evT <= maxage_bias:
                    cand = -1 if self.bias_ev_dir[k] > 0 else 1
                    j0 = bisect.bisect_left(self.bias_ev_t, t - win_sec)
                    implying = int((self.bias_ev_dir[j0:k + 1] == -cand).sum())
                    if implying >= BIAS_MIN_EVENTS:
                        bias = cand
            if bias == 0:
                last_bias = 0
                continue

            # ---------------- STEP 2: zone selection ---------------------------
            if t >= next_recalc or bias != last_bias:
                # advance dead zones out of the window
                while zptr < len(self.zones) and self.zone_tinv[zptr] < t - zmaxage:
                    zptr += 1
                zz = bisect.bisect_right(self.zone_tinv, t)
                zi, bestTap = -1, 0
                nxt = 1 << 62
                # next bias event may refresh the bias / flip it
                kb = bisect.bisect_right(self.bias_ev_t, t)
                if kb < len(self.bias_ev_t): nxt = min(nxt, int(self.bias_ev_t[kb]) - t)
                # next zone entering the window (gets inverted)
                if zz < len(self.zones): nxt = min(nxt, int(self.zone_tinv[zz]) - t)
                for zi_ in range(zz - 1, zptr - 1, -1):
                    z = self.zones[zi_]
                    if z.dir != -bias: continue
                    nxt = min(nxt, int(z.t_inv) + zmaxage - t)
                    if z.t_break > 0:
                        if z.t_break <= t: continue
                        nxt = min(nxt, int(z.t_break) - t)
                    if consumed[z.created] >= MAX_TRADES_PER_ZONE: continue
                    if MIN_ZONE_PTS > 0 and (z.top - z.bottom) < MIN_ZONE_PTS * POINT: continue
                    if MAX_ZONE_PTS > 0 and (z.top - z.bottom) > MAX_ZONE_PTS * POINT: continue
                    key = (z.created, bias)
                    if key not in self.tap_cache:
                        self.tap_cache[key] = self.first_touch_m1(z, bias)
                    tap = self.tap_cache[key]
                    if tap:
                        if tap > t:
                            nxt = min(nxt, tap - t)          # becomes in-progress
                        elif t - tap <= timeout:
                            nxt = min(nxt, tap + timeout - t)  # expires later
                            if tap > bestTap:
                                bestTap, zi = tap, zi_
                        # else: tapped too long ago -> expired forever
                sel_zi, sel_tap, next_recalc = zi, bestTap, t + max(nxt, 60)
                last_bias = bias

            if sel_zi < 0:
                continue
            zone = self.zones[sel_zi]
            zTop, zBottom, zCreated = zone.top, zone.bottom, zone.created
            tap = sel_tap

            # setup death: swing-TF close beyond the protective side after the tap
            sbk = (zCreated, bias, tap)
            if sbk not in self.sb_cache:
                self.sb_cache[sbk] = self.swing_break_time(tap, zTop, zBottom, bias)
            sb = self.sb_cache[sbk]
            if sb and sb < floor_tf(t, TF_SWING):
                continue

            # ---------------- STEP 3: swing pivot ------------------------------
            if bias > 0:
                kk = bisect.bisect_right(self.plo_c, t) - 1
                if kk < 0: continue
                if kk < bisect.bisect_right(self.plo_t, tap): continue
                pivot_t = int(self.plo_t[kk])
            else:
                kk = bisect.bisect_right(self.phi_c, t) - 1
                if kk < 0: continue
                if kk < bisect.bisect_right(self.phi_t, tap): continue
                pivot_t = int(self.phi_t[kk])

            # ---------------- STEP 4: trigger ----------------------------------
            if bias > 0:
                tlist, ttimes = self.trig_bear, self.trig_bear_t
            else:
                tlist, ttimes = self.trig_bull, self.trig_bull_t
            hi = bisect.bisect_right(ttimes, t) - 1
            pivotBarClose = pivot_t + TF_SWING * 60
            ft = None
            for x in range(hi, -1, -1):
                f = tlist[x]
                if f.created <= tap: break
                if f.t_inv <= 0: continue
                if f.t_inv < pivotBarClose: continue
                if f.t_inv > t: continue
                ft = f
                break
            if ft is None:
                continue

            # ---------------- signal (exact port of the MQL4 block) ------------
            sig_key = (zCreated, ft.created)
            e_idx = self.ibar(self.t, ft.t_inv)
            entry = float(self.c[e_idx])
            buf = SL_BUFFER_PTS * POINT
            i0 = self.ibar(self.t, tap)
            swingExt = float(self.l[i0:i + 1].min()) if bias > 0 else float(self.h[i0:i + 1].max())
            if SL_MODE == 'zone':
                sl = zBottom - buf if bias > 0 else zTop + buf
            elif SL_MODE == 'fvg':
                sl = ft.bottom - buf if bias > 0 else ft.top + buf
            else:
                sl = swingExt - buf if bias > 0 else swingExt + buf
            if bias > 0:
                if sl >= entry: sl = swingExt - buf
                if sl >= entry: sl = zBottom - buf
                if sl >= entry: sl = entry - 50 * POINT
            else:
                if sl <= entry: sl = swingExt + buf
                if sl <= entry: sl = zTop + buf
                if sl <= entry: sl = entry + 50 * POINT
            risk = abs(entry - sl)
            if risk < POINT:
                continue
            if TP_MODE == 'fixed':
                tp = entry + TP_PTS * POINT if bias > 0 else entry - TP_PTS * POINT
            else:
                tp = entry + RR * risk if bias > 0 else entry - RR * risk

            already = sig_key in fired
            in_cool = (not already and last_sig_trig_t is not None and
                       abs(ft.t_inv - last_sig_trig_t) < cooldown)
            if already or in_cool:
                continue
            fired.add(sig_key)
            consumed[zCreated] += 1
            last_sig_trig_t = ft.t_inv
            next_recalc = t          # selection changed (zone consumed)
            signals.append(dict(
                dir=bias, t_entry=int(ft.t_inv), entry_bar=e_idx, eval_bar=i,
                entry=entry, sl=sl, tp=tp, risk=risk, swing=swingExt,
                zone_lo=zBottom, zone_hi=zTop, tap=int(tap), pivot=pivot_t,
                spread=float(self.spread[e_idx])))
        return signals

    # --------------------------------------------------------------------------
    def outcomes(self, signals, rr=None):
        """walk forward: SL checked before TP inside the same bar (conservative,
        like the indicator's own tracker). rr overrides TP for sensitivity."""
        out = []
        for s in signals:
            if rr is None:
                tp = s['tp']
            else:
                tp = s['entry'] + rr * s['risk'] if s['dir'] > 0 else s['entry'] - rr * s['risk']
            i = s['entry_bar']
            res, exit_t, mfe = 0, 0, 0.0
            for k in range(i + 1, self.n):
                hi, lo = self.h[k], self.l[k]
                if s['dir'] > 0:
                    mfe = max(mfe, (hi - s['entry']) / PIP)
                    if lo <= s['sl']: res, exit_t = -1, int(self.t[k]); break
                    if hi >= tp:     res, exit_t = 1, int(self.t[k]); break
                else:
                    mfe = max(mfe, (s['entry'] - lo) / PIP)
                    if hi >= s['sl']: res, exit_t = -1, int(self.t[k]); break
                    if lo <= tp:     res, exit_t = 1, int(self.t[k]); break
            gross = 0.0
            if res > 0:   gross = abs(tp - s['entry'])
            elif res < 0: gross = -abs(s['entry'] - s['sl'])
            dur = ((exit_t or int(self.t[-1])) - s['t_entry']) / 60.0
            out.append(dict(s, tp_used=tp, result=res, exit_t=exit_t,
                            dur_min=dur, mfe_pips=mfe, gross_pips=gross / PIP))
        return out

# -----------------------------------------------------------------------------
def main():
    base = os.path.dirname(os.path.abspath(__file__))
    files = sorted(os.path.join(base, 'data', f)
                   for f in os.listdir(os.path.join(base, 'data')) if f.endswith('.csv.gz'))
    print('loading:', [os.path.basename(f) for f in files])
    m1 = load_m1(files)
    print('M1 bars: %d   %s .. %s   mean spread %.2f pips' % (
        len(m1), m1['time'].iloc[0], m1['time'].iloc[-1], m1['spread'].mean() / PIP))

    bt = Backtester(m1)
    print('H1 FVGs: %d (invalidated %d) | M30 FVGs: %d (inverted %d) | M1 FVGs: %d' % (
        len(bt.h1_fvgs), len(bt.bias_ev_t), len(bt.m30_fvgs), len(bt.zones), len(bt.m1_fvgs)))

    print('replaying cascade ...')
    signals = bt.run()
    print('signals fired: %d' % len(signals))

    trades = bt.outcomes(signals)
    df = pd.DataFrame(trades)
    if len(df):
        df['time'] = pd.to_datetime(df['t_entry'], unit='s')
        df['exit_time'] = pd.to_datetime(df['exit_t'], unit='s')
        cols = ['time', 'dir', 'entry', 'sl', 'tp_used', 'risk', 'result',
                'gross_pips', 'mfe_pips', 'dur_min', 'spread', 'swing',
                'zone_lo', 'zone_hi', 'tap', 'pivot', 'eval_bar', 'entry_bar', 'exit_time']
        df = df[[c for c in cols if c in df.columns]]
        df.to_csv(os.path.join(base, 'trades.csv'), index=False)
        closed = df[df.result != 0]
        wins = int((closed.result > 0).sum()); losses = int((closed.result < 0).sum())
        print('closed: %d  wins: %d  losses: %d  win rate: %.1f%%' % (
            len(closed), wins, losses, 100.0 * wins / max(1, len(closed))))
        if len(closed):
            tot = closed.gross_pips.sum()
            print('total gross: %.1f pips  |  avg/trade: %.2f pips  |  open: %d' % (
                tot, tot / len(closed), int((df.result == 0).sum())))
    return bt, df

if __name__ == '__main__':
    bt, df = main()

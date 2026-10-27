#!/usr/bin/env python3
"""
engine_sim.py -- calibration harness for ApexConfluencePro.mq4

This is NOT part of the indicator. It is a line-by-line Python port of the
MQL4 decision engine (same bars, same thresholds, same scoring) used to check
that the defaults produce a sane number of signals on realistic data before
the .mq4 is shipped.

Requirements: Python 3.8+ and numpy.

Usage:
    python3 tools/engine_sim.py [bars]

It prints, per profile and seed: signal frequency per 100 bars, score and R:R
distribution, how often a real S/R zone (rather than the fallback target) was
used, the forward outcome (TP1 first vs stop first), and the filter hit rates.

Indexing: all arrays are chronological (0 = oldest). Every helper that mirrors
MQL4 takes a *position* j and only reads data at index <= j, exactly like the
indicator's forward pass.
"""
import numpy as np

# ---- constants copied from the .mq4 --------------------------------
ACP_MAX_SCORE = 15.0

# ---- profile: day trading (defaults in the .mq4) -------------------
P = dict(
    strength=3, history=700, min_score=9, level_prox=0.55, merge=0.45,
    sweep_lb=12, vol_period=20, vol_spike=1.5, er_period=14, er_trend=0.22,
    er_chop=0.10, htf_steps=2, sl_min=1.0, min_rr=1.5, cooldown=3, ttl=5,
)


def atr_wilder(h, l, c, period):
    n = len(c)
    tr = np.zeros(n)
    tr[0] = h[0] - l[0]
    for i in range(1, n):
        tr[i] = max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1]))
    out = np.zeros(n)
    if n <= period:
        return out
    out[period - 1] = tr[:period].mean()
    for i in range(period, n):
        out[i] = (out[i - 1] * (period - 1) + tr[i]) / period
    return out


class Zone:
    __slots__ = ("price", "top", "bottom", "low_t", "high_t", "strength", "role", "broken", "born")

    def __init__(self):
        self.price = 0.0
        self.top = 0.0
        self.bottom = 0.0
        self.low_t = 0
        self.high_t = 0
        self.strength = 0.0
        self.role = 0
        self.broken = True
        self.born = 0

    def clear(self):
        self.__init__()


class Engine:
    def __init__(self, o, h, l, c, v, htf_trend=None, session_ok=None,
                 blackout=None, spread_ok=True):
        self.o, self.h, self.l, self.c, self.v = o, h, l, c, v
        self.n = len(c)
        self.atr = atr_wilder(h, l, c, 14)
        self.htf = htf_trend if htf_trend is not None else np.zeros(self.n, dtype=int)
        self.session_ok = session_ok
        self.blackout = blackout
        self.spread_ok = spread_ok

        self.zones = []
        self.sh = 0.0
        self.sl = 0.0
        self.struct = 0
        self.last_bos_dir = 0
        self.bos_j = -1
        self.choch_j = -1

        self.eval_signal = False
        self.eval_dir = 0
        self.eval_score = 0
        self.block = ""

        self.signals = []          # (j, dir, score, entry, sl, tp1)
        self.counts = {}
        self.last_signal_j = -10 ** 9

    # ---------------- helpers ---------------------------------------
    def bump(self, key):
        self.counts[key] = self.counts.get(key, 0) + 1

    def zone_add(self, price, ztype, j):
        atr = self.atr[j]
        if price <= 0 or atr <= 0:
            return
        tol = P["merge"] * atr
        best = None
        best_d = tol
        for i, z in enumerate(self.zones):
            d = abs(z.price - price)
            if d <= best_d:
                best_d, best = d, i
        if best is not None:
            z = self.zones[best]
            nb = z.low_t + z.high_t
            z.price = (z.price * nb + price) / (nb + 1)
            z.top = z.price + tol
            z.bottom = z.price - tol
            if ztype > 0:
                z.high_t += 1
            else:
                z.low_t += 1
            z.strength = z.low_t + z.high_t + (1 if z.low_t > 0 and z.high_t > 0 else 0)
            z.broken = False
            z.born = max(z.born, j)
            return
        z = Zone()
        z.price, z.top, z.bottom = price, price + tol, price - tol
        z.low_t = 1 if ztype < 0 else 0
        z.high_t = 1 if ztype > 0 else 0
        z.strength = 1.0
        z.role = -1 if ztype > 0 else 1
        z.broken = False
        z.born = j
        self.zones.append(z)

    def zone_check_break(self, j):
        c = self.c[j]
        for z in self.zones:
            if z.broken:
                continue
            if z.role < 0:
                if c > z.top:
                    z.role = 1
                    z.high_t = 0
                    z.low_t = 2
                    z.strength += 1
            elif z.role > 0:
                if c < z.bottom:
                    z.role = -1
                    z.low_t = 0
                    z.high_t = 2
                    z.strength += 1

    def zone_below(self, j):
        c, lo = self.c[j], self.l[j]
        best, best_gap = None, 1e12
        for z in self.zones:
            if z.broken or z.price >= c:
                continue
            g = max(0.0, lo - z.top)
            if g < best_gap:
                best_gap, best = g, z
        return best, (best_gap if best is not None else 1e9)

    def zone_above(self, j):
        c, hi = self.c[j], self.h[j]
        best, best_gap = None, 1e12
        for z in self.zones:
            if z.broken or z.price <= c:
                continue
            g = max(0.0, z.bottom - hi)
            if g < best_gap:
                best_gap, best = g, z
        return best, (best_gap if best is not None else 1e9)

    def zone_nearest_above(self, price):
        best, bd = None, 1e12
        for z in self.zones:
            if z.broken or z.bottom <= price:
                continue
            d = z.bottom - price
            if d < bd:
                bd, best = d, z
        return best

    def zone_nearest_below(self, price):
        best, bd = None, 1e12
        for z in self.zones:
            if z.broken or z.top >= price:
                continue
            d = price - z.top
            if d < bd:
                bd, best = d, z
        return best

    def structure_step(self, j):
        p = j - P["strength"]
        if p >= 1 and self.is_pivot_hi[p]:
            self.sh = self.h[p]
        if p >= 1 and self.is_pivot_lo[p]:
            self.sl = self.l[p]
        c = self.c[j]
        if self.sh > 0 and c > self.sh:
            self.last_bos_dir = 1
            self.bos_j = j
            if self.struct == -1:
                self.choch_j = j
            self.struct = 1
            self.sh = 0.0
        elif self.sl > 0 and c < self.sl:
            self.last_bos_dir = -1
            self.bos_j = j
            if self.struct == 1:
                self.choch_j = j
            self.struct = -1
            self.sl = 0.0

    def er(self, j, n):
        if j - n < 0:
            n = j
        if n < 2:
            return 0.0
        net = abs(self.c[j] - self.c[j - n])
        s = np.abs(np.diff(self.c[j - n:j + 1])).sum()
        return net / s if s > 0 else 0.0

    def rel_vol(self, j):
        lo = max(0, j - P["vol_period"])
        med = np.median(self.v[lo:j]) if j > lo else 0.0
        return self.v[j] / med if med > 0 else 1.0

    def delta(self, j, n=5):
        lo = max(0, j - n + 1)
        up = sum(self.v[k] for k in range(lo, j + 1) if self.c[k] >= self.o[k])
        dn = sum(self.v[k] for k in range(lo, j + 1) if self.c[k] < self.o[k])
        if up + dn <= 0:
            return 0.0
        return 100.0 * (up - dn) / (up + dn)

    def body_ratio(self, j):
        rng = self.h[j] - self.l[j]
        return abs(self.c[j] - self.o[j]) / rng if rng > 0 else 0.0

    def highest(self, j, n):
        lo = max(0, j - n + 1)
        return self.h[lo:j + 1].max()

    def lowest(self, j, n):
        lo = max(0, j - n + 1)
        return self.l[lo:j + 1].min()

    # ---------------- evaluation ------------------------------------
    def evaluate(self, j, forming=False):
        self.eval_signal = False
        self.eval_dir = 0
        self.eval_score = 0
        self.block = ""

        o, c, h, l = self.o[j], self.c[j], self.h[j], self.l[j]
        atr = self.atr[j]
        rng = h - l
        if atr <= 0 or rng <= 0:
            return
        d = 1 if c > o else (-1 if c < o else 0)
        if d == 0:
            return

        body = abs(c - o)
        upper = h - max(o, c)
        lower = min(o, c) - l
        br = body / rng
        bull_pin = body > 0 and lower >= 1.8 * body and upper <= 0.9 * body and c >= o
        bear_pin = body > 0 and upper >= 1.8 * body and lower <= 0.9 * body and c <= o
        pd = 1 if c > o else (-1 if c < o else 0)
        pd_prev = 1 if self.c[j - 1] > self.o[j - 1] else (-1 if self.c[j - 1] < self.o[j - 1] else 0)
        bull_eng = pd > 0 and pd_prev < 0 and c >= self.o[j - 1] and o <= self.c[j - 1]
        bear_eng = pd < 0 and pd_prev > 0 and c <= self.o[j - 1] and o >= self.c[j - 1]

        rv = self.rel_vol(j)
        delta = self.delta(j, 5)
        er = self.er(j, P["er_period"])

        a0 = max(0, j - 19)
        avg = self.atr[a0:j + 1].mean() if j >= a0 else atr
        atr_ratio = atr / avg if avg > 0 else 1.0

        htf = self.htf[j]

        zsup, dist_sup = self.zone_below(j)
        zres, dist_res = self.zone_above(j)
        sup_str = int(zsup.strength) if zsup else 0
        res_str = int(zres.strength) if zres else 0
        prox = P["level_prox"] * atr

        tail_up = min(o, c) - l
        tail_dn = h - max(o, c)
        close_loc = (c - l) / rng

        rej_bull = d > 0 and tail_up >= 0.35 * rng and close_loc >= 0.55 and dist_sup <= prox
        rej_bear = d < 0 and tail_dn >= 0.35 * rng and close_loc <= 0.45 and dist_res <= prox
        pin_bull = bull_pin and dist_sup <= prox * 1.4
        pin_bear = bear_pin and dist_res <= prox * 1.4
        eng_bull = bull_eng and dist_sup <= prox * 1.4
        eng_bear = bear_eng and dist_res <= prox * 1.4

        # sweep
        n = min(P["sweep_lb"], max(0, j - 2))
        sw_low = sw_high = False
        if n >= 3:
            prior_lo = self.l[j - n:j].min()
            prior_hi = self.h[j - n:j].max()
            sw_low = l < prior_lo - 0.05 * atr and c > prior_lo
            sw_high = h > prior_hi + 0.05 * atr and c < prior_hi

        bfvg = j >= 2 and l - self.h[j - 2] > 0.25 * atr
        sfvg = j >= 2 and self.l[j - 2] - h > 0.25 * atr

        mom_up = br >= 0.55 and c > self.highest(j - 1, 5)
        mom_dn = br >= 0.55 and c < self.lowest(j - 1, 5)

        up, dn = [], []
        us = ds = 0

        if rej_bull or pin_bull:
            pts = 3 if tail_up >= 0.5 * rng else 2
            if sup_str >= 2:
                pts += 1
            us += pts
            up.append("rej_sup")
        if rej_bear or pin_bear:
            pts = 3 if tail_dn >= 0.5 * rng else 2
            if res_str >= 2:
                pts += 1
            ds += pts
            dn.append("rej_res")
        if eng_bull:
            us += 2
            up.append("eng_bull")
        if eng_bear:
            ds += 2
            dn.append("eng_bear")
        if sw_low:
            us += 2
            up.append("sweep_low")
        if sw_high:
            ds += 2
            dn.append("sweep_high")
        if self.bos_j == j and self.last_bos_dir > 0:
            us += 3 if self.choch_j == j else 2
            up.append("choch_up" if self.choch_j == j else "bos_up")
        if self.bos_j == j and self.last_bos_dir < 0:
            ds += 3 if self.choch_j == j else 2
            dn.append("choch_dn" if self.choch_j == j else "bos_dn")
        if self.struct > 0:
            us += 1
            up.append("struct_up")
        if self.struct < 0:
            ds += 1
            dn.append("struct_dn")
        if mom_up:
            us += 1
            up.append("mom_up")
        if mom_dn:
            ds += 1
            dn.append("mom_dn")
        if d > 0 and rv >= P["vol_spike"]:
            us += 2
            up.append("vol_up")
        elif d > 0 and rv >= 1.15:
            us += 1
            up.append("vol_up1")
        if d < 0 and rv >= P["vol_spike"]:
            ds += 2
            dn.append("vol_dn")
        elif d < 0 and rv >= 1.15:
            ds += 1
            dn.append("vol_dn1")
        if delta >= 15:
            us += 1
            up.append("delta_up")
        if delta <= -15:
            ds += 1
            dn.append("delta_dn")
        if bfvg:
            us += 1
            up.append("fvg_up")
        if sfvg:
            ds += 1
            dn.append("fvg_dn")
        if htf > 0:
            us += 2
            up.append("htf_up")
        if htf < 0:
            ds += 2
            dn.append("htf_dn")
        if htf < 0 and d > 0:
            us -= 2
            up.append("htf_against")
        if htf > 0 and d < 0:
            ds -= 2
            dn.append("htf_against")
        if er >= P["er_trend"]:
            if d > 0:
                us += 1
                up.append("er")
            else:
                ds += 1
                dn.append("er")
        if d > 0 and (zres is None or (zres.bottom - c) >= 1.2 * atr):
            us += 1
            up.append("room")
        if d < 0 and (zsup is None or (c - zsup.top) >= 1.2 * atr):
            ds += 1
            dn.append("room")

        if d > 0 and us >= ds:
            bdir, bsc, why = 1, us, up
        elif d < 0 and ds >= us:
            bdir, bsc, why = -1, ds, dn
        else:
            return

        bsc = max(0, min(int(ACP_MAX_SCORE), bsc))
        self.eval_dir = bdir
        self.eval_score = bsc

        if bdir > 0:
            trig = (rej_bull or pin_bull or eng_bull or sw_low or bfvg or
                    (self.bos_j == j and self.last_bos_dir > 0) or
                    (mom_up and self.struct > 0))
        else:
            trig = (rej_bear or pin_bear or eng_bear or sw_high or sfvg or
                    (self.bos_j == j and self.last_bos_dir < 0) or
                    (mom_dn and self.struct < 0))
        if not trig:
            self.block = "no-trigger"
            self.bump("no-trigger")
            return
        if bsc < P["min_score"]:
            self.block = "low-score"
            self.bump("low-score")
            return
        if er < P["er_chop"]:
            self.block = "chop"
            self.bump("chop")
            return
        if atr_ratio < 0.55:
            self.block = "low-vola"
            self.bump("low-vola")
            return
        if self.session_ok is not None and not self.session_ok[j]:
            self.block = "session"
            self.bump("session")
            return
        if self.blackout is not None and self.blackout[j]:
            self.block = "news"
            return
        if not self.spread_ok:
            self.block = "spread"
            return

        entry = c
        if bdir > 0:
            sl = l - 0.35 * atr
            if entry - sl < P["sl_min"] * atr:
                sl = entry - P["sl_min"] * atr
            risk = entry - sl
            tz = self.zone_nearest_above(entry + 0.1 * atr)
            tp1 = tz.bottom if tz else entry + 2.5 * risk
            if tp1 - entry < P["min_rr"] * risk:
                self.block = "rr"
                self.bump("rr")
                return
        else:
            sl = h + 0.35 * atr
            if sl - entry < P["sl_min"] * atr:
                sl = entry + P["sl_min"] * atr
            risk = sl - entry
            tz = self.zone_nearest_below(entry - 0.1 * atr)
            tp1 = tz.top if tz else entry - 2.5 * risk
            if entry - tp1 < P["min_rr"] * risk:
                self.block = "rr"
                self.bump("rr")
                return
        if risk <= 0:
            self.block = "risk"
            return

        self.eval_signal = True
        self.bump("accepted")
        self.signals.append((j, bdir, bsc, entry, sl, tp1,
                             1 if tz is not None else 0))

    # ---------------- driver ----------------------------------------
    def run(self, warmup=120):
        n = self.n
        st = P["strength"]
        self.is_pivot_hi = np.zeros(n, dtype=bool)
        self.is_pivot_lo = np.zeros(n, dtype=bool)
        for i in range(st, n - st):
            hi = lo = True
            for k in range(1, st + 1):
                if self.h[i + k] >= self.h[i] or self.h[i - k] >= self.h[i]:
                    hi = False
                if self.l[i + k] <= self.l[i] or self.l[i - k] <= self.l[i]:
                    lo = False
            self.is_pivot_hi[i] = hi
            self.is_pivot_lo[i] = lo

        for j in range(warmup, n):
            p = j - st
            if p >= st:
                if self.is_pivot_hi[p]:
                    self.zone_add(self.h[p], 1, p)
                if self.is_pivot_lo[p]:
                    self.zone_add(self.l[p], -1, p)
            self.structure_step(j)
            self.zone_check_break(j)
            self.evaluate(j)
            if self.eval_signal:
                if j - self.last_signal_j >= P["cooldown"]:
                    self.last_signal_j = j
                else:
                    self.signals.pop()
                    continue
        return self.signals


# ================= synthetic market ================================
def make_market(n=20000, seed=7, kind="mixed"):
    rng = np.random.default_rng(seed)
    # regime switching: trend / chop / expansion
    vol = np.zeros(n)
    drift = np.zeros(n)
    v = 1.0
    d = 0.0
    i = 0
    while i < n:
        ln = int(rng.integers(120, 900))
        regime = rng.choice(["trend", "chop", "squeeze"], p=[0.38, 0.42, 0.20])
        if regime == "trend":
            nv = rng.uniform(0.9, 1.7)
            nd = rng.normal(0, 0.55) * nv
        elif regime == "chop":
            nv = rng.uniform(0.8, 1.4)
            nd = 0.0
        else:
            nv = rng.uniform(0.45, 0.8)
            nd = 0.0
        vol[i:i + ln] = nv
        drift[i:i + ln] = nd
        i += ln

    ret = drift + vol * rng.standard_normal(n) * 0.9
    close = 1.20 * np.exp(np.cumsum(ret) * 0.0012)
    open_ = np.empty(n)
    open_[0] = close[0]
    open_[1:] = close[:-1]
    noise = np.abs(rng.standard_normal(n)) * 0.00035 * vol + 0.00005
    high = np.maximum(open_, close) + noise * rng.uniform(0.2, 1.4, n)
    low = np.minimum(open_, close) - noise * rng.uniform(0.2, 1.4, n)

    rng_size = (high - low) / 0.0001
    v = np.maximum(1, rng_size * rng.uniform(0.5, 2.2, n)).astype(int)
    return open_, high, low, close, v


def htf_trend_series(o, h, l, c, agg=3):
    n = len(c)
    m = n // agg
    ho = np.zeros(m)
    hh = np.zeros(m)
    hl = np.zeros(m)
    hc = np.zeros(m)
    for k in range(m):
        s = k * agg
        ho[k] = o[s]
        hh[k] = h[s:s + agg].max()
        hl[k] = l[s:s + agg].min()
        hc[k] = c[s + agg - 1]
    # simple structure trend on aggregated bars
    st = 2
    ph = np.zeros(m, dtype=bool)
    pl = np.zeros(m, dtype=bool)
    for i in range(st, m - st):
        hi = lo = True
        for k in range(1, st + 1):
            if hh[i + k] >= hh[i] or hh[i - k] >= hh[i]:
                hi = False
            if hl[i + k] <= hl[i] or hl[i - k] <= hl[i]:
                lo = False
        ph[i], pl[i] = hi, lo
    tr = np.zeros(m, dtype=int)
    sh = sl = 0.0
    t = 0
    for i in range(m):
        p = i - st
        if p >= 0:
            if ph[p]:
                sh = hh[p]
            if pl[p]:
                sl = hl[p]
        if sh > 0 and hc[i] > sh:
            t, sh = 1, 0.0
        elif sl > 0 and hc[i] < sl:
            t, sl = -1, 0.0
        tr[i] = t
    out = np.zeros(n, dtype=int)
    for j in range(n):
        h = j // agg - 1          # last closed HTF bar
        out[j] = tr[h] if 0 <= h < m else 0
    return out


def outcomes(sig, h, l, horizon=120):
    """walk forward after each signal: which comes first, SL or TP1"""
    win = loss = open_ = 0
    mfe = []
    for s in sig:
        j, d, _, entry, sl, tp1 = s[0], s[1], s[2], s[3], s[4], s[5]
        end = min(len(h), j + horizon)
        res = 0
        best = 0.0
        for k in range(j + 1, end):
            if d > 0:
                best = max(best, (h[k] - entry) / (entry - sl))
                if l[k] <= sl:
                    res = -1
                    break
                if h[k] >= tp1:
                    res = 1
                    break
            else:
                best = max(best, (entry - l[k]) / (sl - entry))
                if h[k] >= sl:
                    res = -1
                    break
                if l[k] <= tp1:
                    res = 1
                    break
        mfe.append(best)
        if res > 0:
            win += 1
        elif res < 0:
            loss += 1
        else:
            open_ += 1
    tot = max(1, win + loss + open_)
    return win, loss, open_, np.median(mfe) if mfe else 0.0


def report(name, sig, n, warm=120, extra="", h=None, l=None):
    span = n - warm
    per100 = len(sig) / span * 100
    longs = sum(1 for s in sig if s[1] > 0)
    print(f"{name:22s} bars={span:6d} sig={len(sig):4d} "
          f"({per100:5.1f}/100) L={longs} S={len(sig)-longs} {extra}")
    if sig:
        sc = np.array([s[2] for s in sig])
        rr = np.array([abs(s[5] - s[3]) / abs(s[3] - s[4]) for s in sig])
        zone_t = np.array([s[6] for s in sig])
        print(f"{'':22s} score {sc.min()}/{int(np.median(sc))}/{sc.max()}"
              f"  RR min/med {rr.min():.1f}/{np.median(rr):.1f}"
              f"  zone-target {zone_t.mean()*100:.0f}%")
        if h is not None:
            w, ls, op, mfe = outcomes(sig, h, l)
            tot = w + ls + op
            print(f"{'':22s} TP1 first {w}/{tot} ({w/tot*100:.0f}%)  "
                  f"SL first {ls}/{tot} ({ls/tot*100:.0f}%)  open {op}  "
                  f"median MFE {mfe:.2f}R")
    return per100


PROFILES = {
    # name: overrides on top of the day-trading defaults
    "scalping": dict(strength=2, min_score=10, level_prox=0.60, merge=0.50,
                     sweep_lb=8, vol_period=14, sl_min=0.80, min_rr=1.20,
                     cooldown=3, er_trend=0.20),
    "daytrade": dict(min_score=10, cooldown=4),
    "swing": dict(strength=5, min_score=10, level_prox=0.65, merge=0.55,
                  sweep_lb=20, vol_period=30, sl_min=1.40, min_rr=2.20,
                  cooldown=5, er_trend=0.25),
}


def run_profile(name, seed=7, n=20000):
    P.update(dict(strength=3, min_score=10, level_prox=0.55, merge=0.45,
                  sweep_lb=12, vol_period=20, sl_min=1.0, min_rr=1.5,
                  cooldown=3, er_trend=0.22))
    P.update(PROFILES[name])
    o, h, l, c, v = make_market(n, seed=seed)
    htf = htf_trend_series(o, h, l, c, 3)
    e = Engine(o, h, l, c, v, htf_trend=htf)
    sig = e.run(warmup=150)
    report(f"{name} s{seed}", sig, len(c), h=h, l=l)
    return e, sig


if __name__ == "__main__":
    import sys
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
    for nm in ("scalping", "daytrade", "swing"):
        agg = {}
        for sd in (7, 11):
            e, _ = run_profile(nm, sd, n=n)
            for k, v in e.counts.items():
                agg[k] = agg.get(k, 0) + v
        tot = sum(agg.values())
        print("   filter hit rates:", {k: f"{v*100//max(1,tot)}%"
              for k, v in sorted(agg.items(), key=lambda kv: -kv[1])})
        print()

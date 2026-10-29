#!/usr/bin/env python3
"""
backtest.py - bar-by-bar engine for the FTMO_QuantEdge strategy logic.

This is a faithful Python mirror of the MQL4 decision loop, run against real
broker bars so the strategy can be measured instead of argued about.

Data: MT5 export from FTMO-Server4 (2025-01-02 .. 2026-05-15), mid-price OHLC
with the broker's per-bar median spread in points. Datetimes are UTC.

Realism rules, all deliberately pessimistic:

  * signals are computed from closed bars only and filled at the NEXT bar's
    open - no look-ahead, no same-bar entry;
  * entry pays half the bar spread plus slippage, exit pays half the spread;
  * if a bar's range covers both the stop and the target, the STOP is assumed
    to have been hit first;
  * EA-initiated exits (z-normalisation, time stops) fill at the bar close;
  * the daily-loss anchor rolls at the same server time the EA uses.

Usage:
    python3 tools/backtest.py --symbol EURUSD --tf m15 --preset conservative
    python3 tools/backtest.py --symbol XAUUSD --tf m15 --preset balanced --split
"""
import argparse
import csv
import os
import sys
from datetime import datetime, timedelta

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "research", "data")

# ----------------------------------------------------------------- symbol specs
SPECS = {
    "EURUSD": dict(point=1e-5, digits=5, contract=100000.0, min_lot=0.01, lot_step=0.01,
                   max_lot=50.0, quote_ccy="USD"),
    "XAUUSD": dict(point=0.01, digits=2, contract=100.0, min_lot=0.01, lot_step=0.01,
                   max_lot=100.0, quote_ccy="USD"),
    "US500.cash": dict(point=0.01, digits=2, contract=1.0, min_lot=0.01, lot_step=0.01,
                       max_lot=1000.0, quote_ccy="USD"),
}

PRESETS = {
    "conservative": dict(risk_pct=0.25, max_risk_pct=0.50, max_open=1, max_open_risk=0.75,
                         max_trades_day=3, day_budget=2.0, total_budget=6.0,
                         threshold=0.65, min_abs_z=1.25, trail=True, trail_atr=1.50,
                         max_bars=36, session=(9, 17)),
    "balanced": dict(risk_pct=0.50, max_risk_pct=1.00, max_open=2, max_open_risk=1.50,
                     max_trades_day=6, day_budget=3.5, total_budget=8.0,
                     threshold=0.55, min_abs_z=1.00, trail=False, trail_atr=1.20,
                     max_bars=48, session=(8, 20)),
    "active": dict(risk_pct=0.75, max_risk_pct=1.00, max_open=2, max_open_risk=1.50,
                   max_trades_day=8, day_budget=4.0, total_budget=8.0,
                   threshold=0.50, min_abs_z=0.85, trail=False, trail_atr=1.20,
                   max_bars=48, session=(8, 20)),
}

BASE = dict(
    # statistics
    z_period=20, robust_z=True, z_cap=3.0, mom_lookback=8, mom_cap=2.0,
    atr_period=14, vr_window=240, vr_horizon=4, vr_threshold=0.08,
    neutral_regime="mr", hl_window=240, max_half_life=80.0, hl_t_min=2.86,
    require_hl_gate=True, atr_pct_window=200, min_atr_pct=0.10, max_atr_pct=0.95,
    trend_ma=200, trend_slope_bars=20, use_trend_filter=True,
    fib_lookback=120, fib_levels=(0.382, 0.500, 0.618), fib_tol=0.35,
    # scoring
    strategy="adaptive", w_z=1.0, w_mom=0.6, w_fib=0.4,
    # exits
    exit_mode="meanrev", sl_atr=2.0, rr=1.5, min_tp_r=0.8, exit_on_z=True,
    z_exit=0.25, hl_stop_mult=3.0, use_hl_stop=True, be=True, be_r=1.0,
    be_lock_pts=10,
    # protection / compliance
    target_pct=10.0, lock_at_target=True, hard_daily=5.0, hard_total=10.0,
    min_trade_sec=120, min_sec_between=30, one_per_bar=True,
    close_before_weekend=True, friday_close_hour=20, no_trade_friday_hour=17,
    skip_rollover_min=15, reopen_blackout_min=10, max_spread_mult=3.0, max_spread_pts=0.0,
    max_cost_atr=1.0, commission_pts=0.0,
    # execution
    slippage_pts=0.5, start_equity=100000.0,
    trail=False, trail_atr=1.20, max_bars=48, session=None,
)

# ----------------------------------------------------------------- data loading

def server_offset_hours(dt_utc):
    """FTMO servers run GMT+2 winter / GMT+3 summer (one hour ahead of CET)."""
    year = dt_utc.year
    # EU DST: last Sunday of March 01:00 UTC .. last Sunday of October 01:00 UTC
    def last_sunday(y, month):
        d = datetime(y, month, 31)
        while d.weekday() != 6:
            d -= timedelta(days=1)
        return d
    start = last_sunday(year, 3).replace(hour=1)
    end = last_sunday(year, 10).replace(hour=1)
    return 3 if (start <= dt_utc < end) else 2


def load_bars(symbol, tf, path=None):
    if path is None:
        fname = f"{symbol}_{tf}.csv"
        path = os.path.join(DATA, fname)
    if not os.path.exists(path):
        raise SystemExit(f"data file missing: {path}")
    dt, o, h, l, c, sp = [], [], [], [], [], []
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            dt.append(datetime.strptime(row["datetime"], "%Y-%m-%d %H:%M:%S"))
            o.append(float(row["open"]))
            h.append(float(row["high"]))
            l.append(float(row["low"]))
            c.append(float(row["close"]))
            sp.append(float(row["spread"]))
    return dict(dt=dt, o=np.array(o), h=np.array(h), l=np.array(l), c=np.array(c),
                sp=np.array(sp), n=len(c))


# ----------------------------------------------------------------- indicators

def _roll_sum(x, w):
    """Rolling sum over the previous w values, ending at each index (inclusive)."""
    cs = np.concatenate(([0.0], np.cumsum(x)))
    out = np.full(len(x), np.nan)
    if len(x) >= w:
        out[w - 1:] = cs[w:] - cs[:-w]
    return out


def compute_indicators(b, p):
    n = b["n"]
    c, h, l = b["c"], b["h"], b["l"]
    out = {}

    # --- ATR and its percentile rank (mirrors ComputeATRStats) -------------
    tr = np.empty(n)
    tr[0] = h[0] - l[0]
    tr[1:] = np.maximum.reduce([h[1:] - l[1:], np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])])
    ap = p["atr_period"]
    atr = np.full(n, np.nan)
    s = _roll_sum(tr, ap)
    atr[ap - 1:] = s[ap - 1:] / ap
    out["atr"] = atr

    w = p["atr_pct_window"]
    pct = np.full(n, np.nan)
    valid = ~np.isnan(atr)
    if valid.sum() > w:
        win = np.lib.stride_tricks.sliding_window_view(atr, w)      # view (n-w+1, w)
        cur = atr[w - 1:]
        pct[w - 1:] = (win <= cur[:, None]).sum(axis=1) / float(w)
    out["atr_pct"] = pct

    # --- robust z-score, excluding the judged bar (mirrors ComputeZScore) --
    zp = p["z_period"]
    zv = np.full(n, np.nan)
    zmean = np.full(n, np.nan)
    for i in range(zp + 1, n):
        window = c[i - zp:i]                       # the zp bars BEFORE bar i
        if p["robust_z"]:
            med = np.median(window)
            mad = np.median(np.abs(window - med))
            sigma = 1.4826 * mad
        else:
            med = window.mean()
            sigma = window.std(ddof=0)
        floor = max(SPEC_FLOOR, 0.0 if np.isnan(atr[i]) else atr[i] * 0.02)
        sigma = max(sigma, floor)
        zv[i] = (c[i] - med) / sigma
        zmean[i] = med
    out["z"] = zv
    out["z_mean"] = zmean

    # --- normalised momentum ----------------------------------------------
    k = p["mom_lookback"]
    mom = np.full(n, np.nan)
    mom[k:] = (c[k:] - c[:-k]) / (atr[k:] * np.sqrt(k))
    out["mom"] = mom

    # --- trend filter ------------------------------------------------------
    tm = p["trend_ma"]
    ma_now = np.full(n, np.nan)
    ma_prev = np.full(n, np.nan)
    s_now = _roll_sum(c, tm)
    ma_now[tm - 1:] = s_now[tm - 1:] / tm
    sb = p["trend_slope_bars"]
    ma_prev[sb + tm - 1:] = ma_now[tm - 1:-sb]
    slope = ma_now - ma_prev
    bias = np.where((slope > 0) & (c > ma_now), 1,
                    np.where((slope < 0) & (c < ma_now), -1, 0)).astype(float)
    bias[np.isnan(slope)] = 0.0
    out["trend_bias"] = bias

    # --- Lo-MacKinlay variance ratio --------------------------------------
    q, vw = p["vr_horizon"], p["vr_window"]
    r1 = np.empty(n)
    r1[0] = 0.0
    r1[1:] = c[1:] - c[:-1]
    rq = np.empty(n)
    rq[:q] = 0.0
    rq[q:] = c[q:] - c[:-q]
    s1, s1sq = _roll_sum(r1, vw), _roll_sum(r1 * r1, vw)
    sq, sqsq = _roll_sum(rq, vw), _roll_sum(rq * rq, vw)
    with np.errstate(invalid="ignore", divide="ignore"):
        v1 = (s1sq / vw) - (s1 / vw) ** 2
        vq = (sqsq / vw) - (sq / vw) ** 2
        vr = vq / (q * v1)
    vr[~np.isfinite(vr)] = 1.0
    vr[v1 <= 1e-15] = 1.0
    out["vr"] = vr

    # --- OLS half-life + Dickey-Fuller t (mirrors ComputeHalfLife) --------
    hlw = p["hl_window"]
    x = np.empty(n)
    x[0] = 0.0
    x[1:] = c[:-1]
    y = np.empty(n)
    y[0] = 0.0
    y[1:] = c[1:] - c[:-1]
    sx, sy = _roll_sum(x, hlw), _roll_sum(y, hlw)
    sxx, sxy, syy = _roll_sum(x * x, hlw), _roll_sum(x * y, hlw), _roll_sum(y * y, hlw)
    nn = float(hlw)
    with np.errstate(invalid="ignore", divide="ignore"):
        den = nn * sxx - sx * sx
        bb = (nn * sxy - sx * sy) / den
        aa = (sy - bb * sx) / nn
        sse = syy - aa * sy - bb * sxy
        sxxc = sxx - sx * sx / nn
        se = np.sqrt(np.maximum(sse, 0.0) / (nn - 2.0) / sxxc)
        tstat = bb / se
        bc = bb + (1.0 + 3.0 * bb) / nn
        with np.errstate(invalid="ignore", divide="ignore"):
            half_life = np.log(2.0) / (-np.log(1.0 + bc))
    bad = (~np.isfinite(bb)) | (bc >= 0.0) | (bc <= -1.0) | (se <= 0.0) | (~np.isfinite(se))
    half_life[bad] = -1.0
    tstat[~np.isfinite(tstat)] = 0.0
    out["half_life"] = half_life
    out["hl_t"] = tstat

    # --- Fibonacci confluence ---------------------------------------------
    fl = p["fib_lookback"]
    fib = np.full(n, 0.0)
    win_h = np.lib.stride_tricks.sliding_window_view(h, fl)
    win_l = np.lib.stride_tricks.sliding_window_view(l, fl)
    hi = win_h.max(axis=1)
    lo = win_l.min(axis=1)
    hi_arg = win_h.argmax(axis=1)          # 0 = oldest bar of the window
    lo_arg = win_l.argmin(axis=1)
    rng = hi - lo
    for j in range(fl - 1, n):
        i = j - (fl - 1)
        a = atr[j]
        if not np.isfinite(a) or a <= 0:
            continue
        R = rng[i]
        if R <= a * 2.0:
            continue
        up_leg = hi_arg[i] > lo_arg[i]     # high is the more recent extreme
        best = 0.0
        for lv in p["fib_levels"]:
            if lv <= 0 or lv >= 1:
                continue
            level = (hi[i] - lv * R) if up_leg else (lo[i] + lv * R)
            dist = abs(c[j] - level) / a
            if dist > p["fib_tol"]:
                continue
            strength = 1.0 - dist / max(p["fib_tol"], 0.01)
            s = strength if up_leg else -strength
            if abs(s) > abs(best):
                best = s
        fib[j] = max(-1.0, min(1.0, best))
    out["fib"] = fib
    return out


SPEC_FLOOR = 1e-5 * 0.5     # point * 0.5, replaced per symbol in run()


# ----------------------------------------------------------------- score

def composite_score(z, mom, fib, mr_mode, p):
    fz = max(-1.0, min(1.0, z / p["z_cap"]))
    fm = max(-1.0, min(1.0, mom / p["mom_cap"]))
    ff = max(-1.0, min(1.0, fib))
    if mr_mode:
        fz, fm = -fz, -fm
    wz, wm, wf = p["w_z"], p["w_mom"], p["w_fib"]
    wsum = abs(wz) + abs(wm) + abs(wf)
    if wsum <= 0:
        return 0.0
    return max(-1.0, min(1.0, (wz * fz + wm * fm + wf * ff) / wsum))


# ----------------------------------------------------------------- engine

class Result(dict):
    pass


def run(bars, p, spec, verbose=False):
    global SPEC_FLOOR
    SPEC_FLOOR = spec["point"] * 0.5
    ind = compute_indicators(bars, p)

    n = bars["n"]
    c, o, h, l, sp, dt = bars["c"], bars["o"], bars["h"], bars["l"], bars["sp"], bars["dt"]
    point = spec["point"]
    vpp = spec["contract"] * point            # account currency per point per lot

    warm = max(p["hl_window"], p["vr_window"], p["atr_pct_window"] + p["atr_period"],
               p["trend_ma"] + p["trend_slope_bars"], p["fib_lookback"]) + 5

    equity = p["start_equity"]
    peak_equity = equity
    start_equity = equity
    day_anchor = None
    day_key = None
    trades_today = 0
    halted_days = set()
    total_halted = False
    target_locked = False

    pos = None
    trades = []
    curve = []
    last_entry_i = -10_000

    for i in range(warm, n - 1):
        now = dt[i]
        srv = now + timedelta(hours=server_offset_hours(now))
        # FTMO day: rolls at 01:00 server
        dkey = (srv - timedelta(hours=1)).date()
        if dkey != day_key:
            day_key = dkey
            day_anchor = max(equity, equity)
            trades_today = 0

        atr = ind["atr"][i]
        if not np.isfinite(atr) or atr <= 0:
            curve.append((now, equity))
            continue

        # ---------- manage an open position on bar i -----------------------
        if pos is not None:
            d, entry, sl, tp, opened_i, rdist, mode, lots = pos
            secs = (now - dt[opened_i]).total_seconds()
            hit_sl = (l[i] <= sl) if d > 0 else (h[i] >= sl)
            hit_tp = (h[i] >= tp) if d > 0 else (l[i] <= tp)

            exit_px = None
            why = None
            if hit_sl:                                   # pessimistic: stop first
                exit_px, why = sl, "stop"
            elif hit_tp:
                exit_px, why = tp, "target"
            else:
                # EA-initiated exits, gated by the minimum trade duration
                if secs >= p["min_trade_sec"]:
                    z = ind["z"][i]
                    if p["exit_on_z"] and mode == "mr" and np.isfinite(z):
                        if (d > 0 and z >= -p["z_exit"]) or (d < 0 and z <= p["z_exit"]):
                            if ((c[i] - entry) * d) / rdist > -0.25:
                                exit_px, why = c[i], "z"
                    if exit_px is None:
                        bars_open = (now - dt[opened_i]).total_seconds() / (dt[i] - dt[i - 1]).total_seconds()
                        hl = ind["half_life"][i]
                        if p["max_bars"] and bars_open >= p["max_bars"]:
                            exit_px, why = c[i], "time"
                        elif p["use_hl_stop"] and hl > 0 and bars_open >= p["hl_stop_mult"] * hl:
                            exit_px, why = c[i], "halflife"

            if exit_px is not None:
                half_cost = (sp[i] * 0.5 + p["commission_pts"] * 0.5 + p["slippage_pts"]) * point
                fill = exit_px - d * half_cost
                r_mult = ((fill - entry) * d) / rdist
                pnl = r_mult * rdist / point * vpp * lots
                equity += pnl
                trades.append(dict(open_time=dt[opened_i], close_time=now, dir=d,
                                   entry=entry, exit=fill, r=r_mult, pnl=pnl,
                                   why=why, lots=pos[7], mode=mode))
                pos = None
            else:
                # break-even / trailing, updated from the close
                if secs >= p["min_trade_sec"]:
                    px = c[i]
                    r_now = ((px - entry) * d) / rdist
                    if p["be"] and r_now >= p["be_r"]:
                        be = entry + d * p["be_lock_pts"] * point
                        if (d > 0 and be > sl) or (d < 0 and (sl == 0 or be < sl)):
                            if (abs(px - be) > max(spec["point"] * 2, sp[i] * point * 1.5)):
                                pos = (d, entry, be, tp, opened_i, rdist, mode, lots)
                if pos is not None and p["trail"] and secs >= p["min_trade_sec"]:
                    d, entry, sl, tp, opened_i, rdist, mode, lots = pos
                    px = c[i]
                    dist = max(p["trail_atr"] * atr, sp[i] * point * 1.5)
                    cand = px - d * dist
                    if (d > 0 and cand > sl + point * 0.5) or (d < 0 and (sl == 0 or cand < sl - point * 0.5)):
                        pos = (d, entry, cand, tp, opened_i, rdist, mode, lots)

        peak_equity = max(peak_equity, equity)
        daily_loss = 100.0 * (day_anchor - equity) / day_anchor if day_anchor else 0.0
        total_loss = 100.0 * (start_equity - equity) / start_equity
        curve.append((now, equity))

        # the EA stops adding trades once the governor has tripped for the day
        if daily_loss >= p["hard_daily"]:
            halted_days.add(dkey)
        if total_loss >= p["hard_total"]:
            total_halted = True
        if p["lock_at_target"] and 100.0 * (equity - start_equity) / start_equity >= p["target_pct"]:
            target_locked = True

        # ---------- entry decision at bar i, fill at bar i+1 open ----------
        if pos is not None or total_halted or target_locked:
            continue
        if dkey in halted_days:
            continue
        if daily_loss >= p["day_budget"]:
            continue
        if trades_today >= p["max_trades_day"]:
            continue
        if p["one_per_bar"] and i - last_entry_i < 1:
            continue

        srv_h = srv.hour
        if p["close_before_weekend"]:
            if srv.weekday() == 4 and srv_h >= p["friday_close_hour"]:
                continue
            if srv.weekday() == 4 and srv_h >= p["no_trade_friday_hour"]:
                continue
        if p["session"] and not (p["session"][0] <= srv_h < p["session"][1]):
            continue
        if p["skip_rollover_min"]:
            mins = srv.hour * 60 + srv.minute
            if mins >= 24 * 60 - p["skip_rollover_min"] or mins < p["skip_rollover_min"]:
                continue

        z = ind["z"][i]
        mom = ind["mom"][i]
        vr = ind["vr"][i]
        hl = ind["half_life"][i]
        ts = ind["hl_t"][i]
        pct = ind["atr_pct"][i]
        fib = ind["fib"][i]
        if not (np.isfinite(z) and np.isfinite(mom) and np.isfinite(pct)):
            continue

        # regime -> mode
        strat = p["strategy"]
        if strat == "meanrev":
            mr_mode, mo_mode, fb_mode = True, False, False
        elif strat == "momentum":
            mr_mode, mo_mode, fb_mode = False, True, False
        elif strat == "fibonly":
            mr_mode, mo_mode, fb_mode = False, False, True
        else:
            if vr <= 1.0 - p["vr_threshold"]:
                mr_mode, mo_mode, fb_mode = True, False, False
            elif vr >= 1.0 + p["vr_threshold"]:
                mr_mode, mo_mode, fb_mode = False, True, False
            else:
                mr_mode = (p["neutral_regime"] == "mr")
                mo_mode = (p["neutral_regime"] == "mo")
                fb_mode = False

        if not (mr_mode or mo_mode or fb_mode):
            continue
        score = composite_score(z, mom, fib, mr_mode, p)
        if abs(score) < p["threshold"]:
            continue
        direction = 1 if score > 0 else -1
        if not (p["min_atr_pct"] <= pct <= p["max_atr_pct"]):
            continue
        if abs(z) < p["min_abs_z"]:
            continue
        if mr_mode and p["require_hl_gate"]:
            if not (hl > 0 and hl <= p["max_half_life"] and (p["hl_t_min"] <= 0 or ts <= -p["hl_t_min"])):
                continue
        if mo_mode and p["use_trend_filter"] and ind["trend_bias"][i] != direction:
            continue

        # spread filter
        max_sp = p["max_spread_pts"] if p["max_spread_pts"] > 0 else sp[i] * p["max_spread_mult"]
        if sp[i] > max_sp:
            continue
        # cost gate: a round trip must stay a small fraction of the bar range
        all_in_pts = sp[i] + p["commission_pts"]
        cost_atr = all_in_pts * point / atr
        if cost_atr > p["max_cost_atr"]:
            continue

        # size: risk % of equity, rounded DOWN to the lot step
        sl_dist = p["sl_atr"] * atr
        risk_pct = min(p["risk_pct"], p["max_risk_pct"])
        risk_money = equity * risk_pct / 100.0
        money_per_lot = sl_dist / point * vpp
        if money_per_lot <= 0:
            continue
        lots = np.floor(risk_money / money_per_lot / spec["lot_step"] + 1e-9) * spec["lot_step"]
        lots = round(lots, 2)
        if lots < spec["min_lot"]:
            continue

        half_cost = (sp[i + 1] * 0.5 + p["commission_pts"] * 0.5 + p["slippage_pts"]) * point
        entry = o[i + 1] + direction * half_cost
        sl = entry - direction * sl_dist
        if p["exit_mode"] == "rmult":
            tp = entry + direction * sl_dist * p["rr"]
        else:
            mean = ind["z_mean"][i]
            floor_tp = max(p["min_tp_r"] * sl_dist, sp[i] * point * 1.5)
            tp = max(mean, entry + floor_tp) if direction > 0 else min(mean, entry - floor_tp)

        pos = (direction, entry, sl, tp, i + 1, sl_dist,
               "mr" if mr_mode else ("mo" if mo_mode else "fb"), lots)
        trades_today += 1
        last_entry_i = i
        if verbose:
            print(f"{now} enter {'LONG' if direction > 0 else 'SHORT'} lots={lots:.2f} "
                  f"entry={entry:.5f} sl={sl:.5f} tp={tp:.5f} score={score:+.3f} z={z:+.2f} "
                  f"hl={hl:.1f} t={ts:+.2f} vr={vr:.3f}")

    # ---------- statistics -------------------------------------------------
    eq = np.array([e for _, e in curve]) if curve else np.array([start_equity])
    rets = np.diff(eq) / eq[:-1] if len(eq) > 1 else np.array([0.0])
    dd_series = eq / np.maximum.accumulate(eq) - 1.0
    r_mults = np.array([t["r"] for t in trades]) if trades else np.array([])

    wins = r_mults[r_mults > 0]
    losses = r_mults[r_mults <= 0]
    gross_win = float(wins.sum()) if len(wins) else 0.0
    gross_loss = float(-losses.sum()) if len(losses) else 0.0

    # daily loss audit
    daily = {}
    for t in trades:
        s = (t["close_time"] + timedelta(hours=server_offset_hours(t["close_time"])))
        k = (s - timedelta(hours=1)).date()
        daily[k] = daily.get(k, 0.0) + t["pnl"]
    daily_losses = []
    for k, pnl in daily.items():
        if pnl < 0:
            daily_losses.append(100.0 * -pnl / start_equity)

    months = {}
    for t in trades:
        key = t["close_time"].strftime("%Y-%m")
        months[key] = months.get(key, 0.0) + t["pnl"]

    why_mix = {}
    for t in trades:
        why_mix[t["why"]] = why_mix.get(t["why"], 0) + 1
    avg_win = float(wins.mean()) if len(wins) else 0.0
    avg_loss = float(losses.mean()) if len(losses) else 0.0

    return Result(
        symbol=None, trades=trades, n_trades=len(trades),
        why_mix=why_mix, avg_win=avg_win, avg_loss=avg_loss,
        win_rate=100.0 * len(wins) / len(trades) if trades else 0.0,
        expectancy_r=float(r_mults.mean()) if len(r_mults) else 0.0,
        profit_factor=(gross_win / gross_loss) if gross_loss > 0 else (float("inf") if gross_win > 0 else 0.0),
        gross_win=gross_win, gross_loss=gross_loss,
        total_r=float(r_mults.sum()) if len(r_mults) else 0.0,
        final_equity=float(eq[-1]), net_pct=100.0 * (float(eq[-1]) - start_equity) / start_equity,
        max_dd_pct=100.0 * float(dd_series.min()) if len(dd_series) else 0.0,
        sharpe=float(rets.mean() / rets.std() * np.sqrt(252 * 96)) if len(rets) > 3 and rets.std() > 0 else 0.0,
        worst_day_loss_pct=max(daily_losses) if daily_losses else 0.0,
        days_over_2pct=sum(1 for d in daily_losses if d >= 2.0),
        days_over_5pct=sum(1 for d in daily_losses if d >= 5.0),
        months=months, day_budget_breaches=len(halted_days),
        avg_bars_in_trade=float(np.mean([(t["close_time"] - t["open_time"]).total_seconds() / (dt[1] - dt[0]).total_seconds() for t in trades])) if trades else 0.0,
        curve=curve, first=dt[warm], last=dt[-1],
    )


# ----------------------------------------------------------------- reporting

def summarise(res, label, preset=None):
    pf = res["profit_factor"]
    pfs = "inf" if pf == float("inf") else f"{pf:.2f}"
    print(f"\n=== {label} ===")
    print(f"  period           {res['first']:%Y-%m-%d} .. {res['last']:%Y-%m-%d}")
    print(f"  trades           {res['n_trades']}   ({res['avg_bars_in_trade']:.1f} bars avg hold)")
    print(f"  win rate         {res['win_rate']:.1f}%")
    print(f"  expectancy       {res['expectancy_r']:+.3f} R   total {res['total_r']:+.1f} R")
    print(f"  profit factor    {pfs}")
    print(f"  net              {res['net_pct']:+.2f}%   final equity {res['final_equity']:.0f}")
    print(f"  max drawdown     {res['max_dd_pct']:.2f}%")
    print(f"  worst day loss   {res['worst_day_loss_pct']:.2f}%   "
          f"(days >=2%: {res['days_over_2pct']}, >=5%: {res['days_over_5pct']})")
    print(f"  exits            " + ", ".join(f"{k}:{v}" for k, v in sorted(res["why_mix"].items())))
    print(f"  avg win / loss   {res['avg_win']:+.2f} R / {res['avg_loss']:+.2f} R")
    if res["months"]:
        ms = ", ".join(f"{k}:{v:+.0f}" for k, v in sorted(res["months"].items()))
        print(f"  monthly P/L      {ms}")
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", default="EURUSD")
    ap.add_argument("--tf", default="m15")
    ap.add_argument("--preset", default="conservative")
    ap.add_argument("--split", action="store_true", help="report two halves separately")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    bars = load_bars(args.symbol, args.tf)
    p = dict(BASE)
    p.update(PRESETS[args.preset])
    spec = SPECS[args.symbol]

    if args.split:
        mid = bars["n"] // 2
        halves = [("first half", slice(0, mid)), ("second half", slice(mid, bars["n"]))]
        for name, sl in halves:
            sub = {k: (v[sl] if isinstance(v, np.ndarray) else v) for k, v in bars.items()}
            sub["n"] = len(sub["c"])
            res = run(sub, p, spec, args.verbose)
            summarise(res, f"{args.symbol} {args.tf.upper()} {args.preset} - {name}")
        return

    res = run(bars, p, spec, args.verbose)
    summarise(res, f"{args.symbol} {args.tf.upper()} preset={args.preset}")


if __name__ == "__main__":
    main()

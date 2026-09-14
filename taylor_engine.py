#!/usr/bin/env python3
"""
Taylor Overnight Cycle Engine v2 — full backtest + screener.
(Educational research, not trading advice. See SECRET_STRATEGY.md + DEEP_DIVE.md.)

What v2 adds over taylor_overnight_backtest.py (v1 kept as-is for reference):
  1. Proper Taylor cycle state machine (swing-aware Buy/Sell/Short candidates)
  2. Buy-Day QUALITY filter: close position in range + Low Violation + (optional
     intraday) low-first / afternoon-reclaim confirmation
  3. Trading-day Turn-of-Month + verified FOMC/CPI/NFP calendar pre-macro flags
  4. Three exits: next-open | prior-high-limit-then-time | first-hour-high (intraday)
  5. Score-based (0-3) risk sizing, shorts leg (optional), ATR regime + blackouts
  6. Breakdowns: score / ToM / pre-macro / weekday / close-pos / regime / year
  7. Multi-ticker SCREENER mode (52W ratio+recency, Heston-Sadka seasonal, cycle)
  8. Offline --demo mode (synthetic data, no network) so anyone can run it

Requires: pandas, numpy. Data: yfinance (optional), stooq (stdlib), or local CSV.
  pip install pandas numpy yfinance

Examples:
  python taylor_engine.py --demo
  python taylor_engine.py --ticker SPY --start 2015-01-01 --source stooq
  python taylor_engine.py --ticker SPY --start 2015-01-01 --source yf --exit limit --shorts
  python taylor_engine.py --screen SPY,QQQ,AAPL,MSFT,NVDA --source stooq
"""
import argparse
import csv
import math
import os
import sys
import urllib.request
from datetime import datetime, timedelta

try:
    import numpy as np
    import pandas as pd
except ImportError:
    print("Need pandas + numpy: pip install pandas numpy")
    sys.exit(1)

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(BASE, "data")
SES = {"52W_WINDOW": 252, "ATR_N": 14, "SWING_N": 5, "SEASON_YEARS": 5}

# ---------------------------------------------------------------- data ---
def load_daily_csv(path):
    df = pd.read_csv(path)
    dcol = "Date" if "Date" in df.columns else df.columns[0]
    df[dcol] = pd.to_datetime(df[dcol])
    df = df.set_index(dcol).sort_index()
    df.index = pd.DatetimeIndex(df.index).tz_localize(None).normalize()
    cols = {c.lower(): c for c in df.columns}
    df = df.rename(columns={cols[k]: k.capitalize()
                            for k in ("open", "high", "low", "close") if k in cols})
    return df[["Open", "High", "Low", "Close"]].dropna()


def load_stooq_daily(ticker, start):
    sym = ticker.lower().replace("-", ".") + ("" if "." in ticker.lower() else ".us")
    d1 = pd.Timestamp(start).strftime("%Y%m%d")
    d2 = datetime.now().strftime("%Y%m%d")
    url = f"https://stooq.com/q/d/l/?s={sym}&d1={d1}&d2={d2}&i=d"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        txt = r.read().decode("utf-8", "replace")
    import io
    df = pd.read_csv(io.StringIO(txt), parse_dates=["Date"], index_col="Date").sort_index()
    df.index = pd.DatetimeIndex(df.index).tz_localize(None).normalize()
    df = df[["Open", "High", "Low", "Close"]].dropna()
    if len(df) == 0:
        raise RuntimeError(f"stooq returned no rows for {ticker} ({url})")
    return df


def load_yf_daily(ticker, start):
    import yfinance as yf
    df = yf.download(ticker, start=start, auto_adjust=False, progress=False)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)
    df.index = pd.DatetimeIndex(df.index).tz_localize(None).normalize()
    return df[["Open", "High", "Low", "Close"]].dropna()


def load_daily(args):
    if args.source == "csv":
        return load_daily_csv(args.csv)
    if args.source == "stooq":
        return load_stooq_daily(args.ticker, args.start)
    if args.source == "yf":
        return load_yf_daily(args.ticker, args.start)
    raise ValueError("source must be yf|stooq|csv")


def load_intraday(args):
    """Return 30/60m bars indexed by tz-naive ET datetime, or None."""
    if args.intraday_csv:
        b = pd.read_csv(args.intraday_csv, parse_dates=["Datetime"], index_col="Datetime").sort_index()
        b.index = pd.DatetimeIndex(b.index).tz_localize(None)
        return b[["Open", "High", "Low", "Close"]]
    if args.intraday and args.source == "yf":
        import yfinance as yf
        ivl = args.intraday
        b = yf.download(args.ticker, start=args.start, interval=ivl, auto_adjust=False,
                        progress=False)
        if isinstance(b.columns, pd.MultiIndex):
            b.columns = b.columns.get_level_values(0)
        try:
            b.index = b.index.tz_convert("America/New_York").tz_localize(None)
        except Exception:
            b.index = pd.DatetimeIndex(b.index).tz_localize(None)
        return b[["Open", "High", "Low", "Close"]].dropna()
    return None


# ----------------------------------------------------------- calendars ---
def load_calendars():
    fomc, macro = set(), {}
    fp = os.path.join(DATA, "fomc_dates.csv")
    if os.path.exists(fp):
        with open(fp) as f:
            for r in csv.DictReader(f):
                fomc.add(pd.Timestamp(r["date"]).normalize())
    mp = os.path.join(DATA, "macro_dates.csv")
    if os.path.exists(mp):
        with open(mp) as f:
            for r in csv.DictReader(f):
                macro[pd.Timestamp(r["date"]).normalize()] = r["event"]
    return fomc, macro


def load_earnings_blackout(path, ticker):
    out = set()
    if path and os.path.exists(path):
        with open(path) as f:
            for r in csv.DictReader(f):
                if r.get("ticker", ticker).upper() == ticker.upper() or "ticker" not in r:
                    out.add(pd.Timestamp(r["date"]).normalize())
    return out


# ------------------------------------------------------------ features ---
def true_range(df):
    pc = df["Close"].shift(1)
    return pd.concat([df["High"] - df["Low"], (df["High"] - pc).abs(),
                      (df["Low"] - pc).abs()], axis=1).max(axis=1)


def add_daily_features(df, fomc, macro, earnings):
    df = df.copy()
    df["prev_close"] = df["Close"].shift(1)
    df["prev_high"] = df["High"].shift(1)
    df["prev_low"] = df["Low"].shift(1)
    df["overnight"] = df["Open"] / df["prev_close"] - 1
    df["intraday"] = df["Close"] / df["Open"] - 1
    df["ctc"] = df["Close"] / df["prev_close"] - 1
    rng = (df["High"] - df["Low"]).replace(0, np.nan)
    df["close_pos"] = ((df["Close"] - df["Low"]) / rng).clip(0, 1)  # 1 = closed on high
    df["TR"] = true_range(df)
    df["ATR"] = df["TR"].rolling(SES["ATR_N"]).mean()
    df["atr_pct"] = df["ATR"] / df["Close"]
    df["atr_pctile"] = df["atr_pct"].rolling(252, min_periods=60).rank(pct=True)

    up = df["Close"] > df["Close"].shift(1)
    dn = df["Close"] < df["Close"].shift(1)
    df["up_streak"] = up.groupby((~up).cumsum()).cumsum()
    df["dn_streak"] = dn.groupby((~dn).cumsum()).cumsum()
    df["supertrend"] = (df["up_streak"] >= 6) | (df["dn_streak"] >= 6)

    # penetration of prior day extremes (fraction of ATR)
    df["pen_high"] = (df["High"] - df["prev_high"]) / df["ATR"]
    df["pen_low"] = (df["prev_low"] - df["Low"]) / df["ATR"]  # + = broke under prev low

    # swing high/low with 2-day confirmation lag (point-in-time)
    n = SES["SWING_N"]
    hi = df["High"].rolling(n).max().shift(2)
    df["is_swing_high_lag2"] = df["High"].shift(2) >= hi
    # days since most recent confirmed swing high
    sh = df.index[df["is_swing_high_lag2"].fillna(False)]
    df["days_since_swing_hi"] = [np.searchsorted(sh.values, t, side="right") and
                                 (t - sh[sh < t][-1]).days if (sh < t).any() else np.nan
                                 for t in df.index]

    # --- 52-week high ratio + recency (Bhootra & Hur 2013: RR = 1 - N/365) ---
    w = SES["52W_WINDOW"]
    roll_max = df["High"].rolling(w, min_periods=50).max()
    df["h52_ratio"] = df["Close"] / roll_max
    rec_cal, rec_td = [], []
    H = df["High"].to_numpy()
    Ix = df.index
    for i in range(len(df)):
        j0 = max(0, i - w + 1)
        k = j0 + int(np.argmax(H[j0:i + 1]))
        rec_td.append(1 - (i - k) / w)
        rec_cal.append(1 - (Ix[i] - Ix[k]).days / 365.0)
    df["h52_rec_td"] = rec_td
    df["h52_rec_cal"] = rec_cal

    # --- Heston-Sadka same-calendar-month signal (point-in-time, prior years) ---
    me = df["Close"].resample("ME").last()
    mret = me.pct_change()
    seas, seasz = {}, {}
    for ts, r in mret.items():
        key = (ts.year, ts.month)
        prior = [mret[t] for t in mret.index
                 if t.month == ts.month and t.year < ts.year
                 and t >= ts - pd.DateOffset(years=SES["SEASON_YEARS"])]
        prior = [x for x in prior if pd.notna(x)]
        if len(prior) >= 2:
            mu = float(np.mean(prior))
            sd = float(np.std(prior, ddof=1)) or 1e-9
            seas[key], seasz[key] = mu, mu / sd
        else:
            seas[key], seasz[key] = np.nan, np.nan
    df["seas_ret"] = [(seas.get((t.year, t.month), np.nan)) for t in df.index]
    df["seas_z"] = [(seasz.get((t.year, t.month), np.nan)) for t in df.index]

    # --- Turn-of-Month (trading-day): last trading day + first 3 trading days ---
    ym = pd.Series(df.index.strftime("%Y-%m"), index=df.index)
    df["tom"] = ((ym.groupby(ym).transform("max") == df.index.strftime("%Y-%m-%d")) |
                 (ym.groupby(ym).cumcount() < 3))
    # last-trading-day check done right:
    last_td = ym.map(df.groupby(ym).apply(lambda g: g.index.max()))
    first3 = set()
    for _, g in df.groupby(ym):
        first3.update(g.index[:3].tolist())
    df["tom"] = df.index.isin(first3) | (df.index == last_td.values)

    # --- pre-macro: hold night BEFORE release (exit morning = release day) ---
    idx = df.index
    cal_all = set(fomc) | set(macro.keys())
    pre, exit_macro, exit_fomc = set(), set(), set()
    pos = {t: i for i, t in enumerate(idx)}
    for d in cal_all:
        # release-day morning in sample? find first trading day >= d
        j = pos.get(d, None)
        if j is None:
            fut = idx[idx >= d]
            if len(fut) == 0:
                continue
            j = pos[fut[0]]
        exit_macro.add(idx[j])
        if j > 0:
            pre.add(idx[j - 1])
    for d in fomc:
        fut = idx[idx >= d]
        if len(fut):
            exit_fomc.add(fut[0])
    df["pre_macro"] = idx.isin(pre)
    df["exit_is_macro"] = idx.isin(exit_macro)
    df["exit_is_fomc"] = idx.isin(exit_fomc)
    df["macro_event"] = [macro.get(t, "") for t in idx]

    # earnings blackout: no hold INTO an earnings morning
    df["earn_next"] = pd.Series(idx).shift(-1).isin(earnings).to_numpy()
    df["friday"] = idx.weekday == 4
    df["weekday"] = idx.strftime("%a")
    df["year"] = idx.year
    return df


def add_intraday_features(df, bars):
    """Merge low-first / reclaim / EOD-tape flags onto daily frame."""
    df = df.copy()
    for c in ["low_first", "first_low_vs_prev", "reclaim", "eod_push", "fh_high", "pre14_close"]:
        df[c] = np.nan
    if bars is None or len(bars) == 0:
        return df
    bars = bars.copy()
    bars["day"] = bars.index.normalize()
    for day, g in bars.groupby("day"):
        if day not in df.index:
            continue
        try:
            i_lo = g["Low"].idxmin()
            i_hi = g["High"].idxmax()
            df.at[day, "low_first"] = 1.0 if i_lo <= i_hi else 0.0
            prev_low = df.at[day, "prev_low"]
            atr = df.at[day, "ATR"]
            if pd.notna(prev_low) and pd.notna(atr) and atr > 0:
                df.at[day, "first_low_vs_prev"] = (g["Low"].iloc[0] - prev_low) / atr
            lo, hi, cl = g["Low"].min(), g["High"].max(), g["Close"].iloc[-1]
            df.at[day, "reclaim"] = 1.0 if (g["Low"].iloc[0] < prev_low and cl > prev_low) else 0.0
            df.at[day, "eod_push"] = (cl - g["Close"].iloc[-2] if len(g) > 1 else 0.0) / (atr or 1)
            # first-hour (<=10:30) high and pre-14:00 close for exits
            t = g.index.time
            fh = g[[x.hour == 9 or (x.hour == 10 and x.minute <= 30) for x in t]]
            if len(fh):
                df.at[day, "fh_high"] = fh["High"].max()
            pre = g[[x.hour < 14 or (x.hour == 13 and x.minute <= 55) for x in t]]
            if len(pre):
                df.at[day, "pre14_close"] = pre["Close"].iloc[-1]
        except Exception:
            continue
    return df


# ------------------------------------------------------- cycle + score ---
def label_cycle(df, args):
    df = df.copy()
    # Buy candidate: 2 down closes OR 2 calendar days after confirmed swing high
    swing2 = df["days_since_swing_hi"].between(2, 3)
    df["buy_cand"] = (df["dn_streak"] >= 2) | swing2.fillna(False)
    df["short_cand"] = df["up_streak"] >= 2

    # Buy-Day Low Violation (daily proxy): deep break of prev low + weak close
    df["violation"] = (df["pen_low"] > 0.25) & (df["close_pos"] < 0.35)

    # Quality score 0-100 (see DEEP_DIVE.md §2 for weights)
    q = df["close_pos"] * 55.0
    q += (~df["violation"].fillna(False)) * 20.0
    q += ((df["pen_low"] > 0) & (df["close_pos"] >= 0.5)) * 10.0  # failed breakdown = fuel
    if "low_first" in df and df["low_first"].notna().any():
        q += df["low_first"].fillna(0.5) * 10.0
        q += df["reclaim"].fillna(0.0) * 5.0
    else:
        q += 5.0  # neutral when no intraday: don't pretend
    df["quality"] = q.clip(0, 100)

    df["hold_ok"] = (df["close_pos"] >= args.min_close_pos) & (~df["violation"].fillna(False))

    # Academic score 0-3 (sizing, not entry)
    df["s_tom"] = df["tom"].astype(int)
    df["s_macro"] = df["pre_macro"].astype(int)
    leader = ((df["h52_ratio"] >= args.min_h52) &
              (df["h52_rec_cal"] >= args.min_rec) &
              (df["seas_z"].fillna(0) > 0))
    df["s_lead"] = leader.astype(int)
    df["score"] = df[["s_tom", "s_macro", "s_lead"]].sum(axis=1)
    return df


# --------------------------------------------------------------- trades ---
def build_trades(df, args):
    trades = []
    idx = df.index
    for i in range(len(df) - 1):
        t, nxt = idx[i], idx[i + 1]
        r = df.loc[t]
        if args.no_friday and r["friday"] and r["score"] < 2:
            continue
        if r["earn_next"]:
            continue
        if pd.notna(r["atr_pctile"]) and r["atr_pctile"] > args.max_atr_pctile:
            continue
        # ---- LONG: Buy Day -> Sell Day morning ----
        if r["buy_cand"] and not r["supertrend"] and r["hold_ok"] and pd.notna(r["ATR"]):
            entry = r["Close"]
            s = df.loc[nxt]
            limit = r["High"]
            if args.exit == "open":
                exitpx = s["Open"]
            elif args.exit == "limit":
                if s["Open"] >= limit:
                    exitpx = s["Open"]
                elif s["High"] >= limit:
                    exitpx = limit * (1 - 1e-4)  # 1bp slip vs limit
                else:
                    exitpx = s["Close"]  # conservative: time-stop bleed to close
            elif args.exit == "firsthour":
                exitpx = s.get("fh_high", np.nan)
                exitpx = exitpx * (1 - 1e-4) if pd.notna(exitpx) else s["Open"]
            if args.fomc_extended and bool(df.loc[nxt, "exit_is_fomc"]):
                px = s.get("pre14_close", np.nan)
                if pd.notna(px):
                    exitpx = px
            stop_pct = max(float(r["ATR"]) / entry, 0.002)
            trades.append(dict(entry_date=t, exit_date=nxt, side="LONG",
                               entry=entry, exit=exitpx,
                               ret=exitpx / entry - 1, stop_pct=stop_pct,
                               score=int(r["score"]), tom=bool(r["tom"]),
                               premacro=bool(r["pre_macro"]),
                               exit_macro=bool(df.loc[nxt, "exit_is_macro"]),
                               quality=float(r["quality"]),
                               close_pos=float(r["close_pos"]),
                               weekday=nxt.strftime("%a"), year=nxt.year,
                               atr_reg=_regime(r["atr_pctile"])))
        # ---- SHORT: Sell-Short Day fade (cover same-day close by default) ----
        if args.shorts and r["short_cand"] and not r["supertrend"] and not r["tom"] \
                and not r["pre_macro"] and r["close_pos"] <= 0.45:
            entry = r["Open"] * (1 - 1e-4)
            exitpx = r["Close"]
            stop_pct = max(float(r["ATR"]) / entry, 0.002)
            trades.append(dict(entry_date=t, exit_date=t, side="SHORT",
                               entry=entry, exit=exitpx,
                               ret=entry / exitpx - 1 - 3e-4,  # short leg: extra borrow proxy
                               stop_pct=stop_pct, score=0, tom=False,
                               premacro=False, exit_macro=False,
                               quality=100 - float(r["quality"]),
                               close_pos=float(r["close_pos"]),
                               weekday=t.strftime("%a"), year=t.year,
                               atr_reg=_regime(r["atr_pctile"])))
    tr = pd.DataFrame(trades)
    if len(tr):
        mult = {0: args.mult0, 1: args.mult1, 2: args.mult2, 3: args.mult3}
        tr["mult"] = tr["score"].map(mult).fillna(args.mult0)
        tr["ret_net"] = tr["ret"] - args.cost_bps / 1e4
    return tr


def _regime(p):
    if pd.isna(p):
        return "n/a"
    return "low" if p < 0.33 else ("mid" if p < 0.67 else "high")


# ------------------------------------------------------------------ sim ---
def simulate(tr, args):
    tr = tr.copy()
    eq = args.equity
    curve = []
    peak, maxdd = eq, 0.0
    for _, x in tr.sort_values(["exit_date", "entry_date"]).iterrows():
        risk_dollars = eq * args.risk_pct * x["mult"]
        notion = min(risk_dollars / x["stop_pct"], eq * args.max_pos)
        pnl = notion * x["ret_net"]
        eq += pnl
        peak = max(peak, eq)
        maxdd = max(maxdd, (peak - eq) / peak if peak else 0)
        curve.append(eq)
    tr["equity"] = curve
    rets = tr["ret_net"].to_numpy()
    wins = rets[rets > 0]
    loss = rets[rets <= 0]
    tot = eq / args.equity - 1
    yrs = max((tr["exit_date"].max() - tr["entry_date"].min()).days / 365.25, 1e-9)
    cagr = (eq / args.equity) ** (1 / yrs) - 1 if yrs > 0.5 else float("nan")
    return tr, dict(
        n=len(tr), hit=float((rets > 0).mean()) if len(tr) else 0,
        avg_bps=float(rets.mean() * 1e4) if len(tr) else 0,
        tstat=float(rets.mean() / (rets.std(ddof=1) / math.sqrt(len(tr)))) if len(tr) > 2 else 0,
        avg_win_bps=float(wins.mean() * 1e4) if len(wins) else 0,
        avg_loss_bps=float(loss.mean() * 1e4) if len(loss) else 0,
        profit_factor=float(-wins.sum() / loss.sum()) if len(loss) and loss.sum() != 0 else float("inf"),
        total_pct=float(tot * 100), cagr_pct=float(cagr * 100) if cagr == cagr else float("nan"),
        maxdd_pct=float(maxdd * 100),
        worst_pct=float(rets.min() * 100) if len(tr) else 0,
        best_pct=float(rets.max() * 100) if len(tr) else 0,
        final_equity=float(eq))


def breakdown(tr, col):
    rows = []
    for k, g in tr.groupby(col):
        r = g["ret_net"].to_numpy()
        rows.append((str(k), len(g), r.mean() * 1e4, (r > 0).mean(), r.sum() * 100))
    return rows


def report(df, tr, stats, args, label):
    print(f"=== {label} | exit={args.exit} | costs={args.cost_bps}bps"
          f" | risk={args.risk_pct * 100:.2f}% mults={args.mult0}/{args.mult1}/{args.mult2}/{args.mult3} ===")
    print(f"Sample: {df.index[0].date()} -> {df.index[-1].date()} ({len(df)} days)")
    print(f"Avg overnight {df['overnight'].mean() * 1e4:6.2f}bps  "
          f"intraday {df['intraday'].mean() * 1e4:6.2f}bps  "
          f"close-to-close {df['ctc'].mean() * 1e4:6.2f}bps")
    print(f"ToM days: {df['tom'].mean():.1%}  pre-macro holds: {df['pre_macro'].mean():.1%}")
    if len(tr) == 0:
        print("No trades. Loosen gates (--min-close-pos, --max-atr-pctile).")
        return
    s = stats
    print(f"\nTrades: {s['n']}  hit={s['hit']:.1%}  avg_net={s['avg_bps']:.2f}bps  t={s['tstat']:.2f}")
    print(f"avgWin={s['avg_win_bps']:.1f}bps avgLoss={s['avg_loss_bps']:.1f}bps "
          f"PF={s['profit_factor']:.2f} worst={s['worst_pct']:.2f}% best={s['best_pct']:.2f}%")
    print(f"Equity ${args.equity:,.0f} -> ${s['final_equity']:,.0f} "
          f"({s['total_pct']:+.1f}% total, CAGR {s['cagr_pct']:+.1f}%, maxDD {s['maxdd_pct']:.1f}%)")
    tr["q_closepos"] = pd.qcut(tr["close_pos"], 5, labels=["lo", "2", "3", "4", "hi"],
                               duplicates="drop")
    for col in ["score", "tom", "premacro", "exit_macro", "weekday", "q_closepos",
                "atr_reg", "side"]:
        if col not in tr.columns or tr[col].nunique() < 2:
            continue
        print(f"\n-- by {col} --")
        for k, n, avg, hit, tot in breakdown(tr, col):
            print(f"  {k:>10s} n={n:4d} avg={avg:+7.2f}bps hit={hit:.0%} sum={tot:+8.2f}%")


# -------------------------------------------------------------- screener ---
def screen(args):
    tickers = [t.strip().upper() for t in args.screen.split(",") if t.strip()]
    fomc, macro = load_calendars()
    rows = []
    for t in tickers:
        a = argparse.Namespace(**{**vars(args), "ticker": t})
        try:
            df = load_daily(a)
        except Exception as e:
            rows.append(dict(ticker=t, verdict=f"DATA FAIL: {e}"))
            continue
        df = label_cycle(add_daily_features(df, fomc, macro, set()), a)
        r = df.iloc[-1]
        d = df.index[-1].date()
        if r["buy_cand"] and r["hold_ok"] and not r["supertrend"]:
            v = f"BUY {d} close -> hold (score {int(r['score'])}, q={r['quality']:.0f})"
        elif r["buy_cand"]:
            v = f"BUY-CANDIDATE but gate failed (q={r['quality']:.0f}, viol={bool(r['violation'])})"
        elif r["short_cand"] and r["close_pos"] <= 0.45:
            v = "SHORT-WATCH (fade morning high, cover weak)"
        else:
            v = "FLAT / wait"
        rows.append(dict(
            ticker=t, date=str(d), close=f"{r['Close']:.2f}",
            cycle=("BUY" if r["buy_cand"] else ("SHORT" if r["short_cand"] else "-")),
            close_pos=f"{r['close_pos']:.2f}", quality=f"{r['quality']:.0f}",
            h52=f"{r['h52_ratio']:.3f}", rec=f"{r['h52_rec_cal']:.2f}",
            seas_z=f"{r['seas_z']:+.2f}" if pd.notna(r["seas_z"]) else "n/a",
            tom=int(r["tom"]), premacro=int(r["pre_macro"]),
            score=int(r["score"]), verdict=v))
    w = pd.DataFrame(rows).sort_values(
        ["score", "quality"], ascending=False, key=lambda c: pd.to_numeric(c, errors="coerce"))
    print(w.to_string(index=False))
    return w


# ------------------------------------------------------------------ demo ---
def demo_frame(years=5, seed=7):
    """Synthetic 30-min bars -> daily, with overnight drift + intraday bleed + ToM boost."""
    rng = np.random.default_rng(seed)
    days = pd.bdate_range(end=pd.Timestamp.now().normalize(), periods=252 * years)
    bars = []
    px = 400.0
    for d in days:
        tom = d.day <= 3 or (d + pd.offsets.BDay(1)).month != d.month
        drift_on = 0.0004 + (0.0008 if tom else 0) + rng.normal(0, 0.0012)
        o = px * (1 + drift_on)
        # 13 half-hour bars with slight bleed + noise + U-shape
        path = [o]
        for k in range(13):
            u = 1.4 if k in (0, 12) else 0.7
            path.append(path[-1] * (1 - 0.00003 + rng.normal(0, 0.0011 * u)))
        c = path[-1]
        for k in range(13):
            bo, bc = path[k], path[k + 1]
            j = abs(rng.normal(0, 0.0009))
            bh, bl = max(bo, bc) * (1 + j), min(bo, bc) * (1 - j)
            ts = d + pd.Timedelta(hours=9, minutes=30 + 30 * k)
            bars.append((ts, bo, bh, bl, bc))
        px = c
    b = pd.DataFrame(bars, columns=["ts", "Open", "High", "Low", "Close"]).set_index("ts")
    d = pd.DataFrame({"Open": b.groupby(b.index.normalize())["Open"].first(),
                      "High": b.groupby(b.index.normalize())["High"].max(),
                      "Low": b.groupby(b.index.normalize())["Low"].min(),
                      "Close": b.groupby(b.index.normalize())["Close"].last()})
    d.index = pd.DatetimeIndex(d.index).tz_localize(None)
    return d, b[["Open", "High", "Low", "Close"]]


# ------------------------------------------------------------------- cli ---
def build_parser():
    p = argparse.ArgumentParser(description="Taylor Overnight Cycle Engine v2")
    p.add_argument("--ticker", default="SPY")
    p.add_argument("--start", default="2015-01-01")
    p.add_argument("--source", default="stooq", choices=["yf", "stooq", "csv"])
    p.add_argument("--csv", default=None, help="local daily OHLC csv (Date,Open,High,Low,Close)")
    p.add_argument("--intraday", default=None, choices=["30m", "60m"],
                   help="fetch yfinance intraday for low-first/exit features")
    p.add_argument("--intraday-csv", default=None, help="local intraday csv (Datetime,...)")
    p.add_argument("--exit", default="open", choices=["open", "limit", "firsthour"])
    p.add_argument("--fomc-extended", action="store_true",
                   help="on FOMC exit mornings hold to 13:55 (needs intraday)")
    p.add_argument("--shorts", action="store_true")
    p.add_argument("--min-close-pos", type=float, default=0.6)
    p.add_argument("--min-h52", type=float, default=0.90)
    p.add_argument("--min-rec", type=float, default=0.75)
    p.add_argument("--max-atr-pctile", type=float, default=1.0)
    p.add_argument("--no-friday", action="store_true",
                   help="skip Friday holds unless score>=2")
    p.add_argument("--earnings-csv", default=None, help="csv with date[,ticker] to blackout")
    p.add_argument("--cost-bps", type=float, default=2.0)
    p.add_argument("--risk-pct", type=float, default=0.005)
    p.add_argument("--mult0", type=float, default=0.5)
    p.add_argument("--mult1", type=float, default=1.0)
    p.add_argument("--mult2", type=float, default=1.5)
    p.add_argument("--mult3", type=float, default=2.0)
    p.add_argument("--max-pos", type=float, default=0.5,
                   help="max notional fraction of equity per trade")
    p.add_argument("--equity", type=float, default=100000)
    p.add_argument("--screen", default=None, help="comma tickers -> screener mode")
    p.add_argument("--demo", action="store_true", help="run offline on synthetic data")
    p.add_argument("--save-trades", default=None, help="write trades csv")
    return p


def main():
    args = build_parser().parse_args()
    if args.screen:
        screen(args)
        return
    fomc, macro = load_calendars()
    if args.demo:
        df, bars = demo_frame()
        label = "DEMO (synthetic)"
    else:
        df = load_daily(args)
        bars = load_intraday(args)
        label = f"{args.ticker} ({args.source})"
    earnings = load_earnings_blackout(args.earnings_csv, args.ticker)
    df = add_daily_features(df, fomc, macro, earnings)
    df = add_intraday_features(df, bars)
    df = label_cycle(df, args)
    tr = build_trades(df, args)
    stats = simulate(tr, args) if len(tr) else ({}, {})
    if len(tr):
        tr, stats = simulate(tr, args)
    report(df, tr, stats, args, label)
    if args.save_trades and len(tr):
        tr.to_csv(args.save_trades, index=False)
        print(f"\nTrades saved to {args.save_trades}")


if __name__ == "__main__":
    main()

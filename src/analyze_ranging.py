"""Diagnose the ranging-market complaint on strategy #1.

Question: how many signals fire while price is chopping sideways, and what do
those trades actually cost? Ranging is measured two independent ways so the
answer doesn't hinge on one definition:

  * Kaufman Efficiency Ratio (ER) = |net move| / sum(|bar moves|) over N bars.
    ~1.0 = clean directional move, ~0.0 = pure chop.
  * ADX(14) -- the classic. Below 20-25 is conventionally "no trend".
"""
import os
import sys
import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
from indicators import Cache
from strategies import make
import backtest as bt

ER_WIN = 20
ADX_WIN = 14


def efficiency_ratio(close, n=ER_WIN):
    net = (close - close.shift(n)).abs()
    path = close.diff().abs().rolling(n).sum()
    return net / path.replace(0, np.nan)


def adx(high, low, close, n=ADX_WIN):
    up = high.diff()
    dn = -low.diff()
    plus_dm = up.where((up > dn) & (up > 0), 0.0)
    minus_dm = dn.where((dn > up) & (dn > 0), 0.0)
    pc = close.shift(1)
    tr = pd.concat([(high - low).abs(), (high - pc).abs(), (low - pc).abs()])
    tr = pd.DataFrame({c: np.maximum.reduce([
        (high[c] - low[c]).values,
        (high[c] - pc[c]).abs().values,
        (low[c] - pc[c]).abs().values]) for c in close.columns},
        index=close.index)
    atr = tr.ewm(alpha=1 / n, adjust=False).mean()
    pdi = 100 * plus_dm.ewm(alpha=1 / n, adjust=False).mean() / atr.replace(0, np.nan)
    mdi = 100 * minus_dm.ewm(alpha=1 / n, adjust=False).mean() / atr.replace(0, np.nan)
    dx = 100 * (pdi - mdi).abs() / (pdi + mdi).replace(0, np.nan)
    return dx.ewm(alpha=1 / n, adjust=False).mean(), pdi, mdi


def load():
    return {f.capitalize(): pd.read_parquet(os.path.join(ROOT, "data", f"{f}.parquet"))
            for f in ["open", "high", "low", "close", "volume"]}


def trade_table(pos_sym, ret_sym, er_sym, adx_sym):
    """Split a single symbol's position series into discrete trades."""
    state = (pos_sym.abs() > 1e-12).astype(int)
    chg = state.diff().fillna(state.iloc[0])
    trades = []
    entries = list(state.index[chg == 1])
    for e in entries:
        after = state.loc[e:]
        ex = after[after == 0]
        x = ex.index[0] if len(ex) else state.index[-1]
        seg_r = ret_sym.loc[e:x]
        w = pos_sym.shift(1).loc[e:x].fillna(0.0)
        pnl = (w * seg_r).sum()
        trades.append(dict(entry=e, exit=x, bars=len(seg_r), pnl=pnl,
                           er=er_sym.loc[e], adx=adx_sym.loc[e]))
    return pd.DataFrame(trades)


def main():
    panels = load()
    cache = Cache(panels)
    ret = cache.ret
    close, high, low = panels["Close"], panels["High"], panels["Low"]

    pos = make("trend_vol_filter",
               dict(ma=200, volw=120, volmax=0.12, mode="lo", sizing="vt10"), cache)

    er = efficiency_ratio(close)
    ad, pdi, mdi = adx(high, low, close)

    all_tr = []
    for s in close.columns:
        t = trade_table(pos[s], ret[s], er[s], ad[s])
        if len(t):
            t["sym"] = s
            all_tr.append(t)
    tr = pd.concat(all_tr, ignore_index=True).dropna(subset=["er", "adx"])

    print(f"total trades: {len(tr)}")
    print(f"median hold : {tr.bars.median():.0f} bars\n")

    # ---- split by regime at entry
    for label, mask in [
        ("RANGING  (ER < 0.30)", tr.er < 0.30),
        ("TRENDING (ER >= 0.30)", tr.er >= 0.30),
        ("RANGING  (ADX < 20)", tr.adx < 20),
        ("TRENDING (ADX >= 20)", tr.adx >= 20),
    ]:
        g = tr[mask]
        if not len(g):
            continue
        print(f"{label:24s} n={len(g):4d} ({len(g)/len(tr):5.1%})  "
              f"win={ (g.pnl>0).mean():5.1%}  "
              f"avg={g.pnl.mean():+.4%}  tot={g.pnl.sum():+.3f}  "
              f"med_bars={g.bars.median():.0f}")

    # ---- fraction of TIME in position spent ranging
    inpos = (pos.abs() > 1e-12)
    er_al, ad_al = er.reindex_like(inpos), ad.reindex_like(inpos)
    tot = inpos.sum().sum()
    print(f"\nbars in position: {tot:,.0f}")
    print(f"  with ER  < 0.30 : {(inpos & (er_al < 0.30)).sum().sum()/tot:6.1%}")
    print(f"  with ADX < 20   : {(inpos & (ad_al < 20)).sum().sum()/tot:6.1%}")

    # ---- what if we simply refuse to trade chop?
    print("\n--- adding a regime gate to the ORIGINAL strategy ---")
    base_r, base_to = bt.run(pos, ret)
    print(f"{'variant':28s} {'Sharpe':>7s} {'CAGR':>7s} {'maxDD':>7s} "
          f"{'turn':>6s} {'time in mkt':>11s}")
    base_s = bt.stats(base_r, base_to)
    print(f"{'baseline (no gate)':28s} {base_s['sharpe']:7.2f} "
          f"{base_s['cagr']:7.1%} {base_s['max_dd']:7.1%} "
          f"{base_s['ann_turnover']:6.1f} {inpos.mean().mean():11.1%}")

    for name, gate in [
        ("ER > 0.20", er > 0.20),
        ("ER > 0.30", er > 0.30),
        ("ER > 0.35", er > 0.35),
        ("ADX > 20", ad > 20),
        ("ADX > 25", ad > 25),
        ("ADX>20 & +DI>-DI", (ad > 20) & (pdi > mdi)),
        ("ER>0.30 & ADX>20", (er > 0.30) & (ad > 20)),
    ]:
        p2 = pos * gate.astype(float).reindex_like(pos).fillna(0.0)
        r2, to2 = bt.run(p2, ret)
        s2 = bt.stats(r2, to2)
        ip2 = (p2.abs() > 1e-12)
        print(f"{name:28s} {s2['sharpe']:7.2f} {s2['cagr']:7.1%} "
              f"{s2['max_dd']:7.1%} {s2['ann_turnover']:6.1f} "
              f"{ip2.mean().mean():11.1%}")


if __name__ == "__main__":
    main()

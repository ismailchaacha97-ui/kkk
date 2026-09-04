"""Second pass on the ranging question.

The naive test applied the regime gate bar-by-bar, which forces an exit every
time ADX/ER dips -- that alone explodes turnover and destroys the result.
The fair test is to gate only the ENTRY and let the original rule manage the
exit. This also asks whether "signals during ranging" are even the problem.
"""
import os
import sys
import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
from indicators import Cache
from strategies import make
from analyze_ranging import efficiency_ratio, adx, load
import backtest as bt


def entry_gated(pos, gate):
    """Keep the base rule's exits; only allow a NEW entry when gate is True.

    Position runs until the base rule turns off, so turnover stays sane.
    """
    state = (pos.abs() > 1e-12)
    g = gate.reindex_like(state).fillna(False)
    out = pd.DataFrame(False, index=state.index, columns=state.columns)
    for c in state.columns:
        s = state[c].values
        gg = g[c].values
        live = False
        res = np.zeros(len(s), dtype=bool)
        for i in range(len(s)):
            if not s[i]:
                live = False
            elif not live and gg[i]:
                live = True          # base rule ON and regime OK -> open
            res[i] = live and s[i]
        out[c] = res
    return pos.where(out, 0.0)


def show(name, pos, ret):
    r, to = bt.run(pos, ret)
    s = bt.stats(r, to)
    ip = (pos.abs() > 1e-12)
    print(f"{name:30s} {s['sharpe']:7.2f} {s['cagr']:7.1%} {s['max_dd']:7.1%} "
          f"{s['calmar']:7.2f} {s['ann_turnover']:6.1f} {ip.mean().mean():10.1%}")
    return s


def main():
    panels = load()
    cache = Cache(panels)
    ret = cache.ret
    close, high, low = panels["Close"], panels["High"], panels["Low"]

    pos = make("trend_vol_filter",
               dict(ma=200, volw=120, volmax=0.12, mode="lo", sizing="vt10"), cache)

    er = efficiency_ratio(close)
    ad, pdi, mdi = adx(high, low, close)
    # slope of the 200 SMA: a genuinely rising MA is the simplest "not ranging" test
    ma = close.rolling(200).mean()
    slope = ma / ma.shift(20) - 1.0

    print(f"{'variant':30s} {'Sharpe':>7s} {'CAGR':>7s} {'maxDD':>7s} "
          f"{'Calmar':>7s} {'turn':>6s} {'in mkt':>10s}")
    print("-" * 78)
    show("baseline (no gate)", pos, ret)

    print("\n-- gate applied every bar (forces exits) --")
    for n, g in [("ADX > 20 (every bar)", ad > 20),
                 ("ER > 0.30 (every bar)", er > 0.30)]:
        show(n, pos * g.astype(float).reindex_like(pos).fillna(0.0), ret)

    print("\n-- gate applied at ENTRY only (exits unchanged) --")
    for n, g in [("ADX > 20 at entry", ad > 20),
                 ("ADX > 25 at entry", ad > 25),
                 ("ER > 0.25 at entry", er > 0.25),
                 ("ER > 0.35 at entry", er > 0.35),
                 ("MA200 rising at entry", slope > 0),
                 ("MA200 rising + ADX>20", (slope > 0) & (ad > 20))]:
        show(n, entry_gated(pos, g), ret)

    # Is the complaint about *frequency* of flip-flopping rather than PnL?
    state = (pos.abs() > 1e-12).astype(int)
    flips = state.diff().abs().sum().sum() / 2
    short = 0
    for c in state.columns:
        s = state[c]
        chg = s.diff().fillna(s.iloc[0])
        for e in s.index[chg == 1]:
            after = s.loc[e:]
            ex = after[after == 0]
            x = ex.index[0] if len(ex) else s.index[-1]
            if len(s.loc[e:x]) <= 5:
                short += 1
    print(f"\nround trips: {flips:.0f}   of which <=5 bars: {short} "
          f"({short/max(flips,1):.0%})  <-- the actual chop complaint")

    print("\n-- minimum-hold cure: ignore exit signals for N bars --")
    for hold in [5, 10, 15, 20]:
        p2 = pos.copy()
        for c in pos.columns:
            s = (pos[c].abs() > 1e-12).values
            v = pos[c].values.copy()
            last_entry = -10 ** 9
            live = False
            for i in range(len(s)):
                if s[i] and not live:
                    live, last_entry = True, i
                elif not s[i] and live:
                    if i - last_entry < hold:
                        v[i] = v[i - 1]      # hold through the premature exit
                    else:
                        live = False
            p2[c] = v
        show(f"min hold {hold} bars", p2, ret)


if __name__ == "__main__":
    main()

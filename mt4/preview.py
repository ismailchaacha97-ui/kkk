"""Render what TrendVolFilter.mq4 draws on an MT4 chart (SPY D1)."""
import os
import sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_parity import mql4_port, MA_PERIOD, VOL_WINDOW, VOL_MAX, SIZE_VOL_WINDOW

SYM = "SPY"


def main():
    close = pd.read_parquet(os.path.join(ROOT, "data", "close.parquet"))[SYM]
    high = pd.read_parquet(os.path.join(ROOT, "data", "high.parquet"))[SYM]
    low = pd.read_parquet(os.path.join(ROOT, "data", "low.parquet"))[SYM]
    state, scale = mql4_port(close)

    ma = close.rolling(MA_PERIOD).mean()
    vol = close.pct_change().rolling(VOL_WINDOW).std() * np.sqrt(252)

    d = pd.DataFrame(dict(close=close, ma=ma, vol=vol, state=state,
                          scale=scale, high=high, low=low)).dropna()

    fig, ax = plt.subplots(3, 1, figsize=(15, 11), sharex=True,
                           gridspec_kw={"height_ratios": [3, 1, 1]})
    fig.patch.set_facecolor("#1e1e1e")
    for a in ax:
        a.set_facecolor("#1e1e1e")
        a.tick_params(colors="#cccccc")
        for sp in a.spines.values():
            sp.set_color("#555555")
        a.grid(alpha=0.15, color="#888888")

    # --- price pane
    ax[0].plot(d.index, d.close, color="#dddddd", lw=1.1, label=f"{SYM} close")
    ax[0].plot(d.index, d.ma, color="#1e90ff", lw=1.6, ls=":",
               label=f"SMA({MA_PERIOD})")
    on = d.ma.where(d.state == 1)
    ax[0].plot(d.index, on, color="#32cd32", lw=3.0, label="SMA while LONG")

    # shaded in-position blocks
    st = d.state.values
    idx = d.index
    i = 0
    first = True
    while i < len(st):
        if st[i] == 1:
            j = i
            while j + 1 < len(st) and st[j + 1] == 1:
                j += 1
            ax[0].axvspan(idx[i], idx[j], color="#32cd32", alpha=0.10,
                          label="in position" if first else None)
            first = False
            i = j + 1
        else:
            i += 1

    ent = (d.state.diff() == 1)
    ext = (d.state.diff() == -1)
    ax[0].scatter(d.index[ent], d.low[ent] * 0.97, marker="^", s=90,
                  color="#32cd32", edgecolor="k", zorder=6, label="entry")
    ax[0].scatter(d.index[ext], d.high[ext] * 1.03, marker="v", s=90,
                  color="#ff4500", edgecolor="k", zorder=6, label="exit")

    ax[0].set_title(f"TrendVolFilter.mq4  —  {SYM} Daily  (rank #1 of 9,600)",
                    color="white", fontsize=14)
    ax[0].set_ylabel("price", color="#cccccc")
    ax[0].legend(fontsize=9, facecolor="#2a2a2a", labelcolor="#dddddd", ncol=3)

    # status panel text, as the indicator prints it
    last = d.iloc[-1]
    panel = (f"TREND-VOL FILTER  (rank #1 / 9,600)\n"
             f"Trend  Close vs SMA{MA_PERIOD} : "
             f"{'ABOVE  OK' if last.close > last.ma else 'BELOW  no'}"
             f"  ({(last.close/last.ma-1)*100:+.2f}%)\n"
             f"Vol    Ann{VOL_WINDOW}         : {last.vol*100:.2f}%  "
             f"(max {VOL_MAX*100:.2f}%)  {'OK' if last.vol < VOL_MAX else 'no'}\n"
             f"SIGNAL                : {'LONG' if last.state else 'FLAT'}\n"
             f"Position scale        : {last.scale:.2f}x  (target 10% vol)")
    ax[0].text(0.005, 0.98, panel, transform=ax[0].transAxes, va="top",
               family="monospace", fontsize=9, color="#e0e0e0",
               bbox=dict(boxstyle="round", fc="#000000", ec="#666666", alpha=0.85))

    # --- vol pane
    ax[1].plot(d.index, d.vol * 100, color="#ffa500", lw=1.2,
               label=f"annualised vol({VOL_WINDOW})")
    ax[1].axhline(VOL_MAX * 100, color="#ff4500", ls="--", lw=1.5,
                  label=f"ceiling {VOL_MAX*100:.0f}%")
    ax[1].fill_between(d.index, 0, VOL_MAX * 100, color="#32cd32", alpha=0.08)
    ax[1].set_ylabel("vol %", color="#cccccc")
    ax[1].legend(fontsize=9, facecolor="#2a2a2a", labelcolor="#dddddd")

    # --- size pane
    ax[2].fill_between(d.index, 0, d.scale, color="#1e90ff", alpha=0.55, step="pre")
    ax[2].axhline(3.0, color="#ff4500", ls="--", lw=1.2, label="cap 3.0x")
    ax[2].set_ylabel("position\nscale", color="#cccccc")
    ax[2].set_xlabel("date", color="#cccccc")
    ax[2].legend(fontsize=9, facecolor="#2a2a2a", labelcolor="#dddddd")

    plt.tight_layout()
    out = os.path.join(ROOT, "mt4", "preview.png")
    plt.savefig(out, dpi=120, facecolor=fig.get_facecolor())
    print("wrote", out)
    print(f"in position {d.state.mean():.1%} of bars, "
          f"{int(ent.sum())} entries, avg scale {d.scale[d.state==1].mean():.2f}x")


if __name__ == "__main__":
    main()

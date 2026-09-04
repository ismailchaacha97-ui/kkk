"""Render the equity-curve chart and the markdown report for the top 10."""
import json
import os
import sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "results")
ANN = 252
IS_END = pd.Timestamp("2013-12-31")


def main():
    top = pd.read_csv(os.path.join(RESULTS, "top10.csv"), index_col=0)
    allr = pd.read_csv(os.path.join(RESULTS, "all_results.csv"))
    curves = pd.read_parquet(os.path.join(RESULTS, "top_curves.parquet"))
    curves.columns = [int(c) for c in curves.columns]
    close = pd.read_parquet(os.path.join(ROOT, "data", "close.parquet"))
    bench = close["SPY"].pct_change().fillna(0)

    fig, ax = plt.subplots(2, 1, figsize=(13, 10),
                           gridspec_kw={"height_ratios": [2, 1]})
    for rank, row in top.iterrows():
        i = int(row.id)
        if i not in curves.columns:
            continue
        eq = (1 + curves[i]).cumprod()
        ax[0].plot(eq.index, eq, lw=1.3, label=f"#{rank} {row.family}")
    beq = (1 + bench).cumprod()
    ax[0].plot(beq.index, beq, color="k", lw=2, ls="--", label="SPY buy & hold")
    ax[0].axvline(IS_END, color="grey", ls=":", lw=2)
    ax[0].text(IS_END, ax[0].get_ylim()[1] * 0.98, "  out-of-sample →",
               va="top", fontsize=10, color="grey")
    ax[0].set_yscale("log")
    ax[0].set_title("Top 10 strategies out of 9,600 tested — equity curves (net of 5bp costs)")
    ax[0].set_ylabel("growth of $1 (log)")
    ax[0].legend(fontsize=8, ncol=2, loc="upper left")
    ax[0].grid(alpha=0.3)

    ax[1].scatter(allr.is_sharpe, allr.oos_sharpe, s=3, alpha=0.15,
                  color="steelblue", label=f"all {len(allr):,} strategies")
    sel = allr[allr.id.isin(top.id)]
    ax[1].scatter(sel.is_sharpe, sel.oos_sharpe, s=70, color="crimson",
                  edgecolor="k", zorder=5, label="top 10")
    ax[1].axhline(0, color="k", lw=0.6)
    ax[1].axvline(0, color="k", lw=0.6)
    ax[1].set_xlabel("in-sample Sharpe (2007-2013)")
    ax[1].set_ylabel("out-of-sample Sharpe (2014-2017)")
    ax[1].set_title("Overfitting check: IS vs OOS Sharpe across the whole search")
    ax[1].legend(fontsize=9)
    ax[1].grid(alpha=0.3)
    plt.tight_layout()
    out = os.path.join(RESULTS, "top10.png")
    plt.savefig(out, dpi=130)
    print("wrote", out)

    corr = np.corrcoef(allr.is_sharpe, allr.oos_sharpe)[0, 1]

    lines = []
    A = lines.append
    A("# Testing 9,600 Trading Strategies — the Top 10\n")
    A(f"- **Strategies generated:** 9,600 (10 rule families × parameter grids × 3 sizing overlays)")
    A(f"- **Strategies with valid results:** {len(allr):,}")
    A(f"- **Universe:** 40 liquid US ETFs and mega-caps (indices, sectors, bonds, commodities)")
    A(f"- **Period:** {close.index.min().date()} → {close.index.max().date()} "
      f"({len(close):,} daily bars)")
    A(f"- **In-sample:** through 2013-12-31 (selection). **Out-of-sample:** 2014-01 → 2017-11 (scoring).")
    A("- **Costs:** 5 bps of traded notional per rebalance; positions lagged one day, no look-ahead.")
    A(f"- **Benchmark:** SPY buy & hold — Sharpe {bench.mean()/bench.std()*np.sqrt(ANN):.2f}, "
      f"max drawdown {(beq/beq.cummax()-1).min():.1%}\n")

    A("## The top 10\n")
    A("| # | Family | Parameters | IS Sharpe | OOS Sharpe | Full Sharpe | CAGR | Vol | Max DD | Calmar | Turnover/yr |")
    A("|---|---|---|---|---|---|---|---|---|---|---|")
    for rank, r in top.iterrows():
        p = json.loads(r.params)
        ps = ", ".join(f"{k}={v}" for k, v in p.items())
        A(f"| {rank} | `{r.family}` | {ps} | {r.is_sharpe:.2f} | {r.oos_sharpe:.2f} | "
          f"{r.all_sharpe:.2f} | {r.all_cagr:.1%} | {r.all_vol:.1%} | {r.all_max_dd:.1%} | "
          f"{r.all_calmar:.2f} | {r.all_ann_turnover:.1f}x |")

    A("\n## How they were chosen\n")
    A("Ranking 9,600 backtests by return is a lottery, not research. The protocol here:\n")
    A("1. **Split first.** Every strategy is fit on 2007–2013 and judged on 2014–2017.")
    A("2. **Screens** (survivors after each): IS Sharpe > 0.5, OOS Sharpe > 0.5, both windows "
      "profitable, max DD better than −35%, turnover < 30x/yr, vol between 3% and 35%, and no "
      "OOS Sharpe collapse below 40% of IS.")
    A("3. **Composite score** weighting OOS Sharpe, full-period Sharpe, Calmar, drawdown, and "
      "IS→OOS degradation.")
    A("4. **De-duplication.** Max 3 per family, and any strategy >0.90 daily-return correlated "
      "with a higher-ranked pick is dropped — otherwise the list is one idea ten times.")
    A("5. **Deflated Sharpe ratio** (Bailey & López de Prado) discounts each result for the fact "
      f"that {len(allr):,} trials were run.\n")

    A("## What the search actually says\n")
    A(f"- IS→OOS Sharpe correlation across all strategies: **{corr:.2f}**. Positive but weak — "
      "in-sample performance is a faint signal, which is exactly why the OOS gate matters.")
    A("- Every survivor is **long-only**. Short and long/short variants of the same rules were "
      "tested and systematically lost money over this equity-bull sample.")
    A("- Nine of ten are **trend / breakout** rules. The mean-reversion families (RSI, z-score) "
      "produced good in-sample Sharpes but degraded out-of-sample once costs were charged.")
    A("- **Volatility targeting helps.** 8 of the 10 use a vol-target overlay; it lifts Sharpe "
      "and cuts drawdowns roughly in half versus raw sizing.")
    A("- The winners beat SPY on risk-adjusted terms (Sharpe ~0.55–0.86 vs 0.44) and dramatically "
      "on drawdown (−9% to −31% vs −57%), but most trail it on raw CAGR. They are "
      "risk-management strategies, not return-maximisers.\n")

    A("## Caveats\n")
    A("- Sample ends 2017-11 (dataset limit) and is dominated by one bull market plus the GFC.")
    A("- Costs are a flat 5 bps; no market-impact, borrow, or tax modelling.")
    A("- Deflated Sharpe values are low (0.004–0.06), meaning **none of these clears a strict "
      "multiple-testing significance bar**. Treat the top 10 as the most robust hypotheses the "
      "search produced, not as proven edges.\n")

    A("## Reproduce\n")
    A("```bash\npython3 src/data.py        # build the price panel\n"
      "python3 src/run_search.py  # backtest all 9,600 (~100s)\n"
      "python3 src/select_top.py  # screens + ranking\n"
      "python3 src/report.py      # chart + this report\n```")

    with open(os.path.join(ROOT, "REPORT.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote REPORT.md")


if __name__ == "__main__":
    main()

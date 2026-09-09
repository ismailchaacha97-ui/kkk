"""Figures for the report (matplotlib only, no display backend)."""

from __future__ import annotations

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import TwoSlopeNorm

plt.rcParams.update({
    "figure.dpi": 130, "savefig.dpi": 150, "font.size": 9, "axes.grid": True,
    "grid.alpha": 0.25, "axes.spines.top": False, "axes.spines.right": False,
    "axes.titlesize": 10, "axes.titleweight": "bold", "legend.frameon": False,
})
OK = "#1a7f37"      # good
BAD = "#b3261e"     # bad
ACCENT = "#0b5394"  # highlight
GREY = "#6b7280"

FAMOUS = [(12, 26, "12/26 MACD"), (9, 21, "9/21"), (8, 21, "8/21"), (20, 50, "20/50"),
          (50, 200, "50/200"), (10, 20, "10/20"), (5, 35, "5/35"), (21, 55, "21/55"),
          (10, 100, "10/100"), (20, 100, "20/100"), (5, 20, "5/20"), (13, 48, "13/48")]


def _annotate_famous(ax, agg, col):
    m = agg.set_index(["fast", "slow"])
    for f, s, lab in FAMOUS:
        if (f, s) in m.index:
            ax.plot(s, f, "o", ms=5, mfc="white", mec="black", mew=1.1, zorder=5)
            ax.annotate(lab, (s, f), xytext=(4, 4), textcoords="offset points", fontsize=6.5, color="black")


def surface(agg: pd.DataFrame, cols=("med_sharpe", "nb_min"), title=None, fname="fig_surface.png",
            cmaps=("RdYlGn", "RdYlGn"), fam_label="Sharpe"):
    """Heat-maps of the cross-market consensus surface: raw winner vs robust plateau."""
    fig, axes = plt.subplots(1, len(cols), figsize=(5.05 * len(cols), 4.0))
    axes = np.atleast_1d(axes)
    for ax, col, cm in zip(axes, cols, cmaps):
        P = agg.pivot_table(index="fast", columns="slow", values=col, aggfunc="mean")
        M = P.to_numpy(float)
        finite = M[np.isfinite(M)]
        if finite.size == 0:
            ax.set_visible(False)
            continue
        lo, hi = np.percentile(finite, [2, 98])
        mid = 0.0 if lo < 0 < hi else (lo + hi) / 2
        im = ax.imshow(M, origin="lower", aspect="auto", cmap=cm, vmin=lo, vmax=hi,
                       extent=[P.columns.min(), P.columns.max(), P.index.min(), P.index.max()])
        _annotate_famous(ax, agg, col)
        ax.set_title((title or {}).get(col, col) if isinstance(title, dict) else f"{col}")
        ax.set_xlabel("slow EMA (bars)")
        ax.set_ylabel("fast EMA (bars)")
        cb = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
        cb.set_label(f"median {fam_label} across markets", fontsize=8)
        cb.ax.tick_params(labelsize=7)
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname


def line_by_slow(agg: pd.DataFrame, col: str, fname="fig_lines.png",
                 fasts=(5, 10, 20, 40, 80), title="Median cross-market Sharpe vs slow period"):
    fig, ax = plt.subplots(figsize=(6.4, 3.6))
    for f in fasts:
        d = agg[agg["fast"] == f].sort_values("slow")
        if d.empty:
            continue
        ax.plot(d["slow"], d[col], lw=1.6, label=f"fast = {f}")
    ax.axhline(0, color="black", lw=0.8)
    ax.set_xlabel("slow EMA (bars)")
    # the same helper draws the raw median and the worst-neighbour score, so the axis label has to
    # follow the column: a "median Sharpe" axis under a "Worst-neighbour Sharpe" title once made a
    # figure in the report say something other than what it showed.
    ax.set_ylabel({"med_sharpe": "median Sharpe", "nb_min_sharpe": "median of worst-neighbour Sharpe",
                   "nb_med_sharpe": "median of neighbourhood Sharpe"}.get(col, col))
    ax.set_title(title)
    ax.legend(ncol=2, fontsize=7.5)
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname


def is_vs_oos(ft: pd.DataFrame, fname="fig_is_oos.png"):
    """In-sample winner vs what it actually earned out of sample, per market/fold."""
    fig, axes = plt.subplots(1, 2, figsize=(8.6, 3.7))
    ax = axes[0]
    a = ft.dropna(subset=["is_sharpe", "oos_of_is_best"])
    ax.scatter(a["is_sharpe"], a["oos_of_is_best"], s=9, alpha=0.35, color=ACCENT, edgecolors="none")
    v = a[["is_sharpe", "oos_of_is_best"]].to_numpy().ravel()
    lim = [min(float(np.nanmin(v)), -0.5), max(float(np.nanmax(v)), 0.5)]
    ax.plot(lim, lim, ls="--", color="black", lw=0.8, label="OOS = IS")
    ax.axhline(0, color=GREY, lw=0.8)
    ax.set_xlabel("in-sample Sharpe of the selected pair")
    ax.set_ylabel("out-of-sample Sharpe of that pair")
    ax.set_title("Selection bias: the IS winner rarely repeats")
    ax.legend(fontsize=7.5)
    ax = axes[1]
    d = ft.groupby("fold")[["is_sharpe", "oos_of_is_best", "oos_oracle", "oos_median"]].mean()
    x = np.arange(len(d))
    for c, lab, cl in zip(["is_sharpe", "oos_of_is_best", "oos_oracle", "oos_median"],
                          ["IS winner (train)", "same pair, OOS", "OOS oracle", "median pair, OOS"],
                          [GREY, BAD, "#4c8bf5", OK]):
        ax.plot(x, d[c], marker="o", ms=4, lw=1.4, color=cl, label=lab)
    ax.set_xticks(x)
    ax.set_xticklabels([f"F{i}" for i in x], fontsize=7.5)
    ax.axhline(0, color="black", lw=0.8)
    ax.set_ylabel("mean Sharpe")
    ax.set_title("Walk-forward, averaged over all markets")
    ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname


def equity_curves(curves: dict[str, pd.Series], fname="fig_equity.png", title="Trend book equity curves"):
    fig, ax = plt.subplots(figsize=(7.6, 3.9))
    for lab, s in curves.items():
        s = s.dropna()
        if s.empty:
            continue
        eq = (1 + s).cumprod()
        ax.plot(eq.index, eq.values, lw=1.3, label=lab)
    ax.set_yscale("log")
    ax.set_title(title)
    ax.set_ylabel("growth of 1 (log scale)")
    ax.legend(fontsize=7.5)
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname


def heat_by_market(tab: pd.DataFrame, pairs: list[tuple[int, int]], fname="fig_heat.png",
                   col: str = "sharpe", title="Median Sharpe by market (robust pairs vs market stars)"):
    """Rows = markets, columns = candidate pairs: where each setting actually works."""
    p = tab.pivot_table(index="asset", columns=["fast", "slow"], values=col, aggfunc="median")
    cols = [(f, s) for f, s in pairs if (f, s) in p.columns]
    M = p[cols].to_numpy(float)
    fig, ax = plt.subplots(figsize=(1.05 * len(cols) + 3.4, 0.135 * M.shape[0] + 1.7))
    # TwoSlopeNorm owns the colour scale; passing vmin/vmax alongside a Normalize
    # instance is a matplotlib error, so the bounds live in the norm only.
    vmax = float(np.nanpercentile(np.abs(M), 95)) if np.isfinite(M).any() else 1.0
    vmax = max(vmax, 1e-6)
    im = ax.imshow(M, aspect="auto", cmap="RdYlGn",
                   norm=TwoSlopeNorm(vmin=-vmax, vcenter=0.0, vmax=vmax))
    ax.set_xticks(range(len(cols)))
    ax.set_xticklabels([f"{f}/{s}" for f, s in cols], rotation=45, ha="right", fontsize=7.5)
    ax.set_yticks(range(M.shape[0]))
    ax.set_yticklabels(p.index, fontsize=6.2)
    ax.set_title(title, fontsize=9.5)
    ax.grid(False)
    cb = fig.colorbar(im, ax=ax, fraction=0.03, pad=0.02)
    cb.set_label(col, fontsize=8)
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname


def scatter_vs_prop(df: pd.DataFrame, x: str, y: str, fname="fig_scatter.png",
                    xlabel="", ylabel="", label=None, title=""):
    fig, ax = plt.subplots(figsize=(5.2, 3.7))
    for lab, d in df.groupby(label) if label else [("all", df)]:
        ax.scatter(d[x], d[y], s=18, alpha=0.8, label=lab, edgecolors="white", linewidths=0.4)
    ax.set_xlabel(xlabel or x)
    ax.set_ylabel(ylabel or y)
    ax.set_title(title)
    if label:
        ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname


def bar_compare(d: pd.DataFrame, col: str, fname="fig_bars.png", title="", sort=True, hline=None):
    fig, ax = plt.subplots(figsize=(6.6, 0.32 * len(d) + 1.4))
    x = d[col].to_numpy(float)
    if sort:
        d = d.iloc[np.argsort(x)]
        x = d[col].to_numpy(float)
    ax.barh(np.arange(len(d)), x, color=np.where(x >= 0, OK, BAD), height=0.72)
    ax.set_yticks(np.arange(len(d)))
    ax.set_yticklabels(d["label"].to_numpy(), fontsize=8)
    if hline is not None:
        ax.axvline(hline, color="black", ls="--", lw=0.9)
    ax.axvline(0, color="black", lw=0.8)
    ax.set_title(title)
    ax.set_xlabel(col.replace("_", " "))
    fig.tight_layout()
    fig.savefig(fname, bbox_inches="tight")
    plt.close(fig)
    return fname

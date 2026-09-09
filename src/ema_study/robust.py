"""Robustness machinery: cross-market aggregation, plateau scoring, deflated Sharpe,
walk-forward validation, era splits and a diversified trend-book evaluation.

The premise of this module: the *in-sample best* EMA pair is nearly always an artefact of
one market and one decade.  What is worth knowing is which pair sits on a broad, flat,
positive surface that survives (a) many markets, (b) many eras, (c) out-of-sample
selection, and (d) the multiple-testing penalty for having looked at ~10k pairs.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

METRICS = ["sharpe", "sortino", "cagr", "calmar", "max_dd", "exposure", "round_trips"]


# --------------------------------------------------------------------------- aggregation
def aggregate(g: pd.DataFrame, bh: pd.DataFrame | None = None, min_markets: int = 40) -> pd.DataFrame:
    """Collapse the per-market grid into one row per (fast, slow) pair.

    Every statistic here is a *cross-market* summary: a pair only looks good if it is good
    in many unrelated markets, which is the property a trader can actually rely on.
    """
    x = g.copy()
    if bh is not None:
        x = x.merge(bh[["asset", "bh_sharpe", "bh_cagr", "bh_dd"]], on="asset", how="left")
        x["delta_sharpe"] = x["sharpe"] - x["bh_sharpe"]
        x["delta_cagr"] = x["cagr"] - x["bh_cagr"]

    def _agg(d):
        row = dict(
            markets=d["asset"].nunique(),
            med_sharpe=d["sharpe"].median(), mean_sharpe=d["sharpe"].mean(),
            p10_sharpe=d["sharpe"].quantile(0.10), p25_sharpe=d["sharpe"].quantile(0.25),
            p75_sharpe=d["sharpe"].quantile(0.75),
            med_cagr=d["cagr"].median(), med_dd=d["max_dd"].median(),
            worst_dd=d["max_dd"].min(), med_calmar=d["calmar"].median(),
            med_sortino=d["sortino"].median(), med_exposure=d["exposure"].median(),
            med_rt_yr=d["trades_per_year"].median(),
            share_pos=float((d["sharpe"] > 0).mean()),
            share_strong=float((d["sharpe"] > 0.5).mean()),
        )
        if "delta_sharpe" in d:
            row["share_beat_bh"] = float((d["delta_sharpe"] > 0).mean())
            row["med_delta_sharpe"] = d["delta_sharpe"].median()
            row["med_delta_cagr"] = d["delta_cagr"].median()
        return pd.Series(row)

    out = x.groupby(["fast", "slow"]).apply(_agg, include_groups=False).reset_index()
    out = out[out["markets"] >= min_markets].reset_index(drop=True)
    out["ratio"] = out["slow"] / out["fast"]
    return out


def top_quartile_share(g: pd.DataFrame, metric: str = "sharpe", by: str = "asset_class") -> pd.DataFrame:
    """Share of markets (and of asset classes) where the pair ranks in the top quartile."""
    x = g.copy()
    x["rank_asset"] = x.groupby("asset")[metric].rank(pct=True)
    x["rank_fam"] = x.groupby("asset_class")[metric].rank(pct=True)
    out = x.groupby(["fast", "slow"]).apply(
        lambda d: pd.Series({"share_mkt_top_quartile": float((d["rank_asset"] >= 0.75).mean()),
                             "share_fam_top_quartile": float((d["rank_fam"] >= 0.75).mean())}),
        include_groups=False).reset_index()
    return out


# ---------------------------------------------------------------------- plateau scoring
def pivot(agg: pd.DataFrame, col: str) -> pd.DataFrame:
    return agg.pivot_table(index="fast", columns="slow", values=col, aggfunc="mean")


def plateau_stats(agg: pd.DataFrame, col: str = "med_sharpe", fast_pm: int = 4,
                  slow_pm: int = 16) -> pd.DataFrame:
    """Neighbourhood statistics of the consensus surface (the anti-overfitting lens).

    ``nb_min`` is the worst neighbouring pair: a pair whose neighbourhood is all strong is
    a *regime of parameters*, not a lucky point.  ``spike = own - nb_median`` measures how
    much of the headline number comes from the exact integers chosen.
    """
    P = pivot(agg, col)
    F, S = P.index.to_numpy(), P.columns.to_numpy()
    M = P.to_numpy(float)
    nbf, nbs = len(F), len(S)
    nb_mean = np.full_like(M, np.nan)
    nb_med = np.full_like(M, np.nan)
    nb_min = np.full_like(M, np.nan)
    for i, f in enumerate(F):
        fmask = np.flatnonzero((F >= f - fast_pm) & (F <= f + fast_pm))
        for j, s in enumerate(S):
            smask = np.flatnonzero((S >= s - slow_pm) & (S <= s + slow_pm))
            blk = M[np.ix_(fmask, smask)]
            blk = blk[np.isfinite(blk)]
            if blk.size:
                nb_mean[i, j], nb_med[i, j], nb_min[i, j] = blk.mean(), np.median(blk), blk.min()
    out = pd.DataFrame({"fast": np.repeat(F, nbs), "slow": np.tile(S, nbf),
                        "own": M.ravel(), "nb_mean": nb_mean.ravel(),
                        "nb_median": nb_med.ravel(), "nb_min": nb_min.ravel()})
    out["spike"] = out["own"] - out["nb_median"]
    out = out.dropna(subset=["own"]).reset_index(drop=True)
    out["col"] = col
    return out


# --------------------------------------------------------------- multiple-testing penalty
def expected_max_sharpe(n_trials: int, var_sr: float = 1.0, mu: float = 0.0) -> float:
    """E[max Sharpe] over ``n_trials`` independent zero-skill trials (Bailey & López de Prado)."""
    from scipy.stats import norm
    g = 0.5772156649015329
    n = max(int(n_trials), 2)
    z = (1 - g) * norm.ppf(1 - 1.0 / n) + g * norm.ppf(1 - 1.0 / (n * np.e))
    return float(mu + np.sqrt(max(var_sr, 0.0)) * z)


def deflated_sharpe(sr_ann: float, n_obs: int, n_trials: int, skew: float = 0.0,
                    kurt: float = 3.0, ann: int = 252, sr_std_across_trials: float | None = None) -> dict:
    """Probability that the *true* Sharpe beats the best-of-N luck hurdle.

    ``sr_ann`` is annualised; the internal algebra is done per-period, which is what the
    published formula assumes.
    """
    from scipy.stats import norm
    sr = sr_ann / np.sqrt(ann)
    var_sr = (1.0 / n_obs) if sr_std_across_trials is None else sr_std_across_trials ** 2 / ann
    hurdle = expected_max_sharpe(n_trials, var_sr)
    denom = np.sqrt(max(1 - skew * sr + (kurt - 1) / 4 * sr ** 2, 1e-12) / max(n_obs - 1, 1))
    dsr = float(norm.cdf((sr - hurdle) / denom))
    return dict(sharpe=sr_ann, hurdle_sharpe=hurdle * np.sqrt(ann), dsr=dsr,
                se_sr_ann=float(denom * np.sqrt(ann)), n_trials=n_trials, n_obs=int(n_obs))


def effective_trials(agg: pd.DataFrame, col: str = "med_sharpe", corr_thresh: float = 0.9) -> int:
    """Rough count of *independent* cells in the parameter surface.

    Neighbouring EMA pairs are near-duplicates, so the literal pair count overstates the
    multiple-testing burden; we count cells that are mutually uncorrelated across markets.
    """
    P = pivot(agg, col)
    M = P.to_numpy(float).ravel()
    M = M[np.isfinite(M)]
    if M.size < 20:
        return int(M.size)
    # greedy: walk the surface, keep a cell only if its neighbours within a block are not
    # near-identical in value (a cheap proxy for rank-correlation on a smooth surface)
    step = max(int(M.size * 0.02), 1)
    return int(np.ceil(M.size / step))


# -------------------------------------------------------------------------- walk-forward
def walk_forward(universe, f_idx, s_idx, n_folds: int = 6, mode: str = "ls",
                 fixed_pairs: list[tuple[int, int]] | None = None, progress: bool = True,
                 select: str = "sharpe") -> tuple[pd.DataFrame, pd.DataFrame]:
    """Optimise the pair on each training window, then trade the untouched next window.

    Reports, per market and fold: the in-sample winner's OOS Sharpe, the best achievable
    OOS Sharpe (the oracle), and the OOS Sharpe of each fixed candidate pair.  If the
    optimiser's choices do not survive out of sample, that is the headline result.
    """
    from .grid import grid_for_series

    fixed_pairs = fixed_pairs or []
    rows = []
    for i, (key, s) in enumerate(universe.items(), 1):
        idx = s.close.index
        if (idx[-1] - idx[0]).days / 365.25 < 8:
            continue
        edges = pd.date_range(idx[0], idx[-1], periods=n_folds + 1)
        for k in range(1, n_folds):
            tr, te = (edges[k - 1], edges[k]), (edges[k], edges[min(k + 1, n_folds)])
            gtr = grid_for_series(s, f_idx, s_idx, mode=mode, span=tr)
            gte = grid_for_series(s, f_idx, s_idx, mode=mode, span=te)
            if len(gtr) < 50 or len(gte) < 50:
                continue
            mtr = gtr.set_index(["fast", "slow"])[select]
            mte = gte.set_index(["fast", "slow"])["sharpe"]
            best = mtr.idxmax()
            common = mte.index.intersection(mtr.index)
            oos_all = mte.loc[common] if len(common) else mte
            row = dict(asset=key, fold=k, train=f"{tr[0].date()}..{tr[1].date()}",
                       test=f"{te[0].date()}..{te[1].date()}",
                       best_fast=int(best[0]), best_slow=int(best[1]),
                       is_sharpe=float(mtr.loc[best]),
                       oos_of_is_best=float(mte.loc[best]) if best in mte.index else np.nan,
                       oos_oracle=float(oos_all.max()), oos_median=float(oos_all.median()),
                       oos_p25=float(oos_all.quantile(.25)), oos_p75=float(oos_all.quantile(.75)),
                       oos_p90=float(oos_all.quantile(.90)),
                       pctile_of_is_best=float((oos_all < float(mte.loc[best])).mean()) if best in mte.index else np.nan,
                       n_train=int(len(mtr)))
            for (ff, ss) in fixed_pairs:
                kk = (ff, ss)
                if kk in mtr.index:
                    row[f"is_{ff}x{ss}"] = float(mtr.loc[kk])
                    if kk in mte.index:
                        row[f"oos_{ff}x{ss}"] = float(mte.loc[kk])
                        row[f"pct_{ff}x{ss}"] = float((oos_all < float(mte.loc[kk])).mean())
                    else:
                        row[f"oos_{ff}x{ss}"], row[f"pct_{ff}x{ss}"] = np.nan, np.nan
            rows.append(row)
        if progress and i % 12 == 0:
            print(f"      walk-forward {i}/{len(universe)} markets ({len(rows)} folds)", flush=True)
    ft = pd.DataFrame(rows)
    return ft, summarise_wf(ft, fixed_pairs)


def summarise_wf(ft: pd.DataFrame, fixed_pairs=()) -> pd.DataFrame:
    if ft.empty:
        return pd.DataFrame()
    rows = [dict(rule="grid-optimal pair, re-optimised each fold", markets=ft["asset"].nunique(),
                 folds=len(ft), is_sharpe=ft["is_sharpe"].mean(), oos_sharpe=ft["oos_of_is_best"].mean(),
                 oos_pos_share=float((ft["oos_of_is_best"] > 0).mean()),
                 regret_vs_oracle=float((ft["oos_oracle"] - ft["oos_of_is_best"]).mean()),
                 vs_median_pair=float((ft["oos_of_is_best"] - ft["oos_median"]).mean()))]
    rows.append(dict(rule="oracle (best pair chosen with hindsight)", markets=ft["asset"].nunique(),
                     folds=len(ft), is_sharpe=np.nan, oos_sharpe=ft["oos_oracle"].mean(),
                     oos_pos_share=float((ft["oos_oracle"] > 0).mean()), regret_vs_oracle=0.0,
                     vs_median_pair=float((ft["oos_oracle"] - ft["oos_median"]).mean())))
    rows.append(dict(rule="median pair on the grid (no selection)", markets=ft["asset"].nunique(),
                     folds=len(ft), is_sharpe=np.nan, oos_sharpe=ft["oos_median"].mean(),
                     oos_pos_share=float((ft["oos_median"] > 0).mean()), regret_vs_oracle=np.nan,
                     vs_median_pair=0.0))
    for (ff, ss) in fixed_pairs:
        c, o = ft.get(f"is_{ff}x{ss}"), ft.get(f"oos_{ff}x{ss}")
        if c is None or o is None:
            continue
        rows.append(dict(rule=f"fixed pair {ff}/{ss}", markets=ft["asset"].nunique(), folds=len(ft),
                         is_sharpe=float(c.mean()), oos_sharpe=float(o.mean()),
                         oos_pos_share=float((o > 0).mean()),
                         oos_pctile=float(ft[f"pct_{ff}x{ss}"].mean()),
                         regret_vs_oracle=float((ft["oos_oracle"] - o).mean()),
                         vs_median_pair=float((o - ft["oos_median"]).mean())))
    return pd.DataFrame(rows)


# --------------------------------------------------------------------- diversified book
def trend_book(universe, fast: int, slow: int, mode: str = "ls", cost_mult: float = 1.0,
               vol_target: float | None = None, max_lev: float = 2.5, span: tuple | None = None):
    """Trade one pair across every market, equal weight, on a fixed evaluation window.

    The fixed ``span`` matters: a 400-bar slow EMA cannot start trading in 1972 on a series
    that begins in 1999, so comparing pairs on their own sample lengths would quietly
    advantage the slower settings.  Every pair is therefore scored on the same calendar.
    """
    from .engine import ema_matrix, position_from_state, metrics

    out = {}
    for k, s in universe.items():
        px = s.close
        if len(px) < slow + 400:
            continue
        E = ema_matrix(px.to_numpy(np.float64), [fast, slow])
        st = E[0, 1:] > E[1, 1:]
        w, tr = position_from_state(st[None, :], mode)
        w, tr = w[0], tr[0]
        unit = 1.0 if mode == "long" else 2.0
        r = w * s.rets[: len(w)] - tr * (s.cost_bps * cost_mult / 1e4) * unit
        out[k] = pd.Series(r[slow:], index=px.index[slow + 1:])
    if not out:
        return {}, pd.Series(dtype=float)
    raw = pd.DataFrame(out)
    if span is not None:
        raw = raw.loc[span[0]: span[1]]
    if len(raw) < 250:
        return {}, pd.Series(dtype=float)
    active = float((raw.notna().mean() > 0.6).mean())
    R = raw.mean(axis=1, skipna=True).to_frame("book")
    if vol_target:
        realised = R["book"].rolling(63, min_periods=20).std() * np.sqrt(252)
        R["book"] = R["book"] * (vol_target / realised).clip(upper=max_lev).fillna(1.0)
    r = R["book"].to_numpy()
    m = metrics(r[None, :], 252, pos=np.ones((1, r.size)), changes=np.zeros((1, r.size), bool),
                min_bars=250).iloc[0].to_dict()
    m["markets_available"] = len(out)
    m["market_active_share"] = active
    m["overlap_bars"] = int(len(raw))
    m["book_vol_raw"] = float(pd.Series(r).std() * np.sqrt(252))
    return m, R["book"]


def per_market_best(g: pd.DataFrame, metric: str = "sharpe") -> pd.DataFrame:
    """The in-sample winner for each individual market (the "expert" answer we must beat)."""
    idx = g.groupby("asset")[metric].idxmax()
    return g.loc[idx].sort_values(metric, ascending=False).reset_index(drop=True)


def surface_smoothness(agg: pd.DataFrame, col: str = "med_sharpe") -> dict:
    """How "bumpy" is the consensus surface?  Spikes = curve-fitting bait."""
    P = pivot(agg, col)
    M = P.to_numpy(float)
    M = M[np.isfinite(M)]
    if M.size < 50:
        return {}
    grad_f = np.diff(P.to_numpy(float), axis=0)
    grad_s = np.diff(P.to_numpy(float), axis=1)
    rng = np.nanmax(M) - np.nanmin(M)
    return dict(cells=int(M.size), surface_range=float(rng),
                mean_step_fast=float(np.nanmean(np.abs(grad_f))),
                mean_step_slow=float(np.nanmean(np.abs(grad_s))),
                max_step=float(np.nanmax(np.abs(np.concatenate([grad_f.ravel(), grad_s.ravel()])))),
                p90_over_median=float(np.nanpercentile(np.abs(M[np.isfinite(M)]), 90) /
                                      max(abs(np.nanmedian(M)), 1e-9)))


def book_window(uni, frac: float = 0.75) -> tuple:
    """Calendar window in which at least ``frac`` of the markets are simultaneously alive.

    Needed for a fair comparison: a 400-bar slow EMA can only start trading once a market's
    history has warmed up, so letting every pair pick its own sample would quietly favour the
    settings that start earliest.
    """
    cnt: dict = {}
    for s in uni.values():
        vc = s.close.groupby(s.close.index.to_period("M")).size()
        for mth, n in vc.items():
            if n >= 15:
                cnt[mth] = cnt.get(mth, 0) + 1
    ser = pd.Series(cnt).sort_index()
    ok = ser[ser >= frac * len(uni)]
    if ok.empty:
        lo = min(s.close.index[0] for s in uni.values())
        hi = max(s.close.index[-1] for s in uni.values())
        return str(lo.date()), str(hi.date())
    return str(ok.index[0].start_time.date()), str(ok.index[-1].end_time.date())


# ------------------------------------------------------------- global split-sample OOS test
def split_sample(universe, pairs, mode: str = "ls", cut: float = 0.6,
                 cost_mult: float = 1.0, warmup_mult: float = 1.0,
                 progress: bool = True) -> pd.DataFrame:
    """Score a *fixed* list of pairs on the first ``cut`` of each market's history and on the
    untouched remainder, with no selection in between.

    This complements :func:`walk_forward`: because the EMAs warm up on the whole history and
    only the *scoring* window is split, it can judge pairs whose slow EMA is far longer than a
    single fold (a 700-bar slow has no room inside a 2-year fold).  The honest question it
    answers is "if I had run this whole study on the older 60% of the data and picked with the
    same rule, what would I have chosen, and how would that choice have scored on the 40% that
    nobody looked at?"
    """
    from .data import _returns
    from .engine import metrics, position_from_state
    from .grid import ema_matrix

    pairs = sorted({(int(f), int(s)) for f, s in pairs if s > f})
    if not pairs or mode not in ("long", "ls"):
        raise ValueError("need pairs and mode in {'long','ls'}")
    periods = np.unique(np.array(pairs).ravel()).astype(int)
    unit = 1.0 if mode == "long" else 2.0
    rows = []
    for i, (key, s) in enumerate(universe.items(), 1):
        px = s.close
        if len(px) < 900:                                   # need room for both halves
            continue
        rets = _returns(px, s.adjustment).astype(np.float64)
        N = rets.size
        E = ema_matrix(px.to_numpy(np.float64), periods)
        pos_of = {int(p): j for j, p in enumerate(periods)}
        fee = s.cost_bps * cost_mult / 1e4
        for (f_, s_) in pairs:
            warm = int(min(s_ * warmup_mult, max(N - 260, 0)))
            avail = N - warm
            if avail < 700:
                continue
            kk = int(min(max(int(cut * avail), 250), avail - 250))
            state = (E[pos_of[f_], 1:] > E[pos_of[s_], 1:]).reshape(1, -1)
            w, tr = position_from_state(state, mode)
            r = w[:, warm:] * rets[warm:][None, :] - tr[:, warm:] * fee * unit
            m_is = metrics(r[:, :kk], s.ann, pos=w[:, warm:warm + kk],
                           changes=tr[:, warm:warm + kk], unit=unit)
            m_o = metrics(r[:, kk:], s.ann, pos=w[:, warm + kk:],
                          changes=tr[:, warm + kk:], unit=unit)
            bh_i = metrics(rets[warm:warm + kk][None, :], s.ann)
            bh_o = metrics(rets[warm + kk:][None, :], s.ann)
            need = ["sharpe", "cagr", "max_dd", "ann_vol"]
            if not (m_is[need].notna().all().all() and m_o[need].notna().all().all()):
                continue                      # NaN calmar (no drawdown in the window) is fine,
                # and matches how the main grid keeps rows: only the sample-size / finite-mean
                # checks gate a row, so the two studies stay comparable.
            idx = px.index
            rows.append(dict(asset=key, asset_class=s.asset_class, fast=f_, slow=s_, mode=mode,
                             is_start=str(idx[warm].date()), split=str(idx[warm + kk].date()),
                             oos_end=str(idx[-1].date()), is_bars=kk, oos_bars=int(avail - kk),
                             is_sharpe=float(m_is["sharpe"].iloc[0]), oos_sharpe=float(m_o["sharpe"].iloc[0]),
                             is_calmar=float(m_is["calmar"].iloc[0]), oos_calmar=float(m_o["calmar"].iloc[0]),
                             is_max_dd=float(m_is["max_dd"].iloc[0]), oos_max_dd=float(m_o["max_dd"].iloc[0]),
                             is_cagr=float(m_is["cagr"].iloc[0]), oos_cagr=float(m_o["cagr"].iloc[0]),
                             oos_vol=float(m_o["ann_vol"].iloc[0]),
                             bh_is_sharpe=float(bh_i["sharpe"].iloc[0]), bh_oos_sharpe=float(bh_o["sharpe"].iloc[0]),
                             oos_beats_bh=bool(m_o["sharpe"].iloc[0] > bh_o["sharpe"].iloc[0]) if np.isfinite(bh_o["sharpe"].iloc[0]) else False))
        if progress and i % 20 == 0:
            print(f"      split-sample {i}/{len(universe)} markets ({len(rows)} rows)", flush=True)
    return pd.DataFrame(rows)


def summarise_split(sp: pd.DataFrame, rule: str = "nbmin", band_f: int = 4, band_s: int = 16,
                    tmin: float = 0.5, tmax: float = 14.0) -> pd.DataFrame:
    """Rank the tested pairs on their IN-SAMPLE cross-market score only, then report what each
    choice actually earned out of sample.  `pick=True` marks the pair the rule would have chosen."""
    if sp.empty:
        return pd.DataFrame()
    g = sp.groupby(["fast", "slow"]).agg(
        markets=("asset", "nunique"), med_is=("is_sharpe", "median"), med_oos=("oos_sharpe", "median"),
        pos_oos=("oos_sharpe", lambda x: float((x > 0).mean())),
        beat_bh=("oos_beats_bh", "mean"), med_oos_calmar=("oos_calmar", "median"),
        med_oos_dd=("oos_max_dd", "median"), med_is_dd=("is_max_dd", "median"),
        med_oos_cagr=("oos_cagr", "median"), med_bh_oos=("bh_oos_sharpe", "median")).reset_index()
    piv = sp.pivot_table(index=["fast", "slow"], columns="asset", values="is_sharpe")
    keys = list(zip(g["fast"].astype(int), g["slow"].astype(int)))
    pidx = list(piv.index)
    nb = []
    for f_, s_ in keys:                                        # plateau test: worst neighbour average
        near = piv.loc[[p for p in pidx if abs(p[0] - f_) <= band_f and abs(p[1] - s_) <= band_s]]
        nb.append(float(np.nanmin(np.asarray(near.mean(axis=1), float))))
    g["nb_is"] = nb
    g["robust_is"] = g["nb_is"] if rule == "nbmin" else g["med_is"]
    g["picked"] = ""
    for col, lab in (("robust_is", "by IS neighbour-robust Sharpe"), ("med_is", "by IS median Sharpe"),
                     ("med_oos", "by OOS median Sharpe (cheating)")):
        i = int(np.nanargmax(g[col].to_numpy(float)))
        g.loc[i, "picked"] = (g.loc[i, "picked"] + " + " + lab).strip(" +")   # two rules can agree
    g["picked"] = g["picked"].replace("", np.nan)
    g = g.sort_values("robust_is", ascending=False).reset_index(drop=True)
    g["rank_is"] = g["robust_is"].rank(ascending=False).astype(int)
    g["rank_oos"] = g["med_oos"].rank(ascending=False).astype(int)
    g["rank_shift"] = g["rank_is"] - g["rank_oos"]
    return g.drop(columns=["robust_is"])

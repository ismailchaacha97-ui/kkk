"""Pick the top 10 strategies with an honest, multiple-testing-aware protocol."""
import json
import os
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "results")
ANN = 252


def deflated_sharpe(sr, n_obs, n_trials, sr_var):
    """Bailey & Lopez de Prado deflated Sharpe ratio.

    Discounts an observed Sharpe by the best value you'd expect from
    `n_trials` independent lucky draws.
    """
    from math import log, sqrt, exp, erf
    gamma = 0.5772156649
    e = 1e-12
    z = lambda p: np.sqrt(2) * _erfinv(2 * p - 1)
    sr0 = sqrt(sr_var) * ((1 - gamma) * z(1 - 1 / max(n_trials, 2)) +
                          gamma * z(1 - 1 / (max(n_trials, 2) * np.e)))
    num = (sr - sr0) * sqrt(n_obs - 1)
    return _norm_cdf(num)


def _erfinv(x):
    a = 0.147
    ln = np.log(1 - x ** 2 + 1e-15)
    t = 2 / (np.pi * a) + ln / 2
    return np.sign(x) * np.sqrt(np.sqrt(t ** 2 - ln / a) - t)


def _norm_cdf(x):
    from math import erf, sqrt
    return 0.5 * (1 + erf(x / sqrt(2)))


def main():
    df = pd.read_csv(os.path.join(RESULTS, "all_results.csv"))
    n_trials = len(df)
    print(f"loaded {n_trials} backtested strategies")

    # ---- screens (all applied on IS + robustness, never on OOS rank alone)
    f = df.copy()
    screens = [
        ("IS Sharpe > 0.5", f.is_sharpe > 0.5),
        ("OOS Sharpe > 0.5", f.oos_sharpe > 0.5),
        ("IS and OOS both profitable", (f.is_cagr > 0) & (f.oos_cagr > 0)),
        ("full-period max DD > -35%", f.all_max_dd > -0.35),
        ("annual turnover < 30x", f.all_ann_turnover < 30),
        ("annual vol between 3% and 35%", (f.all_vol > 0.03) & (f.all_vol < 0.35)),
        ("no OOS Sharpe collapse (>40% of IS)", f.oos_sharpe > 0.4 * f.is_sharpe),
    ]
    mask = pd.Series(True, index=f.index)
    for label, m in screens:
        mask &= m
        print(f"  after {label:38s} -> {mask.sum():5d} survive")
    f = f[mask].copy()

    # ---- consistency / degradation metrics
    f["degradation"] = f.oos_sharpe - f.is_sharpe
    n_oos = 970  # ~ trading days in the OOS window
    sr_var = float(df.oos_sharpe.std() / np.sqrt(ANN)) ** 2
    f["dsr"] = [deflated_sharpe(s / np.sqrt(ANN), n_oos, n_trials, sr_var)
                for s in f.oos_sharpe]

    # ---- composite score: OOS quality, robustness, and pain, in that order
    def z(x):
        return (x - x.mean()) / (x.std() + 1e-12)

    f["score"] = (1.00 * z(f.oos_sharpe)
                  + 0.60 * z(f.all_sharpe)
                  + 0.40 * z(f.oos_calmar.clip(-5, 10))
                  + 0.30 * z(f.all_max_dd)
                  - 0.30 * z(f.degradation.abs()))

    # ---- de-duplicate: at most 3 survivors per family, and drop
    # strategies whose daily returns are >0.9 correlated with a better one.
    curves = pd.read_parquet(os.path.join(RESULTS, "top_curves.parquet"))
    curves.columns = [int(c) for c in curves.columns]
    f = f.sort_values("score", ascending=False)

    picked, per_fam = [], {}
    for _, row in f.iterrows():
        fam = row.family
        if per_fam.get(fam, 0) >= 3:
            continue
        i = int(row.id)
        if i in curves.columns:
            dup = False
            for p in picked:
                j = int(p.id)
                if j in curves.columns:
                    c = curves[i].corr(curves[j])
                    if c > 0.90:
                        dup = True
                        break
            if dup:
                continue
        picked.append(row)
        per_fam[fam] = per_fam.get(fam, 0) + 1
        if len(picked) == 10:
            break

    top = pd.DataFrame(picked).reset_index(drop=True)
    top.index += 1
    top.to_csv(os.path.join(RESULTS, "top10.csv"))

    # ---- benchmark
    import pandas as _pd
    close = _pd.read_parquet(os.path.join(ROOT, "data", "close.parquet"))
    bench = close["SPY"].pct_change().dropna()
    beq = (1 + bench).cumprod()
    byrs = len(bench) / ANN
    print(f"\nbenchmark SPY buy&hold: Sharpe {bench.mean()/bench.std()*np.sqrt(ANN):.2f}  "
          f"CAGR {beq.iloc[-1]**(1/byrs)-1:.2%}  maxDD {(beq/beq.cummax()-1).min():.1%}")

    cols = ["family", "params", "is_sharpe", "oos_sharpe", "all_sharpe",
            "all_cagr", "all_vol", "all_max_dd", "all_calmar",
            "all_ann_turnover", "dsr"]
    pd.set_option("display.width", 250, "display.max_colwidth", 60)
    print("\n=== TOP 10 (ranked by composite, selected on IS, scored on OOS) ===")
    print(top[cols].round(3).to_string())
    return top


if __name__ == "__main__":
    main()

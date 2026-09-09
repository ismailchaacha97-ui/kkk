#!/usr/bin/env python3
"""Apples-to-apples buy & hold reference for the diversified trend book.

analyze.py's trend book drops any market whose history is shorter than ``slow + 400`` bars and
starts every market after its own EMA warm-up, then takes the daily cross-market mean.  The
quick buy & hold line printed there uses *all* markets over *all* dates, which quietly gives the
benchmark a longer sample than the strategy.  This script rebuilds buy & hold on the exact same
market set, the same per-market start dates and the same vol-targeting rule, so "did EMA timing
beat holding?" can be answered honestly.

    python scripts/benchmark_book.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

from ema_study.data import load_universe                                       # noqa: E402
from ema_study.engine import metrics                                            # noqa: E402
from ema_study import robust as RB                                              # noqa: E402

TAB = os.path.join(ROOT, "results", "tables")
VT = 0.10                     # same vol target the report quotes for the strategy book
MAXLEV = 2.5                  # same leverage cap inside trend_book


def target(r: pd.Series, vol_target: float = VT) -> pd.Series:
    realised = r.rolling(63, min_periods=20).std() * np.sqrt(252)
    return r * (vol_target / realised).clip(upper=MAXLEV).fillna(1.0)


def main() -> None:
    os.makedirs(TAB, exist_ok=True)
    uni = load_universe(exclude=("macro", "fx_spot_ctrl"), verbose=False)
    print(f"universe: {len(uni)} markets\n")
    rows = []
    for (f_, s_) in [(58, 160), (60, 130), (50, 136), (40, 116), (50, 200), (12, 26), (32, 384),
                     (150, 710)]:
        for mode in ("long", "ls"):
            m_str, cur = RB.trend_book(uni, f_, s_, mode=mode)
            if not m_str or cur is None or len(cur) < 250:
                continue
            m_vt, cur_vt = RB.trend_book(uni, f_, s_, mode=mode, vol_target=VT)
            # ---- buy & hold on the identical market set and identical per-market start dates
            keep = [k for k, s in uni.items() if len(s.close) >= s_ + 400]
            frame = {}
            for k in keep:
                s = uni[k]
                # rets[i] is the return into close.index[i+1], so the bar that starts after
                # the slow EMA's warm-up is rets[slow] <-> close.index[slow+1] (as in trend_book)
                idx = s.close.index[s_ + 1:]
                frame[k] = pd.Series(np.asarray(s.rets, float)[s_:][: len(idx)], index=idx)
            bh_raw = pd.DataFrame(frame).mean(axis=1, skipna=True)
            bh_vt = target(bh_raw)
            row = dict(pair=f"{f_}/{s_}", mode=mode, markets=len(keep), first=str(bh_raw.index[0].date()),
                       exposure=float((cur != 0).mean()) if mode == "long" else np.nan,
                       st_sharpe=m_str["sharpe"], st_cagr=m_str["cagr"], st_dd=m_str["max_dd"],
                       st_calmar=m_str["calmar"], st_vol=m_str["ann_vol"],
                       bh_sharpe=None, bh_cagr=None, bh_dd=None, bh_calmar=None, bh_vol=None,
                       bhvt_sharpe=None, bhvt_cagr=None, bhvt_dd=None, bhvt_calmar=None,
                       vt_sharpe=m_vt["sharpe"], vt_cagr=m_vt["cagr"], vt_dd=m_vt["max_dd"],
                       vt_calmar=m_vt["calmar"], vt_vol=m_vt["ann_vol"], days=int(len(bh_raw)))
            for pref, ser in (("bh", bh_raw), ("bhvt", bh_vt)):
                mm = metrics(np.asarray(ser, float)[None, :], 252, pos=np.ones((1, ser.size)),
                             changes=np.zeros((1, ser.size), bool), min_bars=250).iloc[0]
                row[f"{pref}_sharpe"] = float(mm["sharpe"])
                row[f"{pref}_cagr"] = float(mm["cagr"])
                row[f"{pref}_dd"] = float(mm["max_dd"])
                row[f"{pref}_calmar"] = float(mm["calmar"])
                row[f"{pref}_vol"] = float(mm["ann_vol"])
            row["sharpe_uplift"] = row["st_sharpe"] - row["bh_sharpe"]
            row["dd_improvement"] = row["st_dd"] - row["bh_dd"]                   # >0 = shallower
            row["vt_dd_improvement"] = row["vt_dd"] - row["bhvt_dd"]
            rows.append(row)
            print(f"  {f_}/{s_} {mode:4s}: book Sharpe {m_str['sharpe']:.2f} vs buy&hold "
                  f"{row['bh_sharpe']:.2f} | MaxDD {m_str['max_dd']:.0%} vs {row['bh_dd']:.0%} | "
                  f"vol-targeted: {m_vt['sharpe']:.2f} vs {row['bhvt_sharpe']:.2f}, "
                  f"DD {m_vt['max_dd']:.0%} vs {row['bhvt_dd']:.0%}")
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(TAB, "bh_reference.csv"), index=False)
    try:
        md = df.round(3).to_markdown(index=False)
    except Exception:                                          # tabulate is optional
        md = "```\n" + df.round(3).to_string(index=False) + "\n```"
    with open(os.path.join(TAB, "bh_reference.md"), "w") as fh:
        fh.write(md + "\n")
    print(f"\nwrote {os.path.join(TAB, 'bh_reference.csv')}")
    cols = ["pair", "mode", "markets", "days", "st_sharpe", "bh_sharpe", "st_dd", "bh_dd",
            "vt_sharpe", "bhvt_sharpe", "vt_dd", "bhvt_dd", "vt_calmar", "bhvt_calmar"]
    print("\n" + df[cols].round(3).to_string(index=False))


if __name__ == "__main__":
    main()

"""Vectorised portfolio backtester with costs, and IS/OOS evaluation."""
import numpy as np
import pandas as pd

COST_BPS = 5.0          # 5 bps per unit of notional traded (commission + slippage)
ANN = 252


def equal_weight(pos):
    """Normalise gross exposure to at most 1x the portfolio."""
    gross = pos.abs().sum(axis=1)
    scale = 1.0 / gross.where(gross > 1.0, 1.0)
    return pos.mul(scale, axis=0)


def run(pos, ret, cost_bps=COST_BPS):
    """pos: target weights known at close of t. Applied to t+1 returns."""
    w = equal_weight(pos).shift(1).fillna(0.0)
    gross_pnl = (w * ret).sum(axis=1)
    turnover = (w - w.shift(1).fillna(0.0)).abs().sum(axis=1)
    cost = turnover * cost_bps / 1e4
    return gross_pnl - cost, turnover


def stats(r, turnover=None):
    r = r.dropna()
    if len(r) < 250 or r.std() == 0:
        return None
    eq = (1 + r).cumprod()
    yrs = len(r) / ANN
    cagr = eq.iloc[-1] ** (1 / yrs) - 1 if eq.iloc[-1] > 0 else -1.0
    vol = r.std() * np.sqrt(ANN)
    sharpe = r.mean() / r.std() * np.sqrt(ANN)
    dn = r[r < 0].std()
    sortino = r.mean() / dn * np.sqrt(ANN) if dn and dn > 0 else np.nan
    dd = (eq / eq.cummax() - 1).min()
    calmar = cagr / abs(dd) if dd < 0 else np.nan
    out = dict(cagr=cagr, vol=vol, sharpe=sharpe, sortino=sortino,
               max_dd=dd, calmar=calmar, hit=(r > 0).mean(),
               total_return=eq.iloc[-1] - 1)
    if turnover is not None:
        out["ann_turnover"] = turnover.mean() * ANN
    return out

"""Vectorised indicators over a (T x N) numpy price matrix, with caching."""
import numpy as np
import pandas as pd


class Cache:
    """Lazily computes and memoises indicator matrices."""

    def __init__(self, panels):
        self.close = panels["Close"]
        self.high = panels["High"]
        self.low = panels["Low"]
        self.open = panels["Open"]
        self.volume = panels["Volume"]
        self._m = {}

    def _get(self, key, fn):
        if key not in self._m:
            self._m[key] = fn()
        return self._m[key]

    # --- basics -------------------------------------------------------
    @property
    def ret(self):
        return self._get("ret", lambda: self.close.pct_change().fillna(0.0))

    def sma(self, n):
        return self._get(("sma", n), lambda: self.close.rolling(n).mean())

    def ema(self, n):
        return self._get(("ema", n), lambda: self.close.ewm(span=n, adjust=False).mean())

    def std(self, n):
        return self._get(("std", n), lambda: self.close.rolling(n).std())

    def vol(self, n):
        """Annualised realised volatility of daily returns."""
        return self._get(("vol", n), lambda: self.ret.rolling(n).std() * np.sqrt(252))

    def mom(self, n):
        return self._get(("mom", n), lambda: self.close / self.close.shift(n) - 1.0)

    def hh(self, n):
        return self._get(("hh", n), lambda: self.high.rolling(n).max())

    def ll(self, n):
        return self._get(("ll", n), lambda: self.low.rolling(n).min())

    def rsi(self, n):
        def f():
            d = self.close.diff()
            up = d.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
            dn = (-d.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
            rs = up / dn.replace(0, np.nan)
            return (100 - 100 / (1 + rs)).fillna(50)
        return self._get(("rsi", n), f)

    def atr(self, n):
        def f():
            pc = self.close.shift(1)
            a = (self.high - self.low).to_numpy()
            b = (self.high - pc).abs().to_numpy()
            c = (self.low - pc).abs().to_numpy()
            tr = pd.DataFrame(np.maximum(a, np.maximum(b, c)),
                              index=self.close.index, columns=self.close.columns)
            return tr.ewm(alpha=1 / n, adjust=False).mean()
        return self._get(("atr", n), f)

    def zscore(self, n):
        def f():
            m = self.sma(n)
            s = self.std(n)
            return (self.close - m) / s.replace(0, np.nan)
        return self._get(("z", n), f)

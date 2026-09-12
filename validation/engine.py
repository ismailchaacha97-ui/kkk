"""Python mirror of the Premium/Discount indicator logic (PremiumDiscount.mq4/.mq5).

This is a 1:1 port of the session / level / zone / alert mathematics used by the
MQL indicators, so the algorithm can be validated offline (unit tests,
no-repaint checks, real-data smoke tests) without a MetaTrader installation.

Bar representation: dict with t (int, epoch seconds UTC), o, h, l, c (floats).

Known deliberate difference vs the MQL code:
  * The MQL code derives the "day boundary" from the broker's D1 candle start
    (iTime(_Symbol, PERIOD_D1, k)); this mirror uses UTC midnight.
"""

from dataclasses import dataclass, field
from typing import List, Optional, Tuple

DAY = 86400

ANCHOR_PREV_DAY = 0   # previous completed daily candle
ANCHOR_CUR_DAY = 1    # current developing daily candle
ANCHOR_ASIA = 2       # most recent completed Asia session

# level fractions of the dealing range (from range low upward)
F_EXT_DISC = -0.5
F_EDGE_BOT = 0.0
F_HALF_DISC = 0.25
F_DEEP_DISC = 0.295
F_EQ = 0.5
F_DEEP_PREM = 0.705
F_HALF_PREM = 0.75
F_EDGE_TOP = 1.0
F_EXT_PREM = 1.5

# alert event types (mirrors the MQL fired-flags)
EV_EQ_TOUCH_DOWN = "eq_touch_down"
EV_EQ_TOUCH_UP = "eq_touch_up"
EV_DEEP_DISC = "deep_disc"
EV_DEEP_PREM = "deep_prem"
EV_EQ_RETEST_PREM = "eq_retest_prem"
EV_EQ_RETEST_DISC = "eq_retest_disc"
EV_OPEN_DEEP_DISC = "open_deep_disc"
EV_OPEN_DEEP_PREM = "open_deep_prem"


@dataclass
class Params:
    anchor_mode: int = ANCHOR_PREV_DAY
    use_open_eq: bool = False
    asia_start: Tuple[int, int] = (0, 0)      # (hour, minute) server time
    asia_end: Tuple[int, int] = (6, 0)
    max_bars: int = 800
    min_range_points: float = 0.0             # 0 -> auto (100 points)
    point: float = 0.01
    alerts_enabled: bool = True
    alert_only_killzones: bool = True
    kz1: Tuple[int, int, int, int] = (7, 0, 10, 0)   # London
    kz2: Tuple[int, int, int, int] = (13, 0, 16, 0)  # New York
    alert_eq_touch: bool = True
    alert_deep: bool = True
    alert_eq_retest: bool = True
    alert_open_deep: bool = True

    def min_range(self) -> float:
        if self.min_range_points > 0:
            return self.min_range_points * self.point
        return 100.0 * self.point  # auto: ~10 pips FX / ~$1 gold


@dataclass
class Session:
    start: int = 0
    end: int = 0
    high: float = 0.0
    low: float = 0.0
    open: float = 0.0
    eq: float = 0.0
    valid: bool = False
    tag: str = ""


@dataclass
class Levels:
    eq: float = 0.0
    top: float = 0.0
    bot: float = 0.0
    deep_prem: float = 0.0
    deep_disc: float = 0.0
    half_prem: float = 0.0
    half_disc: float = 0.0
    ext_prem: float = 0.0
    ext_disc: float = 0.0


# ----------------------------------------------------------------------------
# time helpers (mirror of the MQL TimeInWindow / SecondsToOpen / Asia window)
# ----------------------------------------------------------------------------

def day_start(t: int) -> int:
    return (t // DAY) * DAY


def _window_seconds(fh: int, fm: int, th: int, tm: int) -> int:
    dur = (th * 3600 + tm * 60) - (fh * 3600 + fm * 60)
    if dur <= 0:
        dur += DAY
    return dur


def time_in_window(t: int, fh: int, fm: int, th: int, tm: int) -> bool:
    w_start = day_start(t) + fh * 3600 + fm * 60
    dur = _window_seconds(fh, fm, th, tm)
    if w_start <= t < w_start + dur:
        return True
    if w_start - DAY <= t < w_start - DAY + dur:
        return True
    return False


def seconds_to_open(t: int, fh: int, fm: int) -> int:
    w_start = day_start(t) + fh * 3600 + fm * 60
    secs = w_start - t
    while secs <= 0:
        secs += DAY
    return secs


def asia_window(now: int, p: Params) -> Tuple[int, int]:
    """Most recent COMPLETED Asia session [start, end)."""
    fh, fm = p.asia_start
    th, tm = p.asia_end
    start = day_start(now) + fh * 3600 + fm * 60
    dur = _window_seconds(fh, fm, th, tm)
    end = start + dur
    if end > now:  # today's session is not finished yet -> use yesterday's
        start -= DAY
        end -= DAY
    return start, end


# ----------------------------------------------------------------------------
# session detection (mirror of UpdateSession / CollectRange)
# ----------------------------------------------------------------------------

def scan_range(bars: List[dict], i: int, start: int, end: int, p: Params) -> Optional[Session]:
    """Collect high/low/open of bars with start <= t < end, scanning backwards
    from index i. The scan is time-bounded: it stops at bars older than
    `start - DAY` (mirrors the MQL loop bound), capped by p.max_bars.
    `end == 0` means unbounded (current day)."""
    hi = None
    lo = None
    first_open = None
    count = 0
    j = i
    while j >= 0 and bars[j]["t"] >= start - DAY and i - j < p.max_bars:
        t = bars[j]["t"]
        if t < start:
            break
        if end > 0 and t >= end:
            j -= 1
            continue
        h, l, o = bars[j]["h"], bars[j]["l"], bars[j]["o"]
        hi = h if hi is None else max(hi, h)
        lo = l if lo is None else min(lo, l)
        first_open = o          # deepest bar seen so far == first bar of the window
        count += 1
        j -= 1
    if count == 0 or hi is None or lo is None or hi <= lo:
        return None
    if hi - lo < p.min_range():
        return None
    s = Session(start=start, end=(start + DAY) if end == 0 else end,
                high=hi, low=lo, open=first_open)
    s.eq = s.open if p.use_open_eq else (hi + lo) / 2.0
    s.valid = True
    return s



def compute_session(bars: List[dict], i: int, p: Params) -> Optional[Session]:
    if i < 1:
        return None
    now = bars[i]["t"]

    if p.anchor_mode == ANCHOR_ASIA:
        base = now
        for _ in range(7):                      # weekend/holiday fallback chain
            start, end = asia_window(base, p)
            s = scan_range(bars, i, start, end, p)
            if s is not None:
                s.tag = "ASIA"
                return s
            base -= DAY
        # fall through to previous-day chain

    # daily-candle chain: today's D1 bar (CUR_DAY) then up to 3 previous D1 bars
    k0 = 0 if p.anchor_mode == ANCHOR_CUR_DAY else 1
    d_now = day_start(now)
    for k in range(k0, 4):
        start = d_now - k * DAY
        end = d_now - (k - 1) * DAY
        s = scan_range(bars, i, start, end, p)
        if s is not None:
            s.tag = "CUR DAY" if k == 0 else "PREV DAY"
            return s
    return None


# ----------------------------------------------------------------------------
# levels & zone math (mirror of CalcLevels / DescribeZone)
# ----------------------------------------------------------------------------

def calc_levels(s: Session) -> Levels:
    r = s.high - s.low
    lv = Levels()
    lv.top = s.high
    lv.bot = s.low
    lv.eq = s.eq
    lv.deep_prem = s.low + F_DEEP_PREM * r
    lv.deep_disc = s.low + F_DEEP_DISC * r
    lv.half_prem = s.low + F_HALF_PREM * r
    lv.half_disc = s.low + F_HALF_DISC * r
    lv.ext_prem = s.low + F_EXT_PREM * r
    lv.ext_disc = s.low + F_EXT_DISC * r
    return lv


def zone_of(price: float, lv: Levels):
    """Return (side, percent, is_deep). side in {'premium','discount','eq'}."""
    if price > lv.eq:
        pct = (price - lv.eq) / (lv.top - lv.eq) * 100.0
        return ("premium", pct, price >= lv.deep_prem)
    if price < lv.eq:
        pct = (lv.eq - price) / (lv.eq - lv.bot) * 100.0
        return ("discount", pct, price <= lv.deep_disc)
    return ("eq", 0.0, False)


# ----------------------------------------------------------------------------
# bar-close alert engine (mirror of ProcessBarClose) - fires once per
# (session, type); events depend only on closed bars -> no repaint.
# ----------------------------------------------------------------------------

class AlertEngine:
    def __init__(self, p: Params, symbol: str = "XAUUSD", tf: str = "M5"):
        self.p = p
        self.symbol = symbol
        self.tf = tf
        self.fired = {}
        self.visited_deep_prem = {}
        self.visited_deep_disc = {}
        self.processed = {}
        self.events = []   # list of (bar_time, type, text)

    def reset_session(self, key: int):
        self.visited_deep_prem[key] = False
        self.visited_deep_disc[key] = False
        self.processed[key] = 0

    def _fire(self, key: int, ev: str, t: int, text: str):
        if (key, ev) not in self.fired:
            self.fired[(key, ev)] = True
            self.events.append((t, ev, text))

    def _kz_open(self, now: int) -> bool:
        p = self.p
        return (time_in_window(now, *p.kz1) or time_in_window(now, *p.kz2))

    def process(self, bars: List[dict], i: int, sess: Optional[Session], now: int) -> List[Tuple[int, str, str]]:
        """Called when bar `i` opens (i.e. bar i-1 just closed)."""
        p = self.p
        if sess is None or not sess.valid or not p.alerts_enabled or i < 2:
            return []
        closed, prev = bars[i - 1], bars[i - 2]
        if closed["t"] < sess.start:          # bar closed before session began
            return []
        key = sess.start
        if key not in self.processed:
            self.reset_session(key)
        self.processed[key] += 1

        lv = calc_levels(sess)
        c, pc = closed["c"], prev["c"]
        r = sess.high - sess.low
        out = []

        # --- update visited-deep state from the closed bar (always) ---
        if c >= lv.deep_prem:
            self.visited_deep_prem[key] = True
        if c <= lv.deep_disc:
            self.visited_deep_disc[key] = True

        kz = not p.alert_only_killzones or self._kz_open(now)
        f = lambda d: f"{d:.{5}f}"

        # --- EQ touch (entered premium / discount) ---
        if kz and p.alert_eq_touch:
            if c < lv.eq <= pc:
                self._fire(key, EV_EQ_TOUCH_DOWN, closed["t"],
                           f"{self.symbol} {self.tf}: price entered DISCOUNT - BUY AREA "
                           f"({f(c)} below EQ {f(lv.eq)}, target EQ)")
                out = self.events[-1:] + out
            if c > lv.eq >= pc:
                self._fire(key, EV_EQ_TOUCH_UP, closed["t"],
                           f"{self.symbol} {self.tf}: price entered PREMIUM - SELL AREA "
                           f"({f(c)} above EQ {f(lv.eq)}, target EQ)")
                out = self.events[-1:] + out

        # --- deep levels ---
        if kz and p.alert_deep:
            if c <= lv.deep_disc < pc:
                self._fire(key, EV_DEEP_DISC, closed["t"],
                           f"{self.symbol} {self.tf}: DEEP DISCOUNT - price {f(c)} at/below "
                           f"29.5% level {f(lv.deep_disc)} - bargain buy zone")
                out = self.events[-1:] + out
            if c >= lv.deep_prem > pc:
                self._fire(key, EV_DEEP_PREM, closed["t"],
                           f"{self.symbol} {self.tf}: DEEP PREMIUM - price {f(c)} at/above "
                           f"70.5% level {f(lv.deep_prem)} - sell zone")
                out = self.events[-1:] + out

        # --- EQ retest after a deep excursion (profit-target / reversal area) ---
        if kz and p.alert_eq_retest and abs(c - lv.eq) <= 0.05 * r:
            if self.visited_deep_prem.get(key):
                self._fire(key, EV_EQ_RETEST_PREM, closed["t"],
                           f"{self.symbol} {self.tf}: returned to EQ {f(lv.eq)} from deep premium "
                           f"- take-profit / reversal area")
                out = self.events[-1:] + out
            if self.visited_deep_disc.get(key):
                self._fire(key, EV_EQ_RETEST_DISC, closed["t"],
                           f"{self.symbol} {self.tf}: returned to EQ {f(lv.eq)} from deep discount "
                           f"- take-profit / reversal area")
                out = self.events[-1:] + out

        # --- session opened deep in a zone ---
        if kz and p.alert_open_deep and self.processed[key] == 1:
            if c <= lv.deep_disc:
                self._fire(key, EV_OPEN_DEEP_DISC, closed["t"],
                           f"{self.symbol} {self.tf}: session opened in DEEP DISCOUNT ({f(c)})")
                out = self.events[-1:] + out
            if c >= lv.deep_prem:
                self._fire(key, EV_OPEN_DEEP_PREM, closed["t"],
                           f"{self.symbol} {self.tf}: session opened in DEEP PREMIUM ({f(c)})")
                out = self.events[-1:] + out

        return out

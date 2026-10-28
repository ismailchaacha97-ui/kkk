# Strategy specification — Liquidity-Sweep Reversal (H1)

This document specifies the exact rules the Expert Advisor and the Python
reference engine implement. Both implementations are intended to be read side by
side: `EA/LiquiditySweep_Portfolio.mq4` and `backtest/features.py` +
`backtest/engine.py`.

---

## 1. Idea

Breakout traders and stop-losses cluster at prices everyone can see: yesterday's
high and low, last week's high and low, and the confirmed swing highs/lows of the
recent past. When price is pushed through such a level and then **closes back
inside the old range**, the breakout has failed: the orders that were triggered
above the level are now trapped, and the market maker side that filled them has
an incentive (and the inventory) to push price back.

The EA trades that failure. Two mirrored setups:

| Setup | Condition | Direction |
|---|---|---|
| **Failed breakout above resistance** | bar 1 trades above a resistance level **and closes below it** | SHORT |
| **Failed breakdown below support** | bar 1 trades below a support level **and closes above it** | LONG |

Everything is evaluated on the close of a finished H1 bar and filled with a
market order on the next tick (the EA acts on the first tick of the new bar).
There is no intrabar decision making, so there is no repainting and no need for
tick data to reproduce the backtest.

---

## 2. Levels (liquidity pools)

A level is a *candidate* if it is one of:

1. **PDH / PDL** — previous day's high / low (broker server day, i.e. MT4
   `iHigh(_Symbol, PERIOD_D1, 1)`).
2. **PWH / PWL** — previous week's high / low (`PERIOD_W1`, shift 1).
3. **Swing high / low** — a pivot confirmed by `k` bars on each side:
   `High[j] >= max(High[j-1..j-k])` and `High[j] >= max(High[j+1..j+k])`.
   Because the pivot needs `k` bars to its right, it becomes usable only at bar
   `j-k`. The engine keeps the **two most recent** confirmed pivots of each kind.

`k = 3` in the validated preset (the EA input is `InpPivotK`, the search grid
compared `k = 2` and `k = 3`; `k = 3` was better in both the in-sample and the
stress window). `level_mode = 1` means *any* of these levels can
trigger a signal; `level_mode = 0` restricts signals to the single most extreme
level (the highest resistance / lowest support among the candidates).

### Cooldown

A level only produces a signal on its **first** raid: if any of the previous
`level_cooldown` bars (default 12) already traded through it, the level is
skipped. Without this the EA would re-enter the same failed level repeatedly
while price oscillates around it.

---

## 3. Entry conditions

For a **short** on bar 1 (the last closed bar):

```
High[1] > L  and  Close[1] < L           # raid + rejection, L = triggering resistance
Close[1] in the bottom (1 - close_frac) of the bar's range
Range[1] >= min_range_atr * ATR(14)     # the bar must be a real rejection, not noise
|High[1] - L| <= max_penetration * ATR  # shallow raid = stop hunt; deep raid = real breakout
ATR(14) > 0, session filter, day filter
(structure filter)  not (last two pivots are higher-highs and higher-lows)
(volume filter)     Volume[1] >= vol_mult * median(Volume[1..50])
```

and mirrored for a **long** using `Low[1]`, `PDL/PWL`, swing lows and the top
`close_frac` of the range.

* `close_frac = 0.45` means the close must be within the extreme 45% of the bar
  (top 45% for longs, bottom 45% for shorts).
* `max_penetration = 0.25` ATR. **This was the single most valuable filter:**
  raids that go far beyond the level have a completely different (negative)
  expectancy from shallow ones — see `docs/VALIDATION.md`.
* The **structure filter** (`require_htf_trend = 1`, EA input
  `InpRequireStructure`) blocks shorts while the last two confirmed swing highs
  and lows are both rising, and blocks longs while both are falling. It was
  adopted for *risk* reasons: it lowers drawdown in every validation window
  while costing ~10% of the trades.
* Tick volume is **not** used as a hard filter in the validated configuration
  (it tested worse on this broker feed, and tick volume is broker-specific), but
  it is (a) available as an input, and (b) always part of the cross-symbol
  candidate **ranking** described below.

### Session

UTC hours 07:00–17:59 (input `InpSessionStartUTC=7`, `InpSessionEndUTC=18`),
Monday–Friday. The EA converts server time to UTC with `InpGMTOffsetHours`.

### Candidate ranking (portfolio layer)

All symbols are evaluated on the same H1 clock. If more setups fire than there
are free position slots, they are ranked by

```
score = 1.00 * min(penetration / ATR, 3)
      + 0.35 * min(tick_volume / median_volume, 4)
      + 0.50 * close_position_in_bar
```

and filled best-first. This is a deterministic rule that both implementations
compute identically; it is the only place volume influences the decision in the
validated preset.

---

## 4. Orders, stops, targets

* **Entry**: market order at the open of the bar after the signal.
* **Stop**: beyond the sweep extreme —
  `SL = Low[1] - sl_atr_buffer * ATR` for longs,
  `SL = High[1] + sl_atr_buffer * ATR` for shorts (`sl_atr_buffer = 0.30`).
* **Stop-distance sanity**: the distance from the signal close to the stop must
  be between `min_sl_atr = 0.55` and `max_sl_atr = 3.20` ATR; otherwise the
  signal is discarded (too tight = noise stop, too wide = bad risk geometry).
* **Target**: `TP = Entry ± rr * (Entry - SL)` with `rr = 2.0`.
* **Break-even**: when the trade is `be_at_r = 0.9R` in profit at a bar close,
  the stop moves to the entry price.
* **Trail**: chandelier `SL = High - trail_atr * ATR` (shorts mirrored) with
  `trail_atr = 2.0`, evaluated at bar close. The stop never moves against the
  position.
* **Time stop**: close at market after `max_hold_bars = 48` H1 bars.
* **Weekend**: EA positions are closed after 20:00 UTC on Friday.

> MT4 detail: the broker's stop level (`MODE_STOPLEVEL`) is respected when the
> order is sent; if the broker rejects the stop it is widened to the minimum
> distance and the order is re-sent naked, then modified.

---

## 5. Risk model

| Control | Value (standard preset) | Where |
|---|---|---|
| Risk per trade | 0.25% standard / 0.20% in the reports | `InpRiskPercent` |
| Max concurrent positions | 3 (portfolio) | `InpMaxPositions` |
| Max entries per symbol per day | 2 | `InpMaxSignalsPerDay` |
| One position per symbol | always | — |
| Daily soft stop | −1.5% (no new trades) | `InpDailyStopPct` |
| Daily hard stop | −2.5% (flatten all) | `InpDailyHardStopPct` |
| Weekly stop | off by default | `InpWeeklyStopPct` |
| Margin guard | ≤20% of equity per position | `InpMaxMarginUsePct` |
| Spread guard | 2.0 pips FX / 5.0 pips metals | `InpMaxSpreadPips*` |

Position size:

```
lots = (equity * risk_pct / 100) / (|entry - stop| * value_of_1_price_unit)
```

where `value_of_1_price_unit = MODE_TICKVALUE / MODE_TICKSIZE` from the broker,
which handles 5-digit FX, 3-digit JPY pairs and metals automatically. Lots are
floored to the broker lot step (never rounded up) and skipped if the result is
below the minimum lot — the EA refuses to take more risk than configured.

---

## 6. Why these inputs are "leading" rather than lagging

* No moving average, RSI, MACD or other backward-looking smoother creates a
  signal. The only smoothed quantity, ATR, is used **exclusively for sizing and
  stop placement**, never for direction.
* The information used is *positional*: where price is relative to levels where
  other participants' orders must be, what the last bar's rejection looked like,
  and whether the market's own structure (sequence of confirmed pivots) agrees.
* The setup is a **failed auction**, i.e. it trades the moment a price movement
  is rejected, not after a trend has been confirmed.

---

## 7. Known weaknesses

* Frequency is low: ~0.3–0.5 trades per day across five symbols, i.e. roughly
  one trade every two days. That caps the achievable return per unit of risk.
* The edge depends on the level being visible to many participants; when markets
  become quieter (2023+) the rejection moves become smaller and the spread eats
  a larger share of the move.
* Shorts pay the spread on exit (they are bought back at Ask), which the engine
  models explicitly; on a wide retail account shorts can be structurally
  unprofitable.
* The out-of-sample period shows no surviving edge. See `docs/VALIDATION.md`.

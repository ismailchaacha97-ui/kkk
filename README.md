# Sessions Only — MT4 Indicator

A single-purpose MetaTrader 4 indicator that draws the **Forex trading sessions**
(Sydney / Tokyo / London / New York) on your chart as high-low range boxes.
No signals, no arrows, no extra clutter — sessions only.

**File:** [`MQL4/Indicators/SessionsOnly.mq4`](MQL4/Indicators/SessionsOnly.mq4)

---

## Features

- **4 configurable sessions** — name, start/end time, colour, and on/off switch each.
- **GMT or broker time input** — enter session times however you think about them.
- **Automatic broker GMT offset detection**, so the boxes stay correct no matter
  which server your broker runs (GMT+2, GMT+3, GMT-5 …).
- **DST handling** with real Europe / US / Australia rules, so London stays
  08:00–17:00 *London time* all year instead of drifting an hour in summer.
- **Range box per session per day** built from the actual bar highs and lows.
- **Labels** with the session name and the range size in pips.
- **Optional vertical lines** at session open and close.
- **Live info panel** showing which sessions are open and a countdown to the
  next open/close.
- **Optional alerts** (popup / push) when a session opens or closes.
- Cleans up all of its own chart objects on removal.

---

## Installation

1. In MetaTrader 4 choose **File → Open Data Folder**.
2. Copy `SessionsOnly.mq4` into `MQL4/Indicators/`.
3. Back in the terminal, right-click **Indicators** in the Navigator and pick
   **Refresh** (or restart MT4).
4. Open MetaEditor, press **F7** to compile (or just drag the indicator onto a
   chart — MT4 compiles it on demand).
5. Drag **SessionsOnly** onto any chart from M1 up to H4.

> Boxes are drawn from bar highs and lows, so they only make sense on intraday
> timeframes. Above the `Draw only on TF <=` setting (default H4) the indicator
> stays idle and shows a short notice instead of drawing nonsense.

---

## Settings

### General

| Setting | Default | What it does |
|---|---|---|
| Days of history to draw | `10` | How many days back to draw sessions. |
| Session times are given in | `GMT` | Whether your times below are GMT/UTC or broker time. |
| Broker GMT offset mode | `Auto` | Auto-detects the broker's offset from `TimeGMT()`. |
| Manual broker GMT offset | `3.0` | Used when the mode is Manual, or as a fallback. |
| Skip Saturday / Sunday | `on` / `off` | Hide weekend sessions. |
| Draw only on TF <= | `H4` | Timeframe ceiling. |

### Boxes, labels, lines

Toggle fill, border style/width, whether boxes sit behind price, label position
(above / inside / below the box), font, size, and the pip-range suffix.
Open/close vertical lines are off by default.

### Info panel

A small live readout in a chart corner:

```
SESSIONS   srv 14:32  gmt 11:32  (GMT+3.0)
Sydney    closed 06:28  21:00-06:00
Tokyo     closed 09:28  00:00-09:00
London    OPEN   02:28  08:00-17:00
New York  closed 01:28  13:00-22:00
```

The time next to an open session counts down to its **close**; next to a closed
one it counts down to its next **open**.

### Alerts

Off by default. Enable `Alert on session open` / `close`, and pick popup and/or
push notification.

### Session defaults

Times are the standard (winter) GMT values — DST is applied automatically by the
rule in the last column.

| # | Name | Start | End | DST rule |
|---|---|---|---|---|
| 1 | Sydney | 21:00 | 06:00 | Australia |
| 2 | Tokyo | 00:00 | 09:00 | None |
| 3 | London | 08:00 | 17:00 | Europe |
| 4 | New York | 13:00 | 22:00 | United States |

A session whose end time is less than or equal to its start time is treated as
crossing midnight (that is how Sydney's 21:00 → 06:00 works).

---

## How the time handling works

Getting sessions to line up is the whole problem this indicator solves, so it is
worth being explicit:

1. You enter session times as **standard-time GMT** values.
2. The indicator asks the terminal for the **broker's GMT offset**
   (`TimeCurrent() - TimeGMT()`, snapped to the nearest half hour) so it knows
   where GMT sits on your chart's clock.
3. For each day it evaluates that market's **DST rule**. While a market is on
   summer time its local session falls one hour *earlier* in GMT — London's
   08:00 BST is 07:00 GMT — so the window shifts accordingly.
4. The resulting server-time window is used to scan bars for the session high
   and low.

DST switch dates are computed, not hardcoded, using the real rules:

- **Europe** — last Sunday of March → last Sunday of October
- **United States** — 2nd Sunday of March → 1st Sunday of November
- **Australia** — 1st Sunday of October → 1st Sunday of April

If your broker's clock is unusual and auto-detection misfires, switch
**Broker GMT offset mode** to `Manual` and set the value yourself, or set
**Session times are given in** to `Server` and enter the times exactly as you
see them on the chart — that path skips offset and DST math entirely.

---

## Notes

- The indicator only creates objects prefixed `SessOnly_` and removes exactly
  those on deinit, so it will not touch your own drawings.
- The currently running session's box extends with each new bar.
- Compiled `.ex4` files are gitignored.

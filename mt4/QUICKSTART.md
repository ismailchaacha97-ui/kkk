# Quick start — Apex Confluence Pro

Five minutes from download to a working chart.

## 1. Install

1. In MT4: **File → Open Data Folder**
2. Copy `indicators/ApexConfluencePro.mq4` → `MQL4/Indicators/`
3. *(optional)* Copy the files from `presets/` → `MQL4/Presets/`
4. In MT4: right-click **Navigator → Indicators → Refresh**
5. Drag **ApexConfluencePro** onto a chart

If the indicator does not appear, open **MetaEditor** (F4), open the file and
press **F7** to compile; the Errors tab will tell you if anything is wrong.

## 2. Choose your profile

| You trade | Chart | Profile |
|---|---|---|
| Seconds–minutes, many trades | M1 / M5 | Scalping (M1-M5) |
| Intraday, 2–5 trades | M5 / M15 / M30 | Day trading (M5-M30) |
| Days–weeks | H1 / H4 | Swing (H1-H4) |

Leave `InpMinScore = 10` to start.

## 3. Set the clock

Sessions and news windows use **broker server time**. Check the clock in the
Market Watch window, then set:

* `InpSessionMode = London + New York` for scalping
* `InpLondonStart/End`, `InpNYStart/End` if your broker is not on GMT+2/+3
* `InpBlackout1 = "14:30-15:30"` for the US data window, if you want

## 4. Read the panel

```
SIGNAL   BUY  11/15     ← what (or NO SETUP / NO TRADE)
STATUS   ACTIVE (bar 1/5) ← if it is still valid
> ACTION: BUY valid at zone  ← what to do
```

* **Green accent + BUY/SELL** → a qualified setup exists.
* **Orange accent + AVOID ...** → a filter is blocking. Do not trade.
* **Grey + NO SETUP** → nothing to do.

The reasons under the score tell you *why* the setup qualified (rejection,
sweep, volume, HTF trend…).

## 5. Place the trade

The chart already shows:

* **Gold line** — entry
* **Red dotted** — stop
* **Green dotted** — TP1 / TP2

Enter at the signal bar close or on a 50 % retracement. Move to break-even at
TP1. If the panel says `INVALIDATED`, the idea is dead.

## 6. Tune it

| Want | Do |
|---|---|
| Fewer signals | `InpMinScore` 11 or 12 |
| More signals | `InpMinScore` 9 |
| Only my session | `InpSessionMode` + the hour inputs |
| No arrows during news | `InpBlackout1/2` |
| Cleaner chart | `InpMaxZonesShown = 3`, `InpShowWeeklyLevels = false` |
| No panel | `InpShowPanel = false` |

## 7. Alerts

`InpAlertPopup` is on by default. For phone alerts set `InpAlertPush = true`
(requires your MetaQuotes ID in **Tools → Options → Notifications**).

**Do not enable `InpAlertIntrabar` until you understand it** — it also fires on
the unfinished candle, so it can flicker. It is a preview, not a signal.

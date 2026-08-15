# Origin of the Move (OFM) — "Failed Squeeze Refill"

Pine Script **v6** indicator: `OFM_Failed_Squeeze_Refill.pine`

An order-flow scalping model that approximates footprint concepts (aggression, absorption,
high-volume nodes, trapped traders) using **Volume Delta**, **wick rejection** and **HVN** logic.

## Logic

| Stage | Name | Rule |
|---|---|---|
| 1 | **Aggression + Absorption** | `volume >= volMult * SMA(volume)` **and** the candle is a high-volume node **and** a long rejection wick (>= `wickPct` of range) **and** the close is trapped on the far side (`closePct`) **and** delta pushes into the wick (`delta > 0` for an upper wick). The wick extreme is the **Squeeze Catalyst**. |
| 2 | **Squeeze Failure** | Within `failWindow` bars price must break the **opposite** extreme of the catalyst candle ("punch to the wall"). Aggressors are now trapped. |
| 3 | **Refill Zone** | A `box.new` is drawn from the catalyst's wick/body (the *Origin of the Move*) and extended right. Red = supply (trapped buyers), Green = demand (trapped sellers). |
| 4 | **Refill Entry** | Price retraces into the zone (touch proximal / close inside / reach 50%) → **BUY** or **SELL** label + `alertcondition` + `alert()`. The box is deleted once mitigated, or if a close fully breaks it. |

## Volume Delta

* **LTF mode (default)** — `request.security_lower_tf()` sums intrabar volume signed by each
  intrabar's close-vs-open, the closest available proxy to real bid/ask delta.
* **Fallback proxy** — `volume * ((close-low) - (high-close)) / range`, used automatically when
  lower-timeframe data is unavailable (e.g. deep history / non-intraday charts).

## Key inputs

`Volume Multiplier`, `Delta Surge Multiplier`, `Min Rejection Wick %`, `Max Close Position %`,
`HVN Lookback`, `Max Bars to Confirm Failure`, `Zone Anatomy`, `Refill Trigger`,
`Delete Zone After Test`, `Max Live Zones`, colours.

## Install

Copy the contents of `OFM_Failed_Squeeze_Refill.pine` into TradingView → Pine Editor → Save → Add to chart.
Best used on liquid intraday charts (1m–15m) where lower-timeframe delta is available.

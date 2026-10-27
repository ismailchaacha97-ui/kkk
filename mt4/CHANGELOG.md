# Changelog — Apex Confluence Pro

## 1.00 — initial release

### Engine
* Forward-only confluence engine: confirmed swing pivots, support/resistance
  zones with role flipping (broken resistance becomes support), BOS / CHoCH
  structure tracking, tick-volume expansion vs. rolling median, 5-bar delta
  proxy, fair value gaps, liquidity sweeps, Kaufman efficiency ratio and
  higher-timeframe structure bias.
* 15-point weighting model with a mandatory structural trigger on top of the
  score.
* Hard gates: minimum score, chop filter, volatility floor, session filter,
  news blackout, spread cap, reward-to-risk check.
* Entry / stop / TP1 / TP2 construction from the signal bar and the next
  opposing zone, with an ATR floor on the stop.
* Non-repainting: signals only on closed bars; forward-applied cooldown so a
  printed arrow is never removed.

### Interface
* 18-row dashboard: structure, HTF bias, signal, score meter, trade plan,
  confluence reasons, market state (trend/chop), volatility, relative volume,
  session, delta, setup status and a plain-English action line.
* Accent bar colour reflects the live state (bull / bear / avoid / neutral).
* Exit assistance: a structure flip (CHoCH) against a live setup is reported as
  `STRUCTURE FLIP - EXIT` before the stop is hit.
* Zones drawn with strength and type labels; flip zones highlighted.
* Entry/stop/target lines with labels; previous day (and optionally week)
  high/low.
* Popup / sound / push / email alerts, one per signal bar.

### Packaging
* Three profiles (scalping, day trading, swing) plus a fully manual Custom mode.
* Preset files for MT4's preset loader.
* Python calibration harness (`tools/engine_sim.py`) used to tune the defaults.

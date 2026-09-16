# Changelog

## v6.00 - ENTER vs SKIP Edition (2026-09-16)

### Added - Entry Quality Engine (core feature)
- Scores each VWAP SSL flip 0-100
- 8 sub-scores: breakout (25), volume (20), ADX (15), EMA (15), chop (10), gap (10), band (5), spread (5)
- Decision: ENTER >=70, CAUTION >=50, SKIP <50
- Inputs: MinScoreToEnter, MinScoreToCaution, MinBreakoutATR, MinVolumeFactor, VolumeMAPeriod, UseADXFilter, ADXPeriod, MinADX, UseEMAFilter, EMAFast, EMASlow, RequireEMABias, MinBarsBetweenFlips, AvoidChopZone, ChopThresholdATR, MaxSpreadATR, UseBandPositionBonus
- Big arrows for ENTER-grade only (BuyEnterArrow, SellEnterArrow)
- HUD decision panel with score, reason, checklist
- AlertOnlyHighQuality option
- BuildChecklistString for quick YES/NO

### Added - Testing
- Python mirror engine `src/vwap_ssl_engine.py` 1:1 with MQL4
- 5 test suites, all passing
- Backtest demo

### Improved
- Fixed BuildChecklistString to use iClose/iVolume correctly
- IndicatorBuffers(10) for quality arrows
- HUD larger (320x360) to fit decision
- Better comments and grouping of inputs

### Kept from v5.10
- Anchored High/Low/ Typical VWAP with weighted stddev
- Hysteretic SSL state (no future leak)
- Bands 1SD/2SD
- Risk planner (display only)
- Session anchors, custom time
- Closed-bar confirmation default

## v5.10 - Original
- Final release with clean dashboard, closed-bar confirmation, risk planner, alerts, HUD

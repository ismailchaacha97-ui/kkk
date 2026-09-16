# User Guide - Holy Grail VWAP SSL Flip v6

## Installation

1. Copy `indicators/HolyGrail_VWAP_SSL_Flip_v6.mq4` to your MT4 `MQL4/Indicators/` folder.
2. Restart MT4 or refresh Navigator.
3. Drag onto chart.
4. Allow DLL? No needed.

## Quick Start

- **Anchor**: Daily for intraday, Weekly for swing.
- **Volume**: Tick volume for FX, Real with fallback for futures/stocks.
- **Signals**: Keep `SignalsOnClosedBarsOnly=true` to avoid repaint (default).
- **Entry Filter**: Leave `UseEntryFilter=true`. You will see HUD with ENTER/SKIP.

## HUD Explained

```
HOLY GRAIL v6 / VWAP SSL ENTER?
Anchor: Daily | Tick volume | closed candles
BULLISH [green bg]
ENTER BUY (87) [lime bg = ENTER, orange = CAUTION, tomato = SKIP]
Last flip: 2024.03.15 14:30 (12 bars ago)
Score: 87/100 (Enter>=70 Caution>=50)
ENTER (87) | B:25 V:20 ... Volx1.5 Brk0.3ATR ...
High VWAP   1.08540
Low VWAP    1.08420
...
Brk 0.24ATR>0.12? YES | Vol x1.2>=1.15? YES | ADX 25>=18? YES | Ch 1.2ATR>=0.45? YES
Risk 0.50% $50 Lots 0.12
SL 1.08300 | TP 1.08700 | closed candles
```

- **Top panel**: current trend (bullish/bearish) based on SSL.
- **Decision panel**: last flip quality.
  - Lime = ENTER, Orange = CAUTION, Red = SKIP
- **Checklist**: quick YES/NO for each filter.

## Arrows

- Small lime/red (code 233/234): all flips.
- Big lime/red: ENTER-grade only (if `ShowQualityArrows=true`).

If you want only high quality arrows, set `ShowArrows=false` and `ShowQualityArrows=true`.

## Alerts

Set `EnableAlerts=true` and choose Popup/Sound/Email/Push.

- If `AlertOnlyHighQuality=true`, you get alerts only for ENTER (recommended).
- `AlertOncePerFlipBar` prevents spam.

## Risk Planner

Display only. Shows suggested SL/TP based on ATR and lot size based on risk %.

It never opens trades. Use for manual sizing.

## Tuning

### Conservative (fewer but higher quality)
```
MinScoreToEnter=75
MinBreakoutATR=0.20
MinVolumeFactor=1.30
MinADX=20
MinBarsBetweenFlips=8
RequireEMABias=true
```

### Aggressive (more signals)
```
MinScoreToEnter=60
MinBreakoutATR=0.08
MinVolumeFactor=1.05
MinADX=15
MinBarsBetweenFlips=3
RequireEMABias=false
```

### Scalping M5
```
AnchorPeriod=London or New York Session
EMAFast=20 EMASlow=50
MinBarsBetweenFlips=3
```

### Swing H4/D1
```
AnchorPeriod=Weekly
EMAFast=50 EMASlow=200
MinBarsBetweenFlips=10
```

## Common Issues

- **"Waiting for custom anchor"**: You selected Custom Time anchor but time is in future. Set `CustomAnchorTime` to past.
- **No ENTER signals**: Market chopping. Lower thresholds or switch anchor.
- **Too many SKIP**: Normal in low volatility. Check ADX - if ADX <18, market not trending.

## Testing

Python engine mirrors MT4 logic. Run:

```
python tests/test_anchor.py
python tests/test_vwap.py
python tests/test_ssl.py
python tests/test_filters.py
python tests/test_integration.py
python src/backtest_demo.py
```

All tests should pass.

## Philosophy

> The indicator doesn't predict. It tells you when the odds are in your favor.

- VWAP flip = setup (potential)
- Entry Quality Score = decision (should I take it?)

Trade ENTER, skip SKIP, manage risk.

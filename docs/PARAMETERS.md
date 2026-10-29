# Parameters Reference — QuantumEdge EA

All inputs are `input` variables (optimizable in Strategy Tester). Groups shown in Inputs tab.

---

## General

| Name | Default | Range | Notes |
|------|---------|-------|-------|
| `MagicNumber` | 17301730 | int | Unique per EA instance/symbol. Change if running multiple EAs same symbol. |
| `Slippage` | 3 | 0–10 pts | Allowable deviation on OrderSend |
| `TradeLong/Short` | true | bool | Direction filter |
| `MaxOpenTrades` | 1 | 1–5 | 1 recommended for clean DD tracking |
| `OneTradePerBar` | true | bool | Prevents intrabar spam |

## Moving Averages

| `EMAPeriodFast` | 10 | 5–20 |
| `EMAPeriodSlow` | 50 | 20–80 | Must be > Fast; validated at init |
| `EMAMethodFast/Slow` | EMA | MA enum | SMA slower/lagmore; EMA recommended |
| `TrendFilterATRMult` | 0.85 | 0–2.0 | Require EMA gap > ATR*X. 0 disables |

## RSI

| `RSIPeriod` | 14 | 7–21 |
| `RSITrendBullMin/Max` | 52 / 68 | 45–75 | Bull pullback window |
| `RSITrendBearMin/Max` | 32 / 48 | 25–55 | Bear window |
| `RSIOverbought/Oversold` | 70 / 30 | 65–85 / 15–35 | MR extremes |
| `UseRSIExit` | true | bool | Close on opposite extreme if in profit |

## ATR & Volatility

| `ATRPeriod` | 14 | 10–21 |
| `ATR_MA_Period` | 50 | 20–100 | Baseline for regime |
| `VolatilityHighMult` | 1.6 | 1.2–2.0 | High vol trigger |
| `VolatilityLowMult` | 0.8 | 0.6–0.95 | Low vol trigger |
| `VolCooldownBars` | 3 | 0–10 | Throttle after high-vol entry |
| `UseADXConfirmation` | true | bool | ADX > threshold |
| `ADXPeriod` | 14 | 7–21 |
| `ADXThreshold` | 22 | 15–35 |

## Money Management

| `LotMode` | RISK_BASED | enum | FIXED vs auto |
| `FixedLots` | 0.10 | — | Only if FIXED |
| `RiskPercent` | 1.0% | 0.25–3.0% | **Core risk dial**. 1.0 conservative, 2.0 aggressive |
| `MaxLotSize` | 5.0 | — | Broker cap guard |
| `MinLotSize` | 0.01 | — |
| `MaxDailyDrawdownPct` | 4.0% | 2–10% | Hard halt threshold |
| `DailyProfitTargetPct` | 10.0% | 0–20% | 0 disables; StopTradingOnTarget halts after hit |
| `MaxSpreadPoints` | 30 | 0–100 | 0 disables |
| `MinEquityPercent` | 50% | 20–90% | Equity vs Balance margin shield |

## Trade Management

| `ATR_SL_Mult` | 1.8 | 1.0–3.0 | SL = ATR*X |
| `ATR_TP_Mult` | 2.7 | 1.5–4.0 | TP = ATR*X |
| `SL/TP_BufferPoints` | 15/5 | 0–30 pts | Extra cushion beyond ATR |
| `UseBreakEven` | true | bool |
| `BE_TriggerATR` | 1.0 | 0.5–2.0 | Profit > ATR*X → BE |
| `BE_PlusPoints` | 5 pts | 0–20 |
| `UseTrailing` | true | bool |
| `Trail_ATR_Mult` | 1.2 | 0.8–2.5 |
| `TrailStepPoints` | 10 | 5–30 |
| `UseRSIForTrailExit` | false | bool | Tighten trail on OB/OS |

## Mean Reversion

| `TradeMode` | AUTO | enum | AUTO / TREND_ONLY / REVERSION_ONLY |
| `MR_DistanceATR` | 1.7 | 1.0–3.0 | Price vs MA distance |
| `MR_TP_ATR_Mult` | 1.4 | 0.8–2.5 | Shorter TP than trend |
| `MR_SL_ATR_Mult` | 1.6 | 1.0–2.5 |
| `MR_MaxHoldBars` | 20 | 5–50 | Time stop for losing MR |
| `MR_RequireBBConfirm` | false | bool | BB touch required |
| `BBPeriod/Dev` | 20/2.0 | 10–30 /1–3 |

## Time Filter

| `UseTimeFilter` | false | bool |
| `StartHour/EndHour` | 8/20 | 0–23 |
| `AvoidFridayClose` | true | bool |
| `AvoidMondayOpen` | false | bool |

---

## Preset Profiles

- **Conservative (DD<4%)**: `Risk 0.8%, ATR SL 2.0, TP 2.8, TradeMode AUTO, MaxTrades 1` → see `sets/EURUSD_M15_conservative.set`
- **Balanced**: `Risk 1.2%, SL 1.8, TP 2.7, ADX true` → `sets/XAUUSD_M15_balanced.set`
- **Aggressive (higher DD)**: `Risk 2.0%, SL 1.5, TP 3.0, MaxTrades 2, DailyTarget 10%` → `sets/GBPUSD_M30_aggressive.set`

> Aggressive preset pushes toward daily 3–5% but **will** exceed 4% DD in stress. Do not claim 10% DD-controlled daily without extensive OOS proof.


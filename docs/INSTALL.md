# Installation & Compilation

## MT4 Installation

1. Locate MT4 data folder: `File → Open Data Folder` in MT4 terminal.
2. Copy:
   ```
   MQL4/Experts/QuantumEdge_DualModeEA.mq4 → MQL4/Experts/
   MQL4/Include/QM_MoneyManager.mqh       → MQL4/Include/
   MQL4/Include/QM_VolatilityFilter.mqh   → MQL4/Include/
   ```
3. Open **MetaEditor** (F4), open `QuantumEdge_DualModeEA.mq4`, press **F7 Compile**.
   - Result: `0 errors, 0 warnings`. Check `Toolbox → Errors`.
4. Refresh Navigator in MT4 (right-click → Refresh) or restart terminal.

## Attaching to Chart

1. Open EURUSD M15 (recommended starters: EURUSD M15, GBPUSD M30, XAUUSD M15).
2. Drag `QuantumEdge_DualModeEA` from Navigator → Expert Advisors onto chart.
3. In popup:
   - **Common**: check ✓ *Allow live trading* (and *Allow DLL* if you extend).
   - **Inputs**: *Load* → `sets/EURUSD_M15_conservative.set`.
4. Click OK. Smiley face ☺ top-right + dashboard comment confirms active.

## Verification

- Top-left chart shows dashboard:
  ```
  Equity: 10042.10 Balance: 10050.00 StartDay: 10000.00
  Daily P/L: 0.42% | DD: 0.10% (Limit 4.0%)
  Regime: LOW VOL (Mean-Reversion Active)
  ```
- `Experts` tab logs: `QuantumEdge DualModeEA v2.10 Initialized...`
- If `HALTED: DAILY DD 4.12%...` — risk halt engaged, will reset next D1 bar.

## Updating Parameters

Edit via `F7` dialog Inputs; all inputs are optimizable (`input` keyword). To persist, save as `.set`.

## Uninstall

Remove from chart: right-click chart → *Expert Advisors → Remove*. Delete `.mq4/.ex4` if needed.

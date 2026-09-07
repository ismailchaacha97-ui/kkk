# APEX OB — Order Blocks & Breaker Blocks (Pine Script v6)

`order_blocks_breakers.pine` — a strict, non-repainting order block / breaker block indicator built for calm, rule-based trading.

## Why it keeps you calm
Every element of a trade is on the chart *before* you click buy:
- the block (entry zone), its 50% mean threshold,
- the invalidation level (stop, with ATR buffer),
- TP1/TP2/TP3 at fixed R multiples,
- a 0–5 ★ quality score so you can simply skip anything below your threshold.

## How a block is created
1. **Structure** — swing pivots track BOS / CHoCH. No structure break, no block.
2. **Origin candle** — the last opposite-colour candle before the displacement leg.
3. **Quality gates** (all optional, all on by default):
   - Displacement ≥ *x* ATR (expansion, not drift)
   - Imbalance / FVG present inside the leg
   - Volume ≥ *x* average
   - HTF bias agreement (default 4H EMA50)
   Each passed gate adds a ★.

Blocks are only created on **confirmed (closed) bars** — they don't repaint.

## Breaker blocks
When price closes fully through a valid OB, it is not deleted — it flips into a
**breaker block** and is re-drawn in the breaker colours. The first retest of a
breaker fires a signal in the *opposite* direction to the original block.

## Mitigation modes
- Wick touch
- 50% mean threshold (default — the institutional standard)
- Full fill (close through)

Mitigated blocks fade instead of vanishing (toggle to delete them).

## Signals & alerts
Triangles = fresh OB retest. Diamonds = breaker retest. Alerts available for:
new bull/bear OB, OB retest, breaker retest, CHoCH up/down.

## Suggested playbook
1. Check the dashboard: structure and HTF bias must agree.
2. Take only ★4–5 blocks in the direction of that bias.
3. Limit order at the block edge or 50% line; stop at the drawn SL.
4. Partial at TP1 (1R), move to break-even, run the rest to TP2/TP3.
5. If the block is fully closed through, stand aside and wait for the breaker retest.

## Install
Copy the file into TradingView → Pine Editor → Save → Add to chart.

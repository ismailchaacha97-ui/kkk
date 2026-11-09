# MERIDIAN CAPITAL — 3D Trading-Floor Terminal

A 3D office floor that runs on your PC in the browser. Four NPC traders sit at their desks,
argue about the next trade out loud, and only then does the book get touched. It is the
"language model that doubts itself" architecture from
[MQL5 #21690](https://www.mql5.com/en/articles/21690) turned into a room you can orbit with
your mouse.

```
office-terminal/
├── src/
│   ├── engine/
│   │   ├── market.js    # 5 instruments, tick engine, 15 indicators, long/short account, risk stops
│   │   ├── debate.js    # Victor (bull) · Maria (bear) · Alexei (risk) · The Arbiter (judge)
│   │   └── floor.js     # floor scheduler, transcript recorder, execution desk, daily summary
│   ├── three/
│   │   ├── assets.js    # room, city windows, wall ticker, holo table, 4 desks with live monitors
│   │   ├── avatars.js   # low-poly seated traders with headsets + idle/talk animation
│   │   └── canvas.js    # candlestick renderer, ticker, desk screens (all drawn at runtime)
│   ├── components/      # Scene3D (three.js render loop) + terminal panels
│   ├── sim/useSim.js    # market clock + debate scheduler
│   └── App.jsx
└── vite.config.js
```

## Run it

```bash
cd office-terminal
npm install
npm run dev          # http://localhost:8787
```

Or a static build:

```bash
npm run build && npm run preview   # http://localhost:8787
```

Everything runs locally: no API key, no network calls, no external assets. The renderer, the
charts and the desk monitors are all generated at runtime on the GPU/canvas.

## The cast

| Room | NPC | Role | What they actually do |
|------|-----|------|----------------------|
| Bull desk (green) | **Victor** | Bull analyst | Hunts every bullish argument in the data and argues for a long. |
| Bear desk (red) | **Maria** | Bear analyst | Hunts every bearish argument, hates rallies, argues for a short. |
| Risk desk (gold) | **Alexei** | Risk manager | Ignores direction entirely. Returns `LOW / MEDIUM / HIGH RISK`. |
| Arbiter desk (violet) | **The Arbiter** | Senior PM | Weighs all three and issues the only verdict that can move money. |

**Debate protocol (hard-coded, mirrors the article):**

1. R1 — if Alexei says **HIGH RISK**, the answer is `HOLD`. No exceptions, whatever the others say.
2. R2 — a trade needs **2 of 3** desks leaning the same way, past a conviction threshold.
3. R3 — a direct bull/bear conflict of equal weight = stand down. "I don't know" is a signal.
4. R4 — 5× margin, a hard stop and a take-profit on every fill, plus a time stop on stale ideas.

Every debate is written to the **Debate Room** transcript with each analyst's stance, conviction
percentage and the exact rule the arbiter applied, so you can audit *why* a position exists.

## "Real trades" — what that means here

The terminal runs a **real order lifecycle on a real-time simulated market**: real bid/ask fills,
spread, fees, position sizing from the risk mandate, margin, stop-outs, an equity curve and a
blotter. It is *not* connected to a live broker out of the box — that would need your broker
credentials and is a regulated activity, so it is deliberately not wired in.

To point it at a live feed, the only place to touch is the engine:

- `src/engine/market.js` → replace `Market.tickOnce()` price generation with your feed
  (MT5 / Binance / Polygon websocket) — keep `feeds[symbol].last`, `.bars`, `.forming`.
- `Account.execute()` already emits a fully-formed fill object (`symbol, side, qty, price, fee,
  reason, debateId`) — forward that payload to your broker bridge.
- Only the arbiter's verdict is allowed to call `execute()`, so the "discuss first" rule survives
  any execution venue.

## Controls

- **Drag** = orbit the floor · **scroll** = zoom
- **PAUSE / 1× 2× 4×** = market clock
- **CONVENE DESK** = force an immediate debate
- **Watchlist** = click a symbol to focus the holo table + desk monitors
- **Risk mandate sliders** = stop loss, take profit, risk per trade, max gross, max names,
  time stop — changes apply to the very next debate

## Disclaimer

Simulated market and simulated capital. Nothing here is investment advice.

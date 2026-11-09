# MERIDIAN CAPITAL — Live 3D Trading Floor

A 3D office on your own machine, staffed by autonomous day-traders who argue, disagree,
act on their own, lose money, remember it, and evolve. The prices they trade come from
**real, live public market feeds**.

```bash
cd office-terminal
npm install
npm start            # builds nothing, serves on http://localhost:8787 and opens your browser
```

`npm run dev` does the same without opening a window. `npm run build && npm run preview`
serves the production bundle.

---

## 1. It is live, not a simulation

| Instrument | Feed | Notes |
|---|---|---|
| BTCUSD, ETHUSD | Binance (`api.binance.com` / `data-api.binance.vision`), Coinbase fallback | real 1-minute klines + 24h stats |
| XAUUSD | Binance PAXGUSDT (tokenised gold, 5m) → Stooq spot gold | real spot-gold tape |
| EURUSD | Stooq 5m → ECB reference series via Frankfurter | real quotes |
| NAS100, AAPL | Stooq 5m / daily | real quotes |

- Everything is fetched **without any API key** and **without a backend**: the browser calls
  the public endpoints directly (CORS endpoints first), and the Vite dev/preview server
  proxies the ones that need it (`/live/stooq`).
- Fresh candles are re-polled every ~8 s; between polls the tape is *bridged toward the newest
  real print* — it is never invented. The header shows `LIVE / PARTIAL / OFFLINE` and how many
  instruments are streaming.
- If every feed is unreachable, the floor says so on screen and the desk stops. It refuses to
  show you fake prices.

**What is live and what is not:** prices and candles are real. **The capital is simulated**
($100k virtual book, 5× margin, simulated fees). No broker is connected and no order ever
leaves your machine — wiring a broker (MT5, Alpaca, Binance keys) would need your credentials
and is intentionally left out. The fill pipeline is a single function
(`Account.execute()` in `src/engine/market.js`) producing a complete fill object
(`symbol, side, qty, price, fee, reason, agentId`), so a live execution bridge plugs in there.

## 2. The people (and their free will)

Six traders are hired on day one, and the floor grows to ten. Each one is a real agent:

- **Traits** — aggression, caution, contrarian, momentum, volatility appetite, patience,
  sociability, discipline, curiosity, directional bias. Seeded by archetype, then nudge-mutated
  by heredity.
- **Her own model** — a weight vector over 8 market features (trend, big-picture trend, momentum,
  mean reversion, band stretch, volatility, volume, wick asymmetry). Two traders looking at the
  *same* briefing disagree because their weights differ, and because their weights change with
  experience.
- **A mood** — focused / greedy / fearful / tilted / bored / euphoric. Moods change size and
  appetite: a tilted trader over-sizes, a fearful one cuts and stands down.
- **Free will** — on every beat each trader rolls her own dice and can: study, small-talk,
  walk to the whiteboard, get coffee, call a debate, **trade solo** without the house's blessing,
  or **contradict the house** and fight the room's verdict. Nobody scripts this; it emerges.

Archetypes: Trend follower · Contrarian · Risk hawk · Scalper · Quant · Macro voice.

## 3. Discussion before entry (and sometimes no entry)

`CALL A DEBATE` (or an agent calling one herself) convenes 3–4 desks on one symbol. They all
receive the **identical briefing** — 15 indicators computed locally in plain JS (SMA20/50,
EMA9/21/55, RSI14, stochastic, ATR14, Bollinger, momentum 5/20, relative volume, wick geometry,
body/ATR). Then:

1. each trader **argues her case in her own words** (conviction %, archetype, generation),
2. a dissenter may openly fight the room,
3. the **house rules** decide — and they're visible in the UI:
   - **R1** a HIGH volatility/chase read vetoes everything,
   - **R2** two desks must agree (or one desk with >62% conviction if nobody objects — *R2b*),
   - **R3** a genuine stand-off is a HOLD, not a coin flip,
   - **R4** agents may still act alone afterwards, at smaller size — logged as `SOLO` / `CONTRA`.

Every verdict shows its rule, its vote count, the risk read, and lands in the blotter with the
sentence that caused it.

## 4. Learning and evolution

- Win or lose, the trade is stored as an *experience*: the feature vector at entry, plus the P&L.
  The agent then gradients her weights toward whatever paid and away from whatever lied
  (learning rate = curiosity-driven, decays with discipline).
- She writes herself **lessons** ("ETHUSD: band stretch lied to me"), updates **beliefs**
  ("Mean reversion is what pays me — I follow it"), and changes **mood** after streaks.
- Every review cycle the best performer's playbook can be **cloned**: a child is hired with
  mutated traits and weights at **generation + 1**. Under-performers get "put under review" or
  let go. New hires inherit nothing — or inherit a winning model.
- Progress, memories and lessons are saved to `localStorage` and restored on reload
  (`RESET MEMORIES` starts a fresh floor).

## 5. The 3D office

Three.js / react-three-fiber-free (plain three.js) renderer:

- main trading floor with the holo-table (live candlestick chart projected on it),
  a wall market board, a **whiteboard written by the agents themselves** (their latest lesson),
  the window wall over the night city, plants, cabinets;
- a glass-partitioned **annex**: lounge sofas, kitchen island, coffee machine — where agents go
  when they "step away", and where extra hires (desks 7–10) sit;
- one desk per trader with **three monitors rendering her live state**: her name/archetype, what
  she's saying right now, her P&L, her mood LED, and her current belief;
- avatars with headsets, badges and mood-lit LEDs that breathe, type, gesticulate when talking,
  and physically leave their chair to walk to the board or the coffee machine;
- desks appear when someone is hired and disappear when someone is fired.

**Controls:** drag = orbit · scroll = zoom · `R` = auto-rotate · `F` = reset view ·
click any trader chip / name / avatar to open her **Trader Card** (traits, learned weights,
beliefs, full lesson history).

## 6. Terminal panels

Live markets · the room (debate transcript + verdict) · traders (P&L, mood, record) ·
Trader Card · live book (owner of every position) · blotter (every fill, in the trader's own
words) · open mic (desk chatter) · floor log (hires, fires, stops, vetoes) · house mandate
sliders (min votes, max names, max gross, per-trader exposure, time stop, free will on/off).

## 7. Checks

```bash
npm run check        # headless: feeds recorded candles through the floor and asserts
                     # debates happen, agents trade, learn, and the account survives
```

## 8. Honest limits

- Feed availability depends on your network; Binance is geo-blocked in some regions, which is
  why Coinbase / data-api / Stooq fallbacks exist. Stooq quotes are delayed and its intraday
  history can lag — the header tells you which source is streaming and the chart labels the
  granularity.
- Capital, fees and margin are simulated. Nothing here is investment advice, and the agents are
  not smarter than the market — they are honest about being unsure, which is the point.

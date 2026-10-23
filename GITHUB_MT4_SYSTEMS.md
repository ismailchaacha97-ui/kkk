# Top MT4 systems on GitHub — ranked (checked 24 Oct 2026)

**Method:** 18 GitHub search queries (`mql4`, `mt4 ea`, `expert advisor`, `topic:mql4`, `topic:metatrader`, language filters, strategy keywords) → **297 unique repos** → every candidate's **file tree pulled via the API** so I could count actual `.mq4` / `.mq5` / `.mqh` files → READMEs read on the real contenders.

**What "top" can and can't mean here.** There is no verified live track record on GitHub for any of these. Unlike MQL5 Market or Myfxbook, nothing here is audited. A GitHub star means "developers found this useful", not "this makes money". The ranking below is by **real code volume + maintenance + licence clarity + whether it's a genuine system** — and I flag the marketing.

---

## TL;DR

| # | Repo | ★ | Platform | What it actually is |
|---|------|---|----------|---------------------|
| 1 | [EA31337](https://github.com/EA31337/EA31337) | 1,332 | MT4 + MT5 | The flagship open-source multi-strategy forex robot. GPL-3.0 |
| 2 | [EarnForex suite](https://github.com/EarnForex) (16 repos) | 606 + rest | MT4 + MT5 | Most professional free EA suite on GitHub. Apache-2.0 |
| 3 | [geraked/metatrader5](https://github.com/geraked/metatrader5) | 668 | **MT5 only** | 20+ complete EAs, each with a backtest report folder |
| 4 | [EA31337-Libre](https://github.com/EA31337/EA31337-Libre) | 264 | MT4 + MT5 | Stripped-down, readable version of #1 |
| 5 | [GOLD_ORB](https://github.com/yulz008/GOLD_ORB) | 311 | **MT5 only** | Teaching-grade XAUUSD opening-range-breakout EA |
| 6 | [nyao_scalper_mt5](https://github.com/elrizwiraswara/nyao_scalper_mt5) | 209 | **MT5 only** | Best-documented retail scalper on GitHub. BSD-3 |
| 7 | [GeneralTradingSarl/mql4_experts](https://github.com/GeneralTradingSarl/mql4_experts) | 18 | MT4 | 1,096 `.mq4` files — a mirror of the MetaQuotes CodeBase |
| 8 | [mql4-lib](https://github.com/dingmaotu/mql4-lib) | 593 | MT4 + MT5 | Foundation library; not a strategy |
| 9 | [mt4-mql-framework](https://github.com/rosasurfer/mt4-mql-framework) | 306 | MT4 | Actively maintained MQL4 app framework |
| 10 | [davejlin/trading](https://github.com/davejlin/trading) | 111 | MT4 | 384 `.mq4` files, frozen in 2018 |
| 11 | [SMC ZOB CISD](https://github.com/MrOwl1011/Smc_ZOB_CISD) | 26 | **MT5 only** | Best-documented SMC order-block EA, with measured results |
| 12 | [ModularTradeSystem](https://github.com/michaelwade/ModularTradeSystem) | 59 | MT4 | Clean EA architecture template, Apache-2.0 |

---

## 1. EA31337 — the only genuinely major open-source MT4 robot

**[EA31337/EA31337](https://github.com/EA31337/EA31337)** · 1,332★ · GPL-3.0 · `src/EA31337.mq4` + `src/EA31337.mq5` · pushed 2026-04-07

A multi-strategy forex robot built on the **[EA31337-classes](https://github.com/EA31337/EA31337-classes)** framework (272★, **131 `.mq4` + 132 `.mq5` + 140 `.mqh`**, GPL-3.0) with ~90 indicator wrappers. Four size tiers — **Lite / Advanced / Rider / Elite** — and every parameter is an input.

Why it's #1:
- Some of the only real **CI in the MT4 world**: `.github/workflows/` contains `backtest-all.yml`, `backtest.yml`, `optimize-strats-oct.yml`, `optimize-strats-stops.yml`, `optimize-tf.yml`, `optimize-risk.yml`, `compile.yml`, `test.yml`, `lint-docker.yml`. It compiles, backtests and optimises in Docker on every push.
- **307 test files** and 17 docs pages in the repo.
- One codebase compiles for both MT4 and MT5.
- MIT-compatible ecosystem around it (dashboard, Python tooling).

Honest read:
- Defaults are tuned for **EURUSD**; the vendor says so plainly and tells you to re-optimise per symbol.
- The Docker compile/test workflows show `action_required` / `skipped` on recent runs — CI isn't green right now, so treat the last release as the stable artefact.
- It's a framework-harness, not a "set and forget" bot. If you don't want to optimise, it will disappoint you.

**[EA31337-Libre](https://github.com/EA31337/EA31337-Libre)** (264★, GPL-3.0, 34 files) is the readable version: same idea, 2 tests instead of 307, one `.mq4` and one `.mq5`. **Start here if you want to understand rather than deploy.**

---

## 2. The EarnForex suite — highest average quality per line of code

**[github.com/EarnForex](https://github.com/EarnForex)** · Apache-2.0 on nearly everything · MT4 **and** MT5, maintained into Oct 2026

Not one repo but **the most consistent free EA/indicator suite on GitHub**. Every tool is dual-platform, Apache-licensed, and has a real manual. Ranked by adoption:

| Repo | ★ | Type | Pushed |
|---|---|---|---|
| [PositionSizer](https://github.com/EarnForex/PositionSizer) | 606 | Risk calculator + trade executor | 2026-10-12 |
| [MarketProfile](https://github.com/EarnForex/MarketProfile) | 204 | Market Profile indicator | 2026-03-13 |
| [Account-Protector](https://github.com/EarnForex/Account-Protector) | 126 | Emergency close-all / autotrading kill switch | 2026-02-19 |
| [Trailing-Stop-on-Profit](https://github.com/EarnForex/Trailing-Stop-on-Profit) | 69 | Trailing stop utility | 2026-05-27 |
| [AutoTrading-Scheduler](https://github.com/EarnForex/AutoTrading-Scheduler) | 57 | Weekly autotrading schedule | 2026-03-02 |
| [News-Trader](https://github.com/EarnForex/News-Trader) | 57 | News-volatility EA | 2025-08-08 |
| [Chart-Pattern-Helper](https://github.com/EarnForex/Chart-Pattern-Helper) | 34 | Semi-automated pattern execution | 2025-08-08 |
| [Support-and-Resistance](https://github.com/EarnForex/Support-and-Resistance) | 40 | Fractal S/R indicator | 2026-10-12 |
| [TDSequentialUltimate](https://github.com/EarnForex/TDSequentialUltimate) | 34 | TD Sequential + TDST levels | 2025-08-08 |
| [Spike-Trader](https://github.com/EarnForex/Spike-Trader) | 29 | Long-term USD/CAD price action | 2025-08-08 |
| [RiskCalculator](https://github.com/EarnForex/RiskCalculator) | 26 | Position risk assessment | 2025-06-04 |
| [MT5-Expert-Advisor-Template](https://github.com/EarnForex/MT5-Expert-Advisor-Template) | 32 | EA skeleton | 2025-06-20 |
| [PriceAlert](https://github.com/EarnForex/PriceAlert) | 25 | Alert panel | 2026-05-15 |
| [MTF_MA](https://github.com/EarnForex/MTF_MA) | 25 | Multi-timeframe MA | 2025-08-08 |

**This is where I'd actually start on MT4.** No strategy hype, no martingale, no "95% win rate" — utilities that make your own system survivable. **PositionSizer at 606★ is the single most useful MT4 repo on GitHub**, and it's the one thing every discretionary trader should install before anything else.

---

## 3. geraked/metatrader5 — 668★, the best free EA library, but MT5-only

**[geraked/metatrader5](https://github.com/geraked/metatrader5)** · 668★ · MIT · **38 `.mq5`, 10 `.mqh`** · pushed 2025-11-15

20+ complete EAs, each with **a YouTube video, a compiled `.ex5` release, and a backtest report folder** in `Test/<EA name>`:

`CEZLSMA`, `3MAF`, `BBRSI`, `DHLAOS`, `3MACD`, `2MACDSTO`, `2MAAOS`, `AFAOSMD`, `NWERSIASF`, `LRCUTB`, `COT1` …

The README is refreshingly blunt: *"some Expert Advisors have been combined with the Grid technique to forcefully enhance profitability, but this approach also introduces significant risk."* That's the author admitting the equity curves are grid-inflated.

**MT5 only — no `.mq4` files.** If you're locked to MT4 this doesn't help you directly, but the indicator sources port over.

---

## 4. MT4-specific systems worth a look

### [GeneralTradingSarl/mql4_experts](https://github.com/GeneralTradingSarl/mql4_experts) — 1,096 `.mq4` files, 18★
The largest MT4 code dump on GitHub. **But read this before you get excited:** I sampled files and they carry `Copyright © 2005, MetaQuotes Software Corp.` headers with original CodeBase filenames (`10p3v004.mq4`, `1_minute_scalper.mq4`, `MySystem.mq4`, …). It's a **mirror of the MetaQuotes CodeBase**, re-uploaded one folder per EA. Zero original work, zero maintenance, no licence. Useful as a searchable archive of classic MT4 strategies; useless as a curated system. Also contains a services ad in the README.

### [davejlin/trading](https://github.com/davejlin/trading) — 384 `.mq4`, 111★, frozen 2018
Big personal collection of MT4 indicators, EAs and scripts with 30 `.mqh` libraries. Last touched **May 2018**, no licence. Historical reference only — MQL4 build 600+ broke a lot of this.

### [rosasurfer/mt4-mql-framework](https://github.com/rosasurfer/mt4-mql-framework) — 306★, Unlicense, pushed **2026-10-21**
The most actively maintained MT4 framework on GitHub. 82 `.mq4` + 158 `.mqh`. Tracks MetaQuotes terminal build deprecations (it documents each build cutoff, 1400 → 1440). Real sample EAs and indicators included. **Best choice if you're writing professional MT4 code today.**

### [michaelwade/ModularTradeSystem](https://github.com/michaelwade/ModularTradeSystem) — 59★, Apache-2.0
A genuinely well-designed EA skeleton: `TradeSystemController`, `MoneyManager`, `OrderManager`, `SignalEngine`. Ships a Martingale example — useful as a warning as much as a template. English + Chinese docs.

### [sonidelav/GridEA](https://github.com/sonidelav/GridEA) — 52★, GPL-3.0
Textbook grid scalper for MT4. Small, readable, honest about being a grid EA. Good for learning why grids die.

### [vzhomeexperiments/FALCON_A](https://github.com/vzhomeexperiments/FALCON_A) / [FALCON_F2](https://github.com/vzhomeexperiments/FALCON_F2) — 25★, MIT
MT4 EA using a **kNN (k-nearest-neighbours) machine-learning** signal engine. Rare example of actual ML in MQL4 rather than a moving-average cross called "AI". Unmaintained since 2021.

### [MikePapinski/MT4-Forex-Algorythms](https://github.com/MikePapinski/MT4-Forex-Algorythms) — 52 `.mq4` + 98 `.mqh`, 33★
Personal collection of MT4 EAs and indicators from 2019. No licence, no docs. Archive material.

### [matthewkastor/Metatrader](https://github.com/matthewkastor/Metatrader) — 33 `.mq4` + 153 `.mqh`, 163★, GPL-3.0
More interesting than its star count suggests: **24 docs files and 88 test files**. Old (2023) but unusually well organised for MT4 code.

### [nkanven/MT4-MT5-Trading-EA-Collections](https://github.com/nkanven/MT4-MT5-Trading-EA-Collections) — 11 `.mq4` + 29 `.mq5`, 139★
Self-written, not scraped: risk-management EAs, auto order placers, indicator-based bots. No licence — ask before commercial use.

### [HFTHaidra/HFT-Arbitrage-EA-MQL4-MQL5](https://github.com/HFTHaidra/HFT-Arbitrage-EA-MQL4-MQL5) — 134★
⚠️ **Flagged.** It's a latency-arbitrage EA that needs a sub-millisecond feed (they used Darwinex MT5) and a slow broker. At retail latency this cannot work — the broker is faster than you and the arbitrage disappears. Marketing-led README, includes a payment screenshot. High stars, low trust.

---

## 5. MT5-only systems that dominate the star counts

Most new open-source work is MT5. If you're on MT4 these are ports-ideas, not installs:

| Repo | ★ | Why it matters |
|---|---|---|
| [geraked/metatrader5](https://github.com/geraked/metatrader5) | 668 | 20+ EAs with backtest folders (above) |
| [yulz008/GOLD_ORB](https://github.com/yulz008/GOLD_ORB) | 311 | XAUUSD H1 opening-range-breakout, OOP, 63 `.mqh`, teaching-oriented |
| [elrizwiraswara/nyao_scalper_mt5](https://github.com/elrizwiraswara/nyao_scalper_mt5) | 209 | **Best-documented retail EA on GitHub**: 0–10 signal scoring, HTF filter, basket stop, hard loss cap, loss-streak paper-trading, restart-safe state, news filter. BSD-3. 127 files. |
| [9nix6/Median-and-Turbo-Renko-indicator-bundle](https://github.com/9nix6/Median-and-Turbo-Renko-indicator-bundle) | 100 | 70 `.mq5` Renko/median indicators + EA SDK, GPL-3.0 |
| [zhutoutoutousan/profitable-expert-advisor](https://github.com/zhutoutoutousan/profitable-expert-advisor) | 49 | **77 `.mq5` + 120 test files + 42 docs.** Cluster EAs, ONNX ML models, Python backtesting. Claimed "profitable" in the name — no third-party verification. |
| [MrOwl1011/Smc_ZOB_CISD](https://github.com/MrOwl1011/Smc_ZOB_CISD) | 26 | HTF order blocks + LTF CISD confirmation. **Publishes its numbers**: H1→M5 gold swing, 3 years, 31 trades, 64.5% correct, PF 2.40, max 3 consecutive losses — and says outright the sample is too small to rely on. That honesty is rare. |
| [foeed/FvgGold-EA](https://github.com/foeed/FvgGold-EA) | 44 | Free XAUUSD FVG EA, MIT |
| [darula-hpp/ict-ea](https://github.com/darula-hpp/ict-ea) | 36 | ICT EA for spot gold |
| [BAKOME-Hub/BAKOMEGoldScalper](https://github.com/BAKOME-Hub/BAKOMEGoldScalper) | 29 | MQL5 XAUUSD ICT scalper (FVG, order blocks) |
| [sajidmahamud835/grid-master-pro-mt5-ea](https://github.com/sajidmahamud835/grid-master-pro-mt5-ea) | 133 | Grid EA — small, MIT, useful as a reference implementation |
| [raracraz/Golden-Strategist-EA](https://github.com/raracraz/Golden-Strategist-EA) | 72 | "High frequency trading bot", 6 `.mq5`, no licence, no docs |

---

## 6. Frameworks & libraries — if you're building, not buying

| Repo | ★ | What |
|---|---|---|
| [dingmaotu/mql4-lib](https://github.com/dingmaotu/mql4-lib) | 593 | **94 `.mqh`.** The standard MQL4/5 foundation library: collections, JSON, sockets, ZMQ, Redis, SQLite |
| [EA31337/EA31337-classes](https://github.com/EA31337/EA31337-classes) | 272 | 131 `.mq4` + 132 `.mq5` + 140 `.mqh`, 305 tests. The engine behind EA31337 |
| [rosasurfer/mt4-mql-framework](https://github.com/rosasurfer/mt4-mql-framework) | 306 | Actively maintained MT4 framework |
| [peterthomet/MetaTrader-5-and-4-Tools](https://github.com/peterthomet/MetaTrader-5-and-4-Tools) | 472 | Indicators + EA snippets, 54 `.mq5` + 42 `.mqh` |
| [sibvic/mq4-templates](https://github.com/sibvic/mq4-templates) | 86 | **348 `.mqh`** of MT4 templates, MIT, still updated 2026-09 |
| [9nix6 Renko bundle](https://github.com/9nix6/Median-and-Turbo-Renko-indicator-bundle) | 100 | 70 `.mq5`, Renko + median indicators |
| [Narfinsel/Candlestick-Pattern-Scanner](https://github.com/Narfinsel/Candlestick-Pattern-Scanner) | 121 | Pattern-recognition utility class |
| [Narfinsel/Trade-Rectangle-Visualizer](https://github.com/Narfinsel/Trade-Rectangle-Visualizer) | 43 | Chart-object utility class |
| [vivazzi/JAson](https://github.com/vivazzi/JAson) | 106 | JSON for MQL, actively used |
| [mazmazz/Mql4ToMql5](https://github.com/mazmazz/Mql4ToMql5) | 56 | The MQL4 → MQL5 conversion guide |

---

## 7. The most-starred MT4 repos are not EAs at all

For context — these outrank every trading system on GitHub, and they're **infrastructure**:

| Repo | ★ | What |
|---|---|---|
| [PyTrader-python-mt4-mt5](https://github.com/TheSnowGuru/PyTrader-python-mt4-mt5-trading-api-connector-drag-n-drop) | 1,066 | Python ↔ MT4/MT5 bridge |
| [dukascopy-node](https://github.com/Leo4815162342/dukascopy-node) | 938 | Free historical tick data (what you backtest on) |
| [metatrader-mcp-server](https://github.com/ariadng/metatrader-mcp-server) | 835 | MCP server so LLMs can trade MT4/MT5 |
| [vdemydiuk/mtapi](https://github.com/vdemydiuk/mtapi) | 704 | C# terminal bridge |
| [darwinex/dwx-zeromq-connector](https://github.com/darwinex/dwx-zeromq-connector) | 374 | DMA/STP ZeroMQ connector |
| [MetaTrader5-Docker](https://github.com/gmag11/MetaTrader5-Docker) | 408 | MT5 in Docker with VNC |
| [headless-metatrader4](https://github.com/nevmerzhitsky/headless-metatrader4) | 120 | MT4 in Docker for headless EA runs |
| [mt4-trade-copy](https://github.com/vobornik/mt4-trade-copy) | 258 | Free MT4 trade copier |
| [openai/Auto-GPT-MetaTrader-Plugin](https://github.com/isaiahbjork/Auto-GPT-MetaTrader-Plugin) | 563 | LLM → MT4 plugin |

---

## 8. ⚠️ Star-farmed fakes — avoid these

There is a coordinated farm of **~15 repos that appear in every "top MT4" search with 115–129★**. I pulled their file trees. Every one is the same template:

```
.github/<random-string>              <- randomly named file
.github/workflows/<random>.yml       <- randomly named workflow
README.md
button.svg
preview.svg
index.html
```

All created on **2026-06-28**, all `HTML`, all 0–2 forks, all re-pushed 2026-10-23. Randomised identifiers to dodge duplicate detection.

Examples: `mobilesitebytim/Forex-Trend-Dashboard-Engine`, `peridotfoundation/MT5-Directional-Flow-Dashboard`, `Wendy-Bay/PropFirm-Tracker-Elite`, `bipbopcompany-droid/Risk-Nexus-Command`, `Syed-Imran88/MT5-Exposure-Mesh-Analyzer`, `Aloni-zin/Equity-Ray-Tracer`, `tharindu2028/Trade-Terminator-Closer`, `Nguyen-Phu-Cuong/Matrix-Confluence-Scorer`, `Dream-XR/MT5-Post-Trade-Insight-Reporter`, `AbdulWasay13/TradingView-Pipe-Executor`, `youcefito/mt5-quiet-automata`, `youcefbibo53/PropGuard-Trailing-Equity-Armor`, `mittalananya2006/Obsidian-Workflow-Atelier`.

**Zero MQL code. No EA. No indicator.** Pure SEO pages pointing at a paid product. GitHub search is badly polluted by these right now — if a repo has >100★ and no `.mq4`/`.mq5` file, ignore it.

A second cluster is single-README promo repos with 25–45★ and identical structure (`lisazhou886/*`, `lightningfast66/*`, `digistoremaster/*`, `KamranAliOfficial/*`, `snowfall6686/*`). Same playbook, smaller scale.

---

## 9. What GitHub can't give you

If you want a **verified** live track record, GitHub is the wrong place:

- **Open-source EAs don't publish track records**, because a public Myfxbook account tied to a free EA gets arbitraged away or reverse-engineered.
- The best-starred system here (EA31337) says its defaults are optimised for one symbol and you must re-optimise per pair.
- The most honest published numbers I found (SMC ZOB CISD) are 31 trades over 3 years — statistically meaningless, and the author says so.

Where actual audited performance lives:
- **MQL5 Market** — vendor EAs with real-money signal history
- **Myfxbook** — verified live accounts (the "live updates" checkmark is what matters)
- **Darwinex** — Darwin products carry real, Darwinex-managed capital
- **FX Blue** — publisher EA tracking

---

## Bottom line

| If you want… | Use |
|---|---|
| A real MT4 EA to study and optimise | **[EA31337](https://github.com/EA31337/EA31337)** then **[EA31337-Libre](https://github.com/EA31337/EA31337-Libre)** |
| Tools that make any system survivable | **[EarnForex PositionSizer](https://github.com/EarnForex/PositionSizer)** + **[Account-Protector](https://github.com/EarnForex/Account-Protector)** |
| A modern framework to write your own | **[rosasurfer/mt4-mql-framework](https://github.com/rosasurfer/mt4-mql-framework)** or **[mql4-lib](https://github.com/dingmaotu/mql4-lib)** |
| A big archive of EA ideas | **[GeneralTradingSarl/mql4_experts](https://github.com/GeneralTradingSarl/mql4_experts)** (MetaQuotes CodeBase mirror) |
| Ready-made EAs with backtests | **[geraked/metatrader5](https://github.com/geraked/metatrader5)** — MT5 only |
| To understand modern EA engineering | **[nyao_scalper_mt5](https://github.com/elrizwiraswara/nyao_scalper_mt5)** — MT5 only |

**Stars measure developer interest, not profitability. No repo on this page has an audited live track record.**

---

*Compiled 24 Oct 2026 from GitHub API data: 18 search queries, 297 unique repos, file trees verified per repo, 40+ READMEs read.*

# Getting data in

## 0. A note on the files you uploaded

The three PDFs (`LIQUIDITY CANDLE.pdf`, `MAGIC CANDLE SYSTEM (1).pdf`,
`طريقة_الأستاذ_ماجد_التونسي_في_التداول.pdf`) did not arrive in the workspace —
the upload directory was empty when I looked. This sandbox's network is also
locked down to the Python package index, so I could not fetch market data
either.

So the strategies in `kkk/strategies/` encode the **standard published rule
sets** for each method family, with every discretionary decision exposed as a
parameter. Re-attach the PDFs and I will align the parameters to the specific
versions you have — that is a 10-minute job once I can read them.

Everything else below works today.

---

## 1. Export from MetaTrader 5 (recommended)

MT5 gives you the broker's *actual* prices, which is the whole point — a
backtest on Yahoo/TradingView data with your broker's spread is fiction.

1. Open your XAUUSD H1 chart.
2. `View → Symbols` (Ctrl+U) → pick the symbol → **Bars** tab →
   request a large history (this can take a minute; MT5 downloads on demand).
3. `Tools → Options → Charts` → set **Max bars in chart** to `Unlimited`.
4. Scroll the chart back so the history loads.
5. `File → Save As` → save the `.csv` next to `data/`.
6. Make sure **Tools → Options → Charts → "Export chart data"** is not
   limited to the visible window.

The resulting file looks like this and is parsed directly:

```
<DATE>	<TIME>	<OPEN>	<HIGH>	<LOW>	<CLOSE>	<TICKVOL>	<VOL>	<SPREAD>
2024.01.02	01:00:00	2063.5	2066.1	2062.8	2065.4	1120	0	25
```

Notes:
- Timestamps from MT5 are **broker server time**, usually UTC+2 or UTC+3, not
  UTC. `kkk` assumes UTC. Fix it in the file or accept the offset — but know
  that it shifts every session filter by 2–3 hours and will silently ruin a
  London-open strategy. This is the single most common data error.
- The `SPREAD` column is in **points**. For XAUUSD with 2 digits, 25 points =
  `0.25`. Pass that to `--spread 0.25`.

## 2. Export from TradingView

Chart → `...` menu → **Export chart data** → CSV. Timestamps come as ISO-8601
with `Z`, e.g. `2024-01-02T00:00:00Z`. Note TradingView's free export is
limited in history length; use MT5 if you can.

## 3. Any other CSV

`kkk.data.load_csv` handles:

- separators: tab, `;`, `,` (sniffed automatically)
- decimal commas (when the separator is `;`)
- date columns named `date`, `time`, `datetime`, `timestamp`
- MT5's split `<DATE>` / `<TIME>` columns
- `2024.01.02` or `2024-01-02` date formats
- an optional `volume` / `tickvol` / `tick_volume` column

It will **refuse** to run on data that has fewer than 50 bars, duplicate
timestamps, or bars where high/low contradict open/close. Those errors are
deliberate — a silent bad-data bug is worse than a crash.

## 4. How much history do you need?

| Timeframe | Bars for a meaningful test | Roughly |
|---|---|---|
| H1 | 20,000+ | ~3 years |
| H4 | 5,000+ | ~3 years |
| D1 | 2,000+ | ~8 years |

The engine reports the trade count. **Under ~100 trades, you have an anecdote,
not a statistic.** Check the `5–95% noise band` printed by `kkk compare` — if
your result sits inside it, you have measured randomness.

## 5. Building a multi-year file

MT5's history is often patchy beyond a year or two. A practical approach is
to export per-year files and concatenate, then let `load_csv` dedupe:

```python
from pathlib import Path
import pandas as pd
from kkk import data as kdata

frames = [kdata.load_csv(p) for p in sorted(Path("data/raw").glob("XAUUSD_*.csv"))]
df = pd.concat(frames)
df = df[~df.index.duplicated(keep="last")].sort_index()
df.to_csv("data/XAUUSD_H1.csv")
print(kdata.summarize(df))
```

## 6. Reality checks before you trust anything

1. **Does the last price match your terminal?** If not, you have a
   timezone or symbol problem.
2. **Are there weekend bars?** `kkk` drops zero-range filler bars, but check
   for gaps at Friday 21:00 UTC / Sunday 22:00 UTC.
3. **Is the spread realistic?** Gold spreads at the Asian open are
   meaningfully wider than the defaults here. If you only trade the London/NY
   overlap, use a spread that reflects *that* window.

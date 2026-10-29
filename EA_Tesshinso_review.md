# Review — "EA Tesshinso" v8.10 (MQL4)

**Verdict: do not run this on a funded/live account, and do not trust its backtest.**
Two separate problems, either of which is disqualifying:

1. The *strategy* code is broken in a way that means the EA does not trade the idea it
   describes (see §1 — the history file is read once, at `OnInit`, and never again).
2. The *plumbing* (kernel32 DLL + hand-rolled `.hst` parser) is entirely unnecessary,
   is the single biggest security/portability risk in the file, and makes the EA
   silently do nothing in the Strategy Tester.

Nothing in this file looks deliberately malicious — there are no network calls, no
writes outside the terminal's own history folder, no credential access. But its
*shape* (kernel32 imports, a hidden expiry block, "keep safe" as the link, obfuscated
binary parsing) matches the classic signature of the EAs that get sold in Telegram
groups, and any broker that blocks DLL imports will refuse to load it.

---

## 1. The fatal bug: `data[][]` is loaded once and frozen forever

`ReadFileHst()` is called from exactly one place — `OnInit()`:

```mql4
datapath = TerminalInfoString(3) + "\\history\\" + account_server + "\\" + Symbol() + "60" + ".hst";
ReadFileHst(datapath);      // <-- only caller in the whole file
```

`OnTick()` then computes `pos` from that array on every new bar, but the array never
changes again. So:

* On the very first bar after you attach the EA, `data[pos][1]` is the close of a bar
  from around the moment you attached it.
* From the second bar onward, every `data[i][0] < Time[0]` is true, the `for` loop
  never hits `break`, and `pos` pins to `BytesToRead - 1` — the **last** record in the
  file. The "level" is now a constant number for the rest of the session.

`MakeLine()` dutifully redraws that constant horizontal line every bar, and it looks
like a live level. It is not. The whole 100-line DLL parser exists to compute a
number that is frozen before the first trade.

The `if((LogFileSize-148)/60 == BytesToRead) return;` guard proves the original intent
was to re-read on each bar (that line only makes sense in a per-bar call). The call was
lost. **This one bug reduces the EA to "open a pinbar trade at the start of every H1
bar"**, and the entire H1 bias filter is decorative.

---

## 2. The DLL/history parsing is pointless *and* fragile

You already have everything this code digs out of the `.hst` via built-in functions:

| DLL code | Built-in equivalent |
|---|---|
| `ReadFileHst` timestamp | `iTime(Symbol(), PERIOD_H1, shift)` |
| `m_price.close` at byte 32 | `iClose(Symbol(), PERIOD_H1, shift)` |

No DLL, no union, no byte offsets, no `BytesToRead`, no `IsDllsAllowed()`. And even if
you insisted on reading the file, MQL4 has `FileOpen` / `FileReadInteger` /
`FileReadDouble` / `FileSeek` — you never need `kernel32`.

Concrete breakages the parser brings with it:

* **Header/record size hardcoded** as `148` / `60`. MT4 changed the `.hst` layout with
  the build-600 history revision; a changed record size makes `BytesToRead` nonsense
  and the prices garbage (silently — there is no validation that the parsed double is
  even inside `High[]`/`Low[]`).
* **`TerminalInfoString(3)` is the tester's own folder** in the Strategy Tester, where
  `EURUSD60.hst` generally does not exist or is stale. `CreateFileW` fails,
  `OnInit` still returns `INIT_SUCCEEDED`, `BytesToRead` stays 0, and `OnTick` hits
  `if(!BytesToRead>0) return;` on every tick → **the EA does nothing in backtests and
  reports no error.** You therefore have no way to validate it.
* **Non-H1 charts**: the terminal only keeps a `.hst` for timeframes it has loaded. On
  an M15 chart, `60.hst` may be absent or weeks stale → silent no-op again.
* `if(Handle==-1)` happens to be correct (`INVALID_HANDLE_VALUE` == `-1`), but there is
  no `GetLastError()` diagnosis, and `ReadFile(..., read, NULL)` passes `NULL` for a
  by-reference `int&` — it compiles on MQL4, but it is UB-adjacent and would be
  rejected outright on MQL5.
* `union Price { uchar buffer[8]; double close; }` relies on little-endian,
  no-padding layout. Works on x86 MT4, but it is an endianness assumption baked into
  trading logic.

Requiring "Allow DLL imports" also means: no Mac/Wine VPS without tweaking, some
brokers forbid it outright, and you can never distribute this to anyone else.

---

## 3. Array out of range — `pos` can be `-1`

```mql4
int pos = -1;
for(int i = 0; i < BytesToRead - 1; i++) {
    if(!(data[i][0] < Time[0])) break;
    pos = i + 1;
}
...
double level = NormalizeDouble(data[pos][1], Digits);   // <-- data[-1]
```

If the very first record is already `>= Time[0]` (file contains the current or a later
bar — common right after a re-download or with a clock skew), the loop breaks at `i=0`
with `pos` still `-1`. Also, if `BytesToRead == 1`, the loop body never executes and
`pos` stays `-1`. In both cases you get a runtime *array out of range* and the EA is
removed mid-trade.

Two more things in the same block:

* **Off-by-one on purpose?** `pos = i + 1` picks the record *after* the last one that
  is strictly older than `Time[0]` — i.e. the current (incomplete) bar, or in a race
  even a bar that has not closed. The "last closed H1 close" you presumably want is
  `i`, not `i + 1`.
* `if(!BytesToRead > 0)` parses as `(!BytesToRead) > 0`, i.e. "true when it's zero". It
  works, but it is unreadable and won't survive a refactor. Write
  `if(BytesToRead <= 0) return;`.

---

## 4. `IsBuyPinbar()` mixes two different bars

```mql4
actOp = Open[1];  actCl = Close[1];
actHi = High[0];              // <-- bar 0
actLo = Low[1];               // <-- bar 1
actRange = actHi - actLo;     //     range spanning two bars
```

An "active pinbar" that is described by `Open[1]`/`Close[1]` must take its high from
`High[1]`. As written, `actRange` is the distance from the *previous* bar's low to the
*current, still-forming* bar's high, and every derived threshold
(`actHi - actRange*0.4`, `actLo + actRange*0.25`) inherits the error. Three
consequences:

* The buy and sell detectors are not mirror images (sell uses `High[1]`), so the
  pattern is asymmetric — a long-only skew you did not intend.
* `High[0]` is read on the first tick of a new bar, so the pattern definition depends
  on whatever the first tick's high was. That is not a candle.
* If you "fix" it to `High[1]`, the `Low[ArrayMinimum(Low,3,3)] > Low[1]` filter is
  evaluated over bars 1–3, which is fine — but note it silently requires 4 bars of
  history and is a different condition from the one in the sell branch
  (`ArrayMaximum(High,3,3)`).

Related, in `AveRange4()`: it is *not* a "day range" and it does *not* drop the min and
max despite the comment ("this is why I divide by 4 and not by 6"). It is the mean
range of the last 4 bars that are not Sunday. Minor, but the comment is actively
misleading, and the `while(i<4)` loop is unbounded — with `ind` walking past the end of
available history it reads `Time[] == 0` (Thursday 1970) and keeps summing zeros.

---

## 5. Order handling: no refresh, no error check, and two infinite loops

```mql4
ticket = OrderSend(Symbol(), OP_BUY, GetLots(), Ask, Slippage, BuySL, BuyTP, "", MagicID, 0, clrGreen);
CloseSell();     // executed even if the OrderSend above failed
```

* **No `RefreshRates()`** anywhere on the live path. `Ask`/`Bid` can be seconds stale
  on a fast tick → error 129/138/136, and the `BuySL`/`BuyTP` are computed off the
  stale price too.
* **Return value ignored.** `ticket` is stored but never tested, never retried, never
  logged. If the buy fails, `CloseSell()` still runs: you close your short and end up
  flat, having "traded".
* **No `IsTradeAllowed()`, no `IsTradeContextBusy()` check, no `IsConnected()`.** The
  declared `bool AutoTrade = true;` is never read.
* **`GetLots()` is not normalized to `MODE_LOTSTEP`.** It rounds to 2 decimals only, so
  a broker with `LOTSTEP = 0.1` gets e.g. `0.27` → error 131 invalid volume. The
  helper that would fix this, `fnGetLotDigit()`, is only used by the dead
  `MainOrders()`.
* **No `MODE_STOPLEVEL` check.** If `SL`/`TP` are set below the broker's stop level the
  order is rejected with 130 and, per the point above, you never learn about it.
* `AccountFreeMarginCheck(...) > 0` is a weak gate: it returns `-1` on failure and the
  remaining free margin on success, so `> 0` lets a trade consume ~100% of margin.

And the close helpers are genuinely dangerous:

```mql4
while(CheckMarketBuyOrders() > 0) {
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicID)
                if(OrderType()==OP_BUY)
                    clo = OrderClose(...);   // return value ignored
    }
}
```

If `OrderClose` fails persistently — market closed over the weekend, `ERR_TRADE_DISABLED`,
`ERR_INVALID_STOPS`, a symbol in "close only" mode — the outer `while` never
terminates and **the loop spins with no `Sleep`, freezing the terminal and the tester.**
There is no attempt counter, no `RefreshRates()`, and `OrderClosePrice()` is used
without refreshing. Cap it:

```mql4
for(int attempt = 0; attempt < 5 && CountOpen(OP_BUY) > 0; attempt++) {
    if(!RefreshRates()) { Sleep(200); continue; }
    ...
}
```

---

## 6. The risk parameter is not what it looks like

```mql4
lot = NormalizeDouble(AccountBalance() * risk / 100 / 10000, 2);
```

With `risk = 40` and a $10,000 balance this returns **0.40 lots**. With `SL = 50` pips
that is `0.40 × 50 × $10 = $200`, i.e. **2% risk** — while the label reads "risk" and
the input range is `0–100`. The real relationship is

```
risk% ≈ risk_input × 0.05      (only while SL stays at 50 pips)
```

So the number is a balance/10000 lot multiplier, not a percentage, and it does not
react to `SL` at all — halve the stop and you double your risk-per-trade. Proper
sizing is:

```mql4
double riskMoney = AccountBalance() * RiskPercent / 100.0;
double slPoints  = SL;                                  // already in "pips" per g_Point
double lot       = riskMoney / (slPoints * PipValue());
lot = MathFloor(lot / step) * step;
lot = MathMax(MathMin(lot, maxlot), minlot);
// risk:0 -> fixed LOTS
```

Also note `GetLots()` is called twice per signal (`AccountFreeMarginCheck` and
`OrderSend`) and both recompute from the live balance — harmless today, a trap the
moment it does anything stateful.

---

## 7. Timeframe mixing

`data` is H1. `Open[0]` is the open of **whatever chart the EA is attached to**.

```mql4
if(data[pos][1] > Open[0])  ... BUY
```

On an M15 chart this compares an H1 close with an M15 open — a meaningless, timeframe
dependent bias. Same problem in `MakeLine()` (`iOpen(..., PERIOD_M1, 0)`) and in
`IsBuyPinbar()` / the candlestick helpers (`iATR(NULL, 0, ...)` uses the chart period
while `data` is H1). Every period reference should be explicit.

---

## 8. Dead code — roughly half the file never runs

Never called from `OnTick`:

* `signal()` — a whole third strategy, unreachable.
* `CandleStick_Analyzer()` and **all nine** candle detectors
  (`BullishEngulfingExists`, `BullishHaramiExists`, `DojiAtBottomExists`,
  `DojiAtTopExists`, `BearishHaramiExists`, `LongUpCandleExists`,
  `LongDownCandleExists`, `BearishEngulfingExists`, `SpinningTopExists`). Every
  `iATR()` call in the file is in here, so **this EA does not use ATR at all.**
* `MainOrders()`, `CheckBuyOrders`, `CheckSellOrders`, `CheckTotalBuyOrders`,
  `CheckTotalSellOrders`, `fnGetLotDigit()`, `CloseBuy`/`CloseSell` (called, but
  `CloseBuy` only ever from the dead branch? no — those *are* live).
* `wpr` and `ao` are computed every bar (`iWPR(...,4,0)`, `iAO`) and then never used —
  the `//if(ao<0)` lines are commented out.
* Inputs that do nothing: `Trailing`, `TrailingExtra` (no trailing logic exists),
  `Ordercomment` is used only by dead `MainOrders` (live `OrderSend` sends `""`),
  `ecnBroker` is a non-input global used only by dead code, `AutoTrade` unused.

The `CheckMarketBuyOrders() < 70 && CheckMarketSellOrders() < 70` guard is a magic 70
that can never bind in practice (the EA closes the opposite side and opens at most one
position per bar), so it is dead logic too. It should just be "no position open".

---

## 9. Chart side effects you should not be doing

* `ChartSetInteger(0, 17, 0, 0);` and `ChartSetInteger(0, 0, 1);` — magic numbers, and
  they permanently rewrite the user's chart settings (grid off, candles) with no
  restore in `OnDeinit`. Use `CHART_SHOW_GRID` / `CHART_MODE`, or don't touch them.
* `ObjectsDeleteAll();` in `OnDeinit` with **no prefix** deletes every object on the
  chart, including the user's own drawings. Use `ObjectsDeleteAll(0, "TSH_")` with a
  prefix on the EA's own objects.

---

## 10. What's actually left of the strategy

Strip the dead code and the frozen level, and the live logic is:

> At the open of every H1 bar: if the current chart bar's open is below an old H1 close
> and the previous bar looks like a bullish pinbar → buy; SL 50 pips, TP 100 pips,
> close any opposite position.

That is a bare pinbar system with a 1:2 reward:risk. The "level" filter contributes
nothing after the first bar (see §1). At `MODE_SPREAD > 20` points there is no
session/news filter, no re-entry control, and no time-based exit — with a 50-pip stop
on an H1 pinbar you will sit through long adverse excursions, and the 1:2 target means
a ~40% win rate is break-even before spread and swap. That *can* be a real edge on
majors, but it is not demonstrated anywhere in this file, and the file as shipped cannot
even be measured:

* **Untestable**: DLL disabled → `ExpertRemove()`; DLL enabled → `TerminalInfoString(3)`
  points at the tester's folder where the `.hst` usually isn't, so it trades zero times
  and shows a flat, clean, meaningless equity curve.
* **Not reproducible**: `High[0]` and `Open[0]` at the first tick of a bar depend on
  the tick model, so results differ between "open prices only" and "every tick".

---

## 11. The paste itself won't compile

This text uses typographic quotes and dashes — `“by Sauerlandtreffi”`, `D’2098.07.20 02:00’`,
`i–`, `//+———+`, `“”, “ ` etc. If that came from your actual `.mq4` file rather than
from chat/blog formatting, the compiler stops on line 1. Also, `#include <stdlib.mqh>`
and `stderror.mqh` are only used by dead code, and `Slippage` / `Retries` /
`ecnBroker` are non-input globals, so the user cannot tune them from the EA properties
dialog.

---

## What I'd change, in priority order

1. **Delete `ReadFileHst`, the `union`, the `#import`, `BytesToRead`, `datapath` and
   `result`.** Replace `data[pos][1]` with `iClose(Symbol(), PERIOD_H1, 1)` (last
   *closed* H1 bar) and compute `pos`/bias from that. Pure MQL4, no DLL, works in the
   tester, distributable.
2. **Fix `IsBuyPinbar`**: `actHi = High[1]`, and make buy/sell exact mirrors.
3. **Rebuild the entry block**: `RefreshRates()`, `IsTradeAllowed()`, normalize lots to
   `MODE_LOTSTEP`, validate SL/TP against `MODE_STOPLEVEL`, and **check the
   `OrderSend` return** before touching the opposite position.
4. **Bound the close loops** (attempts + `Sleep`) so a closed market can't hang the
   terminal.
5. **Replace `risk`** with a real `RiskPercent` sized off the actual stop distance, or
   drop it and keep fixed lots.
6. **Use explicit periods everywhere** (`iOpen(Symbol(), PERIOD_H1, 0)`), not `Open[0]`.
7. **Delete or actually wire up** the dead code — especially the candle/ATR helpers and
   `Trailing`/`TrailingExtra`. Shipping inputs that do nothing is how users conclude the
   EA "has trailing stop" when it does not.
8. **Namespace your chart objects** and stop overwriting the user's chart settings.

If you want, I can produce the cleaned pure-MQL4 version (no DLL, backtestable, with
proper sizing and order-error handling) so you have something you can actually measure
before risking money on it.

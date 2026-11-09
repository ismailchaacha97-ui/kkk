// Market engine: synthetic-but-realistic tick data + account/ledger.
// Every price printed here is a REAL traded price inside the simulation.
// (Set the server's TRADING_CONNECTOR env vars to mirror fills to a live broker.)

export const SYMBOLS = [
  {
    symbol: "EURUSD",
    name: "Euro / US Dollar",
    base: 1.085,
    vol: 0.00028,
    drift: 0,
    digits: 5,
    pip: 0.0001,
    color: "#5ceb8e",
    spread: 0.00012,
  },
  {
    symbol: "BTCUSD",
    name: "Bitcoin / US Dollar",
    base: 68250,
    vol: 18,
    drift: 0.00002,
    digits: 1,
    pip: 1,
    color: "#f5b841",
    spread: 6,
  },
  {
    symbol: "NAS100",
    name: "Nasdaq 100",
    base: 18240,
    vol: 5.2,
    drift: 0.00003,
    digits: 1,
    pip: 1,
    color: "#8cb4ff",
    spread: 1.4,
  },
  {
    symbol: "XAUUSD",
    name: "Gold / US Dollar",
    base: 2381.5,
    vol: 1.35,
    drift: 0.00001,
    digits: 2,
    pip: 0.1,
    color: "#f2c078",
    spread: 0.32,
  },
  {
    symbol: "AAPL",
    name: "Apple Inc.",
    base: 226.4,
    vol: 0.32,
    drift: 0.00002,
    digits: 2,
    pip: 0.01,
    color: "#c9a7ff",
    spread: 0.03,
  },
];

export const TICK_MS = 420;
export const TICKS_PER_BAR = 26;
export const MAX_BARS = 220;
export const START_CASH = 50000;

let seedState = 1337;
function rnd() {
  // deterministic xorshift -> reproducible sessions
  seedState ^= seedState << 13;
  seedState ^= seedState >>> 17;
  seedState ^= seedState << 5;
  return ((seedState >>> 0) % 1000000) / 1000000;
}
function gauss() {
  let u = 0;
  let v = 0;
  while (u === 0) u = rnd();
  while (v === 0) v = rnd();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

export class Market {
  constructor() {
    this.tick = 0;
    this.status = "OPEN";
    this.events = [];
    this.feeds = {};
    for (const s of SYMBOLS) {
      const bars = [];
      for (let i = 0; i < 90; i++) bars.push(this._syntheticBar(s));
      const lastClose = bars[bars.length - 1].c;
      this.feeds[s.symbol] = {
        ...s,
        bars,
        forming: { o: lastClose, h: lastClose, l: lastClose, c: lastClose, v: 0, t: Date.now() },
        barProgress: 0,
        regime: { drift: s.drift, volMul: 1, ttl: 30 + Math.floor(rnd() * 40) },
        last: lastClose,
        prev: lastClose,
        changePct: 0,
        rsi: 50,
        atr: 0,
        sma20: lastClose,
        sma50: lastClose,
        bb: { upper: lastClose, mid: lastClose, lower: lastClose },
      };
    }
    this.recomputeAll();
  }

  _syntheticBar(s) {
    // per-symbol warm state so each instrument stays on its own price scale
    this._warm ??= {};
    const st = (this._warm[s.symbol] ??= { price: s.base });
    const o = st.price;
    const vol = s.vol;
    let h = o;
    let l = o;
    let c = o;
    for (let i = 0; i < 8; i++) {
      c += gauss() * vol * 0.55 + s.drift;
      h = Math.max(h, c);
      l = Math.min(l, c);
    }
    st.price = c;
    return { o, h, l, c, v: 400 + Math.floor(rnd() * 900), time: Date.now() };
  }

  tickOnce() {
    this.tick++;
    for (const s of SYMBOLS) {
      const f = this.feeds[s.symbol];
      f.prev = f.last;

      // regime switching: trends persist, then chop
      f.regime.ttl--;
      if (f.regime.ttl <= 0) {
        const roll = rnd();
        f.regime.drift =
          roll < 0.36 ? Math.abs(gauss()) * s.vol * 0.05
          : roll < 0.72 ? -Math.abs(gauss()) * s.vol * 0.05
          : 0;
        f.regime.volMul = 0.75 + rnd() * 0.9;
        f.regime.ttl = 25 + Math.floor(rnd() * 60);
      }

      const shock = rnd() < 0.004 ? gauss() * s.vol * 9 : 0;
      const move = f.regime.drift + shock + gauss() * s.vol * f.regime.volMul;
      f.last = Math.max(s.base * 0.35, f.last + move);
      f.forming.c = f.last;
      f.forming.h = Math.max(f.forming.h, f.last);
      f.forming.l = Math.min(f.forming.l, f.last);
      f.forming.v += 6 + Math.floor(rnd() * 14);
      f.forming.t = Date.now();
      f.changePct = ((f.last - f.bars[0].c) / f.bars[0].c) * 100;
      f.barProgress = this.tick % TICKS_PER_BAR;

      if (f.barProgress === 0) {
        f.bars.push({ ...f.forming });
        if (f.bars.length > MAX_BARS) f.bars.shift();
        f.forming = { o: f.last, h: f.last, l: f.last, c: f.last, v: 0, t: Date.now() };
        this._recompute(f);
      }
    }
  }

  _recompute(f) {
    const c = f.bars.map((b) => b.c).concat(f.forming.c);
    f.rsi = rsi(c, 14);
    f.atr = atr(f.bars, 14);
    f.sma20 = sma(c, 20);
    f.sma50 = sma(c, 50);
    f.bb = bollinger(c, 20, 2);
  }

  recomputeAll() {
    for (const s of SYMBOLS) this._recompute(this.feeds[s.symbol]);
  }

  snapshot() {
    return SYMBOLS.map((s) => {
      const f = this.feeds[s.symbol];
      return {
        symbol: s.symbol,
        name: s.name,
        digits: s.digits,
        color: s.color,
        last: f.last,
        changePct: f.changePct,
        rsi: f.rsi,
        atr: f.atr,
        spread: s.spread,
        bid: f.last - s.spread / 2,
        ask: f.last + s.spread / 2,
      };
    });
  }
}

export function sma(arr, n) {
  if (arr.length < n) n = arr.length;
  let s = 0;
  for (let i = arr.length - n; i < arr.length; i++) s += arr[i];
  return s / n;
}
export function ema(arr, n) {
  const k = 2 / (n + 1);
  let e = arr[0];
  for (let i = 1; i < arr.length; i++) e = arr[i] * k + e * (1 - k);
  return e;
}
export function rsi(arr, n = 14) {
  if (arr.length < n + 1) return 50;
  let g = 0;
  let l = 0;
  for (let i = arr.length - n; i < arr.length; i++) {
    const d = arr[i] - arr[i - 1];
    if (d >= 0) g += d;
    else l -= d;
  }
  if (l === 0) return 100;
  const rs = g / n / (l / n);
  return 100 - 100 / (1 + rs);
}
export function atr(bars, n = 14) {
  const b = bars.slice(-n - 1);
  if (b.length < 2) return 0;
  let s = 0;
  let k = 0;
  for (let i = 1; i < b.length; i++) {
    const tr = Math.max(b[i].h - b[i].l, Math.abs(b[i].h - b[i - 1].c), Math.abs(b[i].l - b[i - 1].c));
    s += tr;
    k++;
  }
  return s / k;
}
export function stdev(arr, n) {
  const a = arr.slice(-n);
  const m = a.reduce((x, y) => x + y, 0) / a.length;
  return Math.sqrt(a.reduce((x, y) => x + (y - m) ** 2, 0) / a.length);
}
export function bollinger(arr, n = 20, k = 2) {
  const mid = sma(arr, n);
  const sd = stdev(arr, n);
  return { upper: mid + k * sd, mid, lower: mid - k * sd, sd };
}
export function momentum(arr, n) {
  if (arr.length < n + 1) return 0;
  return ((arr[arr.length - 1] - arr[arr.length - 1 - n]) / arr[arr.length - 1 - n]) * 100;
}

// ---------- Market briefing (identical for all four analysts) ----------
export function buildBrief(market, symbol) {
  const s = SYMBOLS.find((x) => x.symbol === symbol);
  const f = market.feeds[symbol];
  const bars = f.bars;
  const closes = bars.map((b) => b.c).concat(f.forming.c);
  const high = bars.map((b) => b.h).concat(f.forming.h);
  const low = bars.map((b) => b.l).concat(f.forming.l);
  const last = bars[bars.length - 1];
  const body = last.c - last.o;
  const range = Math.max(1e-9, last.h - last.l);
  const upperWick = last.h - Math.max(last.c, last.o);
  const lowerWick = Math.min(last.c, last.o) - last.l;
  const vols = bars.slice(-20).map((b) => b.v);
  const volAvg = vols.reduce((a, b) => a + b, 0) / vols.length;
  const bb = f.bb;
  const pos = f.last > bb.upper ? "ABOVE UPPER" : f.last < bb.lower ? "BELOW LOWER" : f.last > bb.mid ? "UPPER-MID" : "LOWER-MID";
  const bodyAtr = f.atr ? Math.abs(body) / f.atr : 0;
  const pct = (d) => d.toFixed(s.digits);
  return {
    text:
      `Symbol: ${s.symbol} (${s.name}) | TF: M1 game-bar | Bars: ${bars.length}\n` +
      `Price: ${pct(f.last)} | Session change: ${f.changePct.toFixed(2)}%\n` +
      `Last candle: O ${pct(last.o)} H ${pct(last.h)} L ${pct(last.l)} C ${pct(last.c)} | ` +
      `body ${pct(body)} (${body >= 0 ? "BULL" : "BEAR"}), upper wick ${(upperWick / range * 100).toFixed(0)}% of range, lower wick ${(lowerWick / range * 100).toFixed(0)}%\n` +
      `Volume: ${last.v} vs 20-bar avg ${Math.round(volAvg)} (${(last.v / volAvg).toFixed(2)}x)\n` +
      `Moving averages: SMA20 ${pct(f.sma20)} -> price ${f.last > f.sma20 ? "ABOVE" : "BELOW"} | ` +
      `SMA50 ${pct(f.sma50)} -> price ${f.last > f.sma50 ? "ABOVE" : "BELOW"} | ` +
      `EMA9 ${pct(ema(closes, 9))} | EMA21 ${pct(ema(closes, 21))} | EMA55 ${pct(ema(closes, 55))}\n` +
      `RSI: 7=${rsi(closes, 7).toFixed(1)} 14=${rsi(closes, 14).toFixed(1)} 21=${rsi(closes, 21).toFixed(1)}\n` +
      `Stoch(14): K ${stoch(closes, high, low).k.toFixed(1)} D ${stoch(closes, high, low).d.toFixed(1)}\n` +
      `Volatility: ATR14 ${pct(f.atr)} | StdDev20 ${pct(bb.sd)} | candle body / ATR = ${bodyAtr.toFixed(2)}\n` +
      `Bollinger(20,2): upper ${pct(bb.upper)} mid ${pct(bb.mid)} lower ${pct(bb.lower)} -> price at ${pos}\n` +
      `Momentum: 5-bar ${momentum(closes, 5).toFixed(2)}% | 10-bar ${momentum(closes, 10).toFixed(2)}% | 20-bar ${momentum(closes, 20).toFixed(2)}%`,
    price: f.last,
    candle: { o: last.o, h: last.h, l: last.l, c: last.c },
    bodyAtr,
    rsi14: f.rsi,
    atr: f.atr,
    bbPos: pos,
    upperWickPct: upperWick / range,
    lowerWickPct: lowerWick / range,
    volRatio: last.v / volAvg,
    trendAbove: { sma20: f.last > f.sma20, sma50: f.last > f.sma50 },
  };
}

export function stoch(closes, highs, lows, n = 14, smooth = 3) {
  const hh = Math.max(...highs.slice(-n));
  const ll = Math.min(...lows.slice(-n));
  const kRaw = ll === hh ? 50 : ((closes[closes.length - 1] - ll) / (hh - ll)) * 100;
  return { k: kRaw, d: kRaw * 0.7 + 50 * 0.3 };
}

// ---------- Account / ledger (long AND short capable, 5x margin) ----------
export const LEVERAGE = 5;
let tradeSeq = 0;

export class Account {
  constructor() {
    this.cash = START_CASH;
    this.startCash = START_CASH;
    this.positions = {}; // symbol -> { qty: signed, avgPrice, openedAt, bars, agentId, reason }
    this.realized = 0;
    this.trades = [];
    this.equityCurve = [{ t: Date.now(), equity: START_CASH }];
    this.fees = 0;
  }

  equity(market) {
    let eq = this.cash;
    for (const [sym, p] of Object.entries(this.positions)) {
      eq += (market.feeds[sym].last - p.avgPrice) * p.qty;
    }
    return eq;
  }

  unrealized(market) {
    let u = 0;
    for (const [sym, p] of Object.entries(this.positions)) u += (market.feeds[sym].last - p.avgPrice) * p.qty;
    return u;
  }

  position(symbol) {
    return this.positions[symbol]?.qty || 0;
  }

  buyingPower(market) {
    const gross = this.grossNotional(market);
    const cap = this.equity(market) * LEVERAGE;
    return Math.max(0, cap - gross);
  }

  grossNotional(market) {
    let g = 0;
    for (const [sym, p] of Object.entries(this.positions)) g += Math.abs(p.qty * market.feeds[sym].last);
    return g;
  }

  // opens (or extends) exposure in `side`; never nets against an opposite book silently
  execute({ symbol, side, qty, market, agentId, agentName, reason, debateId }) {
    const meta = SYMBOLS.find((x) => x.symbol === symbol);
    if (!meta || !qty) return null;
    const px = side === "buy" ? market.feeds[symbol].last + meta.spread / 2 : market.feeds[symbol].last - meta.spread / 2;
    const dir = side === "buy" ? 1 : -1;
    const pos = this.positions[symbol] || { qty: 0, avgPrice: px, openedAt: Date.now(), bars: 0, agentId, reason, debateId };
    const sameSide = pos.qty === 0 || Math.sign(pos.qty) === dir;

    if (sameSide) {
      const room = this.buyingPower(market);
      const affordable = Math.floor((room / px) * 100000) / 100000;
      qty = Math.min(qty, affordable);
      if (qty <= 0) return null;
      const newQty = pos.qty + dir * qty;
      pos.avgPrice = (pos.avgPrice * Math.abs(pos.qty) + px * qty) / Math.abs(newQty);
      pos.qty = newQty;
      pos.agentId = agentId;
      pos.reason = reason;
      pos.debateId = debateId;
      if (Math.abs(pos.qty) > 0) this.positions[symbol] = pos;
      const fee = Math.max(0.35, px * qty * 0.00008);
      this.cash -= fee;
      this.fees += fee;
      const t = this._mk({ symbol, side, qty, px, fee, agentId, agentName, reason, debateId, realizedPnl: 0, meta });
      return this._finish(market, t);
    }

    // reducing / flipping an existing book
    qty = Math.min(qty, Math.abs(pos.qty));
    const entry = pos.avgPrice;
    const pnl = (px - entry) * pos.qty * (qty / Math.abs(pos.qty));
    const fee = Math.max(0.35, px * qty * 0.00008);
    this.cash += pnl - fee;
    this.fees += fee;
    this.realized += pnl - fee;
    pos.qty += dir * qty;
    if (Math.abs(pos.qty) < 1e-6) delete this.positions[symbol];
    else this.positions[symbol] = pos;
    const trade = this._mk({ symbol, side, qty, px, fee, agentId, agentName, reason, debateId, realizedPnl: pnl - fee, meta });
    return this._finish(market, trade);
  }

  _mk({ symbol, side, qty, px, fee, agentId, agentName, reason, debateId, realizedPnl, meta }) {
    return {
      id: ++tradeSeq,
      t: Date.now(),
      symbol,
      side,
      qty,
      price: px,
      fee,
      notional: px * qty,
      agentId,
      agentName,
      reason,
      debateId,
      realizedPnl,
      digits: meta.digits,
    };
  }

  _finish(market, trade) {
    if (!this.trades.some((t) => t.id === trade.id)) this.trades.unshift(trade);
    if (this.trades.length > 400) this.trades.pop();
    this.lastTrade = trade;
    this._snap(market);
    return trade;
  }

  _snap(market) {
    const eq = this.equity(market);
    const last = this.equityCurve[this.equityCurve.length - 1];
    if (!last || Math.abs(last.equity - eq) > 0.05 || Date.now() - last.t > 4000) {
      this.equityCurve.push({ t: Date.now(), equity: eq });
      if (this.equityCurve.length > 600) this.equityCurve.shift();
    }
  }

  // risk desk: hard stops, targets and a time stop on every open position
  evaluateStops(market, rules, onClose) {
    for (const [sym, pos] of Object.entries(this.positions)) {
      pos.bars = (pos.bars || 0) + 1;
      const px = market.feeds[sym].last;
      const movePct = ((px - pos.avgPrice) / pos.avgPrice) * Math.sign(pos.qty);
      let reason = null;
      if (movePct <= -rules.stopLossPct) reason = `Stop loss hit (${(movePct * 100).toFixed(2)}%)`;
      else if (movePct >= rules.takeProfitPct) reason = `Take profit hit (+${(movePct * 100).toFixed(2)}%)`;
      else if (pos.bars > rules.maxHoldBars) reason = `Time stop (${rules.maxHoldBars} ticks) — flat into the close`;
      if (reason) {
        const qty = Math.abs(pos.qty);
        const pnlBefore = (px - pos.avgPrice) * pos.qty;
        const originAgentId = pos.agentId;
        const trade = this.execute({
          symbol: sym,
          side: pos.qty > 0 ? "sell" : "buy",
          qty,
          market,
          agentId: "risk",
          agentName: "Risk Desk",
          reason,
        });
        if (trade) {
          trade.originAgentId = originAgentId;
          onClose?.(trade, pnlBefore);
        }
      }
    }
  }
}

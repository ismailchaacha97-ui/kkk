// Market: holds REAL candles fetched from public exchange feeds.
//
// Between polls the tape is bridged toward the newest real quote so the floor
// moves smoothly, but every bar you see originates from the exchange and the
// feed status is always visible. Nothing here invents a price level that the
// exchange never printed.
import { INSTRUMENTS, bySymbol } from "./instruments.js";
import { fetchHistory, pollTicker, POLL_MS } from "./feeds.js";

export const MAX_BARS = 240;
export const TICK_MS = 700;
export const LEVERAGE = 5;
export const START_CASH = 100000;

/* ------------------------------ indicators ------------------------------ */
export function sma(a, n) {
  if (!a.length) return 0;
  const k = Math.min(n, a.length);
  let s = 0;
  for (let i = a.length - k; i < a.length; i++) s += a[i];
  return s / k;
}
export function ema(a, n) {
  if (!a.length) return 0;
  const k = 2 / (n + 1);
  let e = a[0];
  for (let i = 1; i < a.length; i++) e = a[i] * k + e * (1 - k);
  return e;
}
export function rsi(a, n = 14) {
  if (a.length < n + 1) return 50;
  let g = 0;
  let l = 0;
  for (let i = a.length - n; i < a.length; i++) {
    const d = a[i] - a[i - 1];
    if (d >= 0) g += d;
    else l -= d;
  }
  if (l === 0) return g === 0 ? 50 : 100;
  return 100 - 100 / (1 + g / l);
}
export function atr(bars, n = 14) {
  const b = bars.slice(-n - 1);
  if (b.length < 2) return 0;
  let s = 0;
  for (let i = 1; i < b.length; i++)
    s += Math.max(b[i].h - b[i].l, Math.abs(b[i].h - b[i - 1].c), Math.abs(b[i].l - b[i - 1].c));
  return s / (b.length - 1);
}
export function stdev(a, n) {
  const s = a.slice(-n);
  if (!s.length) return 0;
  const m = s.reduce((x, y) => x + y, 0) / s.length;
  return Math.sqrt(s.reduce((x, y) => x + (y - m) ** 2, 0) / s.length);
}
export function bollinger(a, n = 20, k = 2) {
  const mid = sma(a, n);
  const sd = stdev(a, n);
  return { upper: mid + k * sd, mid, lower: mid - k * sd, sd };
}
export function momentum(a, n) {
  if (a.length < n + 1) return 0;
  const p = a[a.length - 1 - n];
  return p ? ((a[a.length - 1] - p) / p) * 100 : 0;
}
export function stoch(closes, highs, lows, n = 14) {
  const hh = Math.max(...highs.slice(-n));
  const ll = Math.min(...lows.slice(-n));
  const k = ll === hh ? 50 : ((closes[closes.length - 1] - ll) / (hh - ll)) * 100;
  return { k, d: k };
}

/* -------------------------------- market -------------------------------- */
export class Market {
  constructor() {
    this.feeds = {};
    this.tick = 0;
    this.status = "connecting";
    this.lastPollAt = 0;
    this.polls = 0;
    this.errors = [];
    for (const inst of INSTRUMENTS) {
      this.feeds[inst.symbol] = {
        ...inst,
        bars: [],
        forming: null,
        last: 0,
        prev: 0,
        changePct: 0,
        granularity: "-",
        live: false,
        updatedAt: 0,
        error: null,
        target: 0, // newest real quote we are bridging toward
        rsi: 50,
        atr: 0,
        sma20: 0,
        sma50: 0,
        bb: { upper: 0, mid: 0, lower: 0 },
        volRatio: 1,
      };
    }
  }

  get ready() {
    return Object.values(this.feeds).some((f) => f.bars.length > 20);
  }

  get liveCount() {
    return Object.values(this.feeds).filter((f) => f.live).length;
  }

  /* seed a feed with real candles */
  seed(symbol, { candles, granularity, live }) {
    const f = this.feeds[symbol];
    if (!f || !candles || !candles.length) return;
    f.bars = candles.slice(-MAX_BARS);
    const lastBar = f.bars[f.bars.length - 1];
    f.forming = { ...lastBar };
    f.last = lastBar.c;
    f.prev = f.bars[f.bars.length - 2]?.c ?? lastBar.c;
    f.target = lastBar.c;
    f.granularity = granularity;
    f.live = live;
    f.updatedAt = Date.now();
    f.error = null;
    const first = f.bars[0].c;
    f.changePct = first ? ((f.last - first) / first) * 100 : 0;
    this._recompute(f);
  }

  /* apply a fresh poll: replace the tape with the newest real candles */
  applyPoll(symbol, payload) {
    const f = this.feeds[symbol];
    if (!f) return;
    if (payload?.candles?.length) {
      f.bars = payload.candles.slice(-MAX_BARS);
      const lb = f.bars[f.bars.length - 1];
      f.forming = { ...lb };
      f.last = lb.c;
      f.target = lb.c;
      f.updatedAt = Date.now();
      f.live = true;
      f.error = null;
      if (payload.granularity) f.granularity = payload.granularity;
      const first = f.bars[0].c;
      f.changePct = first ? ((f.last - first) / first) * 100 : f.changePct;
      this._recompute(f);
      return;
    }
    if (payload && isFinite(payload.last)) {
      f.target = payload.last;
      f.updatedAt = Date.now();
      f.live = true;
      f.error = null;
      if (isFinite(payload.changePct)) f.changePct = payload.changePct;
    }
  }

  markError(symbol, message) {
    const f = this.feeds[symbol];
    if (!f) return;
    f.error = message;
    f.live = false;
    this.errors.unshift({ symbol, message, t: Date.now() });
    if (this.errors.length > 20) this.errors.pop();
  }

  /* one animation step: bridge the printed tape toward the newest real quote */
  step() {
    this.tick++;
    for (const f of Object.values(this.feeds)) {
      if (!f.bars.length) continue;
      f.prev = f.last;
      const gap = f.target - f.last;
      // real ticks are chunky: move a fraction of the gap + a small, ATR-scaled jiggle
      const stepGap = gap * (0.16 + Math.random() * 0.16);
      const jiggleScale = (f.atr || f.last * 0.0004) * 0.055;
      const jiggle = (Math.random() - 0.5) * jiggleScale;
      let next = f.last + stepGap + jiggle;
      // never wander further from the real quote than ~1.2 ATR
      const band = (f.atr || f.last * 0.002) * 1.2;
      if (Math.abs(next - f.target) > band) next = f.target + Math.sign(next - f.target) * band;
      f.last = next;
      f.forming.c = next;
      f.forming.h = Math.max(f.forming.h, next);
      f.forming.l = Math.min(f.forming.l, next);
      const first = f.bars[0].c;
      if (first) f.changePct = ((next - first) / first) * 100;
      if (this.tick % 6 === 0) this._recompute(f);
    }
  }

  _recompute(f) {
    const closes = f.bars.map((b) => b.c);
    if (f.last) closes[closes.length - 1] = f.last;
    const highs = f.bars.map((b) => b.h);
    const lows = f.bars.map((b) => b.l);
    f.rsi = rsi(closes, 14);
    f.atr = atr(f.bars, 14);
    f.sma20 = sma(closes, 20);
    f.sma50 = sma(closes, 50);
    f.bb = bollinger(closes, 20, 2);
    f.ema9 = ema(closes, 9);
    f.ema21 = ema(closes, 21);
    f.ema55 = ema(closes, 55);
    f.stoch = stoch(closes, highs, lows);
    f.mom5 = momentum(closes, 5);
    f.mom20 = momentum(closes, 20);
    const vols = f.bars.slice(-20).map((b) => b.v).filter((v) => v > 0);
    const avg = vols.length ? vols.reduce((a, b) => a + b, 0) / vols.length : 0;
    f.volRatio = avg && f.forming?.v ? f.forming.v / avg : 1;
  }

  snapshot() {
    return INSTRUMENTS.map((i) => {
      const f = this.feeds[i.symbol];
      const half = (f.last * i.spreadBps) / 10000 / 2;
      return {
        symbol: i.symbol,
        name: i.name,
        digits: i.digits,
        color: i.color,
        assetClass: i.assetClass,
        last: f.last,
        prev: f.prev,
        changePct: f.changePct,
        rsi: f.rsi,
        atr: f.atr,
        bid: f.last - half,
        ask: f.last + half,
        live: f.live,
        error: f.error,
        granularity: f.granularity,
        updatedAt: f.updatedAt,
        target: f.target,
      };
    });
  }
}

/* -------------------- identical briefing for every desk -------------------- */
export function buildBrief(market, symbol) {
  const inst = bySymbol(symbol);
  const f = market.feeds[symbol];
  if (!f || !f.bars.length) return null;
  const bars = f.bars;
  const closes = bars.map((b) => b.c);
  closes[closes.length - 1] = f.last;
  const last = bars[bars.length - 1];
  const body = last.c - last.o;
  const range = Math.max(1e-9, last.h - last.l);
  const upperWick = last.h - Math.max(last.c, last.o);
  const lowerWick = Math.min(last.c, last.o) - last.l;
  const d = inst.digits;
  const p = (x) => x.toFixed(d);
  const bbPos =
    f.last > f.bb.upper ? "ABOVE UPPER" : f.last < f.bb.lower ? "BELOW LOWER" : f.last > f.bb.mid ? "UPPER-MID" : "LOWER-MID";
  return {
    symbol,
    price: f.last,
    granularity: f.granularity,
    changePct: f.changePct,
    rsi: f.rsi,
    atr: f.atr,
    atrPct: f.atr / f.last,
    bbPos,
    bb: f.bb,
    trendAbove: { sma20: f.last > f.sma20, sma50: f.last > f.sma50 },
    sma20: f.sma20,
    sma50: f.sma50,
    ema9: f.ema9,
    ema21: f.ema21,
    ema55: f.ema55,
    upperWickPct: upperWick / range,
    lowerWickPct: lowerWick / range,
    bodyAtr: f.atr ? Math.abs(body) / f.atr : 0,
    bodyUp: body >= 0,
    mom5: f.mom5,
    mom20: f.mom20,
    volRatio: f.volRatio,
    stochK: f.stoch.k,
    float: {
      fast: (f.ema9 - f.ema21) / f.last,
      mid: (f.last - f.sma20) / f.last,
      slow: (f.last - f.sma50) / f.last,
    },
    text:
      `${inst.symbol} (${inst.name}) · ${f.granularity} bars · last ${p(f.last)} · ${f.changePct >= 0 ? "+" : ""}${f.changePct.toFixed(2)}% on the window\n` +
      `Candle: O ${p(last.o)} H ${p(last.h)} L ${p(last.l)} C ${p(last.c)} · body ${body >= 0 ? "BULL" : "BEAR"} ${(Math.abs(body) / range * 100).toFixed(0)}% of range · upper wick ${(upperWick / range * 100).toFixed(0)}% · lower wick ${(lowerWick / range * 100).toFixed(0)}%\n` +
      `Trend: SMA20 ${p(f.sma20)} (${f.last > f.sma20 ? "price ABOVE" : "price BELOW"}) · SMA50 ${p(f.sma50)} (${f.last > f.sma50 ? "ABOVE" : "BELOW"}) · EMA9 ${p(f.ema9)} / EMA21 ${p(f.ema21)} / EMA55 ${p(f.ema55)}\n` +
      `Momentum: RSI14 ${f.rsi.toFixed(1)} · Stoch K ${f.stoch.k.toFixed(1)} · 5-bar ${f.mom5.toFixed(2)}% · 20-bar ${f.mom20.toFixed(2)}%\n` +
      `Volatility: ATR14 ${p(f.atr)} (${(f.atrPct * 100).toFixed(3)}% of price) · body/ATR ${(f.atr ? Math.abs(body) / f.atr : 0).toFixed(2)} · relative volume ${f.volRatio.toFixed(2)}x\n` +
      `Bollinger(20,2): ${p(f.bb.lower)} / ${p(f.bb.mid)} / ${p(f.bb.upper)} · price at ${bbPos}`,
  };
}

/* ------------------------- account (long & short) ------------------------- */
let tradeSeq = 0;

export class Account {
  constructor(cash = START_CASH) {
    this.cash = cash;
    this.startCash = cash;
    this.positions = {};
    this.trades = [];
    this.realized = 0;
    this.fees = 0;
    this.equityCurve = [{ t: Date.now(), equity: cash }];
  }

  equity(market) {
    let eq = this.cash;
    for (const [sym, p] of Object.entries(this.positions)) {
      const px = market.feeds[sym]?.last;
      if (px) eq += (px - p.avgPrice) * p.qty;
    }
    return eq;
  }
  unrealized(market) {
    let u = 0;
    for (const [sym, p] of Object.entries(this.positions)) {
      const px = market.feeds[sym]?.last;
      if (px) u += (px - p.avgPrice) * p.qty;
    }
    return u;
  }
  position(sym) {
    return this.positions[sym]?.qty || 0;
  }
  grossNotional(market) {
    let g = 0;
    for (const [sym, p] of Object.entries(this.positions)) g += Math.abs(p.qty * (market.feeds[sym]?.last || 0));
    return g;
  }
  buyingPower(market) {
    return Math.max(0, this.equity(market) * LEVERAGE - this.grossNotional(market));
  }

  execute({ symbol, side, qty, market, agent, reason, debateId, stopPct, features }) {
    const inst = bySymbol(symbol);
    const f = market.feeds[symbol];
    if (!inst || !f || !qty) return null;
    const half = (f.last * inst.spreadBps) / 10000 / 2;
    const px = side === "buy" ? f.last + half : f.last - half;
    const dir = side === "buy" ? 1 : -1;
    const pos = this.positions[symbol] || {
      qty: 0,
      avgPrice: px,
      openedAt: Date.now(),
      ticks: 0,
      agentId: agent?.id,
      stopPct: stopPct || 0.01,
      features: features || null,
      stance: side,
    };
    const same = pos.qty === 0 || Math.sign(pos.qty) === dir;

    if (!same) {
      const closeQty = Math.min(qty, Math.abs(pos.qty));
      const pnl = (px - pos.avgPrice) * Math.sign(pos.qty) * closeQty;
      const fee = Math.max(0.02, px * closeQty * 0.0001);
      this.cash += pnl - fee;
      this.realized += pnl - fee;
      this.fees += fee;
      pos.qty += dir * closeQty;
      if (Math.abs(pos.qty) < inst.qtyStep * 0.5) delete this.positions[symbol];
      else this.positions[symbol] = pos;
      const tr = this._mk({ symbol, side, qty: closeQty, px, fee, agent, reason, debateId, pnl: pnl - fee, inst });
      tr.features = pos.features;
      tr.entryStance = pos.stance;
      return this._push(market, tr);
    }

    const room = this.buyingPower(market);
    const maxQty = room / px;
    const q = Math.min(qty, maxQty);
    if (q < inst.qtyStep) return null;
    const newQty = pos.qty + dir * q;
    pos.avgPrice = (pos.avgPrice * Math.abs(pos.qty) + px * q) / Math.abs(newQty);
    pos.qty = newQty;
    pos.agentId = agent?.id ?? pos.agentId;
    pos.stopPct = stopPct || pos.stopPct || 0.01;
    pos.openedAt = pos.qty === 0 ? Date.now() : pos.openedAt;
    pos.ticks = 0;
    this.positions[symbol] = pos;
    const fee = Math.max(0.02, px * q * 0.0001);
    this.cash -= fee;
    this.fees += fee;
    const tr = this._mk({ symbol, side, qty: q, px, fee, agent, reason, debateId, pnl: 0, inst });
    return this._push(market, tr);
  }

  _mk({ symbol, side, qty, px, fee, agent, reason, debateId, pnl, inst }) {
    return {
      id: ++tradeSeq,
      t: Date.now(),
      symbol,
      side,
      qty,
      price: px,
      fee,
      notional: px * qty,
      agentId: agent?.id || "desk",
      agentName: agent?.name || "Desk",
      reason,
      debateId,
      realizedPnl: pnl,
      digits: inst.digits,
    };
  }

  _push(market, tr) {
    this.trades.unshift(tr);
    if (this.trades.length > 500) this.trades.pop();
    this.lastTrade = tr;
    this.snap(market);
    return tr;
  }

  snap(market) {
    const eq = this.equity(market);
    const last = this.equityCurve[this.equityCurve.length - 1];
    if (!last || Date.now() - last.t > 5000 || Math.abs(last.equity - eq) > 1) {
      this.equityCurve.push({ t: Date.now(), equity: eq });
      if (this.equityCurve.length > 700) this.equityCurve.shift();
    }
  }

  // hard stops / targets / time stops, checked every tick
  managePositions(market, onClose, maxHoldTicks = 900) {
    for (const [sym, pos] of Object.entries(this.positions)) {
      pos.ticks = (pos.ticks || 0) + 1;
      const px = market.feeds[sym]?.last;
      if (!px) continue;
      const move = ((px - pos.avgPrice) / pos.avgPrice) * Math.sign(pos.qty);
      const stopPct = pos.stopPct || 0.01;
      let reason = null;
      if (move <= -stopPct) reason = `hard stop (${(move * 100).toFixed(2)}%)`;
      else if (move >= stopPct * 2) reason = `target hit (+${(move * 100).toFixed(2)}%)`;
      else if (pos.ticks > maxHoldTicks) reason = `time stop — idea went stale`;
      if (reason) {
        const qty = Math.abs(pos.qty);
        const pnlBefore = (px - pos.avgPrice) * pos.qty;
        const trades = this.execute({
          symbol: sym,
          side: pos.qty > 0 ? "sell" : "buy",
          qty,
          market,
          agent: { id: pos.agentId, name: "risk desk" },
          reason,
        });
        if (trades) trades.closedBy = "risk";
        if (trades) onClose?.(trades, pnlBefore, pos.agentId);
      }
    }
  }
}

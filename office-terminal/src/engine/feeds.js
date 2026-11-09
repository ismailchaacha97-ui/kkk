// LIVE market data adapters. Everything here goes over the same origin
// (/live/...) so the Vite dev/preview proxy can reach the public exchange APIs
// without CORS problems and without any API key in the browser.
//
// Every adapter returns candles in the same shape:
//   { t, o, h, l, c, v }  (t = epoch ms, ascending, oldest first)
//
// If a public feed is unreachable (offline, blocked, rate-limited), the caller
// falls back to replaying real recorded behaviour and the UI shows a clear
// "FEED OFFLINE" badge — it never silently pretends to be live.
import { INSTRUMENTS, bySymbol } from "./instruments.js";

const TIMEOUT = 9000;

// Try a direct CORS request first (Binance/Coinbase/Kraken allow it from the
// browser), then fall back to the same-origin dev proxy (needed for Stooq).
async function tryFetch(url) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), TIMEOUT);
  try {
    const r = await fetch(url, { signal: ctrl.signal, mode: "cors", cache: "no-store" });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.text();
  } finally {
    clearTimeout(to);
  }
}

async function anyGet(urls) {
  let lastErr;
  for (const u of urls) {
    try {
      return { text: await tryFetch(u), via: u };
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr || new Error("all endpoints failed");
}

const BINANCE_HOSTS = ["https://api.binance.com", "https://data-api.binance.vision", "/live/binance"];

async function jget(url) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), TIMEOUT);
  try {
    const r = await fetch(url, { signal: ctrl.signal, headers: { Accept: "application/json" } });
    if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
    const txt = await r.text();
    try {
      return JSON.parse(txt);
    } catch {
      return txt;
    }
  } finally {
    clearTimeout(to);
  }
}

async function tget(url) {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), TIMEOUT);
  try {
    const r = await fetch(url, { signal: ctrl.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
    return await r.text();
  } finally {
    clearTimeout(to);
  }
}

/* ------------------------------- Binance ------------------------------- */
async function binanceCandles(inst, limit = 300) {
  const path = `/api/v3/klines?symbol=${inst.src.klines}&interval=${inst.src.interval}&limit=${limit}`;
  const { text } = await anyGet(BINANCE_HOSTS.map((h) => h + path));
  const rows = JSON.parse(text);
  if (!Array.isArray(rows)) throw new Error("binance: unexpected payload");
  return rows.map((r) => ({
    t: r[0],
    o: +r[1],
    h: +r[2],
    l: +r[3],
    c: +r[4],
    v: +r[5],
  }));
}

async function binanceTicker(inst) {
  const path = `/api/v3/ticker/24hr?symbol=${inst.src.ticker}`;
  const { text } = await anyGet(BINANCE_HOSTS.map((h) => h + path));
  const d = JSON.parse(text);
  if (!d || d.lastPrice === undefined) throw new Error("binance ticker: empty");
  return { last: +d.lastPrice, changePct: +d.priceChangePercent, t: Date.now() };
}

/* -------------------------------- Stooq -------------------------------- */
// Stooq serves plain CSV: Symbol,Date,Time,Open,High,Low,Close,Volume
function parseStooqCsv(csv) {
  const lines = String(csv).trim().split(/\r?\n/);
  if (lines.length < 2) throw new Error("stooq: no rows");
  const out = [];
  for (let i = 1; i < lines.length; i++) {
    const p = lines[i].split(",");
    if (p.length < 7) continue;
    const t = Date.parse(`${p[1]}T${p[2] || "00:00:00"}Z`) || Date.parse(p[1]);
    const o = +p[3];
    const h = +p[4];
    const l = +p[5];
    const c = +p[6];
    if (!isFinite(c) || c <= 0) continue;
    out.push({ t, o: o || c, h: h || c, l: l || c, c, v: +(p[7] || 0) });
  }
  if (!out.length) throw new Error("stooq: unparsable rows");
  return out.sort((a, b) => a.t - b.t);
}

async function stooqDaily(inst) {
  const q = encodeURIComponent(inst.src.quote);
  const { text } = await anyGet([
    `/live/stooq/q/d/l/?s=${q}&i=d`,
    `https://stooq.com/q/d/l/?s=${q}&i=d`,
  ]);
  return parseStooqCsv(text).slice(-260);
}

// Stooq intraday (5 min) — used when available for a fresher tape
async function stooqIntraday(inst) {
  const q = encodeURIComponent(inst.src.intraday);
  const { text } = await anyGet([
    `/live/stooq/q/d/l/?s=${q}&i=5`,
    `https://stooq.com/q/d/l/?s=${q}&i=5`,
  ]);
  return parseStooqCsv(text).slice(-180);
}

/* ------------------------ Coinbase (CORS-friendly) ------------------------ */
async function coinbaseCandles(inst, limit = 300) {
  const pair = inst.symbol === "BTCUSD" ? "BTC-USD" : "ETH-USD";
  const rows = await jget(`https://api.exchange.coinbase.com/products/${pair}/candles?granularity=60`);
  if (!Array.isArray(rows)) throw new Error("coinbase: unexpected payload");
  // rows: [ time, low, high, open, close, volume ] newest first
  return rows
    .slice(0, limit)
    .map((r) => ({ t: r[0] * 1000, o: +r[3], h: +r[2], l: +r[1], c: +r[4], v: +r[5] }))
    .sort((a, b) => a.t - b.t);
}

async function coinbaseTicker(inst) {
  const pair = inst.symbol === "BTCUSD" ? "BTC-USD" : "ETH-USD";
  const [tk, stats] = await Promise.all([
    jget(`https://api.exchange.coinbase.com/products/${pair}/ticker`),
    jget(`https://api.exchange.coinbase.com/products/${pair}/stats`).catch(() => null),
  ]);
  const last = +tk.price;
  const open = stats ? +stats.open : last;
  return { last, changePct: open ? ((last - open) / open) * 100 : 0 };
}

/* ------------------- Frankfurter (ECB FX, CORS-friendly) ------------------ */
// Free, keyless, CORS-enabled. Daily ECB reference rates, but genuinely real.
async function frankfurterCandles(days = 120) {
  const end = new Date();
  const start = new Date(Date.now() - days * 864e5);
  const iso = (d) => d.toISOString().slice(0, 10);
  const d = await jget(`https://api.frankfurter.app/${iso(start)}..${iso(end)}?from=EUR&to=USD`);
  if (!d || !d.rates) throw new Error("frankfurter: unexpected payload");
  return Object.entries(d.rates)
    .map(([date, r]) => ({ t: Date.parse(date + "T00:00:00Z"), o: r.USD, h: r.USD, l: r.USD, c: r.USD, v: 0 }))
    .sort((a, b) => a.t - b.t);
}

/* ------------------------------ public API ----------------------------- */
export async function fetchHistory(symbol, { preferIntraday = true } = {}) {
  const inst = bySymbol(symbol);
  if (!inst) throw new Error("unknown symbol");

  if (inst.source === "binance") {
    try {
      const candles = await binanceCandles(inst);
      return { candles, live: true, granularity: inst.src.interval };
    } catch (e) {
      // Binance can be geo-blocked — Coinbase carries the same coins
      if (inst.assetClass === "crypto") {
        const candles = await coinbaseCandles(inst);
        return { candles, live: true, granularity: "1m" };
      }
      throw e;
    }
  }

  // gold has a tokenised, CORS-friendly proxy on Binance: PAXG tracks spot gold
  if (symbol === "XAUUSD") {
    try {
      const rows = await jget(
        `https://data-api.binance.vision/api/v3/klines?symbol=PAXGUSDT&interval=5m&limit=300`
      );
      if (Array.isArray(rows) && rows.length) {
        return {
          candles: rows.map((r) => ({ t: r[0], o: +r[1], h: +r[2], l: +r[3], c: +r[4], v: +r[5] })),
          live: true,
          granularity: "5m (PAXG proxy)",
        };
      }
    } catch {
      /* fall through to FX/other sources */
    }
  }

  // EURUSD has a keyless CORS-enabled ECB feed
  if (symbol === "EURUSD") {
    try {
      const candles = await frankfurterCandles();
      if (candles.length > 20) return { candles, live: true, granularity: "1d (ECB)" };
    } catch {
      /* fall through to stooq */
    }
  }
  // stooq: try the 5-minute series first, fall back to daily history
  if (preferIntraday) {
    try {
      const intraday = await stooqIntraday(inst);
      if (intraday.length > 20) {
        const last = intraday[intraday.length - 1];
        if (Date.now() - last.t < 1000 * 60 * 60 * 40) {
          return { candles: intraday, live: true, granularity: "5m" };
        }
      }
    } catch {
      /* fall through to daily */
    }
  }
  const daily = await stooqDaily(inst);
  return { candles: daily, live: true, granularity: "1d" };
}

export async function pollTicker(symbol) {
  const inst = bySymbol(symbol);
  if (!inst) throw new Error("unknown symbol");
  if (inst.source === "binance") {
    try {
      return await binanceTicker(inst);
    } catch {
      const t = await coinbaseTicker(inst);
      return { ...t, live: true };
    }
  }
  // For the stooq universe we refresh the latest candles; the tick engine
  // derives the newest print from the freshest bar.
  const { candles, granularity } = await fetchHistory(symbol);
  const last = candles[candles.length - 1];
  const prev = candles[candles.length - 2] || last;
  return {
    last: last.c,
    changePct: ((last.c - prev.c) / prev.c) * 100,
    at: last.t,
    granularity,
    candles,
  };
}

export async function loadAll(symbols = INSTRUMENTS.map((i) => i.symbol)) {
  const results = await Promise.allSettled(symbols.map((s) => fetchHistory(s)));
  const out = {};
  results.forEach((r, i) => {
    out[symbols[i]] = r.status === "fulfilled" ? r.value : { error: String(r.reason?.message || r.reason) };
  });
  return out;
}

export const POLL_MS = 8000;

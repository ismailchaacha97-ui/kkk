// Headless check of the floor's behaviour using recorded candles (no network).
// Usage: node tools/simcheck.mjs [ticks]
import { Market, Account, buildBrief } from "../src/engine/market.js";
import { Trader, ARCHETYPES } from "../src/engine/traders.js";
import { aggregate } from "../src/engine/consensus.js";
import { INSTRUMENTS } from "../src/engine/instruments.js";
import { Floor } from "../src/engine/floor.js";

globalThis.localStorage = { getItem: () => null, setItem: () => {}, removeItem: () => {} };

const TICKS = Number(process.argv[2] || 1200);

// deterministic synthetic-but-realistic candles so the check is reproducible
function candles(base, vol, n = 240, seed = 42) {
  let s = seed, px = base, out = [];
  const rnd = () => ((s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  for (let i = 0; i < n; i++) {
    const o = px;
    let h = o, l = o, c = o;
    const drift = Math.sin(i / 37) * vol * 0.35;
    for (let k = 0; k < 7; k++) { c += (rnd() - 0.5) * vol + drift; h = Math.max(h, c); l = Math.min(l, c); }
    out.push({ t: Date.now() - (n - i) * 60000, o, h, l, c, v: 100 + rnd() * 900 });
    px = c;
  }
  return out;
}

const bases = { BTCUSD: 96000, ETHUSD: 3200, EURUSD: 1.08, XAUUSD: 2650, NAS100: 20500, AAPL: 230 };
const vols = { BTCUSD: 120, ETHUSD: 6, EURUSD: 0.0006, XAUUSD: 1.8, NAS100: 12, AAPL: 0.5 };

const floor = new Floor({ restore: false });
for (const inst of INSTRUMENTS) {
  floor.market.seed(inst.symbol, {
    candles: candles(bases[inst.symbol], vols[inst.symbol], 240, inst.symbol.length * 7),
    granularity: "1m",
    live: true,
  });
}
floor.feedStatus = "live (recorded test data)";
floor.feedDetail = "test harness";
// stub the network refresh so the harness never touches the web
floor.refresh = async () => [];
floor.lastPollAt = Date.now();

floor.hire("test hire");

// simulate a moving live feed: drift each symbol's real target every tick
let seed = 7;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const gauss = () => Math.sqrt(-2 * Math.log(rnd() || 0.5)) * Math.cos(2 * Math.PI * rnd());
for (let i = 0; i < TICKS; i++) {
  for (const inst of INSTRUMENTS) {
    const f = floor.market.feeds[inst.symbol];
    f.target = Math.max(f.target * 0.5, f.target + gauss() * vols[inst.symbol] * 1.6);
  }
  floor.onTick();
  floor.lastPollAt = Date.now();
}

const s = floor.summary();
console.log("=== FLOOR AFTER", TICKS, "TICKS ===");
console.log("traders:", s.traders, "generations:", s.generations, "lessons:", s.lessons);
console.log("debates:", s.debates, "holds:", s.holds, "solo:", s.soloTrades, "contradictions:", s.contradictions);
console.log("hires:", s.hires, "fires:", s.fires, "evolutions:", s.evolutions);
console.log("fills:", s.fills, "closed:", s.closed, "winRate:", s.winRate.toFixed(1) + "%");
console.log("equity:", s.equity.toFixed(2), "pnl:", s.pnl.toFixed(2), "gross:", s.gross.toFixed(2) + "x");
console.log("\n-- roster --");
for (const a of floor.agents) {
  console.log(
    `${a.name.padEnd(8)} ${a.archetypeName.padEnd(14)} gen${a.generation} eq ${a.equity.toFixed(0).padStart(6)} ` +
    `w/l ${a.wins}/${a.losses} mood ${a.mood.padEnd(8)} rep ${a.reputation.toFixed(2)} beliefs: ${a.beliefs[0] || "-"}`
  );
}
console.log("\n-- last lessons --");
floor.agents.slice(0, 4).forEach((a) => console.log(` ${a.name}: ${a.lessons.slice(0, 2).map((l) => l.text).join(" | ") || "-"}`));
console.log("\n-- sample debate --");
const d = floor.debates.find((x) => x.messages.length > 4) || floor.debates[0];
if (d) {
  console.log(`${d.symbol} -> ${d.signal} (${d.rule}) ${d.comment}`);
  d.messages.slice(0, 7).forEach((m) => console.log(`  [${m.name || m.speaker}] ${m.text.slice(0, 130)}`));
}
console.log("\n-- log tail --");
floor.log.slice(0, 8).forEach((l) => console.log(` ${l.kind}: ${l.text.slice(0, 110)}`));

// assertions
const fail = [];
if (s.debates < 5) fail.push("too few debates");
if (s.fills < 1) fail.push("no fills");
if (s.lessons < 3) fail.push("agents are not learning");
if (floor.agents.some((a) => !a.beliefs.length)) fail.push("some agents have no beliefs");
if (s.equity <= 0) fail.push("account blew up");
if (fail.length) { console.error("\nFAILURES:", fail.join(", ")); process.exit(1); }
console.log("\nOK — agents debate, act, learn and evolve.");

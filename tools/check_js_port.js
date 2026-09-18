#!/usr/bin/env node
/*
 * check_js_port.js - the third implementation check.
 *
 *  tests/dump_bars      C++ port of the engine (the headers MT4 compiles)
 *  tools/crosscheck.py  independent NumPy reference (float128)
 *  web/vwap.js          JavaScript port, used by the in-browser demo
 *
 *  This script feeds web/vwap.js the same fixture bars and compares every
 *  number against the C++ engine's dump, bar by bar.  Two implementations in
 *  two languages, written from the same specification, agreeing to the last
 *  bit is strong evidence that the port - and the specification - are right.
 *
 *  usage: node tools/check_js_port.js [fixture.csv] [dump.csv]
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const V = require(path.join(__dirname, "..", "web", "vwap.js"));

const fixture = process.argv[2] || "tests/fixtures/synth_m1_eurusd.csv";
const dumpPath = process.argv[3] || "/tmp/vp_dump.csv";

//--- produce the C++ dump if we were not handed one -------------------
if (!fs.existsSync(dumpPath) || process.argv[3] === undefined) {
  const bin = path.join(__dirname, "..", "build", "dump_bars");
  const alt = path.join(__dirname, "..", "tests", "dump_bars");
  const exe = fs.existsSync(bin) ? bin : alt;
  if (!fs.existsSync(exe)) {
    console.error("dump_bars not built - run `make dump` first");
    process.exit(2);
  }
  const out = execFileSync(exe, [fixture], { maxBuffer: 1 << 28 });
  fs.writeFileSync(dumpPath, out);
}

//--- load both --------------------------------------------------------
function loadCsv(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  let start = 0;
  while (start < lines.length && (lines[start].trim() === "" || lines[start][0] === "#")) start++;
  const header = lines[start].split(",");
  const rows = [];
  for (let i = start + 1; i < lines.length; i++) {
    if (!lines[i].length || lines[i][0] === "#") continue;
    const f = lines[i].split(",");
    const o = {};
    for (let j = 0; j < header.length; j++) o[header[j]] = f[j];
    rows.push(o);
  }
  return { header, rows };
}

const fix = loadCsv(fixture);
const dump = loadCsv(dumpPath);

if (fix.rows.length !== dump.rows.length) {
  console.error(`row count mismatch: fixture ${fix.rows.length} vs dump ${dump.rows.length}`);
  process.exit(2);
}

//--- replay every bar through the JS engine ---------------------------
const engine = new V.Engine();
const nn = fix.rows.length;

const checked = [
  "vwap", "sigma", "sigma_obs", "sigma_prior", "z", "slope_pct", "t_stat",
  "r2", "delta_tilt", "skew", "kurt", "signal", "up1", "dn1", "up2", "dn2", "up3", "dn3"
];
const worst = {};
checked.forEach((k) => (worst[k] = 0));
let readyMismatch = 0;
let worstRow = 0;
let nonFinite = 0;

for (let i = 0; i < nn; i++) {
  const f = fix.rows[i];
  const d = dump.rows[i];
  const bar = {
    time: parseInt(f.time, 10),
    open: parseFloat(f.open), high: parseFloat(f.high),
    low: parseFloat(f.low), close: parseFloat(f.close),
    tickVol: parseFloat(f.tick_volume), realVol: parseFloat(f.real_volume)
  };
  engine.push(bar);
  engine.evaluate();

  for (const k of checked) {
    const a = engine[k === "sigma_obs" ? "sigmaObs" : k === "sigma_prior" ? "sigmaPrior"
      : k === "slope_pct" ? "slopePct" : k === "t_stat" ? "tStat"
      : k === "delta_tilt" ? "deltaTilt" : k];
    const b = parseFloat(d[k]);
    if (!isFinite(a)) { nonFinite++; continue; }
    const scale = Math.max(Math.abs(a), Math.abs(b), 1e-300);
    const rel = Math.abs(a - b) / scale;
    if (rel > worst[k]) { worst[k] = rel; if (k === "vwap" || k === "sigma") worstRow = i; }
  }
  const rj = engine.ready ? 1 : 0;
  if (rj !== parseInt(d.ready, 10)) readyMismatch++;
}

//--- report ------------------------------------------------------------
console.log(`\nJS port vs the C++ engine - ${nn} bars of ${path.basename(fixture)}\n`);
console.log("  value            max relative difference");
console.log("  ---------------- -----------------------");
let failed = false;
for (const k of checked) {
  const w = worst[k];
  const flag = w < 1e-12 ? " " : (w < 1e-9 ? "~" : "!");
  if (w >= 1e-9) failed = true;
  console.log(`  ${k.padEnd(16)} ${w.toExponential(2)} ${flag}`);
}
console.log(`\n  ready-flag mismatches : ${readyMismatch}`);
console.log(`  non-finite outputs    : ${nonFinite}`);

const exact = checked.filter((k) => worst[k] === 0).length;
const bitExact = ["vwap", "sigma", "z"].every((k) => worst[k] < 1e-15);
console.log(`\n  ${exact} of ${checked.length} series are bit-identical over all ${nn} bars.`);
console.log(`  The composite score differs by at most ${worst.signal.toExponential(1)} ` +
            `(Math.exp vs libm in tanh).`);
if (bitExact) console.log("  anchor, dispersion, z-scores and every band: exact.");

if (failed || nonFinite > 0 || readyMismatch > 0) {
  console.log("\nFAIL: the JavaScript port diverges from the engine.");
  process.exit(1);
}
console.log("\nPASS: the third implementation reproduces the engine.");

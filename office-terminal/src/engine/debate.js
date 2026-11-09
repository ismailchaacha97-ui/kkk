// The debate desk: three analysts with deliberately different "lenses" over the same
// market briefing, plus a deterministic arbiter. Ported from the MQL5 architecture
// (Victor / Maria / Alexei / Arbiter) into a browser-side, dependency-free engine.
import { buildBrief } from "./market.js";

export const ANALYSTS = {
  victor: {
    id: "victor",
    name: "Victor",
    role: "Bull Analyst",
    color: "#5ceb8e",
    desk: "trend",
    personality: "aggressive trend-follower, relentless optimist",
  },
  maria: {
    id: "maria",
    name: "Maria",
    role: "Bear Analyst",
    color: "#f26457",
    desk: "contrarian",
    personality: "skeptical contrarian, sees danger where others see opportunity",
  },
  alexei: {
    id: "alexei",
    name: "Alexei",
    role: "Risk Manager",
    color: "#f5b841",
    desk: "risk",
    personality: "volatility specialist; does not care about direction at all",
  },
};

export const JUDGE = {
  id: "judge",
  name: "The Arbiter",
  role: "Judge / Senior PM",
  color: "#c9a7ff",
  desk: "arbiter",
};

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

/* ------------------------------ ANALYSTS ------------------------------ */
// Each returns { stance: 'buy'|'sell'|'neutral', confidence: 0..1, text, bullets[] }

export function victor(brief) {
  const s = [];
  let score = 0;
  if (brief.trendAbove.sma20) { score += 1.1; s.push("Price holds above SMA20"); }
  if (brief.trendAbove.sma50) { score += 0.9; s.push("SMA50 sits underneath as bid support"); }
  if (brief.rsi14 > 52 && brief.rsi14 < 74) { score += 0.8; s.push(`RSI14 at ${brief.rsi14.toFixed(1)} — momentum leaning up, not exhausted`); }
  if (brief.rsi14 < 32) { score += 0.7; s.push("RSI is coming out of oversold"); }
  if (brief.bbPos === "BELOW LOWER") { score += 0.9; s.push("Lower-band pierce: mean-reversion snap-back setup"); }
  if (brief.volRatio > 1.25 && brief.candle.c > brief.candle.o) { score += 0.7; s.push("Volume surge on a bullish candle — real buyers, not drift"); }
  if (brief.bodyAtr > 0.15 && brief.candle.c > brief.candle.o) { score += 0.4; s.push("Constructive candle body closing near the highs"); }
  if (brief.lowerWickPct > 0.3) { score += 0.5; s.push("Long lower wick: dip was bought aggressively"); }
  const conf = clamp(score / 3.2, 0.15, 0.97);
  const stance = score > 1.35 ? "buy" : "neutral";
  return {
    stance,
    confidence: conf,
    bullets: s.slice(0, 3),
    text:
      stance === "buy"
        ? `I'm a buyer. ${s.slice(0, 2).join(", ")}. ${s[2] ? s[2] + "." : ""} This is a clean with-trend continuation — I'd size it now, not after the breakout print.`
        : `I want to like this but nothing is confirmed yet. ${s[0] || "We're between levels"} — I'd wait for the market to prove the bid before I commit capital.`,
  };
}

export function maria(brief) {
  const s = [];
  let score = 0;
  if (!brief.trendAbove.sma20) { score += 1.1; s.push("Price is trapped below SMA20"); }
  if (!brief.trendAbove.sma50) { score += 0.8; s.push("SMA50 is now overhead supply"); }
  if (brief.rsi14 > 66) { score += 1.1; s.push(`RSI14 at ${brief.rsi14.toFixed(1)} — overbought, late buyers only`); }
  if (brief.rsi14 < 46 && brief.rsi14 > 22) { score += 0.6; s.push("RSI rolling over, momentum decaying"); }
  if (brief.bbPos === "ABOVE UPPER") { score += 1.0; s.push("Stretched above the upper Bollinger band — a fade, not a chase"); }
  if (brief.upperWickPct > 0.3) { score += 0.8; s.push(`Upper wick is ${(brief.upperWickPct * 100).toFixed(0)}% of the range — someone is selling every rally`); }
  if (brief.candle.c < brief.candle.o) { score += 0.4; s.push("Last candle closed red"); }
  const conf = clamp(score / 3.2, 0.15, 0.97);
  const stance = score > 1.35 ? "sell" : "neutral";
  return {
    stance,
    confidence: conf,
    bullets: s.slice(0, 3),
    text:
      stance === "sell"
        ? `I'm on the other side of this. ${s.slice(0, 2).join(", ")}. ${s[2] ? s[2] + "." : ""} Buying here means paying retail for smart money's exit liquidity.`
        : `I can't build a bear case on this data — ${s[0] || "structure is unremarkable"}. Being flat is a position too; I'll pass this round.`,
  };
}

export function alexei(brief) {
  const atrPct = brief.atr / brief.price;
  const flags = [];
  let risk = 0;
  if (brief.volRatio > 1.9) { risk += 2; flags.push(`Volume ${brief.volRatio.toFixed(1)}x normal — news-driven tape`); }
  else if (brief.volRatio > 1.35) { risk += 1; flags.push(`Volume elevated at ${brief.volRatio.toFixed(1)}x normal`); }
  if (brief.bodyAtr > 0.9) { risk += 2; flags.push(`Candle body is ${brief.bodyAtr.toFixed(1)}x ATR — entering now is chasing`); }
  else if (brief.bodyAtr > 0.55) { risk += 1; flags.push(`Body ${brief.bodyAtr.toFixed(1)}x ATR — late entry`); }
  if (brief.bbPos === "ABOVE UPPER" || brief.bbPos === "BELOW LOWER") { risk += 1; flags.push("Price outside the bands: volatility expansion in progress"); }
  if (atrPct > 0.0022) { risk += 1; flags.push(`ATR is ${(atrPct * 100).toFixed(2)}% of price — abnormally wide`); }
  const verdict = risk >= 3 ? "HIGH RISK" : risk >= 2 ? "MEDIUM RISK" : "LOW RISK";
  const conf = verdict === "LOW RISK" ? 0.85 : verdict === "MEDIUM RISK" ? 0.55 : 0.9;
  return {
    stance: "neutral",
    confidence: conf,
    risk,
    verdict,
    bullets: flags.length ? flags.slice(0, 3) : ["ATR normal, bands stable, candle body inside one ATR — orderly tape"],
    text:
      `${verdict}. ${flags.length ? flags.slice(0, 2).join(". ") + "." : "Volatility is inside its normal envelope, bands aren't stretched, and the candle body is smaller than one ATR — this is a tradable, orderly tape."} I don't do direction; I do survivability. ${verdict === "HIGH RISK" ? "Today I would not want exposure." : "Size it sanely and I'll sign it."}`,
  };
}

/* ------------------------------- JUDGE -------------------------------- */
// Deterministic rules, temperature-0.2 equivalent: same input -> same verdict.
export function judge(brief, ops, opts = {}) {
  const { requireAgreement = 2, minConviction = 0.42 } = opts;
  const riskVerdict = ops.alexei.verdict;
  const vStance = ops.victor.stance;
  const mStance = ops.maria.stance;
  const vc = ops.victor.confidence;
  const mc = ops.maria.confidence;

  if (riskVerdict === "HIGH RISK") {
    return {
      signal: "hold",
      comment: "Risk desk veto: HIGH RISK. No exceptions, regardless of direction.",
      rule: "R1 — risk veto",
      blocked: true,
      votes: { buy: vStance === "buy" ? 1 : 0, sell: mStance === "sell" ? 1 : 0 },
    };
  }

  const buyVotes = (vStance === "buy" ? 1 : 0) + (riskVerdict !== "HIGH RISK" && vc > 0.7 ? 1 : 0);
  const sellVotes = (mStance === "sell" ? 1 : 0) + (mc > 0.7 ? 1 : 0);

  if (vStance === "buy" && mStance === "sell") {
    // Rule 3 — conflicting, MEDIUM risk: pick the stronger argument (needs conviction edge)
    if (riskVerdict === "MEDIUM RISK" && Math.abs(vc - mc) > 0.18) {
      const win = vc > mc ? "buy" : "sell";
      return {
        signal: win,
        comment: `${win.toUpperCase()} on conviction edge (${(Math.max(vc, mc) * 100) | 0}% vs ${(Math.min(vc, mc) * 100) | 0}%) — risk MEDIUM, counter-argument logged.`,
        rule: "R3 — stronger argument",
        votes: { buy: win === "buy" ? 2 : 1, sell: win === "sell" ? 2 : 1 },
      };
    }
    return {
      signal: "hold",
      comment: "Direct bull/bear conflict of equal weight. Honest answer to uncertainty is no trade.",
      rule: "R2 — unresolved conflict",
      blocked: false,
      votes: { buy: 1, sell: 1 },
    };
  }

  if (vStance === "buy" && vc >= minConviction) {
    return {
      signal: "buy",
      comment: `Bull/Risk consensus — Victor ${(vc * 100) | 0}%, risk ${riskVerdict}. ${mStance === "neutral" ? "Bear abstained." : "Bear outvoted."}`,
      rule: "R2 — 2 of 3 agree",
      votes: { buy: buyVotes, sell: sellVotes },
    };
  }
  if (mStance === "sell" && mc >= minConviction) {
    return {
      signal: "sell",
      comment: `Bear/Risk consensus — Maria ${(mc * 100) | 0}%, risk ${riskVerdict}. ${vStance === "neutral" ? "Bull abstained." : "Bull outvoted."}`,
      rule: "R2 — 2 of 3 agree",
      votes: { buy: buyVotes, sell: sellVotes },
    };
  }
  return {
    signal: "hold",
    comment: "No analyst reached conviction threshold. Standing down — silence is a signal.",
    rule: "R4 — no conviction",
    votes: { buy: buyVotes, sell: sellVotes },
  };
}

export function runDebate(market, symbol, opts) {
  const brief = buildBrief(market, symbol);
  const ops = { victor: victor(brief), maria: maria(brief), alexei: alexei(brief) };
  const verdict = judge(brief, ops, opts);
  return {
    symbol,
    brief,
    opinions: ops,
    verdict,
    startedAt: Date.now(),
    finishedAt: Date.now() + 1,
  };
}

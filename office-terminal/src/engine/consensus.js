// Turning a room full of opinions into a house decision.
// The rules are hard-coded and visible in the UI:
//   R1  a HIGH-risk read vetoes everything
//   R2  the house only acts when at least two independent reads agree
//   R3  a genuine stand-off is not resolved by flipping a coin — it is a HOLD
import { clamp } from "./util.js";

export function riskRead(brief) {
  if (!brief) return { verdict: "MEDIUM RISK", score: 1, flags: ["no data"] };
  const flags = [];
  let score = 0;
  if (brief.atrPct > 0.004) { score += 2; flags.push(`ATR ${(brief.atrPct * 100).toFixed(2)}% of price — violent tape`); }
  else if (brief.atrPct > 0.0022) { score += 1; flags.push(`ATR ${(brief.atrPct * 100).toFixed(2)}% — wider than usual`); }
  if (brief.bodyAtr > 0.95) { score += 2; flags.push(`candle body ${brief.bodyAtr.toFixed(1)}× ATR — chasing`); }
  else if (brief.bodyAtr > 0.6) { score += 1; flags.push(`body ${brief.bodyAtr.toFixed(1)}× ATR — late entry`); }
  if (brief.bbPos === "ABOVE UPPER" || brief.bbPos === "BELOW LOWER") { score += 1; flags.push("price outside the bands"); }
  if (brief.volRatio > 1.9) { score += 1; flags.push(`relative volume ${brief.volRatio.toFixed(1)}×`); }
  const verdict = score >= 3 ? "HIGH RISK" : score >= 2 ? "MEDIUM RISK" : "LOW RISK";
  return { verdict, score, flags: flags.slice(0, 3) };
}

export function aggregate(reads, opts = {}) {
  const seated = reads.filter((r) => r && r.stance);
  const risk = riskRead(opts.brief);
  if (risk.verdict === "HIGH RISK") {
    return {
      signal: "hold",
      rule: "R1 · risk veto",
      comment: `Risk read is HIGH — ${risk.flags[0] || "tape too violent"}. Nobody trades this.`,
      risk,
      votes: { buy: 0, sell: 0, hold: seated.length },
    };
  }
  const buy = seated.filter((r) => r.stance === "buy");
  const sell = seated.filter((r) => r.stance === "sell");
  const buyWeight = buy.reduce((a, r) => a + r.conviction, 0);
  const sellWeight = sell.reduce((a, r) => a + r.conviction, 0);
  const need = opts.requireAgreement ?? 2;

  if (buy.length >= need && buyWeight > sellWeight * 1.15) {
    return {
      signal: "buy",
      rule: "R2 · agreement",
      comment: `${buy.length} of ${seated.length} reads are long (${(buyWeight / Math.max(1, buy.length) * 100) | 0}% avg conviction), risk ${risk.verdict}.`,
      risk,
      votes: { buy: buy.length, sell: sell.length, hold: seated.length - buy.length - sell.length },
    };
  }
  if (sell.length >= need && sellWeight > buyWeight * 1.15) {
    return {
      signal: "sell",
      rule: "R2 · agreement",
      comment: `${sell.length} of ${seated.length} reads are short (${(sellWeight / Math.max(1, sell.length) * 100) | 0}% avg conviction), risk ${risk.verdict}.`,
      risk,
      votes: { buy: buy.length, sell: sell.length, hold: seated.length - buy.length - sell.length },
    };
  }
  // R2b — a single, very high conviction read with nobody arguing the other way
  if (buy.length === 1 && sell.length === 0 && buy[0].conviction > 0.62) {
    return {
      signal: "buy",
      rule: "R2b · lone conviction",
      comment: `${buy[0].name || "One desk"} is ${(buy[0].conviction * 100) | 0}% long and nobody is arguing the other side. Small size.`,
      risk,
      votes: { buy: 1, sell: 0, hold: seated.length - 1 },
    };
  }
  if (sell.length === 1 && buy.length === 0 && sell[0].conviction > 0.62) {
    return {
      signal: "sell",
      rule: "R2b · lone conviction",
      comment: `${sell[0].name || "One desk"} is ${(sell[0].conviction * 100) | 0}% short and nobody is arguing the other side. Small size.`,
      risk,
      votes: { buy: 0, sell: 1, hold: seated.length - 1 },
    };
  }
  if (buy.length && sell.length) {
    return {
      signal: "hold",
      rule: "R3 · stand-off",
      comment: `The room is split ${buy.length}–${sell.length}. Nobody has earned the right to size this.`,
      risk,
      votes: { buy: buy.length, sell: sell.length, hold: seated.length - buy.length - sell.length },
    };
  }
  return {
    signal: "hold",
    rule: "R4 · no conviction",
    comment: `${seated.length} reads, none cleared the conviction bar. Silence is a position.`,
    risk,
    votes: { buy: 0, sell: 0, hold: seated.length },
  };
}

export function confidenceOf(reads) {
  const seated = reads.filter((r) => r?.stance);
  if (!seated.length) return 0;
  return clamp(seated.reduce((a, r) => a + r.conviction, 0) / seated.length, 0, 1);
}

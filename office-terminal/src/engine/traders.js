// Autonomous trading agents: each one has heritable traits, a learned signal
// model, a memory of her own results, a mood, and enough free will to ignore
// the house view and act on her own — or to refuse to trade at all.

import { clamp, pick } from "./util.js";

const gauss = () => {
  let u = 0;
  let v = 0;
  while (!u) u = Math.random();
  while (!v) v = Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};

export const NAMES = [
  "Victor", "Maria", "Alexei", "Nadia", "Kenji", "Amara", "Diego", "Ilse",
  "Omar", "Sofia", "Lucas", "Priya", "Ravi", "Zoe", "Marcus", "Lina",
  "Hugo", "Aylin", "Noor", "Theo", "Mira", "Jonas", "Chiara", "Tarek",
];

export const ARCHETYPES = [
  { id: "trend", name: "Trend follower", hint: "rides momentum until it breaks",
    traits: { bias: 0.35, aggression: 0.7, caution: 0.35, contrarian: 0.05, momentum: 0.9, volLove: 0.5, patience: 0.6, social: 0.5, discipline: 0.6, curiosity: 0.5 } },
  { id: "contrarian", name: "Contrarian", hint: "fades stretched moves",
    traits: { bias: -0.2, aggression: 0.6, caution: 0.55, contrarian: 0.9, momentum: 0.2, volLove: 0.4, patience: 0.5, social: 0.45, discipline: 0.6, curiosity: 0.6 } },
  { id: "risk", name: "Risk hawk", hint: "small size, tight stops, sleeps well",
    traits: { bias: 0, aggression: 0.3, caution: 0.9, contrarian: 0.3, momentum: 0.3, volLove: 0.15, patience: 0.8, social: 0.4, discipline: 0.9, curiosity: 0.3 } },
  { id: "scalper", name: "Scalper", hint: "in and out, cannot sit still",
    traits: { bias: 0.05, aggression: 0.85, caution: 0.4, contrarian: 0.4, momentum: 0.7, volLove: 0.8, patience: 0.15, social: 0.6, discipline: 0.4, curiosity: 0.7 } },
  { id: "quant", name: "Quant", hint: "trusts the model, not the story",
    traits: { bias: 0, aggression: 0.5, caution: 0.6, contrarian: 0.5, momentum: 0.5, volLove: 0.3, patience: 0.7, social: 0.25, discipline: 0.95, curiosity: 0.8 } },
  { id: "macro", name: "Macro voice", hint: "talks in cycles, trades rarely",
    traits: { bias: 0.15, aggression: 0.45, caution: 0.65, contrarian: 0.5, momentum: 0.35, volLove: 0.35, patience: 0.9, social: 0.85, discipline: 0.7, curiosity: 0.55 } },
];

// each archetype starts from a genuinely different model of the market
export const BASE_WEIGHTS = {
  trend: { trend: 1.25, trendSlow: 0.85, momentum: 1.15, meanrev: -0.35, stretch: 0.15, volatility: 0.1, volume: 0.5, wick: 0.2 },
  contrarian: { trend: -0.7, trendSlow: -0.45, momentum: -0.8, meanrev: 1.3, stretch: -1.15, volatility: -0.2, volume: 0.15, wick: 0.55 },
  risk: { trend: 0.35, trendSlow: 0.3, momentum: 0.25, meanrev: 0.3, stretch: -0.5, volatility: -1.1, volume: -0.45, wick: 0.1 },
  scalper: { trend: 0.55, trendSlow: 0.1, momentum: 0.95, meanrev: 0.45, stretch: -0.5, volatility: 0.65, volume: 0.9, wick: 0.7 },
  quant: { trend: 0.8, trendSlow: 0.6, momentum: 0.55, meanrev: 0.65, stretch: -0.7, volatility: -0.35, volume: 0.45, wick: 0.35 },
  macro: { trend: 0.35, trendSlow: 1.15, momentum: 0.25, meanrev: 0.5, stretch: -0.9, volatility: -0.55, volume: 0.1, wick: 0.15 },
};

export const TRAIT_KEYS = [
  "bias", "aggression", "caution", "contrarian", "momentum",
  "volLove", "patience", "social", "discipline", "curiosity",
];

export const MOODS = {
  focused: { label: "focused", color: "#8cb4ff", aggr: 1.0, risk: 1.0 },
  greedy: { label: "greedy", color: "#5ceb8e", aggr: 1.35, risk: 1.25 },
  fearful: { label: "fearful", color: "#f5b841", aggr: 0.6, risk: 0.55 },
  tilted: { label: "tilted", color: "#f26457", aggr: 1.5, risk: 1.6 },
  bored: { label: "bored", color: "#8697b0", aggr: 1.15, risk: 1.1 },
  euphoric: { label: "euphoric", color: "#c9a7ff", aggr: 1.3, risk: 1.4 },
};

export const FEATURE_LABEL = {
  trend: "Short-term trend",
  trendSlow: "The bigger trend",
  momentum: "Raw momentum",
  meanrev: "Mean reversion",
  stretch: "Band stretch",
  volatility: "Volatility",
  volume: "Volume",
  wick: "Candle wicks",
};

export const FEATURES = ["trend", "trendSlow", "momentum", "meanrev", "stretch", "volatility", "volume", "wick"];

export function extractFeatures(b) {
  return {
    trend: clamp(b.float.mid * 260, -1.6, 1.6),
    trendSlow: clamp(b.float.slow * 140, -1.6, 1.6),
    momentum: clamp(b.mom5 / 1.2, -1.6, 1.6),
    meanrev: clamp((50 - b.rsi) / 26, -1.8, 1.8),
    stretch: clamp((b.bbPos === "ABOVE UPPER" ? 1 : b.bbPos === "BELOW LOWER" ? -1 : 0) + (b.rsi - 50) / 55, -1.8, 1.8),
    volatility: clamp(b.atrPct / 0.0035, 0, 2.4),
    volume: clamp(b.volRatio - 1, -1, 2.4),
    wick: clamp((b.lowerWickPct - b.upperWickPct) * 2, -1.6, 1.6),
  };
}

let seq = 0;

export class Trader {
  constructor(opts = {}) {
    const arch = opts.archetype || pick(ARCHETYPES);
    this.id = opts.id || `t${++seq}_${Math.random().toString(36).slice(2, 6)}`;
    this.name = opts.name || pick(NAMES);
    this.archetype = arch.id;
    this.archetypeName = arch.name;
    this.color = opts.color || pick(["#5ceb8e", "#f26457", "#f5b841", "#c9a7ff", "#8cb4ff", "#f2c078", "#7ee0d4", "#e58cc0"]);
    this.generation = opts.generation ?? 0;
    this.parentId = opts.parentId || null;
    this.bornAt = Date.now();
    this.traits = { ...arch.traits, ...(opts.traits || {}) };
    this.weights = { ...(opts.weights || BASE_WEIGHTS[this.archetype] || BASE_WEIGHTS.quant) };
    this.learningRate = opts.learningRate ?? 0.03 + this.traits.curiosity * 0.085;
    this.mood = "focused";
    this.moodUntil = 0;
    this.moodEnergy = 1;
    this.boredom = Math.random() * 0.4;
    this.quote = "reading the tape…";
    this.lastSpokeAt = 0;
    this.equity = opts.equity ?? 25000;
    this.startEquity = this.equity;
    this.wins = 0;
    this.losses = 0;
    this.fills = 0;
    this.realized = 0;
    this.positions = {};
    this.experiences = []; // { symbol, features, stance, pnl, at }
    this.lessons = []; // strings, newest first
    this.beliefs = opts.beliefs || [];
    this.focusSymbol = null;
    this.lastAction = "reading charts";
    this.lastActionAt = 0;
    this.trades = []; // individual trade log refs
    this.streak = 0;
    this.reputation = 0.5; // peers' opinion, updated by the floor
    this.influence = 0.5;
    this.seeded = !!opts.seeded;
  }

  get total() {
    return this.wins + this.losses;
  }
  get winRate() {
    return this.total ? this.wins / this.total : 0;
  }
  get moodDef() {
    return MOODS[this.mood] || MOODS.focused;
  }

  /* ---------------- perception + judgement (no LLM required) ---------------- */
  read(brief) {
    if (!brief) return { score: 0, features: null, stance: "neutral", conviction: 0 };
    const f = extractFeatures(brief);
    let score = 0;
    for (const k of FEATURES) score += (this.weights[k] || 0) * f[k];
    // personality lens
    score += this.traits.bias * 1.15;
    score *= 0.55 + this.traits.aggression * 0.9;
    score *= this.moodDef.aggr;
    // a cautious trader discounts signals in violent tape
    score *= 1 - clamp(f.volatility - 0.8, 0, 1.6) * this.traits.caution * 0.55;

    const threshold = 0.2 + this.traits.discipline * 0.22 + (this.mood === "fearful" ? 0.18 : 0);
    const conviction = clamp(Math.abs(score) / 1.9, 0, 0.99);
    let stance = "neutral";
    if (score > threshold) stance = "buy";
    else if (score < -threshold) stance = "sell";

    // free will: sometimes a trader just does not trust the read
    const doubt = Math.random();
    if (stance !== "neutral" && doubt < (1 - this.traits.aggression) * 0.22) stance = "neutral";

    return { features: f, score, stance, conviction, threshold, brief };
  }

  /* ---------------- speech ---------------- */
  argue(brief, read) {
    const f = read.features;
    const top = Object.entries(f)
      .sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]))
      .slice(0, 2)
      .map(([k, v]) => `${k} ${v > 0 ? "positive" : "negative"}`);
    const sym = brief.symbol;
    const px = brief.price.toFixed(brief.symbol === "EURUSD" ? 5 : 2);
    if (read.stance === "buy") {
      return pick([
        `I'm long ${sym} at ${px}. ${top.join(", ")} — that's a bid I can lean on. Size it and let it run.`,
        `${sym} is being accumulated, not distributed. ${top[0]} tells me buyers are in control. I want exposure now.`,
        `Everyone waits for confirmation on ${sym}. Confirmation is where the edge dies. ${top.join(" and ")} — I'm a buyer.`,
        `This is the third time ${sym} tested here and held. ${top[0]}. I'd be embarrassed to be flat.`,
      ]);
    }
    if (read.stance === "sell") {
      return pick([
        `${sym} is a short at ${px}. ${top.join(", ")} — the buyers are paying up into supply.`,
        `I'm fading ${sym}. ${top[0]} and nobody wants to admit the move is exhausted.`,
        `Look at the tape, not the story: ${top.join(", ")}. ${sym} goes lower before it goes higher.`,
        `${sym} is distributing. I'd rather sell strength than buy hope.`,
      ]);
    }
    return pick([
      `No trade on ${sym}. ${top[0] || "nothing decisive"} isn't an edge, it's noise.`,
      `I've been burned on setups like this. Sitting out.`,
      `${sym} can do whatever it likes without me. I don't get paid to guess.`,
      `My model says flat. When it changes, I'll change.`,
    ]);
  }

  /* ---------------- learning ---------------- */
  learn(experience) {
    const { features, stance, pnl, symbol } = experience;
    if (!features || !stance || stance === "neutral") return;
    const dir = stance === "buy" ? 1 : -1;
    const outcome = clamp(pnl / Math.max(1, this.equity * 0.01), -1.6, 1.6);
    const lr = this.learningRate * (0.6 + this.traits.discipline * 0.8);
    for (const k of FEATURES) {
      const credit = outcome * features[k] * dir;
      this.weights[k] = clamp((this.weights[k] || 0) + lr * credit, -2.6, 2.6);
    }
    this.experiences.unshift({ symbol, stance, pnl, at: Date.now(), features });
    if (this.experiences.length > 60) this.experiences.pop();

    if (pnl > 0) {
      this.wins++;
      this.streak = Math.max(0, this.streak) + 1;
      if (this.streak >= 3 && Math.random() < 0.5) this.setMood("euphoric");
      if (Math.random() < 0.45) {
        const best = Object.entries(features).sort((a, b) => Math.abs(b[1] * (this.weights[b[0]] || 0)) - Math.abs(a[1] * (this.weights[a[0]] || 0)))[0];
        if (best) this.addLesson(`${symbol}: ${best[0]} paid — I'll weight it harder.`);
      }
    } else {
      this.losses++;
      this.streak = Math.min(0, this.streak) - 1;
      if (this.streak <= -2) this.setMood(Math.random() < 0.6 ? "tilted" : "fearful");
      // the loss-repair lesson names the feature that misled her
      const wrong = Object.entries(features)
        .sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]))
        .map(([k]) => k)[0];
      if (wrong) this.addLesson(`${symbol}: ${wrong} lied to me. Cut the weight, respect the stop.`);
    }
    this.recomputeBeliefs();
  }

  addLesson(text) {
    this.lessons.unshift({ text, at: Date.now(), gen: this.generation });
    if (this.lessons.length > 14) this.lessons.pop();
  }

  recomputeBeliefs() {
    const b = [];
    const w = this.weights;
    const strongest = Object.entries(w).sort((a, c) => Math.abs(c[1]) - Math.abs(a[1]))[0];
    if (strongest) {
      const label = FEATURE_LABEL[strongest[0]] || strongest[0];
      b.push(strongest[1] > 0 ? `${label} is what pays me — I follow it.` : `${label} is a trap — I fade it.`);
    }
    if (this.total >= 4) b.push(`My hit rate is ${(this.winRate * 100).toFixed(0)}% over ${this.total} closed ideas.`);
    if (this.realized > this.startEquity * 0.02) b.push("I am ahead of my own book. I want more rope.");
    if (this.realized < -this.startEquity * 0.02) b.push("My P&L is red. Cut size until it turns.");
    if (this.traits.caution > 0.7) b.push("I would rather miss a move than eat a stop.");
    if (this.traits.aggression > 0.8) b.push("Small size is a slow way to lose.");
    if (this.traits.contrarian > 0.75) b.push("The crowd is right until it is catastrophically wrong.");
    if (this.streak <= -2) b.push("I'm second-guessing myself today.");
    if (this.streak >= 3) b.push("I can't lose right now. Do not touch my sizing.");
    this.beliefs = b.slice(0, 5);
  }

  setMood(mood, ms = 45000) {
    if (!MOODS[mood]) return;
    this.mood = mood;
    this.moodUntil = Date.now() + ms;
  }

  decayMood() {
    if (this.moodUntil && Date.now() > this.moodUntil) {
      this.mood = this.streak >= 3 ? "greedy" : this.streak <= -2 ? "fearful" : "focused";
      this.moodUntil = 0;
    }
    this.boredom = clamp(this.boredom + 0.004 + this.traits.curiosity * 0.004, 0, 1.4);
  }

  /* ---------------- sizing ---------------- */
  sizeFor(equity, price, stopPct) {
    const base = equity * (0.008 + this.traits.aggression * 0.022) * this.moodDef.aggr;
    const riskAdjusted = base / Math.max(0.004, stopPct);
    return Math.min(riskAdjusted, equity * 0.8) / price;
  }

  stopPct() {
    return clamp(0.004 + this.traits.caution * 0.009 + (this.mood === "fearful" ? 0.004 : 0), 0.004, 0.02);
  }

  /* ---------------- heredity ---------------- */
  spawn(parentName) {
    const traits = {};
    for (const k of TRAIT_KEYS) {
      traits[k] = clamp(this.traits[k] + gauss() * 0.09, 0, 1);
    }
    const weights = {};
    for (const k of FEATURES) weights[k] = clamp((this.weights[k] || 0) + gauss() * 0.12, -2.6, 2.6);
    const child = new Trader({
      traits,
      weights,
      generation: this.generation + 1,
      parentId: this.id,
      archetype: ARCHETYPES.find((a) => a.id === this.archetype) || pick(ARCHETYPES),
      learningRate: clamp(this.learningRate + gauss() * 0.02, 0.02, 0.3),
      color: this.color,
    });
    child.addLesson(`Hired from ${parentName}'s playbook (gen ${child.generation}).`);
    child.recomputeBeliefs();
    return child;
  }

  serialize() {
    return {
      id: this.id, name: this.name, archetype: this.archetype, archetypeName: this.archetypeName,
      color: this.color, generation: this.generation, parentId: this.parentId,
      traits: this.traits, weights: this.weights, learningRate: this.learningRate,
      equity: this.equity, startEquity: this.startEquity, wins: this.wins, losses: this.losses,
      fills: this.fills, realized: this.realized, lessons: this.lessons.slice(0, 8),
      beliefs: this.beliefs, streak: this.streak, reputation: this.reputation,
      experiences: this.experiences.slice(0, 12), mood: this.mood,
    };
  }

  static deserialize(o) {
    const t = Object.create(Trader.prototype);
    Object.assign(t, {
      moodEnergy: 1, boredom: Math.random() * 0.3, quote: "back at the desk…",
      lastSpokeAt: 0, positions: {}, focusSymbol: null, lastAction: "reading charts",
      lastActionAt: 0, trades: [], moodUntil: 0, influence: 0.5, seeded: true,
    }, o);
    return t;
  }
}

/* ------------------- free-will action selection ------------------- */
// Returns an intent. The floor decides whether it is allowed to happen.
export function chooseAction(trader, ctx) {
  const t = trader.traits;
  const boredBias = clamp(trader.boredom, 0, 1);
  const tilt = trader.mood === "tilted" ? 1.5 : 1;
  const options = [
    ["study", 1.0 * t.curiosity * (0.6 + boredBias)],
    ["debate", 1.1 * (t.aggression + t.social) * (0.5 + boredBias)],
    ["impulse", 0.85 * t.aggression * t.discipline * 0.4 * tilt],
    ["chat", 0.9 * t.social],
    ["rest", 0.5 * (1 - t.aggression) + (trader.mood === "tilted" ? 1.2 : 0)],
    ["contradict", 0.35 * t.contrarian * (ctx?.lastVerdict === "hold" ? 1.8 : 1)],
  ];
  const total = options.reduce((a, [, w]) => a + Math.max(0, w), 0);
  let r = Math.random() * total;
  for (const [name, w] of options) {
    r -= Math.max(0, w);
    if (r <= 0) return name;
  }
  return "study";
}

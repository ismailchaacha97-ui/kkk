// The floor director. It does not script anybody: it gives every trader a
// market, a personality and a clock, then lets them choose. Debates, solo
// trades, arguments with the house, walks to the whiteboard, hirings and
// firings all emerge from the agents' own traits, moods, memories and models.
import { Market, Account, buildBrief } from "./market.js";
import { INSTRUMENTS, bySymbol } from "./instruments.js";
import { Trader, ARCHETYPES, NAMES, chooseAction, MOODS } from "./traders.js";
import { aggregate, riskRead, confidenceOf } from "./consensus.js";
import { clamp, pick, uid } from "./util.js";

export { TICK_MS } from "./market.js";

const ROSTER_SEED = [
  { archetype: "trend", name: "Victor" },
  { archetype: "contrarian", name: "Maria" },
  { archetype: "risk", name: "Alexei" },
  { archetype: "quant", name: "Priya" },
  { archetype: "scalper", name: "Kenji" },
  { archetype: "macro", name: "Amara" },
];

const STORAGE_KEY = "meridian:floor:v2";

export class Floor {
  constructor({ restore = true } = {}) {
    this.market = new Market();
    this.account = new Account();
    this.agents = [];
    this.debates = [];
    this.log = [];
    this.alerts = [];
    this.chat = []; // open mic channel between desks
    this.tick = 0;
    this.paused = false;
    this.startedAt = Date.now();
    this.cashDayStart = this.account.equity(this.market);
    this.houseRules = {
      minVotes: 2,
      maxNames: 6,
      maxGross: 3.2,
      maxAgentExposure: 0.55, // notional cap per agent, as a fraction of her own equity
      allowSolo: true, // free will: agents may act without a vote
      allowHouseOverride: true,
      evolveOnLoss: true,
      autoHire: true,
      maxHoldTicks: 1200,
    };
    this.stats = { debates: 0, votes: 0, holds: 0, soloTrades: 0, contradictions: 0, hires: 0, fires: 0, evolutions: 0 };
    this.feedStatus = "connecting";
    this.feedDetail = "connecting to public market feeds…";
    this.pending = [];
    this.lastPollAt = 0;
    this.failureStreak = 0;

    if (restore) this.restoreFromStorage();
    if (!this.agents.length) this.seedRoster();
    this.pushLog("system", `Floor online — ${this.agents.length} traders at the desks.`);
  }

  /* ---------------------------- roster ---------------------------- */
  seedRoster() {
    this.agents = ROSTER_SEED.map((s, i) => {
        const t = new Trader({ archetype: ARCHETYPES.find((a) => a.id === s.archetype), name: s.name });
      t.equity = 25000;
      t.startEquity = 25000;
      t.recomputeBeliefs();
      return t;
    });
  }

  hire(reason = "a seat opened up", parent = null) {
    const used = new Set(this.agents.map((a) => a.name));
    const free = NAMES.filter((n) => !used.has(n));
    const t = parent ? parent.spawn(parent.name) : new Trader({ archetype: pick(ARCHETYPES) });
    if (free.length) t.name = pick(free);
    else t.name = `${t.name}-${this.agents.length + 1}`;
    t.equity = 25000;
    t.startEquity = 25000;
    if (!t.lessons.length) t.addLesson(`Joined the floor today. ${reason}.`);
    t.recomputeBeliefs();
    this.agents.push(t);
    this.stats.hires++;
    this.pushLog("hire", `${t.name} (${t.archetypeName}, gen ${t.generation}) joined the desk — ${reason}.`);
    this.say(t, "Just got my seat. Who's showing me the book?");
    return t;
  }

  fire(agent, reason) {
    if (this.agents.length <= 3) return;
    this.agents = this.agents.filter((a) => a.id !== agent.id);
    this.stats.fires++;
    this.pushLog("fire", `${agent.name} was let go — ${reason}.`);
  }

  get(id) {
    return this.agents.find((a) => a.id === id) || null;
  }

  say(agent, text) {
    if (!agent) return;
    agent.quote = text;
    agent.lastSpokeAt = Date.now();
  }

  pushLog(kind, text, meta = {}) {
    this.log.unshift({ id: uid(), t: Date.now(), kind, text, ...meta });
    if (this.log.length > 260) this.log.pop();
  }

  /* ---------------------------- feeds ---------------------------- */
  async connect() {
    const { loadAll } = await import("./feeds.js");
    this.feedDetail = "requesting live candles…";
    const res = await loadAll();
    let ok = 0;
    let firstError = null;
    for (const [sym, payload] of Object.entries(res)) {
      if (payload.error) {
        this.market.markError(sym, payload.error);
        firstError ??= payload.error;
      } else {
        this.market.seed(sym, payload);
        ok++;
      }
    }
    this.feedStatus = ok === 0 ? "offline" : ok < INSTRUMENTS.length ? "partial" : "live";
    this.feedDetail =
      ok === 0
        ? `No public feed reachable (${firstError || "network blocked"}). The floor is paused — it will not invent prices.`
        : `${ok}/${INSTRUMENTS.length} instruments streaming real quotes.`;
    this.lastPollAt = Date.now();
    this.pushLog(ok ? "feed" : "risk", this.feedDetail);
    return ok;
  }

  async refresh() {
    const { pollTicker } = await import("./feeds.js");
    const errors = [];
    await Promise.all(
      INSTRUMENTS.map(async (inst) => {
        if (this.market.feeds[inst.symbol].error && this.failureStreak % 4 !== 0) return; // retry slow
        try {
          const p = await pollTicker(inst.symbol);
          this.market.applyPoll(inst.symbol, p);
        } catch (e) {
          errors.push(inst.symbol);
          this.market.markError(inst.symbol, String(e.message || e));
        }
      })
    );
    this.lastPollAt = Date.now();
    const live = this.market.liveCount;
    this.feedStatus = live === 0 ? "offline" : live < INSTRUMENTS.length ? "partial" : "live";
    if (live) this.failureStreak = 0;
    else this.failureStreak++;
    return errors;
  }

  /* --------------------------- main heartbeat --------------------------- */
  onTick() {
    if (this.paused) return;
    this.tick++;
    this.market.step();

    // risk desk: hard stops & targets on every open position
    this.account.managePositions(this.market, (trade, pnl, agentId) => {
      const agent = this.get(agentId);
      if (agent) {
        agent.realized += pnl;
        agent.equity += pnl;
        agent.learn({
          features: trade.features,
          stance: trade.entryStance === "sell" ? "sell" : "buy",
          pnl,
          symbol: trade.symbol,
        });
        this.say(agent, pnl >= 0 ? `${trade.symbol} paid. That's the trade I wanted.` : `Stopped out of ${trade.symbol}. Lesson filed.`);
      }
      this.pushLog(pnl >= 0 ? "exit" : "risk", `${trade.symbol} ${trade.side} closed ${pnl >= 0 ? "+" : "−"}$${Math.abs(pnl).toFixed(2)} — ${trade.reason}`);
      this.alerts.unshift({ id: uid(), t: Date.now(), text: `${pnl >= 0 ? "WIN" : "STOP"} ${trade.symbol} ${pnl >= 0 ? "+" : "−"}$${Math.abs(pnl).toFixed(0)}`, tone: pnl >= 0 ? "up" : "down" });
      if (this.alerts.length > 8) this.alerts.pop();
    }, this.houseRules.maxHoldTicks);

    for (const a of this.agents) a.decayMood();

    // a real broker feed ticks in the background
    if (Date.now() - this.lastPollAt > 8000) this.refresh();

    // ---------- free will: each agent may act this beat ----------
    const p = 0.055;
    for (const a of this.agents) {
      if (Math.random() > p * (0.6 + a.traits.aggression * 0.9)) continue;
      this._act(a);
    }

    // ---------- reviews: hiring, firing, evolution ----------
    if (this.tick % 90 === 0) this._review();
    if (this.tick % 40 === 0) this.account.snap(this.market);
    if (this.tick % 55 === 0) this._smallTalk();
  }

  /* ------------------------- one agent's decision ------------------------- */
  _act(agent) {
    const symbols = INSTRUMENTS.map((i) => i.symbol).filter((s) => this.market.feeds[s].bars.length > 20);
    if (!symbols.length) return;
    if (!agent.focusSymbol || Math.random() < 0.35) agent.focusSymbol = pick(symbols);
    const brief = buildBrief(this.market, agent.focusSymbol);
    if (!brief) return;
    const read = agent.read(brief);
    const action = chooseAction(agent, { lastVerdict: this.debates[0]?.signal });

    // free will: she can abandon her own trade the moment her model flips
    const ownPos = this.account.positions[agent.focusSymbol];
    if (ownPos && ownPos.agentId === agent.id) {
      const dir = Math.sign(ownPos.qty);
      const flipped = (dir > 0 && read.stance === "sell" && read.conviction > 0.45) || (dir < 0 && read.stance === "buy" && read.conviction > 0.45);
      if (flipped && Math.random() < 0.55) {
        const closed = this.account.execute({
          symbol: agent.focusSymbol,
          side: dir > 0 ? "sell" : "buy",
          qty: Math.abs(ownPos.qty),
          market: this.market,
          agent,
          reason: `${agent.name} changed her mind — model flipped to ${read.stance}`,
        });
        if (closed) {
          agent.realized += closed.realizedPnl;
          agent.equity += closed.realizedPnl;
          agent.learn({ features: read.features, stance: dir > 0 ? "buy" : "sell", pnl: closed.realizedPnl, symbol: agent.focusSymbol });
          this.pushLog("exit", `${agent.name} closed her ${agent.focusSymbol} ${dir > 0 ? "long" : "short"} ${closed.realizedPnl >= 0 ? "for +" : "for −"}$${Math.abs(closed.realizedPnl).toFixed(0)} — changed her mind`);
          this.say(agent, closed.realizedPnl >= 0
            ? `Out of ${agent.focusSymbol} with a profit. My model flipped, so I flipped.`
            : `Cut ${agent.focusSymbol}. My own model turned on me.`);
          agent.lastAction = "closed her own trade";
          return;
        }
      }
    }

    if (action === "study") {
      agent.lastAction = "studying charts";
      agent.lastActionAt = Date.now();
      this.say(agent, pick([
        `${agent.focusSymbol} at ${brief.price.toFixed(bySymbol(agent.focusSymbol).digits)}. Watching the ${brief.rsi > 60 ? "stretched" : brief.rsi < 40 ? "beaten-down" : "balanced"} tape.`,
        `My model reads ${brief.symbol} at ${(read.conviction * 100) | 0}% conviction. Not yet.`,
        `RSI ${brief.rsi.toFixed(0)}, ATR ${(brief.atrPct * 100).toFixed(2)}%. Same story, different day.`,
      ]));
      agent.boredom = clamp(agent.boredom - 0.1, 0, 1.4);
      return;
    }

    if (action === "chat") {
      this._smallTalk(agent);
      return;
    }

    if (action === "rest") {
      agent.lastAction = "stepped away";
      this.say(agent, pick([
        "Going for coffee. Nobody touch my book.",
        "My head is not in it. Better flat than forced.",
        "Ten minutes off the screens. The tape will still be here.",
      ]));
      agent.boredom = 0;
      agent.setMood("focused");
      return;
    }

    if (action === "debate") {
      this.openDebate(agent.focusSymbol, agent);
      return;
    }

    if (action === "impulse" || action === "contradict") {
      if (read.stance === "neutral" && Math.random() > 0.4) {
        this.say(agent, `Not feeling ${brief.symbol} either way. Skipping.`);
        return;
      }
      if (action === "contradict") this.stats.contradictions++;
      // free will: act alone, with smaller size — the house did not bless this
      const stance = read.stance === "neutral" ? (Math.random() < 0.5 ? "buy" : "sell") : read.stance;
      const size = agent.sizeFor(agent.equity, brief.price, agent.stopPct()) * (action === "contradict" ? 0.85 : 0.7);
      this.execute(agent, { symbol: brief.symbol, side: stance, qty: size, brief, read, solo: true, reason:
        action === "contradict"
          ? `went against the house on ${brief.symbol} — ${(read.conviction * 100) | 0}% conviction`
          : `solo conviction play on ${brief.symbol} (${(read.conviction * 100) | 0}%)` });
      return;
    }
  }

  _smallTalk(only) {
    const speaker = only || pick(this.agents);
    if (!speaker) return;
    const other = pick(this.agents.filter((a) => a.id !== speaker.id));
    const sym = speaker.focusSymbol || pick(INSTRUMENTS).symbol;
    const f = this.market.feeds[sym];
    const lines = [
      `${sym} is ${f.last > f.sma20 ? "above" : "below"} the 20. ${other ? other.name : "Anyone"} — you seeing this?`,
      `I keep losing the same way. ${speaker.lessons[0]?.text || "Need a new rule."}`,
      `${other ? other.name : "Desk"}: your ${other?.archetypeName?.toLowerCase() || "style"} book is going to get squeezed one day.`,
      `Who's carrying too much ${sym}? Because it feels crowded.`,
      `Hit rate ${(speaker.winRate * 100) | 0}% over ${speaker.total}. I'll take boring consistency.`,
      `The model says ${sym}. The model is also what got me here.`,
    ];
    const text = pick(lines);
    this.say(speaker, text);
    this.chat.unshift({ id: uid(), t: Date.now(), from: speaker.id, name: speaker.name, color: speaker.color, text });
    if (this.chat.length > 60) this.chat.pop();
    speaker.boredom = clamp(speaker.boredom - 0.25, 0, 1.4);
  }

  /* ---------------------------- debates ---------------------------- */
  openDebate(symbol, initiator, opts = {}) {
    const brief = buildBrief(this.market, symbol);
    if (!brief) return null;
    const participants = opts.participants || this._pickPanel(initiator, Math.min(4, this.agents.length));
    const debate = {
      id: uid(),
      symbol,
      initiator: initiator?.id,
      openedAt: Date.now(),
      status: "open",
      messages: [],
      brief,
      reads: {},
      signal: null,
      rule: null,
      comment: null,
      risk: riskRead(brief),
      trade: null,
    };
    this.debates.unshift(debate);
    if (this.debates.length > 24) this.debates.pop();
    this.stats.debates++;

    this._msg(debate, "system", `${symbol} called to the room by ${initiator?.name || "the desk"} — ${brief.granularity} tape, ${brief.price.toFixed(bySymbol(symbol).digits)}.`);
    if (debate.risk.verdict !== "LOW RISK") {
      this._msg(debate, "system", `Risk pre-read: ${debate.risk.verdict} — ${debate.risk.flags[0] || "tape is normal"}.`);
    }

    for (const a of participants) {
      const read = a.read(brief);
      debate.reads[a.id] = { ...read, name: a.name, color: a.color, archetype: a.archetypeName, stance: read.stance, conviction: read.conviction };
      this._msg(debate, a.id, a.argue(brief, read), {
        name: a.name,
        color: a.color,
        archetype: a.archetypeName,
        stance: read.stance,
        conviction: read.conviction,
        gen: a.generation,
      });
      this.say(a, read.stance === "buy" ? `Long ${symbol}. Anyone disagree?` : read.stance === "sell" ? `${symbol} is a short.` : `Flat on ${symbol}.`);
    }

    // a dissenter may openly fight the emerging consensus (free will)
    const dissent = participants.filter((p) => {
      const r = debate.reads[p.id];
      return r.stance !== "neutral" && p.traits.contrarian > 0.6 && Math.random() < 0.5;
    })[0];
    if (dissent) {
      this._msg(debate, dissent.id, pick([
        `Hold on. I hear the room and I think the room is wrong. ${symbol} is a trap here.`,
        `I'll be the one who says it: this is the exact setup that blows up.`,
        `Everyone is looking at the same three numbers. That's why it stops working.`,
      ]), { name: dissent.name, color: dissent.color, archetype: dissent.archetypeName, kind: "dissent", gen: dissent.generation });
    }

    const verdict = aggregate(Object.values(debate.reads), {
      brief,
      requireAgreement: this.houseRules.minVotes,
    });
    debate.signal = verdict.signal;
    debate.rule = verdict.rule;
    debate.comment = verdict.comment;
    debate.risk = verdict.risk;
    debate.status = "closed";
    debate.confidence = confidenceOf(Object.values(debate.reads));
    debate.closedAt = Date.now();

    this._msg(debate, "house", `${verdict.signal.toUpperCase()} — ${verdict.comment}`, {
      name: "House verdict",
      kind: "verdict",
      signal: verdict.signal,
      rule: verdict.rule,
      color: verdict.signal === "buy" ? "#5ceb8e" : verdict.signal === "sell" ? "#f26457" : "#f5b841",
    });
    if (verdict.signal === "hold") this.stats.holds++;
    this.stats.votes++;

    // the house acts only on a clean verdict
    if (verdict.signal !== "hold") {
      const champion = participants.reduce((best, p) => {
        const r = debate.reads[p.id];
        const aligned = r.stance === verdict.signal;
        const score = (aligned ? 1 : 0) + r.conviction + p.reputation * 0.4;
        return !best || score > best.score ? { p, score, aligned } : best;
      }, null);
      if (champion?.aligned) {
        const read = debate.reads[champion.p.id];
        const qty = champion.p.sizeFor(Math.min(this.account.equity(this.market), champion.p.equity * 3), brief.price, champion.p.stopPct()) * 0.9;
        const trade = this.execute(champion.p, {
          symbol,
          side: verdict.signal,
          qty,
          brief,
          read,
          house: true,
          reason: `${verdict.rule} — ${verdict.signal.toUpperCase()} ${symbol} on a ${(debate.confidence * 100) | 0}% room`,
        });
        debate.trade = trade;
      }
    }

    // participants learn something about the argument itself
    for (const a of participants) {
      if (a.traits.curiosity > 0.5 && Math.random() < 0.35) {
        a.addLesson(`${symbol}: room went ${verdict.signal.toUpperCase()} (${verdict.rule}). ${verdict.signal === a.read(brief).stance ? "I was aligned." : "I was not."}`);
      }
    }
    this.pushLog("debate", `${symbol} — ${verdict.signal.toUpperCase()} · ${verdict.rule} · ${participants.length} desks in the room`);
    return debate;
  }

  _pickPanel(initiator, n = 3) {
    const pool = this.agents.filter((a) => a.id !== initiator?.id);
    const chosen = [];
    if (initiator) chosen.push(initiator);
    // high-reputation / social agents get invited more often
    const weighted = pool
      .map((a) => ({ a, w: 0.5 + a.traits.social + a.reputation }))
      .sort(() => Math.random() - 0.5);
    for (const { a, w } of weighted) {
      if (chosen.length >= n) break;
      if (Math.random() < w / 2.1) chosen.push(a);
    }
    while (chosen.length < Math.min(n, this.agents.length)) {
      const a = pick(pool);
      if (a && !chosen.includes(a)) chosen.push(a);
      else break;
    }
    return chosen;
  }

  _msg(debate, speakerId, text, extra = {}) {
    debate.messages.push({ id: uid(), speaker: speakerId, text, at: Date.now(), ...extra });
  }

  /* --------------------------- execution --------------------------- */
  execute(agent, { symbol, side, qty, brief, read, house = false, solo = false, reason }) {
    const inst = bySymbol(symbol);
    const f = this.market.feeds[symbol];
    if (!inst || !f) return null;

    const grossCap = this.account.equity(this.market) * this.houseRules.maxGross;
    if (this.account.grossNotional(this.market) > grossCap) {
      this.pushLog("risk", `${symbol} ${side} blocked — portfolio gross cap (${this.houseRules.maxGross}×) reached.`);
      return null;
    }
    const openNames = Object.keys(this.account.positions).length;
    const existing = this.account.positions[symbol];
    if (!existing && openNames >= this.houseRules.maxNames) {
      this.pushLog("risk", `${symbol} ${side} blocked — already carrying ${openNames} names.`);
      return null;
    }
    // free will: a trader will happily close somebody else's book if she disagrees
    if (existing && Math.sign(existing.qty) !== (side === "buy" ? 1 : -1)) {
      const closeQty = Math.min(Math.abs(existing.qty), qty);
      const closed = this.account.execute({
        symbol,
        side,
        qty: closeQty,
        market: this.market,
        agent,
        reason: `${agent.name} closing a ${existing.qty > 0 ? "long" : "short"} she disagrees with`,
      });
      if (closed) {
        this.pushLog("fill", `CLOSE ${side.toUpperCase()} ${closeQty.toFixed(inst.qtyStep < 1 ? 3 : 0)} ${symbol} @ ${closed.price.toFixed(inst.digits)} by ${agent.name} — reversed the room`);
        agent.fills++;
        const owner = this.get(existing.agentId);
        if (owner && owner.id !== agent.id) {
          owner.equity += closed.realizedPnl;
          owner.realized += closed.realizedPnl;
          owner.learn({ features: closed.features, stance: existing.qty > 0 ? "buy" : "sell", pnl: closed.realizedPnl, symbol });
          this.say(owner, `Who covered my ${symbol}? That was my trade.`);
        }
      }
      if (qty <= closeQty) return closed;
      qty -= closeQty;
    }

    // an agent's own risk budget caps her size (no leverage tricks on her own equity)
    const maxQty = (agent.equity * this.houseRules.maxAgentExposure) / f.last;
    qty = Math.min(qty, maxQty);
    const step = inst.qtyStep;
    qty = Math.floor(qty / step) * step;
    if (qty * f.last < 50) return null;

    const trade = this.account.execute({
      symbol,
      side,
      qty,
      market: this.market,
      agent,
      reason,
      debateId: house ? this.debates[0]?.id : null,
      stopPct: agent.stopPct(),
      features: read?.features,
    });
    if (!trade) return null;

    agent.fills++;
    agent.lastAction = house ? "executing house trade" : "going solo";
    agent.lastActionAt = Date.now();
    agent.boredom = 0;
    if (solo) this.stats.soloTrades++;
    const tag = house ? "HOUSE" : "SOLO";
    this.pushLog(
      "fill",
      `${tag} ${side.toUpperCase()} ${qty.toFixed(inst.qtyStep < 1 ? 3 : 0)} ${symbol} @ ${trade.price.toFixed(inst.digits)} by ${agent.name} — ${reason}`
    );
    this.alerts.unshift({
      id: uid(),
      t: Date.now(),
      text: `${tag} ${side.toUpperCase()} ${symbol} · ${agent.name}`,
      tone: side === "buy" ? "up" : "down",
    });
    if (this.alerts.length > 8) this.alerts.pop();
    this.say(agent, side === "buy" ? `Filled long ${symbol}. Now we see.` : `Short ${symbol} on. Stop is in.`);
    return trade;
  }

  /* ---------------------- reviews, evolution, jobs ---------------------- */
  _review() {
    for (const a of this.agents) {
      a.recomputeBeliefs();
      // reputation drifts with results
      const score = a.total
        ? clamp(0.55 + (a.winRate - 0.45) * 1.1 + clamp(a.realized / Math.max(1, a.startEquity), -0.3, 0.3), 0.02, 0.98)
        : 0.5;
      a.reputation = clamp(a.reputation * 0.8 + score * 0.2, 0.02, 0.98);
    }
    const ranked = [...this.agents].sort((x, y) => y.equity - x.equity);
    const worst = ranked[ranked.length - 1];
    const best = ranked[0];

    // evolution: the best performer's playbook gets copied
    if (best && this.houseRules.evolveOnLoss && best.total >= 3 && best.winRate > 0.55 && this.agents.length < 10 && Math.random() < 0.5) {
      const child = this.hire(`${best.name}'s approach is being cloned — gen ${best.generation + 1}`, best);
      this.stats.evolutions++;
      child.addLesson(`Built from ${best.name}'s winning model (${(best.winRate * 100) | 0}% hit rate).`);
    }

    // firing: a long-term bleeder gets a serious conversation
    if (worst && worst.total >= 6 && worst.winRate < 0.34 && worst.equity < worst.startEquity * 0.93) {
      this.pushLog("review", `${worst.name} is under review: ${(worst.winRate * 100) | 0}% hit rate, equity ${worst.equity.toFixed(0)}.`);
      if (Math.random() < 0.5 && this.agents.length > 4) this.fire(worst, `bleeding ${(100 - worst.winRate * 100) | 0}% of ideas`);
      else worst.addLesson("Under review. Cut size, take the A+ setup only.");
    }
    if (this.houseRules.autoHire && this.agents.length < 7 && Math.random() < 0.35) {
      this.hire(pick(["a seat opened up", "we need more flow", "the desk is short-staffed"]));
    }
    this.save();
  }

  /* --------------------------- persistence --------------------------- */
  save() {
    try {
      const payload = {
        v: 2,
        savedAt: Date.now(),
        agents: this.agents.map((a) => a.serialize()),
        stats: this.stats,
        rules: this.houseRules,
        equity: this.account.equity(this.market),
        trades: this.account.trades.slice(0, 120),
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    } catch {
      /* storage full or unavailable — the session keeps running */
    }
  }

  restoreFromStorage() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const data = JSON.parse(raw);
      if (!data.agents?.length) return;
      this.agents = data.agents.map((o) => Trader.deserialize(o));
      Object.assign(this.houseRules, data.rules || {});
      this.stats = { ...this.stats, ...(data.stats || {}) };
      if (data.trades) this.account.trades = data.trades;
      this.pushLog("system", `Restored ${this.agents.length} traders and their lessons from your last session.`);
    } catch {
      /* corrupt storage: start fresh */
    }
  }

  resetProgress() {
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      /* ignore */
    }
    this.agents = [];
    this.stats = { debates: 0, votes: 0, holds: 0, soloTrades: 0, contradictions: 0, hires: 0, fires: 0, evolutions: 0 };
    this.seedRoster();
    this.pushLog("system", "Floor reset — new hires, empty memories.");
  }

  /* ----------------------------- summary ----------------------------- */
  summary() {
    const equity = this.account.equity(this.market);
    const closed = this.account.trades.filter((t) => t.realizedPnl !== 0);
    const wins = closed.filter((t) => t.realizedPnl > 0).length;
    const agentEquity = this.agents.reduce((a, x) => a + x.equity, 0);
    return {
      equity,
      cash: this.account.cash,
      pnl: equity - this.cashDayStart,
      pnlPct: ((equity - this.cashDayStart) / this.cashDayStart) * 100,
      unrealized: this.account.unrealized(this.market),
      realized: this.account.realized,
      openPositions: Object.keys(this.account.positions).length,
      gross: this.account.grossNotional(this.market) / Math.max(1, equity),
      fills: this.account.trades.length,
      winRate: closed.length ? (wins / closed.length) * 100 : 0,
      closed: closed.length,
      traders: this.agents.length,
      generations: Math.max(...this.agents.map((a) => a.generation), 0),
      lessons: this.agents.reduce((a, x) => a + x.lessons.length, 0),
      ...this.stats,
      feedStatus: this.feedStatus,
      feedDetail: this.feedDetail,
      liveCount: this.market.liveCount,
      agentEquity,
    };
  }
}

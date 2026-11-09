// The trading floor brain: schedules debates, records the argument transcript,
// routes approved ideas to the execution desk, enforces the risk mandate and
// writes the day's blotter. Long and short are both tradable, 5x margin.
import { SYMBOLS, Market, Account, LEVERAGE } from "./market.js";
import { runDebate } from "./debate.js";

const uid = () => Math.random().toString(36).slice(2, 9);

export const DESKS = {
  victor: { id: "victor", name: "Victor", role: "Bull Analyst", color: "#5ceb8e" },
  maria: { id: "maria", name: "Maria", role: "Bear Analyst", color: "#f26457" },
  alexei: { id: "alexei", name: "Alexei", role: "Risk Manager", color: "#f5b841" },
  judge: { id: "judge", name: "The Arbiter", role: "Senior PM", color: "#c9a7ff" },
};

export const RULES_DEFAULT = {
  stopLossPct: 0.006,
  takeProfitPct: 0.012,
  maxHoldBars: 46,
  riskPerTrade: 0.01, // dollars risked per trade as % of equity
  maxGrossExposure: 2.5, // x equity
  maxPositions: 4,
  requireAgreement: 2,
  minConviction: 0.42,
};

export class Floor {
  constructor() {
    this.market = new Market();
    this.account = new Account();
    this.rules = { ...RULES_DEFAULT };
    this.log = [];
    this.threads = [];
    this.agents = {};
    this.paused = false;
    this.activeThreadId = null;
    this.dayStart = this.account.equity(this.market);
    this.debateCount = 0;
    this.alerts = [];
    for (const [id, d] of Object.entries(DESKS)) {
      this.agents[id] = {
        ...d,
        quote: "reading the tape...",
        lastSpokeAt: 0,
        pnl: 0,
        fills: 0,
        wins: 0,
        losses: 0,
        ideas: 0,
      };
    }
    this.pushLog("system", "Floor opened · 09:30 cash session · risk mandate loaded (R1 veto active).");
  }

  equity() {
    return this.account.equity(this.market);
  }

  pushLog(kind, text) {
    const entry = { id: uid(), t: Date.now(), kind, text };
    this.log.unshift(entry);
    if (this.log.length > 240) this.log.pop();
    return entry;
  }

  say(agentId, text) {
    const a = this.agents[agentId];
    if (!a) return;
    a.quote = text;
    a.lastSpokeAt = Date.now();
  }

  // -------- one simulation step (driven by the market clock) --------
  step() {
    if (this.paused) return;
    this.market.tickOnce();

    this.account.evaluateStops(this.market, this.rules, (trade, pnlBefore) => {
      const desk = trade.originAgentId || "judge";
      this._credit(desk, pnlBefore);
      this.pushLog(
        "exit",
        `${trade.reason.startsWith("Stop loss") ? "STOP" : trade.reason.startsWith("Take") ? "TARGET" : "TIME"} · ${trade.symbol} closed ${pnlBefore >= 0 ? "+" : "−"}$${Math.abs(pnlBefore).toFixed(2)} — ${trade.reason}`
      );
      this.threads.forEach((th) => {
        if (th.symbol === trade.symbol && th.status === "filled") th.status = "closed";
      });
    });

    if (this.market.tick % 6 === 0) this._idleChatter();
    if (this.market.tick % 12 === 0) this.account._snap(this.market);
  }

  _credit(agentId, pnl) {
    const a = this.agents[agentId];
    if (!a) return;
    a.pnl += pnl;
    a.fills += 1;
    if (pnl > 0) a.wins += 1;
    else a.losses += 1;
  }

  _idleChatter() {
    const s = this.market.snapshot();
    const pick = s[Math.floor(Math.random() * s.length)];
    const f = this.market.feeds[pick.symbol];
    const up = f.last > f.sma20 ? "above" : "below";
    const lines = {
      victor: [
        `${pick.symbol} is ${up} the 20. I still like the upside here.`,
        `Did you see that volume print on ${pick.symbol}? Buyers are not shy.`,
        `Every pullback this week got bought. Why fight it?`,
        `Momentum is a position, not an opinion. I'm long-biased.`,
      ],
      maria: [
        `Everyone's long the same three names. That's the trade in reverse.`,
        `Look at the upper wick on ${pick.symbol}. Read the tape, Victor.`,
        `Rallies into resistance are for selling, not buying.`,
        `The crowd is late. I'd rather be early and flat.`,
      ],
      alexei: [
        `ATR is fine. Size is what kills, not direction.`,
        `Nobody panic-sizes on my book.`,
        `If the next candle is 2x ATR we stand down. I'm serious.`,
        `I don't care where it goes. I care what happens if it gaps.`,
      ],
      judge: [
        `I don't vote until I've heard all three.`,
        `Two of three or no trade. That's the rule.`,
        `Silence costs nothing. Bad fills cost everything.`,
        `A hold is a decision, not a failure to decide.`,
      ],
    };
    const who = ["victor", "maria", "alexei", "judge"][Math.floor(Math.random() * 4)];
    const arr = lines[who];
    this.say(who, arr[Math.floor(Math.random() * arr.length)]);
  }

  // -------- open a debate on a symbol --------
  startDebate(symbol) {
    if (this.paused) return null;
    const f = this.market.feeds[symbol];
    if (!f) return null;
    const th = {
      id: uid(),
      symbol,
      status: "talking",
      openedAt: Date.now(),
      messages: [],
      verdict: null,
      trade: null,
      entryPrice: f.last,
      digits: SYMBOLS.find((s) => s.symbol === symbol).digits,
    };
    this.threads.unshift(th);
    if (this.threads.length > 16) this.threads.pop();
    this.activeThreadId = th.id;
    this.debateCount += 1;

    const res = runDebate(this.market, symbol, this.rules);
    const push = (speaker, text, kind = "say", extra = {}) => {
      th.messages.push({ id: uid(), speaker, text, kind, at: Date.now(), ...extra });
    };

    push("system", `DEBATE / ${symbol} · one identical briefing, three different lenses.`);
    push("victor", res.opinions.victor.text, "say", {
      stance: res.opinions.victor.stance,
      conf: res.opinions.victor.confidence,
    });
    push("maria", res.opinions.maria.text, "say", {
      stance: res.opinions.maria.stance,
      conf: res.opinions.maria.confidence,
    });
    push("alexei", res.opinions.alexei.text, "say", { verdict: res.opinions.alexei.verdict });
    if (res.opinions.victor.stance === "buy" && res.opinions.maria.stance === "sell") {
      push(
        "judge",
        res.verdict.signal === "hold"
          ? "You're both right about something and neither of you is right about the trade. We stand down."
          : `Conviction edge goes to the ${res.verdict.signal.toUpperCase()} side. Small size, tight stop.`,
        "interject"
      );
    }
    push("judge", `Verdict: ${res.verdict.signal.toUpperCase()} — ${res.verdict.comment}`, "verdict", {
      signal: res.verdict.signal,
      rule: res.verdict.rule,
    });

    this.say("victor", res.opinions.victor.stance === "buy" ? "I'm arguing the long side." : "Nothing here. I'll pass.");
    this.say("maria", res.opinions.maria.stance === "sell" ? "Short side is the only honest trade." : "I'll stand down this round.");
    this.say("alexei", res.opinions.alexei.verdict);
    this.say("judge", `Deliberating ${symbol}...`);
    if (res.opinions.victor.stance === "buy") this.agents.victor.ideas += 1;
    if (res.opinions.maria.stance === "sell") this.agents.maria.ideas += 1;

    this.pushLog(
      "debate",
      `${symbol} debate — bull ${(res.opinions.victor.confidence * 100) | 0}% · bear ${(res.opinions.maria.confidence * 100) | 0}% · risk ${res.opinions.alexei.verdict}`
    );

    const delay = this.paused ? 400 : 900 + Math.random() * 900;
    setTimeout(() => this._executeVerdict(th, res), delay);
    return th;
  }

  // position sizing: risk a fixed % of equity against the stop distance,
  // then clamp to what the mandate (and the 5x margin) actually allows.
  _sizeFor(price, equity) {
    const riskDollars = equity * this.rules.riskPerTrade;
    let notional = riskDollars / Math.max(0.0015, this.rules.stopLossPct);
    const grossRoom = Math.max(0, equity * this.rules.maxGrossExposure - this.account.grossNotional(this.market)) * 0.95;
    notional = Math.min(notional, equity * 0.6, grossRoom, this.account.buyingPower(this.market) * 0.9);
    return Math.max(0, notional) / price;
  }

  _roundQty(symbol, qty) {
    if (symbol === "BTCUSD") return Math.max(0.01, Math.round(qty * 100) / 100);
    if (symbol === "EURUSD") return Math.max(1000, Math.round(qty / 100) * 100);
    if (symbol === "XAUUSD") return Math.max(1, Math.round(qty));
    return Math.max(1, Math.round(qty));
  }

  _executeVerdict(th, res) {
    if (this.paused) {
      th.status = "no-trade";
      this.pushLog("system", `${th.symbol} — floor paused mid-debate. No action taken.`);
      return;
    }
    const { signal, comment } = res.verdict;
    const sig = signal.toLowerCase();
    const meta = SYMBOLS.find((s) => s.symbol === th.symbol);
    const px = this.market.feeds[th.symbol].last;

    if (sig === "hold") {
      th.status = "no-trade";
      th.verdict = { signal: "hold", comment };
      this.say("judge", `No trade on ${th.symbol}. ${res.verdict.rule}.`);
      this.pushLog("hold", `${th.symbol} — HOLD · ${comment}`);
      return;
    }

    const held = this.account.position(th.symbol);
    const openCount = Object.keys(this.account.positions).length;
    if (held === 0 && openCount >= this.rules.maxPositions) {
      th.status = "no-trade";
      th.verdict = { signal: "hold", comment: `Portfolio already holds ${openCount} names — mandate cap is ${this.rules.maxPositions}.` };
      this.pushLog("risk", `${th.symbol} — ${sig.toUpperCase()} blocked: max concurrent positions reached.`);
      return;
    }
    if (held === 0 && this.account.grossNotional(this.market) / this.equity() >= this.rules.maxGrossExposure) {
      th.status = "no-trade";
      th.verdict = { signal: "hold", comment: "Gross exposure cap reached — carrying more risk would be reckless." };
      this.pushLog("risk", `${th.symbol} — ${sig.toUpperCase()} blocked: gross exposure cap ${this.rules.maxGrossExposure}×.`);
      return;
    }

    // closing / reversing an existing opposite book
    if (held !== 0 && Math.sign(held) !== (sig === "buy" ? 1 : -1)) {
      const trade = this.account.execute({
        symbol: th.symbol,
        side: sig === "buy" ? "buy" : "sell",
        qty: Math.abs(held),
        market: this.market,
        agentId: "judge",
        agentName: "The Arbiter",
        reason: comment,
        debateId: th.id,
      });
      if (!trade) {
        th.status = "no-trade";
        return;
      }
      this._credit("judge", trade.realizedPnl);
      th.status = "filled";
      th.verdict = { signal: sig, comment };
      th.trade = trade;
      this.say("judge", `Closed ${th.symbol} ${sig === "buy" ? "short" : "long"} @ ${px.toFixed(meta.digits)}. Book is flat.`);
      this.pushLog("fill", `${sig === "buy" ? "COVER" : "SELL"} ${Math.abs(held)} ${th.symbol} @ ${px.toFixed(meta.digits)} — ${comment}`);
      return;
    }
    if (held !== 0 && Math.sign(held) === (sig === "buy" ? 1 : -1)) {
      th.status = "no-trade";
      th.verdict = { signal: "hold", comment: "Already long this name — pyramiding into the same idea adds no edge." };
      this.pushLog("hold", `${th.symbol} — ${sig.toUpperCase()} already held. No add.`);
      return;
    }

    const qty = this._roundQty(th.symbol, this._sizeFor(px, this.equity()));
    if (!qty) {
      th.status = "no-trade";
      th.verdict = { signal: "hold", comment: "No risk budget left under the mandate — sizing to zero." };
      this.pushLog("risk", `${th.symbol} — ${sig.toUpperCase()} blocked: no remaining risk budget.`);
      return;
    }
    const origin = sig === "buy" ? "victor" : "maria";
    const trade = this.account.execute({
      symbol: th.symbol,
      side: sig,
      qty,
      market: this.market,
      agentId: origin,
      agentName: this.agents[origin].name,
      reason: comment,
      debateId: th.id,
    });
    if (!trade) {
      th.status = "no-trade";
      th.verdict = { signal: "hold", comment: "Order rejected — not enough buying power at 5× margin." };
      this.pushLog("risk", `${th.symbol} — ${sig.toUpperCase()} rejected: insufficient buying power.`);
      return;
    }
    th.status = "filled";
    th.verdict = { signal: sig, comment };
    th.trade = trade;
    th.origin = origin;
    this.agents[origin].fills += 1;
    this.say(
      "judge",
      `Filled: ${sig === "buy" ? "bought" : "sold short"} ${qty} ${th.symbol} @ ${px.toFixed(meta.digits)}.`
    );
    this.pushLog(
      "fill",
      `${sig === "buy" ? "BUY" : "SHORT"} ${qty} ${th.symbol} @ ${px.toFixed(meta.digits)} · ${(trade.notional).toFixed(0)} USD notional — ${comment}`
    );
    this.alerts.unshift({
      id: uid(),
      t: Date.now(),
      text: `${sig === "buy" ? "LONG" : "SHORT"} ${qty} ${th.symbol}`,
      tone: sig === "buy" ? "up" : "down",
    });
    if (this.alerts.length > 10) this.alerts.pop();
  }

  grossExposure() {
    return this.account.grossNotional(this.market) / this.equity();
  }

  summary() {
    const eq = this.equity();
    const j = this.agents.judge;
    const closed = this.account.trades.filter((t) => t.realizedPnl !== 0);
    const wins = closed.filter((t) => t.realizedPnl > 0).length;
    return {
      equity: eq,
      cash: this.account.cash,
      dayPnl: eq - this.dayStart,
      dayPnlPct: ((eq - this.dayStart) / this.dayStart) * 100,
      realized: this.account.realized,
      unrealized: this.account.unrealized(this.market),
      openPositions: Object.keys(this.account.positions).length,
      grossExposure: this.grossExposure(),
      fills: this.account.trades.length,
      wins,
      closedCount: closed.length,
      winRate: closed.length ? (wins / closed.length) * 100 : 0,
      debates: this.debateCount,
      holds: this.threads.filter((t) => t.status === "no-trade").length,
    };
  }
}

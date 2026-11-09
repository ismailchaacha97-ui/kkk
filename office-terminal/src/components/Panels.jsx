import React, { useEffect, useRef, useState } from "react";
import { INSTRUMENTS, bySymbol } from "../engine/instruments.js";
import { MOODS, FEATURES, FEATURE_LABEL } from "../engine/traders.js";

const fmt = (n, d = 2) =>
  Number(n).toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d });
const signMoney = (n, d = 0) => `${n < 0 ? "−" : "+"}$${fmt(Math.abs(n), d)}`;

/* ------------------------------- top bar ------------------------------- */
export function TopBar({ floor, summary, paused, speed, actions }) {
  const status = summary.feedStatus;
  return (
    <header className="topbar">
      <div className="brand">
        <div className="mark">M</div>
        <div>
          <div className="brand-title">MERIDIAN CAPITAL</div>
          <div className="brand-sub">LIVE DESK · {summary.traders} TRADERS · GEN {summary.generations}</div>
        </div>
      </div>

      <div className={`feed ${status}`}>
        <span className="feed-dot" />
        <div>
          <div className="feed-label">
            {status === "live" ? "LIVE MARKET DATA" : status === "partial" ? "PARTIAL FEED" : status === "connecting" ? "CONNECTING…" : "FEED OFFLINE"}
          </div>
          <div className="feed-detail">
            {summary.liveCount}/{INSTRUMENTS.length} instruments · {summary.feedDetail}
          </div>
        </div>
        <button className="btn tiny" onClick={actions.reconnect} title="Re-fetch live candles">
          ⟳
        </button>
      </div>

      <div className="stats">
        <Stat label="EQUITY" value={`$${fmt(summary.equity, 0)}`} accent />
        <Stat
          label="SESSION P&L"
          value={`${summary.pnl >= 0 ? "+" : "−"}$${fmt(Math.abs(summary.pnl), 0)}`}
          sub={`${summary.pnlPct >= 0 ? "+" : ""}${fmt(summary.pnlPct, 2)}%`}
          tone={summary.pnl >= 0 ? "up" : "down"}
        />
        <Stat label="OPEN" value={`${summary.openPositions}`} sub={`${fmt(summary.gross, 2)}× gross`} />
        <Stat label="WIN RATE" value={`${fmt(summary.winRate, 0)}%`} sub={`${summary.closed} closed`} />
        <Stat label="DEBATES" value={summary.debates} sub={`${summary.holds} held`} />
        <Stat label="SOLO" value={summary.soloTrades} sub={`${summary.contradictions} against house`} />
      </div>

      <div className="controls">
        <button className={paused ? "btn warn" : "btn"} onClick={actions.togglePause}>
          {paused ? "▶ RESUME" : "❚❚ PAUSE"}
        </button>
        <div className="speeds">
          {[1, 2, 4].map((s) => (
            <button key={s} className={`btn tiny ${speed === s ? "on" : ""}`} onClick={() => actions.setSpeed(s)}>
              {s}×
            </button>
          ))}
        </div>
        <button className="btn primary" onClick={actions.callDebate}>
          CALL A DEBATE
        </button>
        <button className="btn" onClick={actions.hire}>
          + HIRE
        </button>
      </div>
    </header>
  );
}

function Stat({ label, value, sub, tone, accent }) {
  return (
    <div className={`stat ${tone || ""} ${accent ? "accent" : ""}`}>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {sub && <div className="stat-sub">{sub}</div>}
    </div>
  );
}

/* ------------------------------ watchlist ------------------------------ */
export function Watchlist({ floor, selected, onSelect }) {
  const snap = floor.market.snapshot();
  return (
    <section className="panel watchlist">
      <div className="panel-head">
        <span>LIVE MARKETS</span>
        <span className="muted">{floor.feedStatus.toUpperCase()}</span>
      </div>
      <div className="wl-rows">
        {snap.map((s) => {
          const f = floor.market.feeds[s.symbol];
          const closes = (f.bars || []).slice(-30).map((b) => b.c);
          const up = s.changePct >= 0;
          const pos = floor.account.position(s.symbol);
          const debating = floor.debates.some((d) => d.symbol === s.symbol && Date.now() - d.openedAt < 4000);
          return (
            <button
              key={s.symbol}
              className={`wl-row ${selected === s.symbol ? "sel" : ""} ${!s.live ? "stale" : ""}`}
              onClick={() => onSelect(s.symbol)}
            >
              <span className="wl-sym" style={{ color: s.color }}>
                {s.symbol}
                {debating && <i className="live" />}
              </span>
              <span className="wl-px">{s.last ? s.last.toFixed(s.digits) : "—"}</span>
              <Sparkline data={closes} color={up ? "#5ceb8e" : "#f26457"} w={84} h={24} />
              <span className={`wl-chg ${up ? "up" : "down"}`}>
                {up ? "▲" : "▼"} {Math.abs(s.changePct).toFixed(2)}%
              </span>
              <span className="wl-rsi">RSI {s.rsi ? s.rsi.toFixed(0) : "—"}</span>
              {pos !== 0 && (
                <span className={`badge ${pos > 0 ? "long" : "short"}`}>
                  {pos > 0 ? "LONG" : "SHORT"} {Math.abs(pos) >= 1000 ? `${(Math.abs(pos) / 1000).toFixed(1)}k` : Math.abs(pos).toFixed(Math.abs(pos) < 10 ? 2 : 0)}
                </span>
              )}
              {!s.live && <span className="badge dead">FEED DOWN</span>}
            </button>
          );
        })}
      </div>
    </section>
  );
}

function Sparkline({ data, color, w = 84, h = 24 }) {
  if (!data || data.length < 2) return <svg width={w} height={h} />;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const span = max - min || 1;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * w},${h - ((v - min) / span) * (h - 3) - 1.5}`).join(" ");
  return (
    <svg width={w} height={h} className="spark">
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.5" />
    </svg>
  );
}

/* ------------------------------ debt room ------------------------------ */
export function DebateRoom({ floor, debaters, onSelectAgent, onCall }) {
  const [idx, setIdx] = useState(0);
  const scroller = useRef(null);
  const debate = floor.debates[Math.min(idx, floor.debates.length - 1)];
  useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight;
  }, [debate?.id, debate?.messages.length]);

  return (
    <section className="panel debate">
      <div className="panel-head">
        <span>THE ROOM</span>
        <span className="muted">{debate ? debate.symbol : "QUIET"}</span>
      </div>
      <div className="thread-tabs">
        {floor.debates.slice(0, 6).map((d, i) => (
          <button key={d.id} className={`thread-tab ${d.id === debate?.id ? "on" : ""}`} onClick={() => setIdx(i)}>
            {d.symbol}
            <small>{d.signal ? d.signal.toUpperCase() : "…"}</small>
          </button>
        ))}
        <button className="thread-tab ghost" onClick={onCall}>
          + CALL
        </button>
      </div>

      <div className="chat" ref={scroller}>
        {!debate && <div className="empty">Nobody has called a debate yet. The desks are reading the tape.</div>}
        {debate?.messages.map((m) => (
          <Message key={m.id} m={m} floor={floor} onSelectAgent={onSelectAgent} />
        ))}
      </div>

      {debate?.signal && (
        <div className={`verdict ${debate.signal}`}>
          <div className="v-label">
            HOUSE VERDICT · {debate.rule} · risk {debate.risk?.verdict}
          </div>
          <div className="v-signal">{debate.signal.toUpperCase()}</div>
          <div className="v-comment">{debate.comment}</div>
        </div>
      )}
    </section>
  );
}

function Message({ m, floor, onSelectAgent }) {
  if (m.kind === "system") return <div className="msg system">{m.text}</div>;
  if (m.kind === "verdict")
    return (
      <div className={`msg verdict-msg ${m.signal}`}>
        <div className="msg-head">
          <span className="who" style={{ color: m.color }}>
            ⚖ HOUSE
          </span>
          <span className="rule">{m.rule}</span>
        </div>
        <div className="msg-body">{m.text}</div>
      </div>
    );
  const agent = floor.get(m.speaker);
  return (
    <div className={`msg ${m.kind || ""}`}>
      <div className="msg-head">
        <span className="avatar" style={{ borderColor: m.color, color: m.color }} onClick={() => onSelectAgent(m.speaker)}>
          {(m.name || "?")[0]}
        </span>
        <span className="who" style={{ color: m.color }}>
          {(m.name || "").toUpperCase()}
        </span>
        <span className="role">
          {m.archetype}
          {m.gen ? ` · gen ${m.gen}` : ""}
        </span>
        {m.stance && m.stance !== "neutral" && <span className={`pill ${m.stance}`}>{m.stance.toUpperCase()}</span>}
        {m.conviction !== undefined && <span className="conf">{Math.round(m.conviction * 100)}%</span>}
      </div>
      <div className="msg-body">{m.text}</div>
    </div>
  );
}

/* ------------------------------- people ------------------------------- */
export function PeoplePanel({ floor, selectedAgent, onSelectAgent, compact = false }) {
  const sorted = [...floor.agents].sort((a, b) => b.equity - a.equity);
  return (
    <section className={`panel people ${compact ? "compact" : ""}`}>
      <div className="panel-head">
        <span>THE FLOOR</span>
        <span className="muted">
          {floor.agents.length} TRADERS · {floor.agents.reduce((a, x) => a + x.lessons.length, 0)} LESSONS
        </span>
      </div>
      <div className="people-rows">
        {sorted.map((a) => {
          const speaking = Date.now() - (a.lastSpokeAt || 0) < 2600;
          const pnl = a.equity - a.startEquity;
          return (
            <button
              key={a.id}
              className={`person ${selectedAgent === a.id ? "sel" : ""} ${speaking ? "speaking" : ""}`}
              style={{ "--c": a.color }}
              onClick={() => onSelectAgent(a.id)}
            >
              <span className="p-av">{a.name[0]}</span>
              <span className="p-main">
                <span className="p-name">
                  {a.name}
                  {a.generation > 0 && <em className="gen">g{a.generation}</em>}
                  <em className="mood" style={{ color: MOODS[a.mood]?.color }}>
                    {a.mood}
                  </em>
                </span>
                <span className="p-role">
                  {a.archetypeName} · {a.wins}W/{a.losses}L
                </span>
              </span>
              <span className={`p-pnl ${pnl >= 0 ? "up" : "down"}`}>{signMoney(pnl, 0)}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

export function TraderCard({ floor, agent, onClose }) {
  if (!agent) return null;
  const pnl = agent.equity - agent.startEquity;
  const learned = [...FEATURES].sort((a, b) => Math.abs(agent.weights[b]) - Math.abs(agent.weights[a]));
  return (
    <section className="panel card">
      <div className="panel-head">
        <span style={{ color: agent.color }}>
          {agent.name.toUpperCase()} · {agent.archetypeName.toUpperCase()}
        </span>
        <button className="btn tiny" onClick={onClose}>
          ✕
        </button>
      </div>
      <div className="card-body">
        <div className="card-row">
          <span>GEN</span>
          <b>{agent.generation}</b>
          <span>MOOD</span>
          <b style={{ color: MOODS[agent.mood]?.color }}>{agent.mood}</b>
          <span>REP</span>
          <b>{agent.reputation.toFixed(2)}</b>
        </div>
        <div className="card-row">
          <span>EQUITY</span>
          <b>${fmt(agent.equity, 0)}</b>
          <span>P&L</span>
          <b className={pnl >= 0 ? "up" : "down"}>{signMoney(pnl, 0)}</b>
          <span>FILLS</span>
          <b>{agent.fills}</b>
        </div>
        <div className="card-quote">“{agent.quote}”</div>

        <div className="card-sub">TRAITS</div>
        <div className="traits">
          {Object.entries(agent.traits).map(([k, v]) => (
            <div key={k} className="trait">
              <span>{k}</span>
              <div className="bar">
                <i style={{ width: `${v * 100}%`, background: agent.color }} />
              </div>
            </div>
          ))}
        </div>

        <div className="card-sub">WHAT SHE BELIEVES</div>
        <ul className="beliefs">
          {(agent.beliefs.length ? agent.beliefs : ["Still forming a view."]).map((b, i) => (
            <li key={i}>{b}</li>
          ))}
        </ul>

        <div className="card-sub">MODEL WEIGHTS (learned)</div>
        <div className="weights">
          {learned.map((k) => {
            const w = agent.weights[k] || 0;
            const max = Math.max(...FEATURES.map((f) => Math.abs(agent.weights[f] || 0)), 1);
            const pct = (Math.abs(w) / max) * 50;
            return (
              <div key={k} className="wrow">
                <span className="wl">{FEATURE_LABEL[k]}</span>
                <div className="wbar">
                  <div className="wzero" />
                  <div
                    className="wfill"
                    style={{
                      width: `${pct}%`,
                      left: w >= 0 ? "50%" : `${50 - pct}%`,
                      background: w >= 0 ? "#5ceb8e" : "#f26457",
                    }}
                  />
                </div>
                <span className="wv">{w.toFixed(2)}</span>
              </div>
            );
          })}
        </div>

        <div className="card-sub">LESSONS ({agent.lessons.length})</div>
        <ul className="lessons">
          {agent.lessons.slice(0, 8).map((l, i) => (
            <li key={i}>
              <span className="gen-tag">g{l.gen}</span>
              {l.text}
            </li>
          ))}
          {!agent.lessons.length && <li className="empty-line">No lessons learned yet.</li>}
        </ul>
      </div>
    </section>
  );
}

/* -------------------------------- book -------------------------------- */
export function BookPanel({ floor }) {
  const positions = Object.entries(floor.account.positions);
  return (
    <section className="panel book">
      <div className="panel-head">
        <span>LIVE BOOK</span>
        <span className="muted">
          {positions.length}/{floor.houseRules.maxNames} NAMES · {fmt(floor.account.grossNotional(floor.market) / Math.max(1, floor.account.equity(floor.market)), 2)}× GROSS
        </span>
      </div>
      {!positions.length ? (
        <div className="empty small">Flat. Nobody has earned a position yet.</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>SYM</th>
              <th>SIDE</th>
              <th>QTY</th>
              <th>ENTRY</th>
              <th>LAST</th>
              <th>U-P&L</th>
              <th>OWNER</th>
            </tr>
          </thead>
          <tbody>
            {positions.map(([sym, p]) => {
              const meta = bySymbol(sym);
              const last = floor.market.feeds[sym].last;
              const pnl = (last - p.avgPrice) * p.qty;
              const owner = floor.get(p.agentId);
              return (
                <tr key={sym}>
                  <td style={{ color: meta.color }}>{sym}</td>
                  <td className={p.qty > 0 ? "up" : "down"}>{p.qty > 0 ? "LONG" : "SHORT"}</td>
                  <td>{fmt(Math.abs(p.qty), meta.qtyStep < 1 ? 3 : 0)}</td>
                  <td>{p.avgPrice.toFixed(meta.digits)}</td>
                  <td>{last.toFixed(meta.digits)}</td>
                  <td className={pnl >= 0 ? "up" : "down"}>{signMoney(pnl, 0)}</td>
                  <td style={{ color: owner?.color || "#8697b0" }}>{owner?.name || "desk"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </section>
  );
}

export function Blotter({ floor }) {
  const rows = floor.account.trades.slice(0, 60);
  return (
    <section className="panel blotter">
      <div className="panel-head">
        <span>BLOTTER</span>
        <span className="muted">REAL PRICES · SIM CAPITAL</span>
      </div>
      <div className="blotter-rows">
        {!rows.length && <div className="empty small">No fills yet.</div>}
        {rows.map((tr) => (
          <div className="blot" key={tr.id}>
            <span className="t">{new Date(tr.t).toLocaleTimeString("en-GB")}</span>
            <span className={`side ${tr.side}`}>{tr.side.toUpperCase()}</span>
            <span className="sym">{tr.symbol}</span>
            <span className="qty">{fmt(Math.abs(tr.qty), tr.qty < 10 ? 3 : 0)}</span>
            <span className="px">@ {tr.price.toFixed(tr.digits)}</span>
            <span className={`pnl ${tr.realizedPnl >= 0 ? "up" : "down"}`}>
              {tr.realizedPnl ? signMoney(tr.realizedPnl, 0) : "OPEN"}
            </span>
            <span className="who" style={{ color: floor.get(tr.agentId)?.color }}>
              {tr.agentName}
            </span>
            <span className="why">{tr.reason}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

export function LogPanel({ floor }) {
  return (
    <section className="panel logs">
      <div className="panel-head">
        <span>FLOOR LOG</span>
        <span className="muted">EVERY DECISION</span>
      </div>
      <div className="log-rows">
        {floor.log.slice(0, 80).map((l) => (
          <div key={l.id} className={`log ${l.kind}`}>
            <span className="lt">{new Date(l.t).toLocaleTimeString("en-GB")}</span>
            <span className="lx">{l.text}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

export function RulesPanel({ floor, actions }) {
  const r = floor.houseRules;
  return (
    <section className="panel rules">
      <div className="panel-head">
        <span>HOUSE MANDATE</span>
        <button className="btn tiny" onClick={() => actions.setRules({ allowSolo: !r.allowSolo })}>
          {r.allowSolo ? "FREE WILL ON" : "FREE WILL OFF"}
        </button>
      </div>
      <Slider label="MIN VOTES" value={r.minVotes} min={1} max={4} step={1} onChange={(v) => actions.setRules({ minVotes: +v })} />
      <Slider label="MAX NAMES" value={r.maxNames} min={1} max={8} step={1} onChange={(v) => actions.setRules({ maxNames: +v })} />
      <Slider label="MAX GROSS" value={r.maxGross} min={0.5} max={6} step={0.1} suffix="×" onChange={(v) => actions.setRules({ maxGross: +v })} />
      <Slider label="PER-TRADER" value={r.maxAgentExposure * 100} min={10} max={300} step={5} suffix="%" onChange={(v) => actions.setRules({ maxAgentExposure: +v / 100 })} />
      <Slider label="TIME STOP" value={r.maxHoldTicks} min={200} max={4000} step={100} suffix="t" onChange={(v) => actions.setRules({ maxHoldTicks: +v })} />
      <div className="mandate">
        <strong>R1</strong> high-risk tape → nobody trades. <strong>R2</strong> two desks must agree.
        <br />
        <strong>R3</strong> stand-off = hold. <strong>R4</strong> agents may still act alone — with smaller size.
      </div>
      <div className="danger-row">
        <button className="btn tiny warn" onClick={actions.reset}>
          RESET MEMORIES
        </button>
      </div>
    </section>
  );
}

function Slider({ label, value, min, max, step, suffix = "", onChange }) {
  return (
    <label className="slider">
      <span className="s-label">{label}</span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(e.target.value)} />
      <span className="s-value">
        {value}
        {suffix}
      </span>
    </label>
  );
}

export function EquityCurve({ floor }) {
  const data = floor.account.equityCurve.slice(-200).map((p) => p.equity);
  if (data.length < 2) return null;
  const w = 268;
  const h = 52;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const span = max - min || 1;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * w},${h - ((v - min) / span) * (h - 6) - 3}`).join(" ");
  const up = data[data.length - 1] >= data[0];
  return (
    <div className="eq">
      <svg width={w} height={h}>
        <polygon points={`0,${h} ${pts} ${w},${h}`} fill={up ? "rgba(92,235,142,0.16)" : "rgba(242,100,87,0.16)"} />
        <polyline points={pts} fill="none" stroke={up ? "#5ceb8e" : "#f26457"} strokeWidth="1.6" />
      </svg>
      <div className="eq-label">ACCOUNT EQUITY · THIS SESSION</div>
    </div>
  );
}

export function ChatPanel({ floor }) {
  return (
    <section className="panel chat-panel">
      <div className="panel-head">
        <span>OPEN MIC</span>
        <span className="muted">DESK CHATTER</span>
      </div>
      <div className="chat-mini">
        {floor.chat.slice(0, 26).map((c) => (
          <div key={c.id} className="chat-line">
            <b style={{ color: c.color }}>{c.name}</b>
            <span>{c.text}</span>
          </div>
        ))}
        {!floor.chat.length && <div className="empty small">Quiet so far.</div>}
      </div>
    </section>
  );
}

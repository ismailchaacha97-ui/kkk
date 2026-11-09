import React, { useEffect, useMemo, useRef, useState } from "react";
import { SYMBOLS } from "../engine/market.js";
import { DESKS } from "../engine/floor.js";

const fmt = (n, d = 2) =>
  Number(n).toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d });

function Sparkline({ data, color = "#5ceb8e", w = 120, h = 34 }) {
  if (!data || data.length < 2) return <svg width={w} height={h} />;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const span = max - min || 1;
  const pts = data
    .map((v, i) => `${(i / (data.length - 1)) * w},${h - ((v - min) / span) * (h - 4) - 2}`)
    .join(" ");
  return (
    <svg width={w} height={h} className="spark">
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.6" />
    </svg>
  );
}

export function TopBar({ floor, summary, paused, actions, speed }) {
  return (
    <header className="topbar">
      <div className="brand">
        <div className="mark">M</div>
        <div>
          <div className="brand-title">MERIDIAN CAPITAL</div>
          <div className="brand-sub">AI TRADING FLOOR · LIVE BOOK</div>
        </div>
      </div>
      <div className="stats">
        <Stat label="EQUITY" value={`$${fmt(summary.equity)}`} accent />
        <Stat
          label="DAY P&L"
          value={`${summary.dayPnl >= 0 ? "+" : "−"}$${fmt(Math.abs(summary.dayPnl))}`}
          sub={`${summary.dayPnlPct >= 0 ? "+" : ""}${fmt(summary.dayPnlPct, 2)}%`}
          tone={summary.dayPnl >= 0 ? "up" : "down"}
        />
        <Stat label="EXPOSURE" value={`${fmt(summary.grossExposure, 2)}×`} sub={`${summary.openPositions} open`} />
        <Stat label="WIN RATE" value={`${fmt(summary.winRate, 1)}%`} sub={`${summary.closedCount} closed · ${summary.fills} fills`} />
        <Stat label="DEBATES" value={summary.debates} sub={`${summary.holds} stood down`} />
      </div>
      <div className="controls">
        <div className="session">
          <span className="dot" /> MKT OPEN · 10:{String(42 + (floor.market.tick % 18)).padStart(2, "0")}
        </div>
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
        <button className="btn primary" onClick={actions.forceDebate}>
          CONVENE DESK
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

export function Watchlist({ floor, selected, onSelect }) {
  const snap = floor.market.snapshot();
  return (
    <section className="panel watchlist">
      <div className="panel-head">
        <span>WATCHLIST</span>
        <span className="muted">{snap.length} SYMBOLS</span>
      </div>
      <div className="wl-rows">
        {snap.map((s) => {
          const f = floor.market.feeds[s.symbol];
          const closes = f.bars.slice(-32).map((b) => b.c);
          const up = s.changePct >= 0;
          const pos = floor.account.position(s.symbol);
          const live = floor.threads.some((t) => t.symbol === s.symbol && t.status === "talking");
          return (
            <button
              key={s.symbol}
              className={`wl-row ${selected === s.symbol ? "sel" : ""}`}
              onClick={() => onSelect(s.symbol)}
            >
              <span className="wl-sym" style={{ color: s.color }}>
                {s.symbol}
                {live && <i className="live" />}
              </span>
              <span className="wl-px">{s.last.toFixed(s.digits)}</span>
              <Sparkline data={closes} color={up ? "#5ceb8e" : "#f26457"} w={86} h={26} />
              <span className={`wl-chg ${up ? "up" : "down"}`}>
                {up ? "▲" : "▼"} {Math.abs(s.changePct).toFixed(2)}%
              </span>
              <span className="wl-rsi">RSI {s.rsi.toFixed(0)}</span>
              {pos !== 0 && (
                <span className={`badge ${pos > 0 ? "long" : "short"}`}>
                  {pos > 0 ? "LONG" : "SHORT"} {Math.abs(pos) >= 1000 ? `${(Math.abs(pos) / 1000).toFixed(1)}k` : Math.abs(pos).toFixed(Math.abs(pos) < 10 ? 2 : 0)}
                </span>
              )}
            </button>
          );
        })}
      </div>
    </section>
  );
}

export function DebateRoom({ floor, thread, onPick, onForce }) {
  const scroller = useRef(null);
  useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight;
  }, [thread?.messages.length, thread?.id]);

  const talking = thread?.status === "talking";
  return (
    <section className="panel debate">
      <div className="panel-head">
        <span>DEBATE ROOM</span>
        <span className="muted">{thread ? thread.symbol : "IDLE"}</span>
      </div>
      <div className="thread-tabs">
        {floor.threads.slice(0, 5).map((t) => (
          <button
            key={t.id}
            className={`thread-tab ${t.id === thread?.id ? "on" : ""} ${t.status}`}
            onClick={() => onPick(t.id)}
          >
            {t.symbol} <small>{t.status === "talking" ? "LIVE" : t.status.replace("-", " ").toUpperCase()}</small>
          </button>
        ))}
        <button className="thread-tab ghost" onClick={onForce}>
          + NEW
        </button>
      </div>
      <div className="chat" ref={scroller}>
        {!thread && <div className="empty">No debate on the floor yet. Hit “CONVENE DESK”.</div>}
        {thread?.messages.map((m) => (
          <Message key={m.id} m={m} />
        ))}
        {talking && (
          <div className="typing">
            <span /> <span /> <span />
          </div>
        )}
      </div>
      {thread?.verdict && (
        <div className={`verdict ${thread.verdict.signal}`}>
          <div className="v-label">FINAL VERDICT</div>
          <div className="v-signal">{thread.verdict.signal.toUpperCase()}</div>
          <div className="v-comment">{thread.verdict.comment}</div>
        </div>
      )}
    </section>
  );
}

function Message({ m }) {
  if (m.kind === "system")
    return <div className="msg system">{m.text}</div>;
  const who = DESKS[m.speaker] || { name: m.speaker, color: "#9fb2cd", role: "" };
  if (m.kind === "verdict")
    return (
      <div className={`msg verdict-msg ${m.signal}`}>
        <div className="msg-head">
          <span className="who" style={{ color: who.color }}>
            ⚖ {who.name.toUpperCase()}
          </span>
          <span className="rule">{m.rule}</span>
        </div>
        <div className="msg-body">{m.text}</div>
      </div>
    );
  return (
    <div className={`msg ${m.kind}`}>
      <div className="msg-head">
        <span className="avatar" style={{ borderColor: who.color, color: who.color }}>
          {who.name[0]}
        </span>
        <span className="who" style={{ color: who.color }}>
          {who.name.toUpperCase()}
        </span>
        <span className="role">{who.role}</span>
        {m.stance && m.stance !== "neutral" && (
          <span className={`pill ${m.stance}`}>{m.stance.toUpperCase()}</span>
        )}
        {m.verdict && <span className={`pill risk-${m.verdict.split(" ")[0].toLowerCase()}`}>{m.verdict}</span>}
        {m.conf !== undefined && <span className="conf">{Math.round(m.conf * 100)}%</span>}
      </div>
      <div className="msg-body">{m.text}</div>
    </div>
  );
}

export function BookPanel({ floor }) {
  const positions = Object.entries(floor.account.positions);
  if (!positions.length)
    return (
      <section className="panel book">
        <div className="panel-head">
          <span>OPEN BOOK</span>
          <span className="muted">FLAT</span>
        </div>
        <div className="empty small">No open exposure. The desk is waiting for a clean setup.</div>
      </section>
    );
  return (
    <section className="panel book">
      <div className="panel-head">
        <span>OPEN BOOK</span>
        <span className="muted">
          {positions.length}/{floor.rules.maxPositions} · GROSS {floor.grossExposure().toFixed(2)}×
        </span>
      </div>
      <table>
        <thead>
          <tr>
            <th>SYM</th>
            <th>SIDE</th>
            <th>QTY</th>
            <th>ENTRY</th>
            <th>LAST</th>
            <th>U-P&L</th>
          </tr>
        </thead>
        <tbody>
          {positions.map(([sym, p]) => {
            const meta = SYMBOLS.find((s) => s.symbol === sym);
            const last = floor.market.feeds[sym].last;
            const pnl = (last - p.avgPrice) * p.qty;
            const stopped = p.agentId === "risk";
            return (
              <tr key={sym}>
                <td style={{ color: meta.color }}>{sym}</td>
                <td className={p.qty > 0 ? "up" : "down"}>{p.qty > 0 ? "LONG" : "SHORT"}</td>
                <td>{fmt(Math.abs(p.qty), Math.abs(p.qty) < 10 ? 2 : 0)}</td>
                <td>{p.avgPrice.toFixed(meta.digits)}</td>
                <td>{last.toFixed(meta.digits)}</td>
                <td className={pnl >= 0 ? "up" : "down"}>
                  {pnl >= 0 ? "+" : "−"}
                  {fmt(Math.abs(pnl))}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </section>
  );
}

export function Blotter({ floor }) {
  const rows = floor.account.trades.slice(0, 40);
  return (
    <section className="panel blotter">
      <div className="panel-head">
        <span>BLOTTER</span>
        <span className="muted">REAL FILLS · SIM CASH</span>
      </div>
      <div className="blotter-rows">
        {rows.length === 0 && <div className="empty small">No fills yet today.</div>}
        {rows.map((tr) => (
          <div className="blot" key={tr.id}>
            <span className="t">{new Date(tr.t).toLocaleTimeString("en-GB")}</span>
            <span className={`side ${tr.side}`}>{tr.side.toUpperCase()}</span>
            <span className="sym">{tr.symbol}</span>
            <span className="qty">{Number(tr.qty).toFixed(tr.qty < 10 ? 2 : 0)}</span>
            <span className="px">@ {tr.price.toFixed(tr.digits)}</span>
            <span className={`pnl ${tr.realizedPnl >= 0 ? "up" : "down"}`}>
              {tr.realizedPnl ? `${tr.realizedPnl >= 0 ? "+" : "−"}${fmt(Math.abs(tr.realizedPnl))}` : "OPEN"}
            </span>
            <span className="why">{tr.reason}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

export function EquityCurve({ floor }) {
  const data = floor.account.equityCurve.slice(-160).map((p) => p.equity);
  if (data.length < 2) return null;
  const w = 260;
  const h = 54;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const span = max - min || 1;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * w},${h - ((v - min) / span) * (h - 6) - 3}`).join(" ");
  const up = data[data.length - 1] >= data[0];
  return (
    <div className="eq">
      <svg width={w} height={h}>
        <defs>
          <linearGradient id="eqg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={up ? "#5ceb8e" : "#f26457"} stopOpacity="0.35" />
            <stop offset="100%" stopColor={up ? "#5ceb8e" : "#f26457"} stopOpacity="0" />
          </linearGradient>
        </defs>
        <polygon points={`0,${h} ${pts} ${w},${h}`} fill="url(#eqg)" />
        <polyline points={pts} fill="none" stroke={up ? "#5ceb8e" : "#f26457"} strokeWidth="1.6" />
      </svg>
      <div className="eq-label">EQUITY · SESSION</div>
    </div>
  );
}

export function RulesPanel({ floor, actions }) {
  const [r, setR] = useState({ ...floor.rules });
  const change = (k, v) => {
    const next = { ...r, [k]: Number(v) };
    setR(next);
    actions.setRules(next);
  };
  return (
    <section className="panel rules">
      <div className="panel-head">
        <span>RISK MANDATE</span>
        <span className="muted">HARD-CODED</span>
      </div>
      <Slider label="STOP LOSS" value={r.stopLossPct * 100} min={0.2} max={3} step={0.1} suffix="%" onChange={(v) => change("stopLossPct", v / 100)} />
      <Slider label="TAKE PROFIT" value={r.takeProfitPct * 100} min={0.4} max={6} step={0.1} suffix="%" onChange={(v) => change("takeProfitPct", v / 100)} />
      <Slider label="RISK / TRADE" value={r.riskPerTrade * 100} min={0.2} max={4} step={0.1} suffix="%" onChange={(v) => change("riskPerTrade", v / 100)} />
      <Slider label="MAX GROSS" value={r.maxGrossExposure} min={0.5} max={4} step={0.1} suffix="×" onChange={(v) => change("maxGrossExposure", v)} />
      <Slider label="MAX NAMES" value={r.maxPositions} min={1} max={5} step={1} suffix="" onChange={(v) => change("maxPositions", v)} />
      <Slider label="TIME STOP" value={r.maxHoldBars} min={10} max={120} step={1} suffix="t" onChange={(v) => change("maxHoldBars", v)} />
      <div className="mandate">
        <strong>R1</strong> Risk VETO on HIGH RISK — no exceptions.
        <br />
        <strong>R2</strong> Trade only with 2 of 3 desks agreeing.
        <br />
        <strong>R3</strong> Unresolved bull/bear conflict → stand down.
        <br />
        <strong>R4</strong> 5× margin, hard stop on every fill, time stop on every idea.
      </div>
    </section>
  );
}

function Slider({ label, value, min, max, step, suffix, onChange }) {
  return (
    <label className="slider">
      <span className="s-label">{label}</span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(e.target.value)} />
      <span className="s-value">
        {Number(value).toFixed(1)}
        {suffix}
      </span>
    </label>
  );
}

export function LogPanel({ floor }) {
  return (
    <section className="panel logs">
      <div className="panel-head">
        <span>FLOOR LOG</span>
        <span className="muted">MT5-STYLE</span>
      </div>
      <div className="log-rows">
        {floor.log.slice(0, 60).map((l) => (
          <div key={l.id} className={`log ${l.kind}`}>
            <span className="lt">{new Date(l.t).toLocaleTimeString("en-GB")}</span>
            <span className="lx">{l.text}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

export function DeskStrip({ floor }) {
  return (
    <div className="desk-strip">
      {Object.values(DESKS).map((d) => {
        const a = floor.agents[d.id];
        const speaking = a && Date.now() - a.lastSpokeAt < 2600;
        return (
          <div key={d.id} className={`desk-chip ${speaking ? "speaking" : ""}`} style={{ "--c": d.color }}>
            <div className="chip-avatar">{d.name[0]}</div>
            <div className="chip-meta">
              <div className="chip-name">{d.name}</div>
              <div className="chip-role">{d.role}</div>
              <div className="chip-quote">{a?.quote}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

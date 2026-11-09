import React from "react";
import Scene3D from "./scene/Scene3D.jsx";
import {
  TopBar,
  Watchlist,
  DebateRoom,
  PeoplePanel,
  TraderCard,
  BookPanel,
  Blotter,
  LogPanel,
  RulesPanel,
  EquityCurve,
  ChatPanel,
} from "./components/Panels.jsx";
import { useSim } from "./sim/useSim.js";
import { INSTRUMENTS } from "./engine/instruments.js";

export default function App() {
  const { floor, booted, paused, speed, selectedSymbol, selectedAgent, actions } = useSim();
  const summary = floor.summary();
  const agent = selectedAgent ? floor.get(selectedAgent) : null;

  return (
    <div className="app">
      <TopBar floor={floor} summary={summary} paused={paused} speed={speed} actions={actions} />

      <main className="layout">
        <aside className="col left">
          <Watchlist floor={floor} selected={selectedSymbol} onSelect={actions.setSelectedSymbol} />
          <PeoplePanel floor={floor} selectedAgent={selectedAgent} onSelectAgent={actions.selectAgent} />
          <div className="panel mini">
            <div className="panel-head">
              <span>SESSION</span>
              <span className="muted">{INSTRUMENTS.length} MARKETS</span>
            </div>
            <EquityCurve floor={floor} />
            <div className="session-facts">
              <div>
                <span>CASH</span>
                <b>${Math.round(summary.cash).toLocaleString()}</b>
              </div>
              <div>
                <span>REALIZED</span>
                <b className={summary.realized >= 0 ? "up" : "down"}>
                  {summary.realized >= 0 ? "+" : "−"}${Math.abs(summary.realized).toFixed(0)}
                </b>
              </div>
              <div>
                <span>UNREALIZED</span>
                <b className={summary.unrealized >= 0 ? "up" : "down"}>
                  {summary.unrealized >= 0 ? "+" : "−"}${Math.abs(summary.unrealized).toFixed(0)}
                </b>
              </div>
              <div>
                <span>GENERATIONS</span>
                <b>{summary.generations}</b>
              </div>
            </div>
          </div>
          <RulesPanel floor={floor} actions={actions} />
        </aside>

        <section className="col center">
          <div className="viewport">
            <Scene3D floor={floor} />
            {!booted && (
              <div className="boot">
                <div className="boot-card">
                  <div className="boot-title">CONNECTING TO LIVE MARKETS</div>
                  <div className="boot-sub">pulling real candles from public exchange feeds…</div>
                  <div className="boot-bar">
                    <i />
                  </div>
                </div>
              </div>
            )}
            <div className="viewport-hud">
              <div className="hud-title">MERIDIAN FLOOR · LIVE 3D</div>
              <div className="hud-hint">drag to orbit · scroll to zoom · R = auto-rotate · F = reset view · click a trader</div>
            </div>
            {summary.feedStatus === "offline" && booted && (
              <div className="offline-banner">
                <b>NO LIVE FEED REACHABLE</b>
                <span>{summary.feedDetail}</span>
                <button className="btn tiny" onClick={actions.reconnect}>RETRY</button>
              </div>
            )}
            <div className="floating-chips">
              {floor.agents.slice(0, 10).map((a) => (
                <button
                  key={a.id}
                  className={`fchip ${Date.now() - (a.lastSpokeAt || 0) < 2600 ? "talking" : ""} ${selectedAgent === a.id ? "sel" : ""}`}
                  style={{ "--c": a.color }}
                  onClick={() => actions.selectAgent(a.id)}
                >
                  <i />
                  {a.name}
                </button>
              ))}
            </div>
          </div>

          <div className="strip">
            {floor.agents.slice(0, 4).map((a) => (
              <div key={a.id} className="desk-chip" style={{ "--c": a.color }}>
                <div className="chip-avatar">{a.name[0]}</div>
                <div className="chip-meta">
                  <div className="chip-name">
                    {a.name} <em>g{a.generation}</em>
                  </div>
                  <div className="chip-quote">{a.quote}</div>
                </div>
              </div>
            ))}
          </div>
        </section>

        <aside className="col right">
          <DebateRoom floor={floor} onSelectAgent={actions.selectAgent} onCall={actions.callDebate} />
          {agent ? (
            <TraderCard floor={floor} agent={agent} onClose={() => actions.selectAgent(agent.id)} />
          ) : (
            <PeoplePanel floor={floor} selectedAgent={selectedAgent} onSelectAgent={actions.selectAgent} compact />
          )}
          <BookPanel floor={floor} />
          <Blotter floor={floor} />
          <div className="dual">
            <ChatPanel floor={floor} />
            <LogPanel floor={floor} />
          </div>
        </aside>
      </main>

      <footer className="ticker-bar">
        <div className="ticker-track">
          {[0, 1].map((k) => (
            <div className="ticker-inner" key={k}>
              {floor.market.snapshot().map((s) => (
                <span key={s.symbol + k}>
                  <b style={{ color: s.color }}>{s.symbol}</b> {s.last ? s.last.toFixed(s.digits) : "—"}{" "}
                  <em className={s.changePct >= 0 ? "up" : "down"}>
                    {s.changePct >= 0 ? "▲" : "▼"} {Math.abs(s.changePct).toFixed(2)}%
                  </em>
                  <i className={s.live ? "dot-live" : "dot-dead"} />
                </span>
              ))}
            </div>
          ))}
        </div>
        <div className="sim-note">
          LIVE PUBLIC MARKET DATA · {summary.feedStatus.toUpperCase()} · TRADING IS SIMULATED — NOT INVESTMENT ADVICE
        </div>
      </footer>
    </div>
  );
}

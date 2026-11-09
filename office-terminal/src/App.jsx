import React from "react";
import Scene3D from "./components/Scene3D.jsx";
import {
  TopBar,
  Watchlist,
  DebateRoom,
  BookPanel,
  Blotter,
  EquityCurve,
  RulesPanel,
  LogPanel,
  DeskStrip,
} from "./components/Panels.jsx";
import { useSim } from "./sim/useSim.js";

export default function App() {
  const { floor, thread, selectedSymbol, speed, paused, actions } = useSim();
  const summary = floor.summary();

  return (
    <div className="app">
      <TopBar floor={floor} summary={summary} paused={paused} actions={actions} speed={speed} />
      <main className="layout">
        <aside className="col left">
          <Watchlist floor={floor} selected={selectedSymbol} onSelect={actions.setSelectedSymbol} />
          <RulesPanel floor={floor} actions={actions} />
          <div className="panel mini">
            <div className="panel-head">
              <span>SESSION</span>
              <span className="muted">M1 · SIM</span>
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
                  {summary.realized >= 0 ? "+" : "−"}${Math.abs(summary.realized).toFixed(2)}
                </b>
              </div>
              <div>
                <span>UNREALIZED</span>
                <b className={summary.unrealized >= 0 ? "up" : "down"}>
                  {summary.unrealized >= 0 ? "+" : "−"}${Math.abs(summary.unrealized).toFixed(2)}
                </b>
              </div>
            </div>
          </div>
        </aside>

        <section className="col center">
          <div className="viewport">
            <Scene3D floor={floor} />
            <div className="viewport-hud">
              <div className="hud-title">FLOOR 41 · LIVE RENDER</div>
              <div className="hud-hint">drag to orbit · scroll to zoom</div>
            </div>
            <div className="spotlight">
              <div className="sp-label">ON THE FLOOR</div>
              <div className="sp-quote">
                {floor.threads.find((t) => t.status === "talking")
                  ? `Breakout room: ${floor.threads.find((t) => t.status === "talking").symbol} being argued right now`
                  : "Desks are scanning. Next debate convenes shortly."}
              </div>
            </div>
          </div>
          <DeskStrip floor={floor} />
        </section>

        <aside className="col right">
          <DebateRoom
            floor={floor}
            thread={thread}
            onPick={actions.selectThread}
            onForce={actions.forceDebate}
          />
          <BookPanel floor={floor} />
          <Blotter floor={floor} />
          <LogPanel floor={floor} />
        </aside>
      </main>
      <footer className="ticker-bar">
        <div className="ticker-track">
          {[0, 1].map((k) => (
            <div className="ticker-inner" key={k}>
              {floor.market.snapshot().map((s) => (
                <span key={s.symbol + k}>
                  <b style={{ color: s.color }}>{s.symbol}</b> {s.last.toFixed(s.digits)}{" "}
                  <em className={s.changePct >= 0 ? "up" : "down"}>
                    {s.changePct >= 0 ? "▲" : "▼"} {Math.abs(s.changePct).toFixed(2)}%
                  </em>
                </span>
              ))}
            </div>
          ))}
        </div>
        <div className="sim-note">SIMULATED MARKET · NOT INVESTMENT ADVICE</div>
      </footer>
    </div>
  );
}

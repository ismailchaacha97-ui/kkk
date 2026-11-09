import { drawChart, drawDeskScreen, drawTicker, drawWhiteboard, drawWallBoard } from "./canvas.js";
import { bySymbol } from "../engine/instruments.js";

const hex = (c) => c;

export function updateScreens(office, desks, floor) {
  const snapshot = floor.market.snapshot();
  const focusSymbol = floor.debates[0]?.symbol || snapshot[0]?.symbol;
  const f = floor.market.feeds[focusSymbol];
  const meta = bySymbol(focusSymbol);

  // wall board
  drawWallBoard(office.wallTex.ctx, 1400, 420, snapshot, floor.feedStatus, floor.summary());
  office.wallTex.tex.needsUpdate = true;

  // whiteboard: who learned what
  drawWhiteboard(office.wbTex.ctx, 1100, 620, floor.agents, floor.log);
  office.wbTex.tex.needsUpdate = true;

  // holo table chart
  if (f && f.bars.length) {
    drawChart(office.holo.ctx, 1024, 620, f.bars.concat([{ ...f.bars[f.bars.length - 1], c: f.last }]), {
      accent: meta.color,
      symbol: focusSymbol,
      price: f.last,
      digits: meta.digits,
      rsi: f.rsi,
      live: f.live,
      granularity: f.granularity,
    });
    office.holo.tex.needsUpdate = true;
  }

  // per-desk monitors
  for (const [id, entry] of desks) {
    const agent = floor.get(id);
    if (!agent) continue;
    entry.deskObj.screens.forEach((screen) => {
      const ctx = screen.tex.ctx;
      if (screen.kind === 0) {
        drawDeskScreen(ctx, 512, 320, agent, {
          lastMessage: agent.quote,
          pnl: agent.equity - agent.startEquity,
          trades: agent.fills,
          mood: agent.moodDef,
        });
      } else if (screen.kind === 1) {
        const sym = agent.focusSymbol || focusSymbol;
        const ff = floor.market.feeds[sym];
        const m = bySymbol(sym);
        if (ff?.bars.length) {
          drawChart(ctx, 512, 320, ff.bars.concat([{ ...ff.bars[ff.bars.length - 1], c: ff.last }]), {
            accent: m.color,
            symbol: sym,
            price: ff.last,
            digits: m.digits,
            rsi: ff.rsi,
            live: ff.live,
            compact: true,
          });
        }
      } else {
        drawTicker(ctx, 512, 320, snapshot.slice(0, 4), 0);
      }
      screen.tex.tex.needsUpdate = true;
    });
  }
}

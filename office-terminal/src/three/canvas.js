import * as THREE from "three";

export function makeCanvas(w, h) {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  return c;
}

export function canvasTexture(w, h) {
  const c = makeCanvas(w, h);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return { canvas: c, ctx: c.getContext("2d"), tex };
}

export function drawCity(ctx, w, h, t = 0) {
  const sky = ctx.createLinearGradient(0, 0, 0, h);
  sky.addColorStop(0, "#050a14");
  sky.addColorStop(0.55, "#0a1424");
  sky.addColorStop(1, "#122036");
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, w, h);
  // moon glow
  const g = ctx.createRadialGradient(w * 0.78, h * 0.18, 4, w * 0.78, h * 0.18, h * 0.5);
  g.addColorStop(0, "rgba(180,210,255,0.35)");
  g.addColorStop(1, "rgba(180,210,255,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);

  let x = -20;
  let seed = 7;
  const rnd = () => {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
  while (x < w + 40) {
    const bw = 30 + rnd() * 70;
    const bh = h * (0.25 + rnd() * 0.55);
    ctx.fillStyle = "#070d18";
    ctx.fillRect(x, h - bh, bw, bh);
    ctx.strokeStyle = "rgba(120,170,255,0.12)";
    ctx.lineWidth = 1;
    ctx.strokeRect(x + 0.5, h - bh + 0.5, bw, bh);
    for (let wy = h - bh + 10; wy < h - 8; wy += 14) {
      for (let wx = x + 6; wx < x + bw - 6; wx += 12) {
        if (rnd() > 0.42) {
          const warm = rnd() > 0.75;
          ctx.fillStyle = warm ? "rgba(245,184,65,0.55)" : "rgba(140,200,255,0.4)";
          ctx.fillRect(wx, wy, 4, 6);
        }
      }
    }
    x += bw + 6 + rnd() * 12;
  }
}

export function drawWhiteboard(ctx, w, h, traders, log) {
  ctx.fillStyle = "#eef3f8";
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = "#0d1b2a";
  ctx.font = "700 40px ui-monospace, monospace";
  ctx.fillText("FLOOR NOTES / WHAT WE LEARNED", 34, 58);
  ctx.strokeStyle = "rgba(13,27,42,0.35)";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(34, 76);
  ctx.lineTo(w - 34, 76);
  ctx.stroke();

  ctx.font = "600 26px ui-monospace, monospace";
  let y = 122;
  const rows = traders.slice(0, 6);
  for (const t of rows) {
    ctx.fillStyle = t.color;
    ctx.fillText(`${t.name.toUpperCase()} · gen ${t.generation}`, 34, y);
    ctx.fillStyle = "#22303f";
    ctx.font = "500 22px ui-monospace, monospace";
    const lesson = t.lessons?.[0]?.text || t.beliefs?.[0] || "still learning the tape";
    const cut = lesson.length > 74 ? lesson.slice(0, 72) + "…" : lesson;
    ctx.fillText(cut, 360, y);
    ctx.font = "600 26px ui-monospace, monospace";
    y += 46;
  }
  ctx.strokeStyle = "#c0392b";
  ctx.font = "700 24px ui-monospace, monospace";
  ctx.fillStyle = "#c0392b";
  ctx.fillText("R1 risk veto · R2 two desks agree · R3 stand-off = hold", 34, h - 30);
}

export function drawWallBoard(ctx, w, h, snapshot, feedStatus, summary) {
  ctx.fillStyle = "#050a12";
  ctx.fillRect(0, 0, w, h);
  // header
  ctx.fillStyle = feedStatus === "live" ? "#5ceb8e" : feedStatus === "partial" ? "#f5b841" : "#f26457";
  ctx.font = "700 30px ui-monospace, monospace";
  ctx.fillText(`LIVE FEED · ${feedStatus.toUpperCase()} · ${snapshot.filter((s) => s.live).length}/${snapshot.length}`, 30, 46);
  ctx.font = "500 22px ui-monospace, monospace";
  ctx.fillStyle = "rgba(159,178,205,0.9)";
  ctx.textAlign = "right";
  ctx.fillText(`EQ $${Math.round(summary.equity).toLocaleString()}  ·  TRADERS ${summary.traders}  ·  GEN ${summary.generations}  ·  ${summary.fills} FILLS`, w - 30, 46);
  ctx.textAlign = "left";

  const cols = 3;
  const cellW = (w - 60) / cols;
  const cellH = (h - 90) / 2;
  snapshot.slice(0, 6).forEach((s, i) => {
    const cx = 30 + (i % cols) * cellW;
    const cy = 76 + Math.floor(i / cols) * cellH;
    ctx.fillStyle = "rgba(255,255,255,0.035)";
    ctx.fillRect(cx + 6, cy + 6, cellW - 16, cellH - 16);
    ctx.fillStyle = s.color;
    ctx.font = "700 28px ui-monospace, monospace";
    ctx.fillText(s.symbol, cx + 20, cy + 48);
    ctx.fillStyle = "#e6eefc";
    ctx.fillText(s.last.toFixed(s.digits), cx + 20, cy + 88);
    ctx.fillStyle = s.changePct >= 0 ? "#5ceb8e" : "#f26457";
    ctx.font = "600 22px ui-monospace, monospace";
    ctx.fillText(`${s.changePct >= 0 ? "▲" : "▼"} ${Math.abs(s.changePct).toFixed(2)}%`, cx + 20, cy + 120);
    ctx.fillStyle = "rgba(159,178,205,0.85)";
    ctx.font = "500 18px ui-monospace, monospace";
    ctx.fillText(`RSI ${s.rsi.toFixed(0)} · ${s.granularity} · ${s.live ? "LIVE" : "OFFLINE"}`, cx + 20, cy + 150);
  });
}

export function drawTicker(ctx, w, h, snapshot, offset) {
  ctx.fillStyle = "#070c15";
  ctx.fillRect(0, 0, w, h);
  const rowH = h / snapshot.length;
  snapshot.forEach((s, i) => {
    const y = i * rowH;
    ctx.fillStyle = i % 2 === 0 ? "rgba(255,255,255,0.025)" : "rgba(255,255,255,0.055)";
    ctx.fillRect(0, y, w, rowH - 2);
    ctx.fillStyle = s.color;
    ctx.fillRect(0, y, 6, rowH - 2);
    ctx.font = "600 26px ui-monospace, monospace";
    ctx.fillStyle = "#e6eefc";
    ctx.textBaseline = "middle";
    ctx.fillText(s.symbol.padEnd(7), 18, y + rowH / 2);
    ctx.fillStyle = "#9fb2cd";
    ctx.fillText(s.last.toFixed(s.digits), 200, y + rowH / 2);
    const up = s.changePct >= 0;
    ctx.fillStyle = up ? "#5ceb8e" : "#f26457";
    ctx.fillText(`${up ? "▲" : "▼"} ${Math.abs(s.changePct).toFixed(2)}%`, w - 190, y + rowH / 2);
  });
}

export function drawChart(ctx, w, h, bars, opts = {}) {
  const { accent = "#5ceb8e", symbol = "", price = 0, digits = 2, rsi = 50, live = false, compact = false, granularity = "" } = opts;
  ctx.fillStyle = "#060b14";
  ctx.fillRect(0, 0, w, h);

  // grid
  ctx.strokeStyle = "rgba(110,150,210,0.13)";
  ctx.lineWidth = 1;
  for (let i = 1; i < 6; i++) {
    const y = (h / 6) * i;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }

  const data = bars.slice(-Math.min(bars.length, 90));
  if (!data.length) return;
  const hi = Math.max(...data.map((b) => b.h));
  const lo = Math.min(...data.map((b) => b.l));
  const pad = (hi - lo) * 0.12 || hi * 0.001;
  const top = hi + pad;
  const bot = lo - pad;
  const Y = (p) => h - ((p - bot) / (top - bot)) * h;
  const bw = w / data.length;

  // area under closes
  const grad = ctx.createLinearGradient(0, 0, 0, h);
  grad.addColorStop(0, "rgba(92,235,142,0.18)");
  grad.addColorStop(1, "rgba(92,235,142,0)");
  ctx.beginPath();
  ctx.moveTo(0, h);
  data.forEach((b, i) => ctx.lineTo(i * bw + bw / 2, Y(b.c)));
  ctx.lineTo(w, h);
  ctx.closePath();
  ctx.fillStyle = grad;
  ctx.fill();

  data.forEach((b, i) => {
    const up = b.c >= b.o;
    const col = up ? "#5ceb8e" : "#f26457";
    const x = i * bw + bw / 2;
    ctx.strokeStyle = col;
    ctx.fillStyle = col;
    ctx.globalAlpha = 0.9;
    ctx.beginPath();
    ctx.moveTo(x, Y(b.h));
    ctx.lineTo(x, Y(b.l));
    ctx.stroke();
    const yo = Y(b.o);
    const yc = Y(b.c);
    const bh = Math.max(1.2, Math.abs(yc - yo));
    ctx.fillRect(x - bw * 0.3, Math.min(yo, yc), Math.max(1.4, bw * 0.6), bh);
    ctx.globalAlpha = 1;
  });

  // last price line
  ctx.setLineDash([6, 6]);
  ctx.strokeStyle = accent;
  ctx.beginPath();
  ctx.moveTo(0, Y(price));
  ctx.lineTo(w, Y(price));
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = accent;
  ctx.fillRect(w - 4, Y(price) - 10, 4, 20);

  // labels
  ctx.font = compact ? "600 16px ui-monospace, monospace" : "600 20px ui-monospace, monospace";
  ctx.fillStyle = "#e6eefc";
  ctx.fillText(symbol, 16, 30);
  if (live) {
    ctx.fillStyle = "#5ceb8e";
    ctx.fillRect(16, 40, 7, 7);
    ctx.fillStyle = "rgba(159,178,205,0.85)";
    ctx.font = "500 13px ui-monospace, monospace";
    ctx.fillText(`LIVE ${granularity || ""}`, 30, 48);
  }
  ctx.fillStyle = accent;
  ctx.textAlign = "right";
  ctx.fillText(price.toFixed(digits), w - 14, 30);
  ctx.textAlign = "left";
  ctx.fillStyle = "rgba(159,178,205,0.85)";
  ctx.font = "500 16px ui-monospace, monospace";
  ctx.fillText(`RSI ${rsi.toFixed(1)}`, 16, h - 14);
  ctx.textAlign = "right";
  ctx.fillText(granularity || "", w - 12, h - 14);
  ctx.textAlign = "left";
}

export function drawDeskScreen(ctx, w, h, agent, state) {
  ctx.fillStyle = "#060b14";
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = agent.color;
  ctx.globalAlpha = 0.5;
  ctx.lineWidth = 3;
  ctx.strokeRect(3, 3, w - 6, h - 6);
  ctx.globalAlpha = 1;

  ctx.font = "700 22px ui-monospace, monospace";
  ctx.fillStyle = agent.color;
  ctx.fillText(`${agent.name.toUpperCase()} · ${agent.archetypeName}`, 14, 30);

  // mood pill
  const mood = state?.mood;
  if (mood) {
    ctx.font = "600 15px ui-monospace, monospace";
    const label = mood.label.toUpperCase();
    const tw = ctx.measureText(label).width;
    ctx.fillStyle = mood.color;
    ctx.globalAlpha = 0.18;
    ctx.fillRect(w - tw - 30, 12, tw + 18, 24);
    ctx.globalAlpha = 1;
    ctx.fillStyle = mood.color;
    ctx.fillText(label, w - tw - 21, 29);
  }

  ctx.font = "600 30px ui-monospace, monospace";
  ctx.fillStyle = "#e6eefc";
  const last = state?.lastMessage || "reading the tape";
  ctx.font = "600 26px ui-monospace, monospace";
  ctx.fillStyle = "#e6eefc";
  wrap(ctx, last, 14, 74, w - 28, 32, 3);

  ctx.font = "500 18px ui-monospace, monospace";
  ctx.fillStyle = "rgba(159,178,205,0.9)";
  const pnl = state?.pnl || 0;
  ctx.fillStyle = pnl >= 0 ? "#5ceb8e" : "#f26457";
  ctx.fillText(`P&L ${pnl >= 0 ? "+" : ""}${pnl.toFixed(2)}`, 14, h - 18);
  ctx.fillStyle = "rgba(159,178,205,0.8)";
  ctx.textAlign = "right";
  ctx.fillText(`${state?.trades || 0} fills`, w - 14, h - 18);
  ctx.textAlign = "left";
  // belief line
  ctx.font = "500 15px ui-monospace, monospace";
  ctx.fillStyle = "rgba(159,178,205,0.6)";
  const belief = agent.beliefs?.[0] || "";
  if (belief) ctx.fillText(belief.length > 58 ? belief.slice(0, 56) + "…" : belief, 14, h - 44);
}

function wrap(ctx, text, x, y, maxW, lh, maxLines) {
  const words = String(text).split(" ");
  let line = "";
  let lines = 0;
  for (const word of words) {
    const test = line ? line + " " + word : word;
    if (ctx.measureText(test).width > maxW && line) {
      ctx.fillText(line, x, y + lines * lh);
      line = word;
      lines++;
      if (lines >= maxLines - 1) break;
    } else line = test;
  }
  if (lines < maxLines) ctx.fillText(line, x, y + lines * lh);
}

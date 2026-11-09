import * as THREE from "three";
import { canvasTexture, drawCity, drawChart, drawTicker, drawDeskScreen } from "./canvas.js";

export function buildRoom(scene) {
  const room = new THREE.Group();
  scene.add(room);

  // floor
  const floorMat = new THREE.MeshStandardMaterial({ color: 0x14181f, roughness: 0.75, metalness: 0.15 });
  const floor = new THREE.Mesh(new THREE.BoxGeometry(16, 0.2, 12), floorMat);
  floor.position.set(0, -0.1, 0);
  floor.receiveShadow = true;
  room.add(floor);

  // carpet inlay (graphic accents)
  const carpet = new THREE.Mesh(
    new THREE.PlaneGeometry(9.5, 7.2),
    new THREE.MeshStandardMaterial({ color: 0x1b2430, roughness: 0.95 })
  );
  carpet.rotation.x = -Math.PI / 2;
  carpet.position.set(0, 0.005, 0.6);
  carpet.receiveShadow = true;
  room.add(carpet);

  // glowing floor strips
  const stripMat = new THREE.MeshBasicMaterial({ color: 0x2b6b8f, transparent: true, opacity: 0.5 });
  for (const x of [-4.4, 4.4]) {
    const strip = new THREE.Mesh(new THREE.PlaneGeometry(0.06, 7), stripMat);
    strip.rotation.x = -Math.PI / 2;
    strip.position.set(x, 0.012, 0.6);
    room.add(strip);
  }

  // walls
  const wallMat = new THREE.MeshStandardMaterial({ color: 0x0f1620, roughness: 0.9 });
  const back = new THREE.Mesh(new THREE.BoxGeometry(16, 5.5, 0.25), wallMat);
  back.position.set(0, 2.75, -6);
  back.receiveShadow = true;
  room.add(back);

  const left = new THREE.Mesh(new THREE.BoxGeometry(0.25, 5.5, 12), wallMat);
  left.position.set(-8, 2.75, 0);
  room.add(left);
  const right = left.clone();
  right.position.x = 8;
  room.add(right);

  // ceiling lights (emissive bars)
  const lightMat = new THREE.MeshBasicMaterial({ color: 0xdfe9ff });
  for (const z of [-2.6, 2.4]) {
    const bar = new THREE.Mesh(new THREE.BoxGeometry(11, 0.06, 0.28), lightMat);
    bar.position.set(0, 4.6, z);
    room.add(bar);
  }

  // ------- windows with city backdrop -------
  const city = canvasTexture(1024, 640);
  drawCity(city.ctx, 1024, 640);
  city.tex.needsUpdate = true;
  const windowMat = new THREE.MeshBasicMaterial({ map: city.tex });
  const windowFrame = new THREE.MeshStandardMaterial({ color: 0x0a0f18, roughness: 0.6, metalness: 0.4 });
  for (const [x, w] of [[-5.6, 4.6], [0, 4.6], [5.6, 4.6]]) {
    const win = new THREE.Mesh(new THREE.PlaneGeometry(w, 3.1), windowMat);
    win.position.set(x, 2.5, -5.84);
    room.add(win);
    const frame = new THREE.Mesh(new THREE.BoxGeometry(w + 0.18, 3.3, 0.08), windowFrame);
    frame.position.set(x, 2.5, -5.9);
    room.add(frame);
  }
  // mullions
  const mull = new THREE.MeshStandardMaterial({ color: 0x131b26, roughness: 0.5, metalness: 0.5 });
  for (const x of [-7.9, -3.3, -2.3, 2.3, 3.3, 7.9]) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(0.1, 3.3, 0.14), mull);
    m.position.set(x, 2.5, -5.8);
    room.add(m);
  }
  const sill = new THREE.Mesh(new THREE.BoxGeometry(15.8, 0.16, 0.4), mull);
  sill.position.set(0, 0.95, -5.8);
  room.add(sill);

  // ------- big wall ticker -------
  const ticker = canvasTexture(1024, 256);
  const tickerMat = new THREE.MeshBasicMaterial({ map: ticker.tex });
  const tickerMesh = new THREE.Mesh(new THREE.PlaneGeometry(9.6, 2.4), tickerMat);
  tickerMesh.position.set(0, 3.55, -5.7);
  room.add(tickerMesh);
  const tickerBezel = new THREE.Mesh(new THREE.BoxGeometry(9.9, 2.7, 0.1), windowFrame);
  tickerBezel.position.set(0, 3.55, -5.76);
  room.add(tickerBezel);

  // ------- central holo table -------
  const table = new THREE.Group();
  const top = new THREE.Mesh(
    new THREE.CylinderGeometry(2.35, 2.35, 0.14, 64),
    new THREE.MeshStandardMaterial({ color: 0x1b2431, roughness: 0.35, metalness: 0.6 })
  );
  top.position.y = 0.9;
  top.castShadow = true;
  top.receiveShadow = true;
  table.add(top);

  const rim = new THREE.Mesh(
    new THREE.TorusGeometry(2.36, 0.035, 12, 80),
    new THREE.MeshBasicMaterial({ color: 0x4fd1ff })
  );
  rim.rotation.x = Math.PI / 2;
  rim.position.y = 0.98;
  table.add(rim);

  const base = new THREE.Mesh(
    new THREE.CylinderGeometry(0.55, 0.95, 0.86, 32),
    new THREE.MeshStandardMaterial({ color: 0x121a24, roughness: 0.4, metalness: 0.7 })
  );
  base.position.y = 0.43;
  base.castShadow = true;
  table.add(base);
  table.position.set(0, 0, 0.4);
  room.add(table);

  // holo chart on the table
  const holo = canvasTexture(1024, 640);
  const holoMat = new THREE.MeshBasicMaterial({ map: holo.tex, transparent: true, opacity: 0.95 });
  const holoMesh = new THREE.Mesh(new THREE.PlaneGeometry(4.2, 2.6), holoMat);
  holoMesh.rotation.x = -Math.PI / 2;
  holoMesh.position.set(0, 1.0, 0.4);
  room.add(holoMesh);

  // projection beam
  const beam = new THREE.Mesh(
    new THREE.CylinderGeometry(2.1, 2.35, 2.6, 48, 1, true),
    new THREE.MeshBasicMaterial({
      color: 0x2f8fd0,
      transparent: true,
      opacity: 0.055,
      side: THREE.DoubleSide,
      depthWrite: false,
    })
  );
  beam.position.set(0, 2.4, 0.4);
  room.add(beam);

  // ------- worker desks -------
  const deskDefs = [
    { id: "victor", x: -3.6, z: -1.2, rot: 0.35, color: "#5ceb8e", role: "BULL ANALYST", name: "Victor" },
    { id: "maria", x: 3.6, z: -1.2, rot: -0.35, color: "#f26457", role: "BEAR ANALYST", name: "Maria" },
    { id: "alexei", x: -5.4, z: 2.1, rot: 1.25, color: "#f5b841", role: "RISK MANAGER", name: "Alexei" },
    { id: "judge", x: 5.4, z: 2.1, rot: -1.25, color: "#c9a7ff", role: "ARBITER / SENIOR PM", name: "Arbiter" },
  ];
  const registry = {};

  for (const d of deskDefs) {
    const g = new THREE.Group();
    g.position.set(d.x, 0, d.z);
    g.rotation.y = d.rot;

    const deskTop = new THREE.Mesh(
      new THREE.BoxGeometry(2.5, 0.1, 1.15),
      new THREE.MeshStandardMaterial({ color: 0x1d2531, roughness: 0.45, metalness: 0.45 })
    );
    deskTop.position.y = 0.78;
    deskTop.castShadow = true;
    deskTop.receiveShadow = true;
    g.add(deskTop);

    const legMat = new THREE.MeshStandardMaterial({ color: 0x0d131b, roughness: 0.7, metalness: 0.3 });
    for (const lx of [-1.15, 1.15]) {
      for (const lz of [-0.48, 0.48]) {
        const leg = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.78, 0.08), legMat);
        leg.position.set(lx, 0.39, lz);
        g.add(leg);
      }
    }
    // accent underglow
    const glow = new THREE.Mesh(
      new THREE.PlaneGeometry(2.4, 0.14),
      new THREE.MeshBasicMaterial({ color: d.color, transparent: true, opacity: 0.45 })
    );
    glow.rotation.x = -Math.PI / 2;
    glow.position.set(0, 0.74, 0.5);
    g.add(glow);

    // monitors (3 per desk)
    const screens = [];
    for (let i = 0; i < 3; i++) {
      const tex = canvasTexture(512, 320);
      const mat = new THREE.MeshBasicMaterial({ map: tex.tex });
      const mon = new THREE.Mesh(new THREE.PlaneGeometry(1.0, 0.62), mat);
      mon.position.set(-0.78 + i * 0.78, 1.24, -0.16);
      mon.rotation.x = -0.12;
      g.add(mon);
      const bezel = new THREE.Mesh(
        new THREE.BoxGeometry(1.06, 0.68, 0.04),
        new THREE.MeshStandardMaterial({ color: 0x080c12, roughness: 0.4, metalness: 0.5 })
      );
      bezel.position.copy(mon.position);
      bezel.position.z -= 0.03;
      bezel.rotation.x = -0.12;
      g.add(bezel);
      const stand = new THREE.Mesh(
        new THREE.CylinderGeometry(0.03, 0.03, 0.28, 8),
        legMat
      );
      stand.position.set(mon.position.x, 0.95, -0.2);
      g.add(stand);
      screens.push({ tex, kind: i });
    }

    // keyboard
    const kb = new THREE.Mesh(
      new THREE.BoxGeometry(0.7, 0.03, 0.22),
      new THREE.MeshStandardMaterial({ color: 0x0b1017, roughness: 0.8 })
    );
    kb.position.set(0, 0.85, 0.22);
    g.add(kb);

    // desk plat card
    const plate = canvasTexture(512, 96);
    const pctx = plate.ctx;
    pctx.fillStyle = "#05090f";
    pctx.fillRect(0, 0, 512, 96);
    pctx.fillStyle = d.color;
    pctx.font = "700 34px ui-monospace, monospace";
    pctx.fillText(d.name.toUpperCase(), 18, 44);
    pctx.fillStyle = "rgba(230,238,252,0.7)";
    pctx.font = "500 22px ui-monospace, monospace";
    pctx.fillText(d.role, 18, 76);
    plate.tex.needsUpdate = true;
    const plateMesh = new THREE.Mesh(
      new THREE.PlaneGeometry(1.9, 0.36),
      new THREE.MeshBasicMaterial({ map: plate.tex, transparent: true })
    );
    plateMesh.position.set(0, 0.62, 0.58);
    plateMesh.rotation.x = -0.35;
    g.add(plateMesh);

    room.add(g);
    registry[d.id] = { group: g, screens, def: d };
  }

  // ------- plants & props -------
  const plantMat = new THREE.MeshStandardMaterial({ color: 0x1e5a3a, roughness: 0.9 });
  const potMat = new THREE.MeshStandardMaterial({ color: 0x2a2118, roughness: 0.9 });
  for (const [x, z] of [[-7.1, -4.6], [7.1, -4.6], [-6.9, 3.9], [6.9, 3.9]]) {
    const pot = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.24, 0.5, 12), potMat);
    pot.position.set(x, 0.25, z);
    pot.castShadow = true;
    room.add(pot);
    for (let i = 0; i < 5; i++) {
      const leaf = new THREE.Mesh(new THREE.ConeGeometry(0.22, 1.1, 6), plantMat);
      leaf.position.set(x + Math.cos(i * 1.3) * 0.14, 0.95 + (i % 3) * 0.18, z + Math.sin(i * 1.3) * 0.14);
      leaf.rotation.z = Math.cos(i) * 0.25;
      leaf.castShadow = true;
      room.add(leaf);
    }
  }

  // coffee bar / printer cabinet at back-left
  const cab = new THREE.Mesh(
    new THREE.BoxGeometry(2.2, 0.9, 0.7),
    new THREE.MeshStandardMaterial({ color: 0x18202b, roughness: 0.6, metalness: 0.3 })
  );
  cab.position.set(-6.3, 0.45, -4.3);
  cab.castShadow = true;
  room.add(cab);

  return { room, registry, table, holo, holoMesh, holoMat, ticker, tickerMat, windowTex: city, beam };
}

export function updateScreens(assets, floor) {
  const snapshot = floor.market.snapshot();
  // ticker
  drawTicker(assets.ticker.ctx, 1024, 256, snapshot, 0);
  assets.ticker.tex.needsUpdate = true;

  // holo table chart for the focused symbol
  const focus = snapshot[2] || snapshot[0];
  const f = floor.market.feeds[focus.symbol];
  drawChart(assets.holo.ctx, 1024, 640, f.bars.concat([f.forming]), {
    accent: focus.color,
    symbol: focus.symbol,
    price: focus.last,
    digits: focus.digits,
    rsi: focus.rsi,
  });
  assets.holo.tex.needsUpdate = true;

  // desk monitors
  for (const [id, entry] of Object.entries(assets.registry)) {
    const agent = floor.agents[id];
    const th = floor.threads.find((t) => t.messages.some((m) => m.speaker === id)) || null;
    const lastMsg = th ? [...th.messages].reverse().find((m) => m.speaker === id) : null;
    entry.screens.forEach((s) => {
      const ctx = s.tex.ctx;
      if (s.kind === 0) {
        drawDeskScreen(ctx, 512, 320, { ...entry.def, color: entry.def.color }, {
          lastMessage: lastMsg?.text || agent?.quote || "reading the tape",
          pnl: agent?.pnl || 0,
          trades: agent?.trades || 0,
        });
      } else if (s.kind === 1) {
        drawChart(ctx, 512, 320, f.bars.concat([f.forming]), {
          accent: focus.color,
          symbol: focus.symbol,
          price: focus.last,
          digits: focus.digits,
          rsi: focus.rsi,
        });
      } else {
        drawTicker(ctx, 512, 320, snapshot.slice(0, 4), 0);
      }
      s.tex.tex.needsUpdate = true;
    });
  }
}

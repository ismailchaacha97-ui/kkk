import * as THREE from "three";
import { canvasTexture, drawCity, drawChart, drawTicker, drawDeskScreen, drawWhiteboard, drawWallBoard } from "./canvas.js";

const WALL = 0x0e1520;
const FLOOR_A = 0x121821;
const FLOOR_B = 0x161d27;

function box(w, h, d, mat, x, y, z) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}

export function buildOffice(scene) {
  const room = new THREE.Group();
  scene.add(room);

  const floorMat = new THREE.MeshStandardMaterial({ color: FLOOR_A, roughness: 0.72, metalness: 0.18 });
  const floorMat2 = new THREE.MeshStandardMaterial({ color: FLOOR_B, roughness: 0.8, metalness: 0.1 });
  const wallMat = new THREE.MeshStandardMaterial({ color: WALL, roughness: 0.92 });
  const trimMat = new THREE.MeshStandardMaterial({ color: 0x0a1018, roughness: 0.5, metalness: 0.55 });

  // ---- main trading floor (16 x 11) ----
  room.add(box(16, 0.2, 11, floorMat, 0, -0.1, 0));

  // ---- annex (break room / lounge) to the right ----
  const annex = new THREE.Group();
  annex.position.set(11.4, 0, -1.4);
  room.add(annex);
  annex.add(box(7, 0.2, 8, floorMat2, 0, -0.1, 0));

  // glowing edge strips where materials change
  const stripMat = new THREE.MeshBasicMaterial({ color: 0x2a6b8f, transparent: true, opacity: 0.45 });
  for (const [x, z, w, d] of [[0, 5.5, 16, 0.05], [0, -5.5, 16, 0.05], [-8, 0, 0.05, 11], [8, 0, 0.05, 11]]) {
    const s = new THREE.Mesh(new THREE.PlaneGeometry(w, d), stripMat);
    s.rotation.x = -Math.PI / 2;
    s.position.set(x, 0.008, z);
    room.add(s);
  }

  // ---- walls ----
  const backWall = box(16, 5.4, 0.22, wallMat, 0, 2.7, -5.5);
  room.add(backWall);
  room.add(box(0.22, 5.4, 11, wallMat, -8, 2.7, 0)); // left
  room.add(box(0.22, 5.4, 11, wallMat, 8, 2.7, 0)); // right (shared with annex door)
  // annex walls
  annex.add(box(7, 5.4, 0.22, wallMat, 0, 2.7, -4));
  annex.add(box(7, 5.4, 0.22, wallMat, 0, 2.7, 4));
  annex.add(box(0.22, 5.4, 8, wallMat, 3.5, 2.7, 0));
  // glass partition between floor and annex with a doorway
  const glass = new THREE.MeshPhysicalMaterial({
    color: 0x9fc4ff, transparent: true, opacity: 0.12, roughness: 0.05,
    metalness: 0.1, transmission: 0.6, side: THREE.DoubleSide,
  });
  const partitionA = new THREE.Mesh(new THREE.PlaneGeometry(3.0, 3.2), glass);
  partitionA.position.set(8, 1.6, -3.0);
  partitionA.rotation.y = Math.PI / 2;
  room.add(partitionA);
  const partitionB = partitionA.clone();
  partitionB.position.set(8, 1.6, 2.6);
  room.add(partitionB);

  // ---- ceiling light bars ----
  const lightMat = new THREE.MeshBasicMaterial({ color: 0xe8f1ff });
  for (const z of [-3.3, 0.2, 3.6]) {
    for (const x of [-5.2, 0, 5.2]) room.add(box(4.2, 0.05, 0.24, lightMat, x, 4.5, z));
  }
  for (const z of [-2.2, 2.2]) annex.add(box(4.4, 0.05, 0.2, lightMat, 0, 4.4, z));

  // ---- window wall with the city ----
  const city = canvasTexture(2048, 720);
  drawCity(city.ctx, 2048, 720);
  city.tex.needsUpdate = true;
  const cityMat = new THREE.MeshBasicMaterial({ map: city.tex });
  for (const x of [-6.0, -2.0, 2.0, 6.0]) {
    const win = new THREE.Mesh(new THREE.PlaneGeometry(3.7, 2.9), cityMat);
    win.position.set(x, 2.55, -5.34);
    room.add(win);
    const frame = box(3.86, 3.06, 0.06, trimMat, x, 2.55, -5.4);
    room.add(frame);
  }
  for (const x of [-8, -4.05, -3.95, 0, 3.95, 4.05, 8]) {
    room.add(box(0.1, 3.2, 0.16, trimMat, x, 2.55, -5.3));
  }
  room.add(box(15.8, 0.14, 0.42, trimMat, 0, 1.02, -5.3));
  // annex window
  for (const z of [-2.6, 0.6]) {
    const win2 = new THREE.Mesh(new THREE.PlaneGeometry(2.9, 2.9), cityMat);
    win2.position.set(3.4, 2.5, 0);
    win2.rotation.y = -Math.PI / 2;
    win2.position.z = z;
    annex.add(win2);
  }

  // ---- wall-mounted board (market board) ----
  const wallTex = canvasTexture(1400, 420);
  const wallBoard = new THREE.Mesh(new THREE.PlaneGeometry(10.4, 3.1), new THREE.MeshBasicMaterial({ map: wallTex.tex }));
  wallBoard.position.set(0, 3.42, -5.16);
  room.add(wallBoard);
  room.add(box(10.7, 3.36, 0.09, trimMat, 0, 3.42, -5.22));

  // ---- whiteboard (strategy / lessons) ----
  const wbTex = canvasTexture(1100, 620);
  const whiteboard = new THREE.Mesh(new THREE.PlaneGeometry(4.4, 2.5), new THREE.MeshBasicMaterial({ map: wbTex.tex }));
  whiteboard.position.set(-5.9, 2.3, 5.36);
  whiteboard.rotation.y = Math.PI;
  room.add(whiteboard);
  room.add(box(4.62, 2.72, 0.08, trimMat, -5.9, 2.3, 5.42));

  // ---- holo table (centre of the room) ----
  const table = new THREE.Group();
  table.position.set(0, 0, 0.2);
  const rimMat = new THREE.MeshBasicMaterial({ color: 0x4fd1ff });
  table.add(
    new THREE.Mesh(
      new THREE.CylinderGeometry(2.25, 2.25, 0.13, 64),
      new THREE.MeshStandardMaterial({ color: 0x1a2330, roughness: 0.32, metalness: 0.65 })
    )
  );
  const rim = new THREE.Mesh(new THREE.TorusGeometry(2.26, 0.032, 10, 80), rimMat);
  rim.rotation.x = Math.PI / 2;
  rim.position.y = 0.08;
  table.add(rim);
  const base = new THREE.Mesh(
    new THREE.CylinderGeometry(0.5, 0.9, 0.82, 32),
    new THREE.MeshStandardMaterial({ color: 0x111923, roughness: 0.4, metalness: 0.7 })
  );
  base.position.y = -0.42;
  table.add(base);
  table.children[0].castShadow = true;
  table.position.y = 0.9;
  room.add(table);

  const holo = canvasTexture(1024, 620);
  const holoMesh = new THREE.Mesh(
    new THREE.PlaneGeometry(4.0, 2.42),
    new THREE.MeshBasicMaterial({ map: holo.tex, transparent: true })
  );
  holoMesh.rotation.x = -Math.PI / 2;
  holoMesh.position.set(0, 0.985, 0.2);
  room.add(holoMesh);

  const beam = new THREE.Mesh(
    new THREE.CylinderGeometry(2.0, 2.25, 2.6, 40, 1, true),
    new THREE.MeshBasicMaterial({ color: 0x2f8fd0, transparent: true, opacity: 0.05, side: THREE.DoubleSide, depthWrite: false })
  );
  beam.position.set(0, 2.3, 0.2);
  room.add(beam);

  // ---- standing desks (for agents that prefer pacing) ----
  const standRoom = new THREE.Group();
  standRoom.position.set(-6.2, 0, 2.6);

  // ---- plants, cabinets, coffee bar ----
  const plantMat = new THREE.MeshStandardMaterial({ color: 0x1f5b3b, roughness: 0.9 });
  const potMat = new THREE.MeshStandardMaterial({ color: 0x261f18, roughness: 0.9 });
  const plantSpots = [[-7.3, -4.6], [7.3, -4.6], [-7.2, 4.6], [7.2, 4.9], [-4.2, 5.0], [14.2, 1.9], [9.6, -4.6]];
  for (const [x, z] of plantSpots) {
    const pot = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.22, 0.46, 12), potMat);
    pot.position.set(x, 0.23, z);
    pot.castShadow = true;
    room.add(pot);
    for (let i = 0; i < 5; i++) {
      const leaf = new THREE.Mesh(new THREE.ConeGeometry(0.2, 1.0, 6), plantMat);
      leaf.position.set(x + Math.cos(i * 1.25) * 0.13, 0.9 + (i % 3) * 0.17, z + Math.sin(i * 1.25) * 0.13);
      leaf.rotation.z = Math.cos(i) * 0.26;
      leaf.castShadow = true;
      room.add(leaf);
    }
  }
  const cabMat = new THREE.MeshStandardMaterial({ color: 0x161e29, roughness: 0.6, metalness: 0.35 });
  room.add(box(2.4, 0.9, 0.7, cabMat, -6.4, 0.45, -4.9));
  room.add(box(2.0, 0.9, 0.65, cabMat, 6.4, 0.45, -4.9));

  // ---- lounge: sofas, coffee machine, kitchen island ----
  const sofaMat = new THREE.MeshStandardMaterial({ color: 0x222b38, roughness: 0.95 });
  const sofa = (x, z, rotY) => {
    const g = new THREE.Group();
    g.position.set(x, 0, z);
    g.rotation.y = rotY;
    g.add(box(2.0, 0.42, 0.8, sofaMat, 0, 0.24, 0));
    g.add(box(2.0, 0.5, 0.22, sofaMat, 0, 0.58, -0.3));
    annex.add(g);
  };
  sofa(-1.2, 1.9, 0);
  sofa(1.3, -1.6, Math.PI);
  const tableL = new THREE.Mesh(
    new THREE.CylinderGeometry(0.62, 0.62, 0.07, 24),
    new THREE.MeshStandardMaterial({ color: 0x2a2018, roughness: 0.5 })
  );
  tableL.position.set(0.2, 0.44, 0.2);
  tableL.castShadow = true;
  annex.add(tableL);
  annex.add(
    new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.12, 0.44, 12), trimMat)
  ).position.set(0.2, 0.22, 0.2);

  // kitchen island with coffee machine
  annex.add(box(2.6, 0.94, 0.8, cabMat, 2.0, 0.47, 2.9));
  const machine = box(0.5, 0.55, 0.4, new THREE.MeshStandardMaterial({ color: 0x0b0f15, roughness: 0.4, metalness: 0.6 }), 2.0, 1.24, 2.9);
  annex.add(machine);
  const machineLed = new THREE.Mesh(new THREE.SphereGeometry(0.035, 8, 8), new THREE.MeshBasicMaterial({ color: 0xff6b3d }));
  machineLed.position.set(2.0, 1.34, 2.7);
  annex.add(machineLed);

  // ping-pong / standing table in the far annex corner
  annex.add(box(1.6, 0.06, 0.9, new THREE.MeshStandardMaterial({ color: 0x123a2a, roughness: 0.8 }), -1.6, 0.72, -2.9));

  return {
    room, annex, table, holo, holoMesh, beam, wallTex, wbTex,
    cityTex: city, standRoom, machineLed,
  };
}

/* ------------------------- desk construction ------------------------- */
export function buildDesk(desk, agent) {
  const g = new THREE.Group();
  g.position.set(desk.x, 0, desk.z);
  g.rotation.y = desk.rot;

  const topMat = new THREE.MeshStandardMaterial({ color: 0x1c2431, roughness: 0.42, metalness: 0.45 });
  const legMat = new THREE.MeshStandardMaterial({ color: 0x0c1118, roughness: 0.7, metalness: 0.35 });

  const deskTop = box(2.5, 0.09, 1.1, topMat, 0, 0.76, 0);
  g.add(deskTop);
  for (const lx of [-1.16, 1.16]) for (const lz of [-0.46, 0.46]) g.add(box(0.07, 0.76, 0.07, legMat, lx, 0.38, lz));

  // underglow
  const glow = new THREE.Mesh(
    new THREE.PlaneGeometry(2.36, 0.12),
    new THREE.MeshBasicMaterial({ color: agent.color, transparent: true, opacity: 0.5 })
  );
  glow.rotation.x = -Math.PI / 2;
  glow.position.set(0, 0.72, 0.48);
  g.add(glow);

  // three monitors with live textures
  const screens = [];
  for (let i = 0; i < 3; i++) {
    const tex = canvasTexture(512, 320);
    const mon = new THREE.Mesh(new THREE.PlaneGeometry(0.98, 0.6), new THREE.MeshBasicMaterial({ map: tex.tex }));
    mon.position.set(-0.76 + i * 0.76, 1.22, -0.14);
    mon.rotation.x = -0.1;
    g.add(mon);
    const bezel = box(1.04, 0.66, 0.035, legMat, mon.position.x, mon.position.y, -0.17);
    bezel.rotation.x = -0.1;
    g.add(bezel);
    g.add(box(0.035, 0.3, 0.035, legMat, mon.position.x, 0.95, -0.2));
    screens.push({ tex, kind: i });
  }

  // keyboard + mouse
  g.add(box(0.66, 0.025, 0.2, legMat, 0, 0.83, 0.22));
  g.add(box(0.1, 0.03, 0.14, legMat, 0.5, 0.83, 0.24));

  // desk plate: name + archetype + generation + mood led
  const plate = canvasTexture(512, 112);
  const pctx = plate.ctx;
  pctx.fillStyle = "#05090f";
  pctx.fillRect(0, 0, 512, 112);
  pctx.fillStyle = agent.color;
  pctx.font = "700 40px ui-monospace, monospace";
  pctx.fillText(agent.name.toUpperCase(), 20, 48);
  pctx.fillStyle = "rgba(230,238,252,0.72)";
  pctx.font = "500 22px ui-monospace, monospace";
  pctx.fillText(`${agent.archetypeName} · GEN ${agent.generation}`, 20, 84);
  plate.tex.needsUpdate = true;
  const plateMesh = new THREE.Mesh(
    new THREE.PlaneGeometry(1.7, 0.37),
    new THREE.MeshBasicMaterial({ map: plate.tex, transparent: true })
  );
  plateMesh.position.set(0, 0.6, 0.56);
  plateMesh.rotation.x = -0.3;
  g.add(plateMesh);

  // mood LED strip on the desk edge
  const moodLed = new THREE.Mesh(
    new THREE.BoxGeometry(0.42, 0.035, 0.035),
    new THREE.MeshBasicMaterial({ color: 0x8cb4ff })
  );
  moodLed.position.set(0, 0.79, 0.52);
  g.add(moodLed);

  return { group: g, screens, plate, plateMesh, moodLed, glow, desk };
}

/* ---------------------------- avatars ---------------------------- */
export function makeAvatar({ color = "#5ceb8e", seed = 0, seated = true, female = false } = {}) {
  const g = new THREE.Group();
  const skins = [0xd7a17a, 0x8d5524, 0xf0c9a0, 0x5c3b22, 0xe2b48c, 0x3f2a1c];
  const shirts = [0x22303f, 0x2f2a3d, 0x1f2f2a, 0x2a2420, 0x1d2733, 0x33262d];
  const hairs = [0x171310, 0x2b1d12, 0x0d0b0a, 0x4a2f1c, 0x6b4a2c, 0x9a7a52];
  const skin = new THREE.MeshStandardMaterial({ color: skins[seed % skins.length], roughness: 0.72 });
  const shirt = new THREE.MeshStandardMaterial({ color: shirts[seed % shirts.length], roughness: 0.88 });
  const hairMat = new THREE.MeshStandardMaterial({ color: hairs[(seed + 2) % hairs.length], roughness: 0.95 });
  const trouser = new THREE.MeshStandardMaterial({ color: 0x161b23, roughness: 0.92 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x0a0e14, roughness: 0.45, metalness: 0.4 });
  const accentMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(color) });

  const part = (geo, mat, x, y, z) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    m.castShadow = true;
    m.receiveShadow = true;
    return m;
  };

  const hips = new THREE.Group();
  hips.position.y = 0.5;
  g.add(hips);

  const torso = part(new THREE.CapsuleGeometry(0.2, 0.3, 6, 12), shirt, 0, 0.3, 0);
  torso.scale.set(female ? 0.95 : 1.08, 1, 0.8);
  hips.add(torso);
  // lanyard + badge (every floor has one)
  hips.add(part(new THREE.BoxGeometry(0.02, 0.24, 0.02), accentMat, 0.07, 0.34, 0.16));
  hips.add(part(new THREE.BoxGeometry(0.09, 0.06, 0.01), accentMat, 0.07, 0.22, 0.165));

  const head = new THREE.Group();
  head.position.y = 0.63;
  hips.add(head);
  const skull = part(new THREE.SphereGeometry(0.15, 20, 16), skin, 0, 0, 0);
  skull.scale.set(0.94, 1.06, 0.94);
  head.add(skull);
  head.add(part(new THREE.SphereGeometry(0.157, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), hairMat, 0, 0.008, 0));
  if (female) head.add(part(new THREE.SphereGeometry(0.12, 14, 10), hairMat, 0, -0.06, -0.11));
  for (const ex of [-0.052, 0.052]) head.add(part(new THREE.SphereGeometry(0.018, 8, 8), dark, ex, 0.012, 0.135));
  // headset + mic
  const band = part(new THREE.TorusGeometry(0.155, 0.013, 8, 24, Math.PI), dark, 0, 0.02, 0);
  band.rotation.z = Math.PI / 2;
  head.add(band);
  head.add(part(new THREE.CapsuleGeometry(0.013, 0.06, 4, 8), dark, -0.145, -0.03, 0.02));
  const mic = part(new THREE.CapsuleGeometry(0.008, 0.085, 4, 8), dark, -0.1, -0.085, 0.1);
  mic.rotation.z = 0.7;
  head.add(mic);
  const led = new THREE.Mesh(new THREE.SphereGeometry(0.016, 8, 8), accentMat.clone());
  led.position.set(-0.145, -0.02, 0.04);
  head.add(led);

  // arms
  const arms = [];
  for (const side of [-1, 1]) {
    const shoulder = new THREE.Group();
    shoulder.position.set(side * 0.25, 0.47, 0);
    hips.add(shoulder);
    shoulder.add(part(new THREE.CapsuleGeometry(0.062, 0.19, 5, 10), shirt, 0, -0.12, 0));
    const elbow = new THREE.Group();
    elbow.position.y = -0.24;
    shoulder.add(elbow);
    elbow.add(part(new THREE.CapsuleGeometry(0.052, 0.17, 5, 10), skin, 0, -0.11, 0));
    elbow.add(part(new THREE.SphereGeometry(0.055, 10, 8), skin, 0, -0.22, 0));
    shoulder.rotation.x = seated ? -0.9 : -0.12;
    elbow.rotation.x = seated ? -0.9 : -0.3;
    shoulder.rotation.z = side * 0.1;
    arms.push({ shoulder, elbow, side });
  }

  // legs
  for (const side of [-1, 1]) {
    const hip = new THREE.Group();
    hip.position.set(side * 0.105, -0.02, 0);
    hips.add(hip);
    if (seated) {
      hip.rotation.x = Math.PI / 2;
      hip.add(part(new THREE.CapsuleGeometry(0.078, 0.22, 5, 10), trouser, 0, -0.15, 0));
      const knee = new THREE.Group();
      knee.position.y = -0.31;
      hip.add(knee);
      knee.rotation.x = -Math.PI / 2;
      knee.add(part(new THREE.CapsuleGeometry(0.068, 0.28, 5, 10), trouser, 0, -0.18, 0));
      knee.add(part(new THREE.BoxGeometry(0.12, 0.06, 0.2), dark, 0, -0.36, 0.04));
    } else {
      hip.add(part(new THREE.CapsuleGeometry(0.072, 0.36, 5, 10), trouser, 0, -0.26, 0));
      hip.add(part(new THREE.BoxGeometry(0.11, 0.06, 0.19), dark, 0, -0.58, 0.04));
    }
  }

  // chair
  const chair = new THREE.Group();
  const chairMat = new THREE.MeshStandardMaterial({ color: 0x0d1218, roughness: 0.75 });
  chair.add(part(new THREE.BoxGeometry(0.54, 0.08, 0.52), chairMat, 0, 0, 0.02));
  const backrest = part(new THREE.BoxGeometry(0.54, 0.62, 0.08), chairMat, 0, 0.34, -0.25);
  backrest.rotation.x = -0.1;
  chair.add(backrest);
  chair.position.set(0, 0.45, -0.05);
  g.add(chair);

  return { g, hips, head, arms, torso, chair, led, chairMat, seated };
}

export function animateAvatar(rig, t, speaking, walking = 0, moodColor) {
  const breathe = Math.sin(t * 1.5) * 0.011;
  rig.hips.position.y = 0.5 + breathe;
  rig.head.rotation.y = Math.sin(t * 0.45) * 0.14;
  rig.head.rotation.x = Math.sin(t * 0.7) * 0.045 - 0.03;
  rig.head.rotation.z = speaking ? Math.sin(t * 8.5) * 0.035 : rig.head.rotation.z * 0.9;
  const talkArm = speaking ? Math.sin(t * 5.2) * 0.2 : 0;
  if (rig.seated) {
    rig.arms[0].elbow.rotation.x = -0.9 + talkArm;
    rig.arms[1].elbow.rotation.x = -0.9 + Math.sin(t * 4.6 + 1) * (speaking ? 0.14 : 0.02);
  } else if (walking > 0) {
    const swing = Math.sin(t * 7.5) * 0.55;
    rig.arms[0].shoulder.rotation.x = -0.12 + swing;
    rig.arms[1].shoulder.rotation.x = -0.12 - swing;
    rig.hips.position.y = 0.5 + Math.abs(Math.sin(t * 7.5)) * 0.03;
  } else {
    rig.arms[0].shoulder.rotation.x += (-0.12 - rig.arms[0].shoulder.rotation.x) * 0.15;
    rig.arms[1].shoulder.rotation.x += (-0.12 - rig.arms[1].shoulder.rotation.x) * 0.15;
    rig.arms[0].elbow.rotation.x += (-0.3 + talkArm - rig.arms[0].elbow.rotation.x) * 0.15;
    rig.arms[1].elbow.rotation.x += (-0.3 - rig.arms[1].elbow.rotation.x) * 0.15;
  }
  if (moodColor && rig.led) rig.led.material.color.set(moodColor);
}

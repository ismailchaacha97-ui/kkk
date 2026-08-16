// The Realm map: a maester's chart drawn in SVG from world state.
import { makeRng } from './rng.js';
import { regionName, shortName } from './world.js';
import { wildDragons, houseDragons } from './dragons.js';

const BIOME_DOODADS = {
  frost: 'peaks', mountain: 'peaks', vale: 'peaks',
  forest: 'trees', fen: 'reeds', river: 'river',
  coast: 'waves', plain: 'grass', south: 'grass',
};

function doodad(kind, x, y, rng) {
  const ink = '#6b5a3a';
  switch (kind) {
    case 'peaks': {
      const w = 26 + rng.random() * 14;
      return `<path d="M${x - w / 2} ${y} L${x} ${y - w * 0.55} L${x + w / 2} ${y} M${x - w * 0.1} ${y - w * 0.3} L${x + w * 0.16} ${y - w * 0.3}" stroke="${ink}" stroke-width="2" fill="none" opacity="0.55"/>`;
    }
    case 'trees': {
      const s = 9 + rng.random() * 5;
      return `<path d="M${x} ${y} L${x} ${y - s * 1.5} M${x - s} ${y - s * 0.6} Q${x} ${y - s * 2.4} ${x + s} ${y - s * 0.6} Z" stroke="${ink}" stroke-width="1.8" fill="${ink}" fill-opacity="0.14" opacity="0.6"/>`;
    }
    case 'waves': {
      const w = 22 + rng.random() * 10;
      return `<path d="M${x - w / 2} ${y} Q${x - w / 4} ${y - 6} ${x} ${y} Q${x + w / 4} ${y + 6} ${x + w / 2} ${y}" stroke="${ink}" stroke-width="1.8" fill="none" opacity="0.5"/>`;
    }
    case 'reeds': {
      return `<path d="M${x - 6} ${y} L${x - 7} ${y - 12} M${x} ${y} L${x} ${y - 15} M${x + 6} ${y} L${x + 8} ${y - 11}" stroke="${ink}" stroke-width="1.6" fill="none" opacity="0.55"/>`;
    }
    case 'river': {
      const w = 30 + rng.random() * 16;
      return `<path d="M${x - w / 2} ${y - 8} Q${x - w / 6} ${y + 6} ${x + w / 6} ${y - 4} T${x + w / 2} ${y + 4}" stroke="#4a5a6e" stroke-width="2.2" fill="none" opacity="0.45"/>`;
    }
    default: {
      return `<path d="M${x - 5} ${y} L${x - 3} ${y - 7} M${x} ${y} L${x + 1} ${y - 8} M${x + 5} ${y} L${x + 7} ${y - 6}" stroke="${ink}" stroke-width="1.4" fill="none" opacity="0.45"/>`;
    }
  }
}

// tiny shield marker for a house on the map
function seatMarker(state, h, isPlayer, isCrown) {
  const s = h.sigil;
  const size = isCrown ? 15 : h.tier === 'great' ? 13 : 10;
  const stroke = isPlayer ? '#8a6d1a' : '#2b1d0e';
  const sw = isPlayer ? 2.6 : 1.2;
  const extinct = !h.alive;
  const fill1 = extinct ? '#9a8f78' : s.c1;
  const fill2 = extinct ? '#b3a88f' : s.c2;
  let g = `<g class="map-seat${isPlayer ? ' map-mine' : ''}" data-house="${h.id}" transform="translate(${h.mapX},${h.mapY})" style="cursor:pointer">`;
  g += `<path d="M${-size} ${-size} L${size} ${-size} L${size} ${size * 0.4} Q${size} ${size} 0 ${size * 1.3} Q${-size} ${size} ${-size} ${size * 0.4} Z" fill="${fill1}" stroke="${stroke}" stroke-width="${sw}"/>`;
  g += `<path d="M${-size} ${-size} L${size} ${-size} L${size} ${size * 0.4} Q${size} ${size} 0 ${size * 1.3} L0 ${-size} Z" fill="${fill2}" opacity="${extinct ? 0.4 : 0.85}"/>`;
  if (isCrown) g += `<text x="0" y="${-size - 5}" text-anchor="middle" font-size="14" fill="#6e2440">♛</text>`;
  if (extinct) g += `<text x="0" y="5" text-anchor="middle" font-size="12" fill="#2b1d0e" opacity="0.7">✕</text>`;
  g += `</g>`;
  return g;
}

// Back-fill map coordinates for saves made before the map existed.
export function ensureMapPositions(state) {
  const rng = makeRng(state.seed ^ 0xBADA55);
  const cells = [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]];
  state.regions.forEach((r, i) => {
    if (r.mx == null) { const [cx, cy] = cells[i % 6]; r.mx = cx * 333; r.my = cy * 330; r.mw = 334; r.mh = 330; }
  });
  for (const h of Object.values(state.houses)) {
    if (h.mapX != null) continue;
    if (h.tier === 'royal') { h.mapX = 500; h.mapY = 330; continue; }
    const r = state.regions.find((x) => x.id === h.regionId) || state.regions[0];
    for (let tries = 0; tries < 60; tries++) {
      const x = r.mx + 60 + rng.random() * (r.mw - 120);
      const y = r.my + 60 + rng.random() * (r.mh - 120);
      const others = Object.values(state.houses).filter((o) => o.mapX != null);
      const tooClose = others.some((o) => (o.mapX - x) ** 2 + (o.mapY - y) ** 2 < 72 ** 2) ||
        ((x - 500) ** 2 + (y - 330) ** 2 < 110 ** 2);
      if (!tooClose || tries === 59) { h.mapX = Math.round(x); h.mapY = Math.round(y); break; }
    }
  }
}

export function renderMapSVG(state) {
  const rng = makeRng(state.seed ^ 0xC0FFEE);
  const W = 1000, H = 660;
  let s = '';

  // parchment sea border
  s += `<rect x="0" y="0" width="${W}" height="${H}" fill="#d9c894"/>`;
  s += `<rect x="14" y="14" width="${W - 28}" height="${H - 28}" fill="#e9dcbe" stroke="#8a744c" stroke-width="2"/>`;

  // landmass blob (rough hand-drawn coast)
  const pts = [];
  const n = 26;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const rx = 445 + rng.random() * 45, ry = 285 + rng.random() * 38;
    pts.push([500 + Math.cos(a) * rx, 330 + Math.sin(a) * ry]);
  }
  let path = `M${pts[0][0].toFixed(0)} ${pts[0][1].toFixed(0)}`;
  for (let i = 1; i <= n; i++) {
    const p = pts[i % n], prev = pts[i - 1];
    const mx = (prev[0] + p[0]) / 2, my = (prev[1] + p[1]) / 2;
    path += ` Q${prev[0].toFixed(0)} ${prev[1].toFixed(0)} ${mx.toFixed(0)} ${my.toFixed(0)}`;
  }
  s += `<path d="${path} Z" fill="#efe4c6" stroke="#6b5a3a" stroke-width="2.5"/>`;
  s += `<path d="${path} Z" fill="none" stroke="#6b5a3a" stroke-width="1" opacity="0.4" transform="translate(3,3)"/>`;

  // region borders (dashed) and labels + terrain doodads
  for (const r of state.regions) {
    s += `<rect x="${r.mx + 20}" y="${r.my + 20}" width="${r.mw - 40}" height="${r.mh - 40}" fill="none" stroke="#8a744c" stroke-width="1" stroke-dasharray="6 5" opacity="0.35" rx="18"/>`;
    s += `<text x="${r.mx + r.mw / 2}" y="${r.my + 44}" text-anchor="middle" class="map-region-label">${r.name.toUpperCase()}</text>`;
    const kind = BIOME_DOODADS[r.biome] || 'grass';
    for (let i = 0; i < 7; i++) {
      const x = r.mx + 50 + rng.random() * (r.mw - 100);
      const y = r.my + 70 + rng.random() * (r.mh - 120);
      // skip doodads too close to seats
      const close = Object.values(state.houses).some((h) => h.mapX != null && (h.mapX - x) ** 2 + (h.mapY - y) ** 2 < 40 ** 2);
      if (!close) s += doodad(kind, x, y, rng);
    }
  }

  // crownlands label
  s += `<text x="500" y="296" text-anchor="middle" class="map-region-label" fill="#6e2440">THE CROWNLANDS</text>`;

  // wild dragon lairs
  for (const d of wildDragons(state)) {
    const r = state.regions.find((x) => x.id === d.lairRegionId) || state.regions[0];
    const dx = r.mx + r.mw / 2 + (rng.random() - 0.5) * 60;
    const dy = r.my + r.mh - 72;
    s += `<g class="map-dragon" transform="translate(${dx.toFixed(0)},${dy.toFixed(0)})">
      <path fill="${d.colorHex}" stroke="#2b1d0e" stroke-width="1" d="M-14 4 Q-8 -10 4 -11 L2 -16 L11 -11 Q20 -8 18 0 L11 -3 Q13 4 6 7 L8 16 L1 9 Q-9 11 -14 4 Z"/>
      <text x="0" y="30" text-anchor="middle" class="map-dragon-label">${d.name} (wild)</text>
    </g>`;
  }

  // seats: minors first, then greats, then crown on top
  const sorted = Object.values(state.houses).filter((h) => h.mapX != null)
    .sort((a, b) => (a.tier === 'minor' ? 0 : a.tier === 'great' ? 1 : 2) - (b.tier === 'minor' ? 0 : b.tier === 'great' ? 1 : 2));
  for (const h of sorted) {
    const isPlayer = h.id === state.playerHouseId;
    const isCrown = h.id === state.crownHouseId;
    s += seatMarker(state, h, isPlayer, isCrown);
    const fs = isCrown ? 12.5 : h.tier === 'great' ? 11.5 : 10;
    const dy = (isCrown ? 15 : h.tier === 'great' ? 13 : 10) * 1.3 + fs + 2;
    s += `<text x="${h.mapX}" y="${h.mapY + dy}" text-anchor="middle" class="map-seat-label${isPlayer ? ' mine' : ''}${h.alive ? '' : ' dead'}" font-size="${fs}">${h.name}</text>`;
    // house dragon marker beside seat
    if (h.alive && houseDragons(state, h.id).length) {
      const d0 = houseDragons(state, h.id)[0];
      s += `<text x="${h.mapX + (isCrown ? 20 : 15)}" y="${h.mapY - 8}" font-size="13" fill="${d0.colorHex}" stroke="#2b1d0e" stroke-width="0.4">🜂</text>`;
    }
  }

  // war marker
  if (state.war) {
    const a = state.houses[state.war.attackers[0]], dd = state.houses[state.war.defenders[0]];
    if (a && dd && a.mapX != null && dd.mapX != null) {
      s += `<line x1="${a.mapX}" y1="${a.mapY}" x2="${dd.mapX}" y2="${dd.mapY}" stroke="#7a1f1f" stroke-width="2" stroke-dasharray="8 5" opacity="0.65"/>`;
      const mx = (a.mapX + dd.mapX) / 2, my = (a.mapY + dd.mapY) / 2;
      s += `<text x="${mx}" y="${my - 6}" text-anchor="middle" font-size="16" fill="#7a1f1f">⚔</text>`;
    }
  }

  // compass + title cartouche
  s += `<g transform="translate(66,600)" opacity="0.75">
    <circle r="24" fill="none" stroke="#6b5a3a" stroke-width="1.5"/>
    <path d="M0 -20 L5 0 L0 20 L-5 0 Z" fill="#6b5a3a"/>
    <text y="-30" text-anchor="middle" font-size="13" fill="#6b5a3a" font-weight="bold">N</text>
  </g>`;
  s += `<g transform="translate(${W - 190},${H - 54})">
    <rect x="-16" y="-26" width="200" height="44" fill="#e3d3ab" stroke="#8a744c" stroke-width="1.5"/>
    <text x="84" y="-6" text-anchor="middle" class="map-cartouche">The Realm of ${state.realmName}</text>
    <text x="84" y="10" text-anchor="middle" class="map-cartouche-sub">as charted in Year ${state.year}</text>
  </g>`;

  return `<svg viewBox="0 0 ${W} ${H}" class="realm-map" xmlns="http://www.w3.org/2000/svg">${s}</svg>`;
}

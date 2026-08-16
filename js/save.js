// Save / load via localStorage. The namer (closures) and pending decisions
// (functions) are not serializable; the namer is rebuilt on load, decisions dropped.
import { makeRng } from './rng.js';
import { makeNamer } from './names.js';

const KEY = 'oaths-banners-save-v2';

export function saveGame(state) {
  try {
    const copy = {};
    for (const [k, v] of Object.entries(state)) {
      if (k === 'namer' || k === 'pendingDecisions') continue;
      copy[k] = v;
    }
    copy.pendingDecisions = [];
    localStorage.setItem(KEY, JSON.stringify(copy));
    return true;
  } catch { return false; }
}

export function loadGame() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const state = JSON.parse(raw);
    if (!state || !state.houses || !state.playerHouseId) return null;
    state.pendingDecisions = [];
    // Rebuild the namer and re-register used names so no duplicates appear.
    const namer = makeNamer(makeRng((state.rngSeed ^ 0x9e3779b9) >>> 0));
    state.namer = namer;
    for (const h of Object.values(state.houses)) {
      namer.houseName; // (sets exist inside closure; feed them via probe calls below)
    }
    // Probe: the namer's uniqueness sets are internal; simplest guard is to
    // pre-mark existing names by monkey-wrapping the generators.
    const usedHouses = new Set(Object.values(state.houses).map((h) => h.name));
    const usedSeats = new Set(Object.values(state.houses).map((h) => h.seat));
    const usedDragons = new Set(Object.values(state.dragons || {}).map((d) => d.name));
    const origHouse = namer.houseName, origSeat = namer.seatName, origDragon = namer.dragonName;
    namer.houseName = () => { for (let i = 0; i < 50; i++) { const n = origHouse(); if (!usedHouses.has(n)) return n; } return origHouse(); };
    namer.seatName = () => { for (let i = 0; i < 50; i++) { const n = origSeat(); if (!usedSeats.has(n)) return n; } return origSeat(); };
    namer.dragonName = () => { for (let i = 0; i < 50; i++) { const n = origDragon(); if (!usedDragons.has(n)) return n; } return origDragon(); };
    return state;
  } catch { return null; }
}

export function hasSave() {
  try { return !!localStorage.getItem(KEY); } catch { return false; }
}

export function clearSave() {
  try { localStorage.removeItem(KEY); } catch { /* ignore */ }
}

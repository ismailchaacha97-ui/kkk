// Dragons: the last fires of the world.

export const DRAGON_COLORS = [
  ['black as a starless night', '#1c1c1e'],
  ['red as old blood', '#7a1f1f'],
  ['bronze and smoke', '#8a6d3a'],
  ['pale as bone', '#cfc6b0'],
  ['green as wildfire', '#2e6b3a'],
  ['blue-grey as a storm front', '#4a5a6e'],
  ['gold with black veins', '#a8862a'],
  ['silver-white', '#b8bfc6'],
  ['the color of embers', '#b0501e'],
  ['violet-dark', '#3d2b56'],
];

export const DRAGON_STAGES = ['hatchling', 'young drake', 'adult', 'elder wyrm'];

export function makeDragon(state, rng, opts = {}) {
  const id = 'd' + (state.nextDragonId++);
  const color = rng.pick(DRAGON_COLORS);
  const d = {
    id,
    name: opts.name || state.namer.dragonName(),
    colorDesc: color[0], colorHex: color[1],
    birthYear: opts.birthYear ?? (state.year - rng.int(8, 60)),
    alive: true, deathYear: null, causeOfDeath: null,
    wild: opts.wild ?? false,
    houseId: opts.houseId || null,   // house that holds/claims it
    riderId: opts.riderId || null,   // bonded character
    temperament: rng.pick(['proud', 'sullen', 'cunning', 'wrathful', 'lazy and vast', 'restless']),
    kills: [],                        // notable things it burned
    lairRegionId: opts.lairRegionId || null, // for wild dragons
  };
  state.dragons[id] = d;
  return d;
}

export function dragonAge(state, d) { return state.year - d.birthYear; }

export function dragonStage(state, d) {
  const a = dragonAge(state, d);
  if (a < 4) return 0;
  if (a < 12) return 1;
  if (a < 60) return 2;
  return 3;
}

export function dragonStageName(state, d) { return DRAGON_STAGES[dragonStage(state, d)]; }

// Battle power contribution
export function dragonPower(state, d) {
  const stage = dragonStage(state, d);
  return [150, 900, 3200, 5200][stage];
}

export function describeDragon(state, d) {
  return `${d.name}, a ${dragonStageName(state, d)} ${d.colorDesc}, ${d.temperament}`;
}

export function livingDragons(state) {
  return Object.values(state.dragons).filter((x) => x.alive);
}

export function houseDragons(state, houseId) {
  return livingDragons(state).filter((x) => !x.wild && x.houseId === houseId);
}

export function wildDragons(state) {
  return livingDragons(state).filter((x) => x.wild);
}

export function killDragon(state, d, cause) {
  if (!d.alive) return;
  d.alive = false;
  d.deathYear = state.year;
  d.causeOfDeath = cause;
  if (d.riderId && state.characters[d.riderId]) {
    state.characters[d.riderId].dragonId = null;
  }
  d.riderId = null;
}

export function hasDragonblood(ch) {
  return ch.traits.includes('Dragonblood');
}

// A small inline SVG mark for dragons in the UI
export function dragonMark(d, size = 18) {
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" style="vertical-align:-3px" xmlns="http://www.w3.org/2000/svg">
  <path fill="${d ? d.colorHex : '#7a1f1f'}" d="M3 14 Q6 6 13 5 L12 2 L17 5 Q22 7 21 12 L17 10 Q18 14 14 16 L15 22 L11 18 Q5 19 3 14 Z"/>
  <circle cx="15.2" cy="6.8" r="1" fill="#f6edd4"/>
</svg>`;
}

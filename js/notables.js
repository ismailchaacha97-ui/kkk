// Notables: famous characters of the realm who belong to no great house —
// hedge knights, maesters, singers, sellsword captains, mystics.
import { makeRng } from './rng.js';

const ROLES = {
  knight: { label: 'Hedge Knight', icon: '⚔' },
  maester: { label: 'Wandering Maester', icon: '📜' },
  singer: { label: 'Singer', icon: '🎵' },
  sellsword: { label: 'Sellsword Captain', icon: '🗡' },
  mystic: { label: 'Mystic', icon: '☽' },
};
export const NOTABLE_ROLES = ROLES;

const KNIGHT_STYLES = ['of the Hollow Hill', 'of the Salt Road', 'the Penniless', 'of the Seven Scars', 'the Younger', 'of Nowhere', 'Half-Helm', 'the Unbowed'];
const DEEDS = {
  knight: ['unhorsed three lords in a single afternoon', 'held a ford alone through a night attack', 'won a mêlée with a broken arm'],
  maester: ['cured a village the Citadel had written off', 'forged three links no one will name', 'read the stars right, once, terribly'],
  singer: ['made a queen weep with six verses', 'knows a version of every song that is true', 'was banned from two courts for accuracy'],
  sellsword: ['sacked a city and returned its septs untouched', 'has never broken a paid contract', 'lost an eye and raised his price'],
  mystic: ['predicted the red comet to the very night', 'speaks to something in the fire', 'was drowned once and disagrees'],
};

export function makeNotable(state, rng, role) {
  role = role || rng.pick(Object.keys(ROLES));
  const gender = role === 'knight' || role === 'sellsword' ? (rng.chance(0.85) ? 'm' : 'f') : (rng.chance(0.6) ? 'm' : 'f');
  const id = 'n' + (state.nextNotableId = (state.nextNotableId || 1) + 1);
  const n = {
    id, role, gender,
    name: state.namer.firstName(gender) + (role === 'knight' ? ' ' + rng.pick(KNIGHT_STYLES) : ''),
    birthYear: state.year - rng.int(20, 45),
    alive: true, deathYear: null,
    fame: rng.int(2, 8),
    war: role === 'knight' ? rng.int(12, 18) : role === 'sellsword' ? rng.int(11, 16) : rng.int(3, 8),
    deed: rng.pick(DEEDS[role]),
    patronHouseId: null,
  };
  if (!state.notables) state.notables = {};
  state.notables[id] = n;
  return n;
}

export function ensureNotables(state) {
  if (state.notables && Object.keys(state.notables).length) return;
  const rng = makeRng(((state.seed ^ 0xAB1E5) >>> 0) || (state.seed + 77));
  state.notables = {};
  const mix = ['knight', 'knight', 'knight', 'maester', 'singer', 'sellsword', 'mystic', 'knight', 'singer', 'sellsword'];
  for (const r of mix) makeNotable(state, rng, r);
}

export function livingNotables(state) {
  return Object.values(state.notables || {}).filter((n) => n.alive);
}

export function patronNotables(state, houseId) {
  return livingNotables(state).filter((n) => n.patronHouseId === houseId);
}

export function notableRoleLabel(n) {
  return ROLES[n.role] ? ROLES[n.role].label : n.role;
}

export function tickNotables(state, rng, logFn) {
  for (const n of livingNotables(state)) {
    const a = state.year - n.birthYear;
    let p = a > 70 ? 0.06 : a > 55 ? 0.02 : 0.004;
    if (rng.chance(p)) {
      n.alive = false; n.deathYear = state.year;
      const how = n.role === 'knight' ? rng.pick(['died as he lived: in the mud, refusing to yield', 'was found dead beside a polished sword and an unpaid inn bill'])
        : n.role === 'sellsword' ? 'died rich, which among sellswords counts as a miracle'
        : n.role === 'singer' ? 'died mid-verse, which the other singers call showing off'
        : n.role === 'mystic' ? 'walked into the sea, smiling, at the exact hour foretold'
        : 'died correcting someone, correctly';
      logFn(state, `${n.name}, the famed ${notableRoleLabel(n).toLowerCase()}, is dead — ${how}.`, 'event');
    } else if (rng.chance(0.06)) {
      n.fame = Math.min(20, n.fame + 1);
    }
  }
  // new fame rises
  if (livingNotables(state).length < 12 && rng.chance(0.05)) {
    const n = makeNotable(state, rng);
    logFn(state, `A new name is on every tongue: ${n.name}, a ${notableRoleLabel(n).toLowerCase()} who ${n.deed}.`, 'event');
  }
}

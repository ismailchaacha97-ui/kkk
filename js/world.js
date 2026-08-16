// World generation: realm, regions, houses, characters.
import { makeRng } from './rng.js';
import { makeNamer, TRAITS } from './names.js';
import { makeSigil } from './sigil.js';
import { makeDragon } from './dragons.js';

export function newCharId(state) { return 'c' + (state.nextCharId++); }

export function makeCharacter(state, rng, opts = {}) {
  const gender = opts.gender || (rng.chance(0.5) ? 'm' : 'f');
  const id = newCharId(state);
  const traits = [];
  const pairs = rng.shuffle(TRAITS).slice(0, 2);
  for (const p of pairs) traits.push(rng.pick(p));
  const ch = {
    id, gender,
    name: opts.name || state.namer.firstName(gender),
    houseId: opts.houseId || null,
    birthHouseId: opts.birthHouseId || opts.houseId || null,
    birthYear: opts.birthYear ?? (state.year - rng.int(16, 55)),
    alive: true, deathYear: null, causeOfDeath: null,
    traits,
    skills: {
      war: rng.int(2, 12), dip: rng.int(2, 12),
      stew: rng.int(2, 12), intr: rng.int(2, 12),
    },
    spouseId: null, fatherId: opts.fatherId || null, motherId: opts.motherId || null,
    childrenIds: [],
    epithet: null,
    glory: 0, // tourney wins, battle honors
    wounded: false,
  };
  // Dragonblood: rare heritable gift of the old blood
  if (opts.dragonblood || (!opts.fatherId && !opts.motherId && rng.chance(0.03))) {
    ch.traits.push('Dragonblood');
  } else if (opts.fatherId || opts.motherId) {
    const f = state.characters[opts.fatherId];
    const m = state.characters[opts.motherId];
    const fB = f && f.traits.includes('Dragonblood');
    const mB = m && m.traits.includes('Dragonblood');
    if ((fB && mB && rng.chance(0.85)) || ((fB || mB) && rng.chance(0.45))) {
      ch.traits.push('Dragonblood');
    }
  }
  // Trait skill bumps
  if (traits.includes('Brave')) ch.skills.war += 2;
  if (traits.includes('Shrewd')) { ch.skills.stew += 2; ch.skills.intr += 1; }
  if (traits.includes('Charming')) ch.skills.dip += 3;
  if (traits.includes('Scheming')) ch.skills.intr += 3;
  if (traits.includes('Dull')) { ch.skills.stew -= 2; ch.skills.dip -= 1; }
  for (const k of Object.keys(ch.skills)) ch.skills[k] = Math.max(1, Math.min(18, ch.skills[k]));
  state.characters[id] = ch;
  return ch;
}

export function age(state, ch) { return state.year - ch.birthYear; }

function makeFamily(state, rng, house) {
  // Lord
  const lord = makeCharacter(state, rng, { houseId: house.id, gender: rng.chance(0.85) ? 'm' : 'f' });
  lord.birthYear = state.year - rng.int(28, 58);
  house.lordId = lord.id;
  house.memberIds.push(lord.id);

  // Consort
  if (rng.chance(0.8)) {
    const consort = makeCharacter(state, rng, {
      houseId: house.id, gender: lord.gender === 'm' ? 'f' : 'm',
    });
    consort.birthYear = state.year - Math.max(18, age(state, lord) - rng.int(-4, 8));
    consort.birthHouseId = null; // from a distant line
    lord.spouseId = consort.id; consort.spouseId = lord.id;
    house.memberIds.push(consort.id);

    // Children
    const nKids = rng.int(0, Math.min(4, Math.floor((age(state, lord) - 18) / 6) + 1));
    for (let i = 0; i < nKids; i++) {
      const kid = makeCharacter(state, rng, {
        houseId: house.id, fatherId: lord.gender === 'm' ? lord.id : consort.id,
        motherId: lord.gender === 'f' ? lord.id : consort.id,
      });
      kid.birthYear = state.year - rng.int(1, Math.max(2, age(state, lord) - 19));
      lord.childrenIds.push(kid.id); consort.childrenIds.push(kid.id);
      house.memberIds.push(kid.id);
    }
  }
  // A sibling of the lord sometimes
  if (rng.chance(0.5)) {
    const sib = makeCharacter(state, rng, { houseId: house.id });
    sib.birthYear = lord.birthYear + rng.int(-6, 8);
    if (state.year - sib.birthYear < 14) sib.birthYear = state.year - 14;
    house.memberIds.push(sib.id);
  }
}

function makeHouse(state, rng, tier, regionId, liegeId) {
  const id = 'h' + (state.nextHouseId++);
  const house = {
    id, tier, regionId, liegeId,
    name: state.namer.houseName(),
    seat: state.namer.seatName(),
    motto: state.namer.motto(),
    sigil: makeSigil(rng),
    alive: true, extinctYear: null,
    lordId: null, memberIds: [],
    gold: tier === 'royal' ? rng.int(900, 1400) : tier === 'great' ? rng.int(380, 650) : rng.int(120, 260),
    income: tier === 'royal' ? rng.int(90, 130) : tier === 'great' ? rng.int(48, 75) : rng.int(18, 34),
    troops: tier === 'royal' ? rng.int(7000, 10000) : tier === 'great' ? rng.int(2800, 5200) : rng.int(500, 1400),
    prestige: tier === 'royal' ? rng.int(80, 95) : tier === 'great' ? rng.int(48, 70) : rng.int(12, 34),
    relations: {},
    foundedNote: null,
  };
  state.houses[id] = house;
  makeFamily(state, rng, house);
  return house;
}

export function generateWorld(seed) {
  const rng = makeRng(seed);
  const state = {
    seed,
    rngSeed: seed,
    year: rng.int(180, 340),
    season: 0, // 0 spring, 1 summer, 2 autumn, 3 winter
    nextCharId: 1, nextHouseId: 1, nextDragonId: 1,
    characters: {}, houses: {}, dragons: {},
    dragonEggs: 0, // eggs held by the player house
    regions: [], realmName: null,
    crownHouseId: null,
    playerHouseId: null,
    war: null, // { name, attackers:[houseIds], defenders:[houseIds], cause, seasonsLeft, score }
    winterSeverity: 0,
    log: [],        // current season events (strings)
    annals: [],     // [{year, entries:[...]}] full history
    pendingDecisions: [],
    actionsLeft: 2,
    gameOver: null,
    turnCount: 0,
  };
  state.namer = makeNamer(rng);
  state.realmName = state.namer.realmName();
  state.dynastyEra = rng.pick(['the Long Peace', 'the Age of Ash', 'the Second Founding', 'the Years of the Broken Wheel', 'the Ravenmarked Century']);

  // Regions
  const regionDefs = state.namer.regions(6);
  regionDefs.forEach(([name, biome], i) => {
    state.regions.push({ id: 'r' + i, name, biome });
  });

  // Royal house — holds the Wyrmspire Throne
  const crown = makeHouse(state, rng, 'royal', state.regions[0].id, null);
  state.crownHouseId = crown.id;
  crown.seat = rng.pick(['Wyrmspire', 'The Hollow Crown', 'Kingsreach', 'Thronehold', 'Sunspire']);

  // Great houses, one per region
  const greats = [];
  for (const r of state.regions) {
    const g = makeHouse(state, rng, 'great', r.id, crown.id);
    greats.push(g);
  }

  // Minor houses, 2-4 per region sworn to that region's great house
  for (const g of greats) {
    const n = rng.int(2, 4);
    for (let i = 0; i < n; i++) makeHouse(state, rng, 'minor', g.regionId, g.id);
  }

  // Relations
  const ids = Object.keys(state.houses);
  for (const a of ids) for (const b of ids) {
    if (a === b) continue;
    const ha = state.houses[a], hb = state.houses[b];
    let base = rng.int(-25, 25);
    if (ha.liegeId === b || hb.liegeId === a) base += 20;
    if (ha.regionId === hb.regionId && ha.tier === 'minor' && hb.tier === 'minor') base -= 8; // local rivals
    state.houses[a].relations[b] = Math.max(-80, Math.min(80, base));
  }
  // ---- Dragons: the last fires of the world ----
  // The crown keeps one chained wonder — the reason no one has taken the throne in living memory.
  const crownLord = state.characters[crown.lordId];
  if (crownLord && rng.chance(0.7)) crownLord.traits.push('Dragonblood');
  const royalDragon = makeDragon(state, rng, {
    houseId: crown.id,
    riderId: crownLord && crownLord.traits.includes('Dragonblood') && rng.chance(0.7) ? crownLord.id : null,
    birthYear: state.year - rng.int(40, 90),
  });
  if (royalDragon.riderId) crownLord.dragonId = royalDragon.id;

  // One or two wild dragons haunt the far regions.
  const nWild = rng.chance(0.6) ? 2 : 1;
  for (let i = 0; i < nWild; i++) {
    makeDragon(state, rng, {
      wild: true,
      lairRegionId: rng.pick(state.regions).id,
      birthYear: state.year - rng.int(15, 70),
    });
  }

  // A couple of Dragonblood lines among the great/minor houses (dormant gift, no dragon)
  const bloodHouses = rng.shuffle(ids.filter((i) => state.houses[i].tier !== 'royal')).slice(0, 3);
  for (const bi of bloodHouses) {
    const bh = state.houses[bi];
    const bl = state.characters[bh.lordId];
    if (bl && !bl.traits.includes('Dragonblood')) bl.traits.push('Dragonblood');
    for (const kidId of (bl ? bl.childrenIds : [])) {
      const k = state.characters[kidId];
      if (k && rng.chance(0.45) && !k.traits.includes('Dragonblood')) k.traits.push('Dragonblood');
    }
  }

  // Seed one famous blood feud
  const feudPool = ids.filter((i) => state.houses[i].tier !== 'royal');
  const fa = rng.pick(feudPool);
  let fb = rng.pick(feudPool);
  while (fb === fa) fb = rng.pick(feudPool);
  state.houses[fa].relations[fb] = -75; state.houses[fb].relations[fa] = -75;
  state.feud = [fa, fb];

  state.rngSeed = Math.floor(rng.random() * 2 ** 31);
  return state;
}

export function livingMembers(state, house) {
  return house.memberIds.map((i) => state.characters[i]).filter((c) => c && c.alive);
}

export function houseOf(state, ch) { return state.houses[ch.houseId]; }

export function fullName(state, ch) {
  const h = ch.houseId ? state.houses[ch.houseId] : null;
  let n = ch.name + (h ? ' ' + h.name : '');
  if (ch.epithet) n += ' ' + ch.epithet;
  return n;
}

export function shortName(state, ch) {
  const h = ch.houseId ? state.houses[ch.houseId] : null;
  return ch.name + (h ? ' ' + h.name : '');
}

// Succession: eldest son -> eldest daughter -> eldest living male member -> eldest living member
export function findHeir(state, house, excludeId) {
  const living = livingMembers(state, house).filter((c) => c.id !== excludeId);
  if (living.length === 0) return null;
  const lord = state.characters[house.lordId];
  const kids = (lord ? lord.childrenIds : [])
    .map((i) => state.characters[i])
    .filter((c) => c && c.alive && c.houseId === house.id && c.id !== excludeId);
  const byAge = (a, b) => a.birthYear - b.birthYear;
  const sons = kids.filter((c) => c.gender === 'm').sort(byAge);
  if (sons.length) return sons[0];
  const daughters = kids.filter((c) => c.gender === 'f').sort(byAge);
  if (daughters.length) return daughters[0];
  // grandchildren via dead children? keep simple: any blood member (not a married-in consort)
  const blood = living.filter((c) => c.birthHouseId === house.id).sort(byAge);
  if (blood.length) return blood[0];
  return living.sort(byAge)[0];
}

export function regionName(state, id) {
  const r = state.regions.find((x) => x.id === id);
  return r ? r.name : 'the realm';
}

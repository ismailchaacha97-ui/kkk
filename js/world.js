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
    awayUntil: null,   // turnCount until which the character is off adventuring
    awayReason: null,
    mood: 0,           // -3..3, affected by interactions
    tutoredThisYear: false,
  };
  // Dragonblood: rare heritable gift of the old blood
  if (opts.dragonblood || (!opts.fatherId && !opts.motherId && rng.chance(0.03))) {
    ch.traits.push('Dragonblood');
  } else if (opts.fatherId || opts.motherId) {
    const f = state.characters[opts.fatherId];
    const m = state.characters[opts.motherId];
    const fB = f && f.traits.includes('Dragonblood');
    const mB = m && m.traits.includes('Dragonblood');
    if ((fB && mB && rng.chance(0.9)) || ((fB || mB) && rng.chance(0.5))) {
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
    council: { castellan: null, marshal: null, envoy: null, spymaster: null },
    designatedHeirId: null,
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

  // Regions — laid out on a 3x2 map grid (map is 1000x660, crownlands at center)
  const regionDefs = state.namer.regions(6);
  const cells = rng.shuffle([[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]]);
  regionDefs.forEach(([name, biome], i) => {
    const [cx, cy] = cells[i];
    state.regions.push({
      id: 'r' + i, name, biome,
      mx: cx * 333, my: cy * 330, mw: 334, mh: 330, // map cell bounds
    });
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

  // Minor houses, 4-6 per region sworn to that region's great house
  for (const g of greats) {
    const n = rng.int(4, 6);
    for (let i = 0; i < n; i++) makeHouse(state, rng, 'minor', g.regionId, g.id);
  }

  // Map positions: crown at the heart of the realm, others scattered in their region cells
  crown.mapX = 500; crown.mapY = 330;
  for (const h of Object.values(state.houses)) {
    if (h.tier === 'royal') continue;
    const r = state.regions.find((x) => x.id === h.regionId);
    for (let tries = 0; tries < 60; tries++) {
      const x = r.mx + 60 + rng.random() * (r.mw - 120);
      const y = r.my + 60 + rng.random() * (r.mh - 120);
      // keep away from crown and from other placed seats
      const others = Object.values(state.houses).filter((o) => o.mapX != null);
      const tooClose = others.some((o) => (o.mapX - x) ** 2 + (o.mapY - y) ** 2 < 72 ** 2) ||
        ((x - 500) ** 2 + (y - 330) ** 2 < 110 ** 2);
      if (!tooClose || tries === 59) { h.mapX = Math.round(x); h.mapY = Math.round(y); break; }
    }
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

// Succession: designated heir -> eldest son -> eldest daughter -> eldest blood member -> anyone
export function findHeir(state, house, excludeId) {
  const living = livingMembers(state, house).filter((c) => c.id !== excludeId);
  if (house.designatedHeirId) {
    const dh = state.characters[house.designatedHeirId];
    if (dh && dh.alive && dh.houseId === house.id && dh.id !== excludeId) return dh;
  }
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

// A new house rises mid-game: cadet branch, upjumped knight, or a merchant buying a ruin.
export function foundNewHouse(state, rng) {
  const region = rng.pick(state.regions);
  const liege = Object.values(state.houses).find((h) => h.alive && h.tier === 'great' && h.regionId === region.id)
    || state.houses[state.crownHouseId];
  const house = makeHouse(state, rng, 'minor', region.id, liege ? liege.id : null);
  // young houses start leaner
  house.gold = rng.int(60, 140);
  house.troops = rng.int(300, 800);
  house.prestige = rng.int(5, 18);
  // relations with everyone
  for (const other of Object.values(state.houses)) {
    if (other.id === house.id) continue;
    const base = rng.int(-10, 15);
    house.relations[other.id] = base;
    other.relations[house.id] = base + rng.int(-5, 5);
  }
  if (liege) { house.relations[liege.id] = 25; liege.relations[house.id] = 20; }
  // founding lore, written now
  const lord = state.characters[house.lordId];
  house.ancestorsGenerated = true;
  house.heirloom = null;

  // Founding story — sometimes they claim an extinct house's empty seat
  const ruins = Object.values(state.houses).filter((h) => !h.alive && h.extinctYear && h.seat !== house.seat);
  let story;
  const kind = rng.pick(ruins.length ? ['cadet', 'knight', 'ruin', 'ruin'] : ['cadet', 'knight', 'knight']);
  if (kind === 'ruin') {
    const ruin = rng.pick(ruins);
    house.seat = ruin.seat;
    story = `was granted the empty seat of ${ruin.seat}, silent since House ${ruin.name} died in Year ${ruin.extinctYear}, and swore to fill its halls with living voices`;
  } else if (kind === 'cadet') {
    const parents = Object.values(state.houses).filter((h) => h.alive && h.id !== house.id && h.tier !== 'royal' && h.memberIds.length >= 5);
    const parent = parents.length ? rng.pick(parents) : liege;
    story = `led the second sons of House ${parent ? parent.name : 'a crowded hall'} out to raw land, a cadet branch determined to be no one's second anything`;
    if (parent) { house.relations[parent.id] = 40; parent.relations[house.id] = 35; }
  } else {
    story = rng.pick([
      `was a landless knight who ${rng.pick(['won a royal mêlée and asked for land instead of gold', 'held a bridge alone against reavers until the levies came', 'caught the eye of the crown at a moment history declines to specify'])}`,
      `made a fortune in ${rng.pick(['salt', 'wool', 'timber', 'other people\u2019s wars'])} and bought what older blood pretends cannot be bought`,
    ]);
  }
  house.lore = {
    foundingYear: state.year,
    founderName: lord ? lord.name : state.namer.firstName('m'),
    founderGender: lord ? lord.gender : 'm',
    deed: story,
  };
  return house;
}

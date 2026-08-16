// Season-turn simulation engine.
import { makeRng } from './rng.js';
import { epithetFor } from './names.js';
import {
  makeCharacter, age, livingMembers, fullName, shortName,
  findHeir, regionName,
} from './world.js';

export const SEASONS = ['Spring', 'Summer', 'Autumn', 'Winter'];

function rngFor(state) {
  const rng = makeRng(state.rngSeed);
  state.rngSeed = Math.floor(rng.random() * 2 ** 31) + 1;
  return rng;
}

export function log(state, text, kind = 'event') {
  state.log.push({ text, kind });
}

function relMod(state, aId, bId, delta) {
  const a = state.houses[aId], b = state.houses[bId];
  if (!a || !b) return;
  a.relations[bId] = Math.max(-100, Math.min(100, (a.relations[bId] || 0) + delta));
  b.relations[aId] = Math.max(-100, Math.min(100, (b.relations[aId] || 0) + delta));
}

// ---------- Death & succession ----------
export function kill(state, rng, ch, cause) {
  if (!ch.alive) return;
  ch.alive = false; ch.deathYear = state.year; ch.causeOfDeath = cause;
  const house = state.houses[ch.houseId];
  if (!house) return;
  const isPlayer = house.id === state.playerHouseId;
  const wasLord = house.lordId === ch.id;
  if (wasLord) {
    const heir = findHeir(state, house, ch.id);
    if (heir) {
      house.lordId = heir.id;
      const title = heir.gender === 'f' ? 'Lady' : 'Lord';
      log(state, `${fullName(state, ch)} — ${cause}. ${shortName(state, heir)} rises as ${title} of ${house.seat}.`, isPlayer ? 'death-player' : 'death');
      // A new lord may earn an epithet later; young heirs cause instability
      if (age(state, heir) < 16) {
        house.prestige = Math.max(0, house.prestige - 6);
        log(state, `A child ${title.toLowerCase()} sits uneasy in ${house.seat}; the bannermen mutter.`, 'note');
      }
    } else {
      house.alive = false; house.extinctYear = state.year;
      log(state, `${fullName(state, ch)} — ${cause}. With no heir of the blood, House ${house.name} is EXTINGUISHED. ${house.seat} stands empty.`, 'extinct');
      if (isPlayer) {
        state.gameOver = { reason: `House ${house.name} died with ${shortName(state, ch)}. ${cause}.`, year: state.year };
      }
    }
  } else {
    log(state, `${fullName(state, ch)} — ${cause}.`, isPlayer ? 'death-player' : 'death');
  }
}

function deathRisk(state, ch) {
  const a = age(state, ch);
  let annual;
  if (a < 5) annual = 0.05;
  else if (a < 15) annual = 0.01;
  else if (a < 45) annual = 0.012;
  else if (a < 60) annual = 0.05;
  else if (a < 70) annual = 0.13;
  else if (a < 80) annual = 0.28;
  else annual = 0.5;
  if (ch.traits.includes('Drunkard')) annual *= 1.4;
  if (ch.wounded) annual *= 1.6;
  if (state.season === 3) annual *= 1 + state.winterSeverity * 0.4;
  return annual / 4; // per-season
}

const NATURAL_CAUSES = [
  'died of a winter fever', 'died in their sleep', 'was carried off by a flux',
  'succumbed to a wasting illness', 'died of a pox', 'choked at a feast',
  'was thrown from a horse', 'died of a festering wound',
];

// ---------- Season tick pieces ----------
function tickMortality(state, rng) {
  for (const ch of Object.values(state.characters)) {
    if (!ch.alive || !ch.houseId) continue;
    if (!state.houses[ch.houseId] || !state.houses[ch.houseId].alive) continue;
    if (rng.chance(deathRisk(state, ch))) {
      const a = age(state, ch);
      let cause = rng.pick(NATURAL_CAUSES);
      if (a >= 70) cause = rng.pick(['died in their sleep, full of years', 'faded quietly at ' + state.houses[ch.houseId].seat, 'died of old age']);
      if (a < 10) cause = rng.pick(['was taken by a crib fever', 'died of the grey chill', 'did not survive a pox']);
      kill(state, rng, ch, cause);
    }
  }
}

function tickBirths(state, rng) {
  for (const house of Object.values(state.houses)) {
    if (!house.alive) continue;
    for (const ch of livingMembers(state, house)) {
      if (ch.gender !== 'f' || !ch.spouseId) continue;
      const sp = state.characters[ch.spouseId];
      if (!sp || !sp.alive) continue;
      const a = age(state, ch);
      if (a < 16 || a > 45) continue;
      let p = 0.10;
      if (ch.childrenIds.length >= 5) p *= 0.4;
      if (rng.chance(p)) {
        // child belongs to the father's house by convention; if mother is the ruling line, hers
        const mHouse = state.houses[ch.houseId];
        const fHouse = state.houses[sp.houseId];
        const kidHouse = (mHouse && mHouse.lordId === ch.id) || ch.birthHouseId === ch.houseId ? mHouse : (fHouse || mHouse);
        const kid = makeCharacter(state, rng, {
          houseId: kidHouse.id, birthYear: state.year,
          fatherId: sp.gender === 'm' ? sp.id : ch.id,
          motherId: ch.gender === 'f' ? ch.id : sp.id,
        });
        kid.birthYear = state.year;
        ch.childrenIds.push(kid.id); sp.childrenIds.push(kid.id);
        kidHouse.memberIds.push(kid.id);
        if (rng.chance(0.06)) {
          kill(state, rng, kid, 'died within days of birth');
          if (rng.chance(0.3)) kill(state, rng, ch, 'died in childbed');
        } else {
          const kindTag = kidHouse.id === state.playerHouseId ? 'birth-player' : 'birth';
          log(state, `A ${kid.gender === 'f' ? 'daughter' : 'son'}, ${kid.name}, is born to ${shortName(state, ch)} at ${kidHouse.seat}.`, kindTag);
        }
      }
    }
  }
}

function tickEconomy(state, rng) {
  for (const house of Object.values(state.houses)) {
    if (!house.alive) continue;
    let inc = house.income;
    if (state.season === 3) inc = Math.floor(inc * (1 - 0.25 * state.winterSeverity)); // winter bites
    if (state.season === 2) inc = Math.floor(inc * 1.25); // harvest
    const lord = state.characters[house.lordId];
    if (lord) inc = Math.floor(inc * (0.8 + lord.skills.stew * 0.025));
    house.gold += inc;
    // upkeep
    house.gold -= Math.floor(house.troops / 100);
    if (house.gold < 0) {
      house.gold = 0;
      house.troops = Math.max(200, Math.floor(house.troops * 0.92));
      if (house.id === state.playerHouseId) log(state, `The coffers of ${house.seat} run dry; unpaid levies drift home.`, 'warn');
    }
    // slow troop replenish
    const cap = house.tier === 'royal' ? 10000 : house.tier === 'great' ? 6000 : 2000;
    if (house.troops < cap) house.troops = Math.min(cap, house.troops + Math.floor(cap * 0.02));
    house.prestige = Math.max(0, house.prestige - 0.25); // prestige decays slowly
  }
}

function marriageableOf(state, house, minAge = 16) {
  return livingMembers(state, house).filter((c) => !c.spouseId && age(state, c) >= minAge && age(state, c) <= 50);
}

function tickAIMarriages(state, rng) {
  const houses = Object.values(state.houses).filter((h) => h.alive && h.id !== state.playerHouseId);
  for (const h of houses) {
    if (!rng.chance(0.10)) continue;
    const cands = marriageableOf(state, h);
    if (!cands.length) continue;
    const partnerHouse = rng.pick(houses.filter((x) => x.id !== h.id && x.alive));
    if (!partnerHouse) continue;
    const pc = marriageableOf(state, partnerHouse).filter((c) => c.gender !== cands[0].gender);
    const a = cands[0];
    const b = pc.find((c) => c.gender !== a.gender);
    if (!b) continue;
    const aName = shortName(state, a), bName = shortName(state, b);
    a.spouseId = b.id; b.spouseId = a.id;
    // bride traditionally joins groom's house (whichever isn't the ruling heir)
    const mover = a.gender === 'f' ? a : b;
    const stayer = mover === a ? b : a;
    const mh = state.houses[mover.houseId];
    if (mh && mh.lordId !== mover.id) {
      const idx = mh.memberIds.indexOf(mover.id);
      if (idx >= 0) mh.memberIds.splice(idx, 1);
      mover.houseId = stayer.houseId;
      state.houses[stayer.houseId].memberIds.push(mover.id);
    }
    relMod(state, h.id, partnerHouse.id, rng.int(12, 24));
    log(state, `${aName} weds ${bName}; Houses ${h.name} and ${partnerHouse.name} are joined.`, 'marriage');
  }
}

// ---------- Wars ----------
function housePower(state, house) {
  let p = house.troops;
  const lord = state.characters[house.lordId];
  if (lord) p *= 0.85 + lord.skills.war * 0.02;
  return p;
}

function sidePower(state, ids) {
  return ids.reduce((s, i) => s + (state.houses[i] && state.houses[i].alive ? housePower(state, state.houses[i]) : 0), 0);
}

export function startWar(state, rng, attackerId, defenderId, cause) {
  const A = state.houses[attackerId], D = state.houses[defenderId];
  const attackers = [attackerId], defenders = [defenderId];
  // Lieges and friendly houses may join
  for (const h of Object.values(state.houses)) {
    if (!h.alive || h.id === attackerId || h.id === defenderId) continue;
    if (h.liegeId === defenderId || (h.relations[defenderId] || 0) > 45) { if (rng.chance(0.6)) defenders.push(h.id); }
    else if (h.liegeId === attackerId || (h.relations[attackerId] || 0) > 45) { if (rng.chance(0.5)) attackers.push(h.id); }
  }
  state.war = {
    name: `The ${rng.pick(['War of', 'Rising of', 'Strife of', 'Reaving of'])} ${rng.pick([A.name + ' Pride', 'the ' + regionName(state, D.regionId).replace('The ', ''), D.seat, 'Broken Oaths', 'the ' + rng.pick(['Red', 'Grey', 'Salt', 'Winter']) + ' Banners'])}`,
    attackers, defenders, cause,
    score: 0, seasonsLeft: rng.int(3, 6), startYear: state.year, battles: [],
  };
  relMod(state, attackerId, defenderId, -40);
  log(state, `WAR! ${state.war.name} begins. House ${A.name} marches on House ${D.name} — ${cause}. Banners: ${attackers.length} against ${defenders.length}.`, 'war');
}

function tickWar(state, rng) {
  const w = state.war;
  if (!w) return;
  const aliveA = w.attackers.filter((i) => state.houses[i] && state.houses[i].alive);
  const aliveD = w.defenders.filter((i) => state.houses[i] && state.houses[i].alive);
  if (!aliveA.length || !aliveD.length) { state.war = null; return; }

  const pa = sidePower(state, aliveA), pd = sidePower(state, aliveD);
  const roll = rng.range(0.6, 1.4);
  const ratio = (pa * roll) / Math.max(1, pd);
  const site = rng.pick(['the fords of', 'the fields before', 'the walls of', 'the pass at', 'the burning of']);
  const place = state.houses[rng.pick(rng.chance(0.5) ? aliveD : aliveA)].seat;
  const battleName = `Battle at ${site} ${place}`;

  let winnerSide, margin;
  if (ratio > 1) { winnerSide = 'A'; w.score += ratio > 1.5 ? 2 : 1; margin = ratio; }
  else { winnerSide = 'D'; w.score -= ratio < 0.66 ? 2 : 1; margin = 1 / ratio; }

  // casualties
  for (const id of [...aliveA, ...aliveD]) {
    const h = state.houses[id];
    const onWinning = (winnerSide === 'A') === w.attackers.includes(id);
    const lossFrac = onWinning ? rng.range(0.04, 0.10) : rng.range(0.10, 0.22);
    h.troops = Math.max(100, Math.floor(h.troops * (1 - lossFrac)));
    // named characters risk death in battle
    for (const ch of livingMembers(state, h)) {
      if (ch.gender !== 'm' || age(state, ch) < 16 || age(state, ch) > 60) continue;
      const risk = (h.lordId === ch.id ? 0.03 : 0.05) * (onWinning ? 0.6 : 1.3);
      if (rng.chance(risk)) {
        kill(state, rng, ch, `fell in the ${battleName}`);
      } else if (rng.chance(0.05)) {
        ch.wounded = true;
        log(state, `${shortName(state, ch)} is carried wounded from the ${battleName}.`, 'note');
      } else if (!onWinning ? false : rng.chance(0.04)) {
        ch.glory += 1;
        log(state, `${shortName(state, ch)} wins renown in the ${battleName}.`, 'glory');
        if (!ch.epithet && ch.glory >= 2) {
          const ep = epithetFor(rng, ch);
          if (ep) { ch.epithet = ep; log(state, `Men begin to call ${ch.name} "${ep}."`, 'glory'); }
        }
      }
    }
  }
  const winName = winnerSide === 'A' ? state.houses[aliveA[0]].name : state.houses[aliveD[0]].name;
  log(state, `${battleName}: the banners of House ${winName} carry the day${margin > 1.5 ? ' in a rout' : ''}.`, 'war');
  w.battles.push(battleName);

  w.seasonsLeft -= 1;
  if (w.seasonsLeft <= 0 || Math.abs(w.score) >= 4) {
    endWar(state, rng);
  }
}

function endWar(state, rng) {
  const w = state.war;
  const attackersWin = w.score > 0;
  const winners = attackersWin ? w.attackers : w.defenders;
  const losers = attackersWin ? w.defenders : w.attackers;
  const lead = state.houses[winners[0]];
  const loser = state.houses[losers[0]];
  if (Math.abs(w.score) <= 1) {
    log(state, `${w.name} gutters out after ${state.year - w.startYear} year(s). A white peace is sworn; nothing is settled, and everything is remembered.`, 'war');
  } else {
    const tribute = Math.min(loser.gold, Math.floor(loser.gold * 0.4) + 60);
    loser.gold -= tribute; lead.gold += tribute;
    lead.prestige += 14; loser.prestige = Math.max(0, loser.prestige - 12);
    log(state, `${w.name} ends. House ${lead.name} dictates terms: ${tribute} gold in tribute and hostages given. House ${loser.name} bends the knee.`, 'war');
    // crown usurpation check
    if (losers.includes(state.crownHouseId) && winners.includes(state.playerHouseId) && w.targetCrown) {
      seizeThrone(state, rng, state.playerHouseId);
    }
  }
  state.war = null;
}

function seizeThrone(state, rng, houseId) {
  const h = state.houses[houseId];
  const old = state.houses[state.crownHouseId];
  old.tier = 'great';
  h.tier = 'royal';
  state.crownHouseId = houseId;
  h.prestige += 40;
  const lord = state.characters[h.lordId];
  log(state, `THE THRONE FALLS. ${fullName(state, lord)} is crowned ${lord.gender === 'f' ? 'Queen' : 'King'} of ${state.realmName}. House ${old.name} is cast down. The maesters mark a new dynasty.`, 'crown');
  state.wonCrown = true;
}

// ---------- Random events ----------
function tickEvents(state, rng) {
  const houses = Object.values(state.houses).filter((h) => h.alive);
  // AI feud escalation into war
  if (!state.war && rng.chance(0.10)) {
    const pairs = [];
    for (const h of houses) {
      if (h.id === state.playerHouseId) continue;
      for (const [oid, v] of Object.entries(h.relations)) {
        const o = state.houses[oid];
        if (o && o.alive && v < -45 && oid !== state.playerHouseId) pairs.push([h.id, oid]);
      }
    }
    if (pairs.length) {
      const [a, b] = rng.pick(pairs);
      startWar(state, rng, a, b, rng.pick(['an old blood feud', 'a slain envoy', 'a stolen bride', 'disputed borderlands', 'an insult at court']));
    }
  }

  // flavor events
  const flavorRolls = [
    [0.06, () => {
      const h = rng.pick(houses);
      h.gold = Math.max(0, h.gold - rng.int(20, 60));
      log(state, `Reavers strike the coasts near ${h.seat}; granaries burn in ${regionName(state, h.regionId)}.`, 'event');
    }],
    [0.05, () => {
      const h = rng.pick(houses);
      const l = state.characters[h.lordId];
      if (l) { h.prestige += 4; log(state, `${shortName(state, l)} holds a great feast at ${h.seat}; singers carry the tale across the realm.`, 'event'); }
    }],
    [0.04, () => {
      const h = rng.pick(houses);
      log(state, `A comet the color of ${rng.pick(['blood', 'old gold', 'sea-glass', 'bone'])} hangs over ${regionName(state, h.regionId)}. The smallfolk name it an omen.`, 'omen');
    }],
    [0.04, () => {
      if (state.season !== 3) return;
      const h = rng.pick(houses);
      h.troops = Math.max(100, h.troops - rng.int(60, 200));
      log(state, `The grey chill stalks ${regionName(state, h.regionId)}; the sick-carts roll out of ${h.seat} each dawn.`, 'event');
    }],
    [0.03, () => {
      const h = rng.pick(houses.filter((x) => x.tier === 'minor'));
      if (!h) return;
      h.gold += rng.int(40, 90);
      log(state, `A vein of silver is struck in the hills near ${h.seat}. House ${h.name} grows bold.`, 'event');
    }],
  ];
  for (const [p, fn] of flavorRolls) if (rng.chance(p)) fn();

  // Crown politics
  if (rng.chance(0.05)) {
    const crown = state.houses[state.crownHouseId];
    const target = rng.pick(houses.filter((h) => h.tier === 'great' && h.id !== crown.id));
    if (target) {
      relMod(state, crown.id, target.id, rng.int(-15, 10));
      log(state, `Whispers at ${crown.seat}: the crown eyes House ${target.name} with ${(crown.relations[target.id] || 0) < 0 ? 'suspicion' : 'favor'}.`, 'court');
    }
  }
}

// ---------- Player decisions (event cards) ----------
function maybePlayerDecision(state, rng) {
  if (state.pendingDecisions.length > 0) return;
  const P = state.houses[state.playerHouseId];
  if (!P || !P.alive) return;
  if (!rng.chance(0.38)) return;

  const lord = state.characters[P.lordId];
  const decisions = [];

  decisions.push({
    id: 'hedge_knight',
    title: 'A Hedge Knight at the Gates',
    text: `A weathered hedge knight, ${state.namer.firstName('m')} of the ${rng.pick(['Hollow Road', 'Salt March', 'Barrowlands'])}, offers his sword to House ${P.name}. His mail is rusted but his eyes are steady.`,
    options: [
      { label: 'Take him into service (20 gold)', effect: (st, r) => { const h = st.houses[st.playerHouseId]; if (h.gold < 20) return 'Your coffers cannot spare it. He rides on.'; h.gold -= 20; h.troops += 150; return 'He kneels and swears. Men follow him in; your garrison swells by 150.'; } },
      { label: 'Turn him away', effect: (st, r) => (r.chance(0.25) ? 'He rides to a rival hall. You will see that sword again.' : 'He bows stiffly and rides into the rain.') },
    ],
  });

  decisions.push({
    id: 'grain',
    title: 'The Smallfolk Hunger',
    text: `A lean season in ${regionName(state, P.regionId)}. Villagers gather below ${P.seat}, asking their ${lord && lord.gender === 'f' ? 'lady' : 'lord'} for grain.`,
    options: [
      { label: 'Open the granaries (30 gold)', effect: (st) => { const h = st.houses[st.playerHouseId]; if (h.gold < 30) return 'There is nothing to give. They remember that too.'; h.gold -= 30; h.prestige += 6; return 'Wagons roll out under your banner. The smallfolk will remember who fed them. (+6 prestige)'; } },
      { label: 'Let them fend for themselves', effect: (st, r) => { const h = st.houses[st.playerHouseId]; h.prestige = Math.max(0, h.prestige - 4); return r.chance(0.3) ? 'Grumbling turns to poaching and torched fences. (-4 prestige)' : 'They disperse, sullen. Songs are sung, and none are kind. (-4 prestige)'; } },
    ],
  });

  const rivalIds = Object.entries(P.relations).filter(([i, v]) => v < -20 && state.houses[i] && state.houses[i].alive).map(([i]) => i);
  if (rivalIds.length) {
    const rid = rng.pick(rivalIds);
    const R = state.houses[rid];
    decisions.push({
      id: 'insult',
      title: 'An Insult at Court',
      text: `At a gathering in ${regionName(state, P.regionId)}, a knight of House ${R.name} names your line "${rng.pick(['upjumped stewards', 'oathbreakers', 'sheep in wolf skins', 'gutter heraldry'])}" before the assembled lords.`,
      options: [
        { label: 'Demand a duel of honor', effect: (st, r) => {
            const h = st.houses[st.playerHouseId];
            const champ = livingMembers(st, h).filter((c) => age(st, c) >= 16 && c.gender === 'm').sort((a, b) => b.skills.war - a.skills.war)[0] || state.characters[h.lordId];
            if (!champ) return 'No champion steps forward. The hall laughs.';
            const winP = 0.35 + champ.skills.war * 0.03;
            if (r.chance(winP)) { h.prestige += 8; champ.glory += 1; relMod(st, h.id, rid, -10); return `${shortName(st, champ)} humbles the knight in three passes. The hall falls silent, then roars. (+8 prestige)`; }
            if (r.chance(0.2)) { kill(st, r, champ, `was slain in a duel of honor against a knight of House ${R.name}`); relMod(st, h.id, rid, -25); return 'The duel goes wrong. Terribly wrong.'; }
            champ.wounded = true; h.prestige = Math.max(0, h.prestige - 4);
            return `${shortName(st, champ)} is beaten bloody and yields. (-4 prestige)`;
          } },
        { label: 'Laugh it off', effect: (st) => { const h = st.houses[st.playerHouseId]; h.prestige = Math.max(0, h.prestige - 2); return 'You smile thinly. The remark travels anyway. (-2 prestige)'; } },
        { label: 'Remember it', effect: (st) => { relMod(st, st.playerHouseId, rid, -12); return `Nothing is said. Something is written down. (Relations with House ${R.name} worsen.)`; } },
      ],
    });
  }

  const kids = livingMembers(state, P).filter((c) => age(state, c) >= 6 && age(state, c) <= 14);
  if (kids.length && rng.chance(0.8)) {
    const kid = rng.pick(kids);
    decisions.push({
      id: 'ward',
      title: 'A Ward for the Crown',
      text: `A raven from ${state.houses[state.crownHouseId].seat}: the crown invites young ${kid.name} to be fostered at court. An honor — and a hostage, as all wards are.`,
      options: [
        { label: 'Send the child', effect: (st, r) => {
            const h = st.houses[st.playerHouseId];
            relMod(st, h.id, st.crownHouseId, 15); h.prestige += 4;
            const c = st.characters[kid.id];
            c.skills.dip += 2; c.skills.intr += 1;
            return `${kid.name} rides south with a small retinue. Court will sharpen the child — one way or another. (+crown favor, +4 prestige)`;
          } },
        { label: 'Politely refuse', effect: (st) => { relMod(st, st.playerHouseId, st.crownHouseId, -10); return 'The refusal is wrapped in courtesies. The crown hears it plainly. (-crown favor)'; } },
      ],
    });
  }

  decisions.push({
    id: 'bastard',
    title: 'A Bastard Rumor',
    text: `A whisper runs through the taverns of ${regionName(state, P.regionId)}: a baseborn child of your line lives in a fishing village, the very image of ${lord ? lord.name : 'your lord'}.`,
    options: [
      { label: 'Acknowledge the child', effect: (st, r) => {
          const h = st.houses[st.playerHouseId];
          const kid = makeCharacter(st, r, { houseId: h.id, birthYear: st.year - r.int(6, 14) });
          h.memberIds.push(kid.id);
          kid.traits.push('Baseborn');
          h.prestige = Math.max(0, h.prestige - 3);
          return `${kid.name} is brought to ${h.seat} and given your name. The septons frown; your line grows stronger. (-3 prestige, +1 family member)`;
        } },
      { label: 'Pay for silence (25 gold)', effect: (st) => { const h = st.houses[st.playerHouseId]; if (h.gold < 25) { h.prestige = Math.max(0, h.prestige - 5); return 'You cannot pay. The song writes itself. (-5 prestige)'; } h.gold -= 25; return 'Coin changes hands. The whisper fades — for now.'; } },
      { label: 'Ignore it', effect: (st, r) => (r.chance(0.4) ? (st.houses[st.playerHouseId].prestige = Math.max(0, st.houses[st.playerHouseId].prestige - 4), 'The rumor hardens into a ballad with seventeen verses. (-4 prestige)') : 'The rumor dies of neglect, as most do.') },
    ],
  });

  state.pendingDecisions.push(rng.pick(decisions));
}

// ---------- Promotion / goals ----------
function checkStanding(state) {
  const P = state.houses[state.playerHouseId];
  if (!P || !P.alive) return;
  if (P.tier === 'minor' && P.prestige >= 80) {
    P.tier = 'great';
    const oldLiege = state.houses[P.liegeId];
    P.liegeId = state.crownHouseId;
    log(state, `BY ROYAL DECREE: House ${P.name} is raised to a GREAT HOUSE of ${state.realmName}${oldLiege ? `, released from its oath to House ${oldLiege.name}` : ''}. The banners of ${regionName(state, P.regionId)} take note.`, 'crown');
  }
}

// ---------- Main season advance ----------
export function advanceSeason(state) {
  const rng = rngFor(state);
  state.log = [];
  state.turnCount++;

  // roll season forward
  state.season = (state.season + 1) % 4;
  if (state.season === 0) state.year += 1;
  if (state.season === 3) {
    state.winterSeverity = rng.weighted([[0.3, 30], [0.6, 40], [1.0, 22], [1.5, 8]]);
    const w = state.winterSeverity;
    log(state, w >= 1.5 ? 'A CRUEL WINTER descends. The old men say they have seen nothing like it.' :
      w >= 1.0 ? 'Winter comes hard this year. Snows close the high roads.' :
      'Winter settles over the realm.', 'season');
  }
  if (state.season === 2) log(state, 'The harvest is brought in across the realm.', 'season');

  tickEconomy(state, rng);
  tickMortality(state, rng);
  if (state.gameOver) { archiveSeason(state); return; }
  tickBirths(state, rng);
  tickAIMarriages(state, rng);
  tickWar(state, rng);
  tickEvents(state, rng);
  maybePlayerDecision(state, rng);
  checkStanding(state);

  state.actionsLeft = 2;
  archiveSeason(state);
}

function archiveSeason(state) {
  if (state.log.length === 0) return;
  let yearEntry = state.annals.find((a) => a.year === state.year);
  if (!yearEntry) { yearEntry = { year: state.year, entries: [] }; state.annals.push(yearEntry); }
  for (const e of state.log) {
    yearEntry.entries.push({ season: SEASONS[state.season], ...e });
  }
}

// ---------- Player actions ----------
export const ACTIONS = {
  improve: {
    label: 'Improve the Holdings', cost: 80,
    desc: '+4–7 permanent income. Roads, mills, a deeper harbor.',
    run(state, rng) {
      const h = state.houses[state.playerHouseId];
      const gain = rng.int(4, 7);
      h.income += gain;
      return `Masons and reeves set to work around ${h.seat}. Income rises by ${gain}.`;
    },
  },
  levies: {
    label: 'Raise Levies', cost: 60,
    desc: '+400–700 troops. Spears cost bread; bread costs gold.',
    run(state, rng) {
      const h = state.houses[state.playerHouseId];
      const gain = rng.int(400, 700);
      h.troops += gain;
      return `${gain} men muster in the yard of ${h.seat}, green but willing.`;
    },
  },
  tourney: {
    label: 'Host a Tourney', cost: 100,
    desc: '+prestige, glory for your kin, goodwill — and splintered lances.',
    run(state, rng) {
      const h = state.houses[state.playerHouseId];
      h.prestige += rng.int(6, 12);
      const knights = livingMembers(state, h).filter((c) => age(state, c) >= 16 && age(state, c) <= 45 && c.gender === 'm');
      let extra = '';
      if (knights.length && rng.chance(0.5)) {
        const k = rng.pick(knights);
        if (rng.chance(0.30 + k.skills.war * 0.025)) {
          k.glory += 1; h.prestige += 5;
          extra = ` ${shortName(state, k)} unhorses all comers and is crowned champion before the realm.`;
          if (!k.epithet && k.glory >= 2) { const ep = epithetFor(rng, k); if (ep) { k.epithet = ep; extra += ` Men now call him "${ep}."`; } }
        } else if (rng.chance(0.15)) {
          k.wounded = true;
          extra = ` ${shortName(state, k)} is carried from the lists with a shattered shoulder.`;
        }
      }
      // goodwill with random attendees
      const others = Object.values(state.houses).filter((x) => x.alive && x.id !== h.id);
      for (let i = 0; i < 3 && others.length; i++) relMod(state, h.id, rng.pick(others).id, rng.int(3, 8));
      return `Banners crowd the fields below ${h.seat}. The tourney is the talk of the realm.${extra}`;
    },
  },
  court_crown: {
    label: 'Court the Crown', cost: 40,
    desc: 'Send gifts and honeyed words to the throne. Diplomacy helps.',
    run(state, rng) {
      const h = state.houses[state.playerHouseId];
      if (h.id === state.crownHouseId) return 'You ARE the crown. The mirror is flattered.';
      const lord = state.characters[h.lordId];
      const bonus = lord ? lord.skills.dip : 6;
      const gain = rng.int(6, 12) + Math.floor(bonus / 3);
      relMod(state, h.id, state.crownHouseId, gain);
      h.prestige += 2;
      return `Your envoys are received at ${state.houses[state.crownHouseId].seat}. The crown's regard warms. (+${gain} favor)`;
    },
  },
  scheme: {
    label: 'Weave a Scheme', cost: 50,
    desc: 'Undermine a rival with whispers and coin. Intrigue helps. Risky.',
    needsTarget: true,
    run(state, rng, targetId) {
      const h = state.houses[state.playerHouseId];
      const T = state.houses[targetId];
      if (!T || !T.alive) return 'The target of your scheme no longer matters.';
      const lord = state.characters[h.lordId];
      const skill = lord ? lord.skills.intr : 6;
      const p = 0.35 + skill * 0.03;
      if (rng.chance(p)) {
        const mode = rng.pick(['coin', 'shame', 'discord']);
        if (mode === 'coin') { const amt = Math.min(T.gold, rng.int(40, 90)); T.gold -= amt; h.gold += amt; return `Your factor in ${T.seat} bleeds their counting house of ${amt} gold. No one the wiser.`; }
        if (mode === 'shame') { T.prestige = Math.max(0, T.prestige - rng.int(6, 12)); return `A scandal blossoms around House ${T.name} — forged letters, a compromised septon. Their name is mud this season.`; }
        const others = Object.values(state.houses).filter((x) => x.alive && x.id !== T.id && x.id !== h.id);
        if (others.length) { const o = rng.pick(others); relMod(state, T.id, o.id, -rng.int(10, 20)); return `Your whisperers set House ${T.name} and House ${o.name} at each other's throats.`; }
        return 'The scheme fizzles harmlessly.';
      }
      if (rng.chance(0.5)) {
        relMod(state, h.id, T.id, -rng.int(12, 22)); h.prestige = Math.max(0, h.prestige - 5);
        return `Your agent is caught in ${T.seat} with your letters on him. House ${T.name} knows, and soon everyone will. (-5 prestige)`;
      }
      return 'The scheme unravels quietly. Money spent, nothing gained — but nothing traced.';
    },
  },
  press_claim: {
    label: 'Declare War', cost: 120,
    desc: 'Call your banners against a rival house. Wars end in tribute — or graves.',
    needsTarget: true,
    warAction: true,
    run(state, rng, targetId) {
      if (state.war) return 'The realm already bleeds from one war. Wait for it to end.';
      const h = state.houses[state.playerHouseId];
      const T = state.houses[targetId];
      const cause = rng.pick(['a pressed claim', 'unpaid debts of honor', 'the old feud', 'disputed lands', 'an unavenged insult']);
      startWar(state, rng, h.id, targetId, cause);
      if (targetId === state.crownHouseId) { state.war.targetCrown = true; log(state, 'You have raised your banners against the THRONE itself. Win, and the realm is yours. Lose, and your name becomes a warning.', 'crown'); }
      return `The ravens fly. Your banners are called against House ${T.name}.`;
    },
  },
};

export function runAction(state, key, targetId) {
  const rng = rngFor(state);
  const act = ACTIONS[key];
  const h = state.houses[state.playerHouseId];
  if (!act || !h || !h.alive) return null;
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  if (h.gold < act.cost) return { ok: false, msg: `Not enough gold (${act.cost} needed).` };
  h.gold -= act.cost;
  state.actionsLeft -= 1;
  const msg = act.run(state, rng, targetId);
  log(state, msg, 'action');
  archiveTail(state);
  return { ok: true, msg };
}

// Player-arranged marriage
export function arrangeMarriage(state, myCharId, targetHouseId) {
  const rng = rngFor(state);
  const h = state.houses[state.playerHouseId];
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const me = state.characters[myCharId];
  const T = state.houses[targetHouseId];
  if (!me || !T || !T.alive) return { ok: false, msg: 'That match cannot be made.' };
  const cands = livingMembers(state, T).filter((c) => !c.spouseId && c.gender !== me.gender && age(state, c) >= 16 && age(state, c) <= 50);
  if (!cands.length) return { ok: false, msg: `House ${T.name} has no suitable match of the opposite sex unwed.` };
  // acceptance check
  const rel = h.relations[T.id] || 0;
  const prestigeGap = T.prestige - h.prestige;
  let p = 0.55 + rel / 200 - Math.max(0, prestigeGap) / 150;
  const lord = state.characters[h.lordId];
  if (lord) p += lord.skills.dip * 0.015;
  state.actionsLeft -= 1;
  if (!rng.chance(Math.max(0.1, Math.min(0.95, p)))) {
    relMod(state, h.id, T.id, -3);
    const msg = `House ${T.name} declines the match, with courtesies sharp enough to shave with.`;
    log(state, msg, 'action');
    archiveTail(state);
    return { ok: true, msg };
  }
  const partner = rng.pick(cands);
  me.spouseId = partner.id; partner.spouseId = me.id;
  // partner joins player house unless partner is heir/lord of theirs
  if (T.lordId !== partner.id) {
    const idx = T.memberIds.indexOf(partner.id);
    if (idx >= 0) T.memberIds.splice(idx, 1);
    partner.houseId = h.id;
    h.memberIds.push(partner.id);
  } else {
    // marrying their ruler: our member moves? keep both where they are, alliance only
  }
  relMod(state, h.id, T.id, rng.int(18, 30));
  h.prestige += T.tier === 'royal' ? 12 : T.tier === 'great' ? 7 : 3;
  const msg = `${shortName(state, me)} weds ${partner.name} of House ${T.name}. Septons bless it; the alliance is sealed with bread and salt.`;
  log(state, msg, 'marriage');
  archiveTail(state);
  return { ok: true, msg };
}

function archiveTail(state) {
  // append the most recent log entry to annals (actions happen between season archives)
  let yearEntry = state.annals.find((a) => a.year === state.year);
  if (!yearEntry) { yearEntry = { year: state.year, entries: [] }; state.annals.push(yearEntry); }
  const last = state.log[state.log.length - 1];
  if (last) yearEntry.entries.push({ season: SEASONS[state.season], ...last });
}

export function resolveDecision(state, decisionIdx, optionIdx) {
  const rng = rngFor(state);
  const d = state.pendingDecisions[decisionIdx];
  if (!d) return null;
  state.pendingDecisions.splice(decisionIdx, 1);
  const opt = d.options[optionIdx];
  const msg = opt.effect(state, rng);
  log(state, `${d.title}: ${msg}`, 'decision');
  archiveTail(state);
  return msg;
}

// Character interactions: what a lord can do with (and to) their kin.
import { makeRng } from './rng.js';
import { age, livingMembers, shortName, fullName } from './world.js';
import { log, kill } from './engine.js';

function rngFor(state) {
  const rng = makeRng(state.rngSeed);
  state.rngSeed = Math.floor(rng.random() * 2 ** 31) + 1;
  return rng;
}

function archiveTail(state) {
  let yearEntry = state.annals.find((a) => a.year === state.year);
  if (!yearEntry) { yearEntry = { year: state.year, entries: [] }; state.annals.push(yearEntry); }
  const last = state.log[state.log.length - 1];
  if (last) yearEntry.entries.push({ season: ['Spring', 'Summer', 'Autumn', 'Winter'][state.season], ...last });
}

function done(state, msg, kind = 'action') {
  log(state, msg, kind);
  archiveTail(state);
  return { ok: true, msg };
}

export function isAway(state, ch) {
  return ch.awayUntil != null && state.turnCount < ch.awayUntil;
}

export const COUNCIL_POSTS = {
  castellan: { label: 'Castellan', skill: 'stew', desc: 'Runs the keep. Bonus income from their stewardship.' },
  marshal: { label: 'Marshal', skill: 'war', desc: 'Drills the levies. Bonus battle power, fewer casualties.' },
  envoy: { label: 'Envoy', skill: 'dip', desc: 'Speaks for the house. Better marriages and crown relations.' },
  spymaster: { label: 'Spymaster', skill: 'intr', desc: 'Keeps the ledger of secrets. Better schemes; unlocks assassination.' },
};

// ---------- Interactions (each costs 1 action unless noted) ----------

export function tutorCharacter(state, chId, skill) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const rng = rngFor(state);
  const ch = state.characters[chId];
  if (!ch || !ch.alive) return { ok: false, msg: 'They are beyond tutoring.' };
  if (isAway(state, ch)) return { ok: false, msg: `${ch.name} is away from the keep.` };
  const a = age(state, ch);
  state.actionsLeft -= 1;
  const skillNames = { war: 'the sword and the field', dip: 'courtesy and statecraft', stew: 'ledgers and land', intr: 'watching and whispering' };
  let gain = a <= 16 ? rng.int(1, 2) : a <= 30 ? 1 : rng.chance(0.5) ? 1 : 0;
  if (ch.traits.includes('Dull')) gain = Math.max(0, gain - (rng.chance(0.5) ? 1 : 0));
  if (gain === 0) return done(state, `${ch.name} spends a season being taught ${skillNames[skill]}, and emerges precisely as before. Some clay has already set.`);
  ch.skills[skill] = Math.min(20, ch.skills[skill] + gain);
  ch.mood = Math.min(3, ch.mood + 1);
  return done(state, `${ch.name} is drilled in ${skillNames[skill]} for a season. (+${gain} ${skill === 'war' ? '⚔ war' : skill === 'dip' ? '🕊 diplomacy' : skill === 'stew' ? '🜚 stewardship' : '🗡 intrigue'})`);
}

export function rewardCharacter(state, chId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const h = state.houses[state.playerHouseId];
  if (h.gold < 30) return { ok: false, msg: 'Not enough gold (30 needed).' };
  const rng = rngFor(state);
  const ch = state.characters[chId];
  if (!ch || !ch.alive) return { ok: false, msg: 'The dead want for nothing.' };
  h.gold -= 30;
  state.actionsLeft -= 1;
  ch.mood = Math.min(3, ch.mood + 2);
  const gift = rng.pick(['a courser of the southern breed', 'a sword of castle-forged steel', 'a cloak of winter sable', 'lands by the mill stream', 'a harp strung with silver']);
  const idx = ch.traits.indexOf('Resentful');
  if (idx >= 0 && rng.chance(0.6)) {
    ch.traits.splice(idx, 1);
    return done(state, `${ch.name} is given ${gift} before the whole hall. Something long-frozen in ${ch.gender === 'f' ? 'her' : 'his'} face thaws. The old resentment is buried.`);
  }
  return done(state, `${ch.name} is honored before the hall with ${gift}. Loyalty, like steel, is forged warm.`);
}

export function sendAdventuring(state, chId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const ch = state.characters[chId];
  const h = state.houses[state.playerHouseId];
  if (!ch || !ch.alive) return { ok: false, msg: 'They cannot ride.' };
  if (isAway(state, ch)) return { ok: false, msg: `${ch.name} is already away.` };
  if (age(state, ch) < 16) return { ok: false, msg: 'They are too young to ride out.' };
  if (h.lordId === ch.id) return { ok: false, msg: 'The lord cannot abandon the seat. Send another.' };
  const rng = rngFor(state);
  state.actionsLeft -= 1;
  ch.awayUntil = state.turnCount + rng.int(2, 4);
  ch.awayReason = rng.pick(['riding the borderlands against reavers', 'seeking a name in the free companies', 'hunting rumors of treasure in the old ruins', 'escorting a septon to the far shrines']);
  return done(state, `${ch.name} rides out from ${h.seat}, ${ch.awayReason}. The road will return ${ch.gender === 'f' ? 'her' : 'him'} changed — or not at all.`);
}

export function banishCharacter(state, chId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const ch = state.characters[chId];
  const h = state.houses[state.playerHouseId];
  if (!ch || !ch.alive) return { ok: false, msg: 'They are gone already.' };
  if (h.lordId === ch.id) return { ok: false, msg: 'A lord cannot banish themselves. Abdication is not yet written into the game of thrones.' };
  const rng = rngFor(state);
  state.actionsLeft -= 1;
  // remove from house
  const idx = h.memberIds.indexOf(ch.id);
  if (idx >= 0) h.memberIds.splice(idx, 1);
  for (const post of Object.keys(h.council)) if (h.council[post] === ch.id) h.council[post] = null;
  if (h.designatedHeirId === ch.id) h.designatedHeirId = null;
  ch.houseId = null;
  h.prestige = Math.max(0, h.prestige - 3);
  const fate = rng.pick(['takes the black of the far watch', 'sails for the eastern cities', 'is last seen on the kingsroad, walking north', 'swears to a mercenary company']);
  return done(state, `${ch.name} is stripped of name and lands and cast out of ${h.seat}. ${ch.gender === 'f' ? 'She' : 'He'} ${fate}. (-3 prestige; the hall is quieter now.)`, 'decision');
}

export function nameHeir(state, chId) {
  const h = state.houses[state.playerHouseId];
  const ch = state.characters[chId];
  if (!ch || !ch.alive || ch.houseId !== h.id) return { ok: false, msg: 'They cannot inherit.' };
  if (h.lordId === ch.id) return { ok: false, msg: 'The lord already holds the seat.' };
  h.designatedHeirId = ch.id;
  return done(state, `Before septon and hall, ${shortName(state, ch)} is named HEIR to ${h.seat}. Let no one claim they were not told.`, 'crown');
}

export function appointCouncil(state, post, chId) {
  const h = state.houses[state.playerHouseId];
  const def = COUNCIL_POSTS[post];
  if (!def) return { ok: false, msg: 'No such office.' };
  if (chId === null) {
    const old = h.council[post] ? state.characters[h.council[post]] : null;
    h.council[post] = null;
    return done(state, `The office of ${def.label} stands empty${old ? `; ${old.name} returns to the household` : ''}.`);
  }
  const ch = state.characters[chId];
  if (!ch || !ch.alive || ch.houseId !== h.id) return { ok: false, msg: 'They cannot serve.' };
  if (h.lordId === ch.id) return { ok: false, msg: 'The lord cannot sit their own council. Ruling is already an office.' };
  if (age(state, ch) < 16) return { ok: false, msg: 'They are too young for office.' };
  if (isAway(state, ch)) return { ok: false, msg: `${ch.name} is away from the keep.` };
  for (const p of Object.keys(h.council)) if (h.council[p] === ch.id) h.council[p] = null;
  h.council[post] = ch.id;
  ch.mood = Math.min(3, ch.mood + 1);
  return done(state, `${shortName(state, ch)} is raised to ${def.label} of ${h.seat}. (${def.desc})`);
}

export function councilBonus(state, house, post) {
  const id = house.council ? house.council[post] : null;
  if (!id) return 0;
  const ch = state.characters[id];
  if (!ch || !ch.alive || ch.houseId !== house.id || house.lordId === ch.id) { house.council[post] = null; return 0; }
  if (ch.awayUntil != null && state.turnCount < ch.awayUntil) return 0;
  return ch.skills[COUNCIL_POSTS[post].skill];
}

// ---------- Adventure resolution (called each season from the engine) ----------
export function resolveAdventures(state, rng, killFn, makeDragonFn) {
  const h = state.houses[state.playerHouseId];
  if (!h || !h.alive) return;
  for (const ch of livingMembers(state, h)) {
    if (ch.awayUntil == null) continue;
    if (state.turnCount < ch.awayUntil) continue;
    // Return roll
    ch.awayUntil = null;
    const reason = ch.awayReason || 'wandering'; ch.awayReason = null;
    const roll = rng.random();
    if (roll < 0.08) {
      killFn(state, rng, ch, `never returned from ${reason}; a rusted sword and a story came back instead`);
    } else if (roll < 0.20) {
      ch.wounded = true;
      log(state, `${ch.name} returns to ${h.seat} lamed and quieter, carrying scars from ${reason}. The tale is not offered.`, 'note');
    } else if (roll < 0.45) {
      const gold = rng.int(30, 90);
      h.gold += gold; ch.glory += 1; ch.skills.war += 1;
      log(state, `${ch.name} rides home from ${reason} with ${gold} gold, a new scar, and a better sword-arm. (+1 ⚔, +glory)`, 'glory');
    } else if (roll < 0.50 && makeDragonFn && rng.chance(0.5)) {
      state.dragonEggs += 1;
      log(state, `${ch.name} returns from ${reason} carrying something wrapped in oilcloth: a scaled stone, warm as a sleeping cat. A DRAGON'S EGG, or the realm's best fake. It goes to the crypt.`, 'dragon-player');
    } else if (roll < 0.62) {
      ch.skills[rng.pick(['war', 'dip', 'intr'])] += 1; ch.mood = Math.min(3, ch.mood + 1);
      log(state, `${ch.name} returns from ${reason} taller in some way that has nothing to do with height. (+1 skill)`, 'event');
    } else {
      log(state, `${ch.name} returns from ${reason} with empty saddlebags and a full head of stories.`, 'event');
    }
  }
}

// ---------- Assassination (requires spymaster) ----------
export function assassinate(state, targetCharId) {
  const h = state.houses[state.playerHouseId];
  if (!h.council.spymaster) return { ok: false, msg: 'You need a Spymaster on your council for work this dark.' };
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  if (h.gold < 90) return { ok: false, msg: 'Not enough gold (90 needed). Knives are cheap; silence is expensive.' };
  const rng = rngFor(state);
  const target = state.characters[targetCharId];
  if (!target || !target.alive) return { ok: false, msg: 'Someone was quicker than you.' };
  const T = state.houses[target.houseId];
  h.gold -= 90;
  state.actionsLeft -= 1;
  const spy = state.characters[h.council.spymaster];
  const skill = spy ? spy.skills.intr : 5;
  let p = 0.30 + skill * 0.025;
  if (T && T.lordId === target.id) p -= 0.08; // lords are guarded
  if (T && T.tier === 'royal') p -= 0.10;
  const KILLS = ['a fall from a tower window', 'a fever no maester could name', 'a tavern quarrel that no one witnessed clearly', 'bad oysters', 'a loose saddle girth on a high road'];
  if (rng.chance(Math.max(0.08, p))) {
    const cause = rng.pick(KILLS);
    const name = shortName(state, target);
    kill(state, rng, target, `died of ${cause}`);
    return done(state, `Word arrives from ${T ? T.seat : 'afar'}: ${name} is dead — ${cause}. No one looks at you. Everyone looks at you.`, 'decision');
  }
  if (rng.chance(0.45)) {
    if (T) {
      h.relations[T.id] = Math.max(-100, (h.relations[T.id] || 0) - 35);
      T.relations[h.id] = Math.max(-100, (T.relations[h.id] || 0) - 35);
    }
    h.prestige = Math.max(0, h.prestige - 8);
    return done(state, `The catspaw is taken alive beneath ${T ? T.seat : 'their walls'} and sings your name to the rack. House ${T ? T.name : '???'} knows. The realm suspects. (-8 prestige, relations ruined)`, 'decision');
  }
  return done(state, `The knife finds only an empty bed. Your spymaster burns the letters; the gold is gone; nothing points home.`, 'decision');
}

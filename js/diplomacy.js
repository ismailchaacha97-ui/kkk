// Diplomacy: direct dealings between the player house and another house.
import { makeRng } from './rng.js';
import { livingMembers, age, shortName, regionName } from './world.js';
import { log } from './engine.js';
import { councilBonus } from './characters.js';

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

function relMod(state, aId, bId, delta) {
  const a = state.houses[aId], b = state.houses[bId];
  if (!a || !b) return;
  a.relations[bId] = Math.max(-100, Math.min(100, (a.relations[bId] || 0) + delta));
  b.relations[aId] = Math.max(-100, Math.min(100, (b.relations[aId] || 0) + delta));
}

export function getPacts(state) {
  if (!state.pacts) state.pacts = {}; // houseId -> {until: year}
  return state.pacts;
}

export function hasPact(state, houseId) {
  const p = getPacts(state)[houseId];
  return p && p.until >= state.year;
}

// ---------- Envoy actions (each costs 1 action) ----------

export function sendGift(state, targetId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const h = state.houses[state.playerHouseId];
  const T = state.houses[targetId];
  if (!T || !T.alive) return { ok: false, msg: 'There is no hall left to receive it.' };
  if (h.gold < 50) return { ok: false, msg: 'Not enough gold (50 needed).' };
  const rng = rngFor(state);
  h.gold -= 50; state.actionsLeft -= 1;
  const gain = rng.int(8, 16) + Math.floor(councilBonus(state, h, 'envoy') / 3);
  relMod(state, h.id, targetId, gain);
  const gift = rng.pick(['a matched pair of falcons', 'a cask of arbor-gold wine', 'a tapestry of their founder\u2019s great deed', 'six palfreys with silvered tack', 'a reliquary said to hold a hero\u2019s knucklebone']);
  return done(state, `Your envoys ride to ${T.seat} bearing ${gift}. House ${T.name} receives them warmly. (+${gain} relations)`);
}

export function proposePact(state, targetId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const h = state.houses[state.playerHouseId];
  const T = state.houses[targetId];
  if (!T || !T.alive) return { ok: false, msg: 'That house is dust.' };
  if (hasPact(state, targetId)) return { ok: false, msg: `A pact already binds you to House ${T.name}.` };
  const rng = rngFor(state);
  state.actionsLeft -= 1;
  const rel = h.relations[targetId] || 0;
  let p = 0.3 + rel / 120 + councilBonus(state, h, 'envoy') * 0.015;
  if (T.tier === 'royal') p -= 0.15;
  if (!rng.chance(Math.max(0.05, Math.min(0.95, p)))) {
    relMod(state, h.id, targetId, -2);
    return done(state, `House ${T.name} hears the proposal out, then speaks at length about the weather. There is no pact.`);
  }
  const years = rng.int(8, 15);
  getPacts(state)[targetId] = { until: state.year + years };
  relMod(state, h.id, targetId, 10);
  return done(state, `Bread and salt at ${T.seat}: a PACT OF FRIENDSHIP is sworn with House ${T.name} for ${years} years. Their banners will answer if war finds you.`, 'marriage');
}

export function demandTribute(state, targetId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const h = state.houses[state.playerHouseId];
  const T = state.houses[targetId];
  if (!T || !T.alive) return { ok: false, msg: 'You cannot squeeze a ruin.' };
  const rng = rngFor(state);
  state.actionsLeft -= 1;
  const myPower = h.troops + (state.characters[h.lordId] ? state.characters[h.lordId].skills.war * 50 : 0);
  const theirPower = T.troops;
  const ratio = myPower / Math.max(1, theirPower);
  let p = ratio > 2.5 ? 0.75 : ratio > 1.5 ? 0.5 : ratio > 1 ? 0.25 : 0.08;
  relMod(state, h.id, targetId, -15);
  if (rng.chance(p)) {
    const amt = Math.min(T.gold, rng.int(40, 100));
    T.gold -= amt; h.gold += amt; h.prestige += 3;
    return done(state, `Your riders arrive at ${T.seat} with a polite letter and an impolite number of spears. House ${T.name} pays ${amt} gold and remembers it. (+${amt} gold, -relations)`);
  }
  if (rng.chance(0.25)) {
    h.prestige = Math.max(0, h.prestige - 5);
    return done(state, `House ${T.name} reads your demand aloud at their feast, to general laughter. The letter is returned folded into a paper bird. (-5 prestige, -relations)`);
  }
  return done(state, `House ${T.name} declines, with formal regret and informal archers on the walls. (-relations)`);
}

export function sendInsult(state, targetId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const h = state.houses[state.playerHouseId];
  const T = state.houses[targetId];
  if (!T || !T.alive) return { ok: false, msg: 'Mocking the dead is free, and worthless.' };
  const rng = rngFor(state);
  state.actionsLeft -= 1;
  relMod(state, h.id, targetId, -rng.int(15, 25));
  const insult = rng.pick([
    `a singer is dispatched to every tavern in ${regionName(state, T.regionId)} with a new ballad: "The ${rng.pick(['Limp', 'Bald', 'Beardless', 'Coinless'])} ${T.tier === 'great' ? 'Lion' : 'Lord'} of ${T.seat}"`,
    `your herald returns their last letter torn into strips and braided into a horse's tail`,
    `at the next market day, a pig wearing House ${T.name} colors is entered in the beauty contest. It places second, which is somehow worse`,
    `you send them a gift: an empty box, beautifully wrapped, with a note reading "your honor — we found it"`,
  ]);
  h.prestige += 2;
  return done(state, `The insult lands: ${insult}. The realm laughs; House ${T.name} does not. (+2 prestige, relations badly soured)`, 'decision');
}

export function inviteHunt(state, targetId) {
  if (state.actionsLeft <= 0) return { ok: false, msg: 'No actions remain this season.' };
  const h = state.houses[state.playerHouseId];
  const T = state.houses[targetId];
  if (!T || !T.alive) return { ok: false, msg: 'Their halls are empty.' };
  if (h.gold < 25) return { ok: false, msg: 'Not enough gold (25 needed) to host.' };
  const rng = rngFor(state);
  h.gold -= 25; state.actionsLeft -= 1;
  const rel = h.relations[targetId] || 0;
  if (rel < -40 && rng.chance(0.5)) {
    return done(state, `House ${T.name} declines the invitation with a single line: "We hunt with friends." Cold, but at least it rhymes with nothing.`);
  }
  const gain = rng.int(6, 12);
  relMod(state, h.id, targetId, gain);
  let extra = '';
  const rider = rng.pick(livingMembers(state, h).filter((c) => age(state, c) >= 16)) || null;
  if (rider && rng.chance(0.12)) {
    rider.wounded = true;
    extra = ` (Though ${rider.name} takes a boar tusk to the thigh and is carried home cursing.)`;
  } else if (rng.chance(0.2)) {
    h.prestige += 3;
    extra = ` A white hart is taken — an omen the singers will argue over. (+3 prestige)`;
  }
  return done(state, `Three days of hounds and horns with House ${T.name} in the woods below ${h.seat}. Wine does the diplomacy. (+${gain} relations)${extra}`);
}

// Pact enforcement: called from engine when a war starts against the player.
export function pactAllies(state) {
  const out = [];
  const pacts = getPacts(state);
  for (const [hid, p] of Object.entries(pacts)) {
    if (p.until >= state.year && state.houses[hid] && state.houses[hid].alive) out.push(hid);
  }
  return out;
}

// Playable tourneys: an 8-rider bracket of named knights, tilt by tilt.
import { makeRng } from './rng.js';
import { livingMembers, age, shortName } from './world.js';
import { log } from './engine.js';
import { livingNotables } from './notables.js';
import { epithetFor } from './names.js';

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

// Build an 8-slot field: player's champion + 7 riders (house knights + notables)
export function openTourney(state, championId) {
  const rng = rngFor(state);
  const P = state.houses[state.playerHouseId];
  const champ = state.characters[championId];
  if (!champ || !champ.alive) return null;

  const riders = [{
    kind: 'char', refId: champ.id, name: shortName(state, champ),
    houseId: P.id, war: champ.skills.war + (champ.glory || 0), isPlayer: true,
  }];

  // rival house knights
  const pool = [];
  for (const h of Object.values(state.houses)) {
    if (!h.alive || h.id === P.id) continue;
    for (const c of livingMembers(state, h)) {
      if (c.gender !== 'm' || age(state, c) < 16 || age(state, c) > 50 || c.wounded) continue;
      pool.push({ kind: 'char', refId: c.id, name: shortName(state, c), houseId: h.id, war: c.skills.war + (c.glory || 0) });
    }
  }
  // famous hedge knights & sellswords
  for (const n of livingNotables(state)) {
    if (n.role !== 'knight' && n.role !== 'sellsword') continue;
    pool.push({ kind: 'notable', refId: n.id, name: n.name, houseId: null, war: n.war + Math.floor(n.fame / 3) });
  }
  const picked = rng.shuffle(pool).slice(0, 7);
  while (picked.length < 7) picked.push({ kind: 'filler', refId: null, name: 'A mystery knight in patched mail', houseId: null, war: rng.int(8, 14) });
  riders.push(...picked);

  state.tourney = {
    round: 0, // 0=quarter, 1=semi, 2=final
    bracket: rng.shuffle(riders),
    results: [],
    wager: 0, wagerOn: null,
    champion: null, done: false,
    playerOut: false,
  };
  return state.tourney;
}

export function placeWager(state, amount, riderName) {
  const t = state.tourney;
  const P = state.houses[state.playerHouseId];
  if (!t || t.round > 0 || amount <= 0 || P.gold < amount) return false;
  P.gold -= amount;
  t.wager = amount;
  t.wagerOn = riderName;
  return true;
}

// Run one round; returns array of {a, b, winner, text}
export function runTourneyRound(state) {
  const rng = rngFor(state);
  const t = state.tourney;
  if (!t || t.done) return [];
  const field = t.bracket;
  const next = [];
  const results = [];
  for (let i = 0; i < field.length; i += 2) {
    const A = field[i], B = field[i + 1];
    const pa = (A.war + rng.range(0, 8));
    const pb = (B.war + rng.range(0, 8));
    const winner = pa >= pb ? A : B;
    const loser = winner === A ? B : A;
    const flavor = rng.pick([
      `${winner.name} takes ${loser.name} clean off the horse on the ${rng.pick(['first', 'second', 'third'])} tilt`,
      `three lances shatter before ${winner.name} finds the gap in ${loser.name}'s guard`,
      `${loser.name}'s saddle girth slips — the crowd cries foul, the judges do not`,
      `${winner.name} and ${loser.name} splinter five lances; the sixth decides it`,
    ]);
    // injury chance for the loser (real characters only)
    let injury = '';
    if (loser.kind === 'char' && rng.chance(0.12)) {
      const c = state.characters[loser.refId];
      if (c) {
        c.wounded = true;
        injury = ` ${loser.name} is carried from the lists.`;
        if (rng.chance(0.06)) {
          // rare tourney death (applied at conclusion)
          c.wounded = false;
          injury = ` ${loser.name} does not rise. The lists fall silent.`;
          loser.died = true;
        }
      }
    }
    if (loser.isPlayer) t.playerOut = true;
    results.push({ a: A.name, b: B.name, winner: winner.name, text: flavor + injury, winnerRef: winner, loserRef: loser });
    next.push(winner);
  }
  t.results.push(results);
  t.bracket = next;
  t.round += 1;
  if (next.length === 1) {
    t.champion = next[0];
    t.done = true;
  }
  return results;
}

// Finish: apply outcomes, log, clean up. queenChoice: {houseId} or null (only if player champion won)
export function concludeTourney(state, queenChoice) {
  const rng = rngFor(state);
  const t = state.tourney;
  const P = state.houses[state.playerHouseId];
  if (!t || !t.done) return null;
  const champ = t.champion;
  let msg;

  // deaths flagged during rounds
  for (const round of t.results) {
    for (const r of round) {
      if (r.loserRef && r.loserRef.died && r.loserRef.kind === 'char') {
        const c = state.characters[r.loserRef.refId];
        if (c && c.alive) {
          c.alive = false; c.deathYear = state.year;
          c.causeOfDeath = `died in the lists at the tourney of ${P.seat}`;
          log(state, `${r.loserRef.name} — died in the lists at the tourney of ${P.seat}.`, 'death');
        }
      }
    }
  }

  if (champ.isPlayer) {
    const c = state.characters[champ.refId];
    state.tourneyWon = true;
    P.prestige += 14;
    if (c) {
      c.glory += 2;
      if (!c.epithet && c.glory >= 2) { const ep = epithetFor(rng, c); if (ep) c.epithet = ep; }
    }
    msg = `${champ.name} is CHAMPION of the tourney of ${P.seat}! The champion's purse and the crowd's love both come home. (+14 prestige)`;
    if (queenChoice && queenChoice.houseId) {
      const QH = state.houses[queenChoice.houseId];
      if (QH) {
        const ladies = livingMembers(state, QH).filter((x) => x.gender === 'f' && age(state, x) >= 14 && age(state, x) <= 45);
        const lady = ladies.length ? rng.pick(ladies) : null;
        if (lady) {
          const wedded = lady.spouseId && state.characters[lady.spouseId] && state.characters[lady.spouseId].alive;
          P.relations[QH.id] = Math.max(-100, Math.min(100, (P.relations[QH.id] || 0) + (wedded ? -20 : 15)));
          QH.relations[P.id] = P.relations[QH.id];
          msg += wedded
            ? ` The crown of Love and Beauty is laid in the lap of ${lady.name} — a WEDDED woman. Her husband's face could curdle milk. (House ${QH.name} relations sour)`
            : ` ${lady.name} of House ${QH.name} is crowned Queen of Love and Beauty; her house glows. (+relations)`;
        }
      }
    }
  } else {
    P.prestige += 6;
    msg = `${champ.name} takes the champion's crown at ${P.seat}. A fine tourney nonetheless; the realm will speak well of it. (+6 prestige)`;
    if (champ.kind === 'char' && champ.houseId && state.houses[champ.houseId]) {
      const WH = state.houses[champ.houseId];
      WH.prestige += 6;
      const c = state.characters[champ.refId];
      if (c) c.glory += 1;
    }
    if (champ.kind === 'notable') {
      const n = state.notables[champ.refId];
      if (n) n.fame = Math.min(20, n.fame + 3);
    }
  }

  // wager resolution: paid 3:1 if your pick won
  if (t.wager > 0) {
    if (t.wagerOn && champ.name === t.wagerOn) {
      const winnings = t.wager * 3;
      P.gold += winnings;
      msg += ` Your wager pays: +${winnings} gold.`;
    } else {
      msg += ` Your wager of ${t.wager} gold is lost to the bookmakers' smiles.`;
    }
  }

  log(state, msg, 'glory');
  archiveTail(state);
  state.tourney = null;
  return msg;
}

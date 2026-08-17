// Drama systems: nemeses, succession crises, the Great Council,
// plagues & wildfire, the Faith, granaries.
import { livingMembers, age, shortName, fullName, regionName, findHeir } from './world.js';
import { log, kill, startWar } from './engine.js';

function relMod(state, aId, bId, delta) {
  const a = state.houses[aId], b = state.houses[bId];
  if (!a || !b) return;
  a.relations[bId] = Math.max(-100, Math.min(100, (a.relations[bId] || 0) + delta));
  b.relations[aId] = Math.max(-100, Math.min(100, (b.relations[aId] || 0) + delta));
}

// ---------- NEMESIS ----------
// A house whose relations with the player fall below -60 declares itself a nemesis.
export function tickNemesis(state, rng) {
  const P = state.houses[state.playerHouseId];
  if (!P || !P.alive) return;
  if (state.nemesisId && state.houses[state.nemesisId] && !state.houses[state.nemesisId].alive) {
    log(state, `House ${state.houses[state.nemesisId].name}, your sworn nemesis, is EXTINCT — and House ${P.name} still stands. Vengeance, it turns out, is mostly patience.`, 'crown');
    state.nemesisDefeated = true;
    state.nemesisId = null;
  }
  if (!state.nemesisId || !state.houses[state.nemesisId] || !state.houses[state.nemesisId].alive) {
    state.nemesisId = null;
    const worst = Object.entries(P.relations)
      .filter(([id, v]) => v <= -60 && state.houses[id] && state.houses[id].alive)
      .sort((a, b) => a[1] - b[1])[0];
    if (worst && rng.chance(0.35)) {
      state.nemesisId = worst[0];
      const N = state.houses[state.nemesisId];
      const nlord = state.characters[N.lordId];
      log(state, `A NEMESIS DECLARES ITSELF: ${nlord ? fullName(state, nlord) : 'House ' + N.name} has made the ruin of House ${P.name} a life's work. Expect no small cruelties — only large ones.`, 'war');
    }
    return;
  }
  const N = state.houses[state.nemesisId];
  // reconciliation path: relations climbing above -25 ends the feud
  if ((P.relations[N.id] || 0) > -25) {
    log(state, `The long enmity of House ${N.name} cools at last. Their lord toasts your health at a feast, and appears to mean most of it. The nemesis is no more.`, 'event');
    state.nemesisId = null;
    return;
  }
  if (!rng.chance(0.22)) return;
  const schemes = [
    () => {
      const amt = Math.min(P.gold, rng.int(25, 60));
      P.gold -= amt;
      return `Agents of House ${N.name} bribe your toll-keepers; ${amt} gold vanishes down their pockets.`;
    },
    () => {
      P.prestige = Math.max(0, P.prestige - rng.int(4, 8));
      return `A vicious ballad about House ${P.name} sweeps the taverns. The rhymes are cheap; the author's patron, everyone knows, is House ${N.name}. (-prestige)`;
    },
    () => {
      const allies = Object.entries(P.relations).filter(([id, v]) => v > 20 && state.houses[id] && state.houses[id].alive);
      if (!allies.length) return null;
      const [aid] = rng.pick(allies);
      relMod(state, P.id, aid, -rng.int(10, 18));
      return `House ${N.name} whispers poison into the ear of House ${state.houses[aid].name}; your friendship cools by careful degrees.`;
    },
    () => {
      if (state.war) return null;
      if (!rng.chance(0.3)) return null;
      startWar(state, rng, N.id, P.id, 'the nemesis strikes at last');
      return null; // startWar logs itself
    },
  ];
  for (let i = 0; i < 4; i++) {
    const msg = rng.pick(schemes)();
    if (msg !== null) { if (msg) log(state, msg, 'warn'); break; }
  }
}

// ---------- SUCCESSION CRISIS (player house) ----------
// Called from kill() flow: when a young/female/designated heir takes the seat
// while an ambitious adult male kinsman is passed over, he may rebel.
export function checkSuccessionCrisis(state, rng, house, newLord) {
  if (house.id !== state.playerHouseId) return;
  const passed = livingMembers(state, house).filter((c) =>
    c.id !== newLord.id && c.gender === 'm' && age(state, c) >= 18 && age(state, c) <= 60 &&
    c.birthHouseId === house.id &&
    (c.traits.includes('Ambitious') || c.traits.includes('Scheming') || c.traits.includes('Resentful')) &&
    (newLord.gender === 'f' || age(state, newLord) < 16 || house.designatedHeirId === newLord.id));
  if (!passed.length || !rng.chance(0.5)) return;
  const rival = passed.sort((a, b) => b.skills.war - a.skills.war)[0];
  state.pendingDecisions.push({
    id: 'succession_crisis',
    title: 'The Claim of ' + rival.name,
    text: `${rival.name} stands in the hall in half-armor with a dozen sworn swords at his back. "${newLord.gender === 'f' ? 'A girl' : age(state, newLord) < 16 ? 'A child' : 'A named favorite'} on the seat of ${house.seat}, while I stood by it for years? The bannermen will follow ME." The household holds its breath.`,
    options: [
      { label: 'Buy his loyalty (100 gold + a council seat)', effect: (st, r) => {
          const h = st.houses[st.playerHouseId];
          if (h.gold < 100) return 'You cannot pay. He sees it in your face — and walks out with his swords. Word is he rides to your enemies.';
          h.gold -= 100;
          const c = st.characters[rival.id];
          if (c) { h.council.marshal = c.id; c.mood = 2; const idx = c.traits.indexOf('Resentful'); if (idx >= 0) c.traits.splice(idx, 1); }
          return `${rival.name} weighs the purse and the office of Marshal, and kneels. "The house first," he says, and may even mean it.`;
        } },
      { label: 'Cast him out', effect: (st, r) => {
          const h = st.houses[st.playerHouseId];
          const c = st.characters[rival.id];
          const idx = h.memberIds.indexOf(c.id);
          if (idx >= 0) h.memberIds.splice(idx, 1);
          c.houseId = null;
          if (r.chance(0.4)) {
            h.troops = Math.max(200, Math.floor(h.troops * 0.8));
            return `${rival.name} rides out — and a fifth of your levies ride with him. They say a sellsword company has a new captain. You will hear that name again.`;
          }
          return `${rival.name} is escorted to the gate with his dozen swords and nothing else. The hall exhales.`;
        } },
      { label: 'Let the swords decide', effect: (st, r) => {
          const h = st.houses[st.playerHouseId];
          const c = st.characters[rival.id];
          const lord = st.characters[h.lordId];
          const loyal = 0.5 + (lord ? lord.skills.war * 0.015 : 0) + (h.prestige > 50 ? 0.1 : 0);
          h.troops = Math.max(200, Math.floor(h.troops * r.range(0.75, 0.9)));
          if (r.chance(loyal)) {
            kill(st, r, c, `was cut down in the hall of ${h.seat}, claiming the seat by steel`);
            return `Steel rings in your own hall. When it stops, ${rival.name} is dead on the stones his grandfather laid — and every man present will remember which side he chose. The KINSLAYER whispers begin.`;
          }
          kill(st, r, lord, `was slain by ${rival.name}'s faction in the rising at ${h.seat}`);
          return `The hall erupts — and the wrong side wins it. The seat passes over blood-wet stones.`;
        } },
    ],
  });
}

// ---------- GREAT COUNCIL ----------
// When the crown dies out entirely, the great houses elect a new dynasty.
export function greatCouncil(state, rng) {
  const P = state.houses[state.playerHouseId];
  const electors = Object.values(state.houses).filter((h) => h.alive && (h.tier === 'great' || h.tier === 'royal') && h.id !== state.crownHouseId);
  const candidates = Object.values(state.houses).filter((h) => h.alive && h.tier === 'great')
    .sort((a, b) => b.prestige - a.prestige).slice(0, 4);
  if (!candidates.length) return;
  const playerEligible = candidates.some((c) => c.id === P.id) || (P.alive && P.tier === 'great');
  if (P.alive && P.tier === 'great' && !candidates.some((c) => c.id === P.id)) candidates.push(P);

  const votes = {};
  for (const e of electors) {
    let best = null, bestScore = -1e9;
    for (const c of candidates) {
      if (c.id === e.id) { if (bestScore < 1e8) { best = c; bestScore = 1e8; } continue; }
      const score = (e.relations[c.id] || 0) + c.prestige * 0.5 + rng.int(-10, 10);
      if (score > bestScore) { best = c; bestScore = score; }
    }
    if (best) votes[best.id] = (votes[best.id] || 0) + 1;
  }
  // player prestige & crown-favor sway
  if (playerEligible) votes[P.id] = (votes[P.id] || 0) + (P.prestige > 80 ? 1 : 0);

  if (P.alive && (P.tier === 'great' || P.tier === 'royal')) state.councilVoted = true;
  const winnerId = Object.entries(votes).sort((a, b) => b[1] - a[1])[0][0];
  const W = state.houses[winnerId];
  const old = state.houses[state.crownHouseId];
  if (old) old.tier = old.alive ? 'great' : old.tier;
  W.tier = 'royal';
  state.crownHouseId = W.id;
  W.prestige += 30;
  const wlord = state.characters[W.lordId];
  const tally = Object.entries(votes).map(([id, v]) => `House ${state.houses[id].name}: ${v}`).join(', ');
  log(state, `THE GREAT COUNCIL: with the throne empty, the great houses gather beneath one roof for the first time in a generation. The tally — ${tally}. ${wlord ? fullName(state, wlord) : 'House ' + W.name} is chosen, and crowned before the leaves turn.`, 'crown');
  if (W.id === P.id) { state.wonCrown = true; log(state, 'The realm chose YOU. No war, no dragonfire — just years of banked favors falling due at once. The maesters note it as the cleanest coronation on record.', 'crown'); }
}

// ---------- CATASTROPHES: plague & wildfire ----------
export function tickCatastrophes(state, rng) {
  // plague: rare, realm-shaking
  if (!state.plague && rng.chance(0.006)) {
    state.plague = { yearsLeft: rng.int(1, 2), name: rng.pick(['the Pale Sweat', 'the Grey Cough', 'the Shivers', 'the Red Bloom']) };
    state.sawPlague = true;
    log(state, `PLAGUE. ${state.plague.name} appears in the port towns and begins to walk inland. Septs fill. Roads empty. The maesters burn sweet herbs and admit nothing.`, 'extinct');
  }
  if (state.plague) {
    for (const h of Object.values(state.houses)) {
      if (!h.alive) continue;
      h.troops = Math.max(100, Math.floor(h.troops * 0.96));
      h.income = Math.max(8, Math.floor(h.income * 0.98));
      for (const c of livingMembers(state, h)) {
        if (rng.chance(0.012)) kill(state, rng, c, `was taken by ${state.plague.name}`);
      }
    }
    if (state.season === 3) {
      state.plague.yearsLeft -= 1;
      if (state.plague.yearsLeft <= 0) {
        log(state, `${state.plague.name} burns itself out at last. The realm counts its dead and plants twice as much in spring.`, 'season');
        state.plague = null;
      }
    }
  }
  // wildfire cache: a city-block-levelling event at a random seat
  if (rng.chance(0.004)) {
    const h = rng.pick(Object.values(state.houses).filter((x) => x.alive));
    const dmg = rng.int(60, 140);
    h.gold = Math.max(0, h.gold - dmg);
    h.troops = Math.max(100, h.troops - rng.int(100, 300));
    log(state, `GREEN FIRE at ${h.seat}: an alchemist's forgotten cache beneath the old sept goes up in a pillar of jade flame seen three regions away. House ${h.name} digs its dead from glassed rubble.`, 'extinct');
    if (h.id === state.playerHouseId) {
      for (const c of livingMembers(state, h)) if (rng.chance(0.06)) kill(state, rng, c, 'died in the green fire beneath the sept');
    }
  }
}

// ---------- THE FAITH ----------
export function tickFaith(state, rng) {
  if (state.piety === undefined) state.piety = 10;
  const P = state.houses[state.playerHouseId];
  if (!P || !P.alive) return;
  // High piety: occasional blessings; low piety: septon trouble
  if (state.piety >= 25 && rng.chance(0.04)) {
    P.prestige += 3;
    log(state, `The High Septon names House ${P.name} among the Faithful in his seventh-day sermon. Pilgrims leave coins at your sept. (+3 prestige)`, 'event');
  }
  if (state.piety <= -15 && rng.chance(0.08)) {
    P.prestige = Math.max(0, P.prestige - 4);
    log(state, `A begging brother preaches against House ${P.name} at your own gates, and the smallfolk listen with their arms crossed. (-4 prestige)`, 'warn');
  }
}

// ---------- GRANARIES ----------
export function granaryLevel(state) { return state.granary || 0; }

export function applyWinterGranary(state) {
  // Called at winter onset: stored grain blunts winter income loss & death
  const g = state.granary || 0;
  if (g > 0) {
    state.granary = g - 1;
    return true;
  }
  return false;
}

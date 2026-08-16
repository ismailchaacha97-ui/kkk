// The Maester's Forbidden Shelf — cheats.
// Unlocked in the UI by typing "valar" anywhere, or via the hidden button.
import { makeRng } from './rng.js';
import { livingMembers, shortName } from './world.js';
import { makeDragon } from './dragons.js';
import { log } from './engine.js';

function rngFor(state) {
  const rng = makeRng(state.rngSeed);
  state.rngSeed = Math.floor(rng.random() * 2 ** 31) + 1;
  return rng;
}

export const CHEATS = [
  {
    id: 'gold', label: 'Rains of Gold', icon: '🜚',
    desc: '+1000 gold. The mines of your enemies weep.',
    run(state) {
      state.houses[state.playerHouseId].gold += 1000;
      return 'A caravan arrives unmarked and unexplained. Your steward has learned not to ask. (+1000 gold)';
    },
  },
  {
    id: 'army', label: 'The Golden Company', icon: '⚔',
    desc: '+5000 troops appear beneath your banners.',
    run(state) {
      state.houses[state.playerHouseId].troops += 5000;
      return 'Five thousand spears march out of the morning mist and kneel. Below the drum, no one questions it. (+5000 troops)';
    },
  },
  {
    id: 'prestige', label: 'Songs of Glory', icon: '★',
    desc: '+40 prestige. Every singer in the realm suddenly knows your name.',
    run(state) {
      state.houses[state.playerHouseId].prestige += 40;
      return 'Overnight, seventeen ballads about your house appear in every tavern from coast to coast. All flattering. Suspiciously flattering. (+40 prestige)';
    },
  },
  {
    id: 'dragon', label: 'Waken the Stone', icon: '🜂',
    desc: 'A full-grown dragon appears in your keep, bonded to your lord.',
    run(state) {
      const rng = rngFor(state);
      const h = state.houses[state.playerHouseId];
      const lord = state.characters[h.lordId];
      const d = makeDragon(state, rng, { houseId: h.id, birthYear: state.year - rng.int(20, 40) });
      if (lord && lord.alive) {
        if (!lord.traits.includes('Dragonblood')) lord.traits.push('Dragonblood');
        d.riderId = lord.id; lord.dragonId = d.id;
      }
      return `The sky darkens over ${h.seat}, and ${d.name} — ${d.colorDesc} — lands on your tower as if it has always lived there. ${lord ? lord.name + ' hears it speak a name inside the blood.' : ''} The realm is about to become very polite to you.`;
    },
  },
  {
    id: 'eggs', label: 'The Crypt Warms', icon: '◉',
    desc: '+3 dragon eggs, all of them real.',
    run(state) {
      state.dragonEggs += 3;
      return 'Three scaled stones appear in the crypt, warm as fresh bread. The dragonkeepers develop religion. (+3 eggs)';
    },
  },
  {
    id: 'heal', label: 'The Stranger Sleeps', icon: '✚',
    desc: 'Heal all wounds and lift all sorrows in your house.',
    run(state) {
      const h = state.houses[state.playerHouseId];
      let n = 0;
      for (const c of livingMembers(state, h)) {
        if (c.wounded) { c.wounded = false; n++; }
        c.mood = Math.max(c.mood, 1);
      }
      return n ? `Old wounds close overnight; ${n} of your kin wake whole. The maester checks his own pulse, twice.` : 'Your household was already whole. The blessing settles in for later.';
    },
  },
  {
    id: 'blood', label: 'The Old Blood Wakes', icon: '🩸',
    desc: 'Every living member of your house gains Dragonblood.',
    run(state) {
      const h = state.houses[state.playerHouseId];
      let n = 0;
      for (const c of livingMembers(state, h)) {
        if (!c.traits.includes('Dragonblood')) { c.traits.push('Dragonblood'); n++; }
      }
      return `Something ancient stirs in the veins of your line. ${n} of your kin dream of wings tonight. (Dragonblood for all)`;
    },
  },
  {
    id: 'love', label: 'Universal Adoration', icon: '❦',
    desc: 'Every house in the realm warms to you (+50 relations).',
    run(state) {
      const h = state.houses[state.playerHouseId];
      for (const o of Object.values(state.houses)) {
        if (o.id === h.id) continue;
        h.relations[o.id] = Math.min(100, (h.relations[o.id] || 0) + 50);
        o.relations[h.id] = Math.min(100, (o.relations[h.id] || 0) + 50);
      }
      return 'A strange warmth spreads through the halls of the realm. Rivals write friendly letters and are alarmed by themselves. (+50 relations with all)';
    },
  },
  {
    id: 'crown', label: 'The Throne, Simply', icon: '♛',
    desc: 'Skip the war. Take the crown. Coward\u2019s road, king\u2019s chair.',
    run(state) {
      const h = state.houses[state.playerHouseId];
      if (h.id === state.crownHouseId) return 'You already sit the throne. Greed is unbecoming. (Nothing happens.)';
      const old = state.houses[state.crownHouseId];
      old.tier = 'great';
      h.tier = 'royal';
      state.crownHouseId = h.id;
      h.prestige += 40;
      state.wonCrown = true;
      const lord = state.characters[h.lordId];
      log(state, `By means the chronicle declines to record, ${lord ? shortName(state, lord) : 'your house'} is crowned. House ${old.name} discovers the throne room redecorated. The maesters write "a peaceful transition" and press very hard with the quill.`, 'crown');
      return 'The throne is yours. The chronicle will be diplomatically vague about how.';
    },
  },
  {
    id: 'doom', label: 'Doom of the Rivals', icon: '☠',
    desc: 'A mysterious plague strikes every house that hates you (relations < -20).',
    run(state) {
      const rng = rngFor(state);
      const h = state.houses[state.playerHouseId];
      let hit = 0;
      for (const o of Object.values(state.houses)) {
        if (!o.alive || o.id === h.id) continue;
        if ((h.relations[o.id] || 0) < -20) {
          o.troops = Math.max(100, Math.floor(o.troops * 0.5));
          o.gold = Math.floor(o.gold * 0.5);
          hit++;
          if (rng.chance(0.4)) {
            const victims = livingMembers(state, o);
            if (victims.length) {
              const v = rng.pick(victims);
              // late import avoided: use engine kill through log-only fallback
              v.alive = false; v.deathYear = state.year; v.causeOfDeath = 'was taken by the Pale Sweat, which struck only certain houses, curiously';
              if (o.lordId === v.id) {
                const heir = livingMembers(state, o)[0];
                if (heir) o.lordId = heir.id; else { o.alive = false; o.extinctYear = state.year; }
              }
              log(state, `${v.name} of House ${o.name} ${v.causeOfDeath}.`, 'death');
            }
          }
        }
      }
      return hit ? `The Pale Sweat sweeps through ${hit} unfriendly hall${hit > 1 ? 's' : ''}, sparing — curiously — everyone who likes you. Septons are baffled.` : 'No house hates you enough to catch it. How dull.';
    },
  },
];

export function runCheat(state, id) {
  const c = CHEATS.find((x) => x.id === id);
  if (!c) return null;
  state.cheated = true;
  const msg = c.run(state);
  log(state, `[FORBIDDEN SHELF] ${msg}`, 'cheat');
  let yearEntry = state.annals.find((a) => a.year === state.year);
  if (!yearEntry) { yearEntry = { year: state.year, entries: [] }; state.annals.push(yearEntry); }
  yearEntry.entries.push({ season: ['Spring', 'Summer', 'Autumn', 'Winter'][state.season], kind: 'cheat', text: `[FORBIDDEN SHELF] ${msg}` });
  return msg;
}

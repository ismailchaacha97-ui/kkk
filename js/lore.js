// Lore: house foundings, ancestors, realm history, heirlooms.
import { makeRng } from './rng.js';
import { makeCharacter } from './world.js';
import { epithetFor } from './names.js';

const FOUNDING_DEEDS = [
  'won SEAT at swordpoint in a single bloody dawn, and held it against three sieges',
  'was a landed knight who lent the crown coin in a lean year and was repaid in stone and title',
  'carried a dying king off the field at the cost of an arm, and was raised for it',
  'built SEAT with the gold of a merchant fleet no one asked too many questions about',
  'was the last captain standing after the Reaving, and kept the land because no one dared take it',
  'married the widow who held SEAT and never let anyone forget whose name came first after that',
  'drove the hill clans from the valley in a winter campaign the singers still argue about',
  'was born a miller\u2019s child and died a lord, and the family has been proving it ever since',
  'took SEAT in a wager the old lord was too proud to refuse and too drunk to win',
  'slew a wyvern-brood in the crags and claimed the land it had emptied',
];

const ANCESTOR_DEATHS = [
  'fell holding the bridge in the Wars of the Broken Wheel',
  'died of the Pale Sweat when it last swept the realm',
  'was lost at sea escorting the grain fleets',
  'died in a duel over a slight no one now remembers',
  'fell defending SEAT against reavers',
  'died in the saddle, old and unbeaten, hunting at seventy',
  'was executed by the old dynasty for loyalty to the new one — a season too early',
  'died at a wedding, of poison the maesters politely called a bad oyster',
  'took the black after a scandal and died beyond the maps',
  'was crushed at a tourney by a horse named, the records insist, Buttercup',
  'starved with the smallfolk in the Great Winter, having given the granaries away',
];

const HEIRLOOM_NAMES = [
  ['blade', 'Winterfang', 'a longsword of rippled dawn-steel, older than the house that bears it'],
  ['blade', 'Oathkeeper\u2019s Edge', 'a bastard sword said to sweat in the presence of liars'],
  ['blade', 'the Widow\u2019s Point', 'a slender blade that has ended four rebellions and two marriages'],
  ['horn', 'the Horn of the First Watch', 'a bronze-bound warhorn; sounded thrice, the levies come running from memory alone'],
  ['crown', 'the Iron Circlet', 'a crude crown from before the realm was a realm, worn only at funerals'],
  ['ring', 'the Seal of the Drowned Lord', 'a signet pulled from a drowned ancestor\u2019s hand; letters under it are never refused',],
  ['cloak', 'the Weirwood Cloak', 'a cloak clasped with white wood; brides of the house have worn it for two centuries'],
  ['shield', 'the Doorstep', 'a tower shield with forty-one axe scars, each one named'],
  ['blade', 'Emberlight', 'a dagger of dragonglass and gold, warm to the touch on the eve of bad news'],
];

const REALM_EVENTS = [
  (r, s) => `the Old Dynasty of the ${r.pick(['Silver', 'Ashen', 'Hollow', 'First'])} Kings ended when its last king died ${r.pick(['heirless in a cold bed', 'screaming of dragons no one else could see', 'at a feast held in his honor', 'in a war he started for a river'])}`,
  (r, s) => `House ${s.houses[s.crownHouseId].name} took the throne ${r.pick(['by right of conquest, which is to say by dragon', 'through a marriage, a funeral, and excellent timing', 'when the great houses could agree on nothing except exhaustion'])}`,
  (r, s) => `the Great Winter froze the rivers for ${r.int(2, 4)} years; the realm still measures hardship against it`,
  (r, s) => `the Reaving burned half the coast; the sea-lords\u2019 skulls line a wall that tourists are not shown`,
  (r, s) => `a dragon plague thinned the old fires; of the wild dragons, only the hardiest lines survived`,
  (r, s) => s.feud ? `Houses ${s.houses[s.feud[0]].name} and ${s.houses[s.feud[1]].name} began their feud over ${r.pick(['a bride taken from a wedding', 'a border stone moved in the night', 'an insult at a coronation', 'a hunting accident that was neither'])}; it has outlived everyone who understood it` : null,
  (r, s) => `the Maesters\u2019 Conclave burned its own tower rather than surrender ${r.pick(['a book', 'a prophecy', 'a name'])}; what it was protecting is still argued`,
];

export function ensureLore(state) {
  if (state.loreGenerated) return;
  const rng = makeRng((state.seed ^ 0x10AE5) >>> 0);

  // --- Realm history: Elder Days ---
  if (!state.realmHistory) {
    state.realmHistory = [];
    const shuffled = rng.shuffle(REALM_EVENTS);
    let y = state.year - rng.int(180, 260);
    for (const ev of shuffled.slice(0, 5)) {
      const text = ev(rng, state);
      if (!text) continue;
      state.realmHistory.push({ year: y, text });
      y += rng.int(20, 60);
      if (y >= state.year - 10) break;
    }
    state.realmHistory.sort((a, b) => a.year - b.year);
  }

  // --- Per-house founding lore, heirlooms, ancestors ---
  for (const h of Object.values(state.houses)) {
    if (!h.lore) {
      const foundingYear = state.year - (h.tier === 'royal' ? rng.int(120, 280) : h.tier === 'great' ? rng.int(150, 300) : rng.int(60, 220));
      const founderGender = rng.chance(0.8) ? 'm' : 'f';
      h.lore = {
        foundingYear,
        founderName: state.namer.firstName(founderGender),
        founderGender,
        deed: rng.pick(FOUNDING_DEEDS).replace(/SEAT/g, h.seat),
      };
    }
    if (h.heirloom === undefined) {
      h.heirloom = (h.tier === 'royal' || rng.chance(0.4)) ? (() => {
        const [kind, name, desc] = rng.pick(HEIRLOOM_NAMES);
        return { kind, name, desc };
      })() : null;
    }
    // Ancestors: the founder + a few dead lords of the line
    if (!h.ancestorsGenerated) {
      h.ancestorsGenerated = true;
      const span = state.year - h.lore.foundingYear;
      const nGen = Math.min(4, Math.max(2, Math.floor(span / 45)));
      for (let i = 0; i < nGen; i++) {
        const frac = i / nGen;
        const birthYear = Math.round(h.lore.foundingYear + frac * (span - 60)) - rng.int(0, 15);
        const isFounder = i === 0;
        const ch = makeCharacter(state, rng, {
          houseId: h.id, birthHouseId: h.id,
          gender: isFounder ? h.lore.founderGender : (rng.chance(0.75) ? 'm' : 'f'),
          birthYear,
        });
        if (isFounder) ch.name = h.lore.founderName;
        ch.alive = false;
        ch.deathYear = birthYear + rng.int(35, 78);
        if (ch.deathYear >= state.year - 5) ch.deathYear = state.year - rng.int(5, 25);
        ch.causeOfDeath = isFounder
          ? `founded the house: ${h.lore.deed}. Died ${rng.pick(['in bed, disbelieving it', 'as lords should and rarely do — old', 'with the work unfinished', 'of wounds long deferred'])}`
          : (ch.gender === 'f' && rng.chance(0.2))
            ? 'died in childbed giving the house its heir'
            : rng.pick(ANCESTOR_DEATHS).replace(/SEAT/g, h.seat);
        ch.glory = rng.int(0, 3);
        if (isFounder || rng.chance(0.4)) {
          const ep = epithetFor(rng, ch);
          if (ep) ch.epithet = ep;
          else if (isFounder) ch.epithet = rng.pick(['the Founder', 'the First', 'Firstlord']);
        }
      }
    }
  }
  state.loreGenerated = true;
}

export function houseAncestors(state, houseId) {
  const h = state.houses[houseId];
  if (!h || !h.lore) return [];
  return Object.values(state.characters)
    .filter((c) => !c.alive && c.houseId === houseId && c.deathYear && c.deathYear < (state.startYear || state.year))
    .sort((a, b) => a.deathYear - b.deathYear);
}

export function foundingBlurb(state, h) {
  if (!h.lore) return '';
  const l = h.lore;
  return `Founded in Year ${l.foundingYear} by ${l.founderName}, who ${l.deed}.`;
}

// Name generation: people, houses, seats, regions, realm, mottos.

const M_FIRST = [
  'Aldric','Baelor','Corwin','Daven','Edric','Falken','Gareth','Harwin','Ivar','Joren',
  'Kaelan','Lucan','Maro','Norvin','Osric','Perren','Quill','Roderic','Steffon','Torrin',
  'Ulric','Varyn','Willem','Yorick','Alesander','Brandel','Cedric','Dorian','Emmon','Florian',
  'Garlan','Hosten','Ilyn','Jasper','Kevan','Lyonel','Merek','Nestor','Ormund','Preston',
  'Raynald','Symon','Tybald','Uthor','Vickon','Walder','Alyn','Benfred','Clement','Damon',
  'Erren','Gawen','Hallis','Jonos','Leobald','Malcon','Olyvar','Rickard','Selwyn','Tristan',
];
const F_FIRST = [
  'Alys','Bethan','Carys','Delia','Elinor','Fiona','Gwyn','Helya','Isolde','Jeyne',
  'Kella','Lira','Maris','Nyra','Ondine','Perra','Rhea','Sabel','Talia','Una',
  'Vessa','Wynne','Ysolde','Alerie','Branwen','Cassana','Dorna','Elenya','Falyse','Genna',
  'Helaena','Ilena','Jonquil','Kyra','Leona','Meredyth','Nella','Olenna','Perriane','Rhialta',
  'Serra','Tanda','Ursa','Valena','Willow','Ashara','Bellena','Corenna','Dacey','Elissa',
  'Gilly','Lyarra','Mira','Rowena','Sybell','Tyene','Verena','Wylla','Yrene','Zhoe',
];

const HOUSE_A = [
  'Black','Grey','White','Storm','Frost','Iron','Stone','Raven','Wolf','Hart',
  'Ash','Thorn','Oak','Ryver','Marsh','Fell','Snow','Wind','Salt','Ember',
  'Gold','Dusk','Dawn','Moor','Crag','Hollow','Vale','Mist','Reed','Pike',
];
const HOUSE_B = [
  'wood','more','mont','well','ford','gate','crest','march','shore',
  'brook','field','helm','mere','burn','cliff','holt','ward','bourne','stead',
  'fall','ridge','hale','worth','ley','combe','strand','garde','tor','fen',
];
const HOUSE_WHOLE = [
  'Vaelric','Corvane','Draymoor','Ostwyck','Ferren','Mallor','Quinlan','Serrat','Tarwick','Umbray',
  'Veymar','Wrenfield','Ambrose','Byrne','Calloway','Danvers','Elsworth','Farrow','Garrick','Halloran',
  'Ingram','Jexley','Kirwan','Lockewood','Morrow','Norcross','Ockley','Penhallow','Quade','Ravenser',
  'Sallow','Tremaine','Underhill','Varric','Wystan','Yarrow','Aldermane','Vireth','Caswyn',
];

const SEAT_A = ['Storm', 'Raven', 'High', 'Old', 'Winter', 'Salt', 'Grim', 'Gold', 'Deep', 'Iron', 'Star', 'Moon', 'Wolf', 'King\u2019s', 'Crow\u2019s', 'Dragon', 'Sea', 'Red', 'Black', 'Silver'];
const SEAT_B = ['hold', 'rest', 'keep', 'watch', 'gard', 'spire', 'fort', 'den', 'gate', 'haven', 'roost', 'reach', 'mont', 'fall', 'cairn', 'tower', 'harrow', 'moot', 'perch', 'bastion'];

const REGION_NAMES = [
  ['The Frostlands', 'frost'], ['The Rivermarches', 'river'], ['The Stormcoast', 'coast'],
  ['The Golden Reach', 'plain'], ['The Iron Hills', 'mountain'], ['The Thornwood', 'forest'],
  ['The Sunward Marches', 'south'], ['The Greywater Fens', 'fen'], ['The Shield Vales', 'vale'],
];

const REALM_A = ['Aster', 'Vael', 'Cor', 'Thal', 'Mor', 'Eld', 'Bran', 'Cael', 'Dor', 'Ostr'];
const REALM_B = ['ia', 'oria', 'wyn', 'mere', 'gard', 'eth', 'una', 'oth', 'avia', 'enn'];

const DRAGON_NAMES = [
  'Balerax', 'Vhagrix', 'Syraxis', 'Morghul', 'Aethrax', 'Cinderfell', 'Umbrax', 'Nyxwing',
  'Pyraxes', 'Sorrowfyre', 'Gryvane', 'Tempesth', 'Veldrith', 'Ashvein', 'Duskrender', 'Embermaw',
  'Karrax', 'Smokewing', 'Thornfyre', 'Valdrax', 'Wintermaw', 'Hexwing', 'Ironfyre', 'Stormcaller',
  'Ravenna', 'Goldwrath', 'Seylix', 'Mordrake', 'Cryptfyre', 'Halyx', 'Obsidyan', 'Bruma',
];

const MOTTO_TEMPLATES = [
  'NOUN and NOUN2', 'We Do Not VERB', 'NOUN Endures', 'From NOUN, VERB2', 'Ours Is the NOUN',
  'NOUN Before NOUN2', 'The NOUN Remembers', 'VERB2 and Prevail', 'No NOUN Without NOUN2',
  'First in NOUN', 'Sworn to the NOUN', 'By NOUN We Rise', 'NOUN Is Our Shield',
];
const MOTTO_NOUNS = ['Fire', 'Blood', 'Winter', 'Honor', 'Iron', 'Storm', 'Duty', 'Night', 'Stone', 'The Sea', 'The Wolf', 'Vengeance', 'Truth', 'The Old Ways', 'Steel', 'The Dawn', 'Silence', 'Faith', 'The Harvest', 'The Deep'];
const MOTTO_VERBS = ['Kneel', 'Yield', 'Forget', 'Sow', 'Break', 'Bend', 'Falter', 'Sleep'];
const MOTTO_VERBS2 = ['Rise', 'Strike', 'Endure', 'Stand', 'Reap', 'Guard', 'Burn'];

export function makeNamer(rng) {
  const usedHouse = new Set();
  const usedSeat = new Set();
  const usedDragon = new Set();

  function firstName(gender) {
    return rng.pick(gender === 'f' ? F_FIRST : M_FIRST);
  }

  function houseName() {
    for (let i = 0; i < 200; i++) {
      let n;
      if (rng.chance(0.55)) {
        n = rng.pick(HOUSE_A) + rng.pick(HOUSE_B);
      } else {
        n = rng.pick(HOUSE_WHOLE);
      }
      if (!usedHouse.has(n)) { usedHouse.add(n); return n; }
    }
    return 'Nameless' + rng.int(1, 999);
  }

  function seatName() {
    for (let i = 0; i < 200; i++) {
      const n = rng.pick(SEAT_A) + rng.pick(SEAT_B);
      if (!usedSeat.has(n)) { usedSeat.add(n); return n; }
    }
    return 'Lostkeep';
  }

  function motto() {
    let t = rng.pick(MOTTO_TEMPLATES);
    const n1 = rng.pick(MOTTO_NOUNS);
    let n2 = rng.pick(MOTTO_NOUNS);
    while (n2 === n1) n2 = rng.pick(MOTTO_NOUNS);
    return t.replace('NOUN2', n2).replace('NOUN', n1)
      .replace('VERB2', rng.pick(MOTTO_VERBS2)).replace('VERB', rng.pick(MOTTO_VERBS));
  }

  function realmName() {
    return rng.pick(REALM_A) + rng.pick(REALM_B);
  }

  function dragonName() {
    for (let i = 0; i < 100; i++) {
      const n = rng.pick(DRAGON_NAMES);
      if (!usedDragon.has(n)) { usedDragon.add(n); return n; }
    }
    return 'Nameless Terror';
  }

  function regions(count) {
    return rng.shuffle(REGION_NAMES).slice(0, count);
  }

  return { firstName, houseName, seatName, motto, realmName, regions, dragonName };
}

export const TRAITS = [
  ['Brave', 'Craven'], ['Honorable', 'Scheming'], ['Kind', 'Cruel'],
  ['Ambitious', 'Content'], ['Shrewd', 'Dull'], ['Temperate', 'Drunkard'],
  ['Pious', 'Godless'], ['Charming', 'Grim'],
];

export function epithetFor(rng, ch) {
  const pool = [];
  if (ch.skills.war >= 14) pool.push('the Bold', 'the Hammer', 'Ironhand', 'the Warbound');
  if (ch.skills.intr >= 14) pool.push('the Whisperer', 'the Spider-touched', 'the Quiet');
  if (ch.skills.dip >= 14) pool.push('the Silver-Tongued', 'the Gracious');
  if (ch.skills.stew >= 14) pool.push('the Provider', 'Goldhand');
  if (ch.traits.includes('Cruel')) pool.push('the Grim', 'the Flayer');
  if (ch.traits.includes('Kind')) pool.push('the Gentle', 'the Good');
  if (ch.traits.includes('Drunkard')) pool.push('the Sodden');
  if (ch.traits.includes('Brave')) pool.push('the Lionheart');
  if (pool.length === 0) return null;
  return rng.pick(pool);
}

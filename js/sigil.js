// Procedural heraldry: generates a sigil descriptor and renders it as SVG.

const TINCTURES = [
  ['#7a1f1f', 'crimson'], ['#1f3a5f', 'azure'], ['#1e4d2b', 'viridian'],
  ['#8a6d1a', 'gold'], ['#3d2b56', 'violet'], ['#54442b', 'umber'],
  ['#232323', 'sable'], ['#5b6770', 'steel'], ['#7a4a1f', 'russet'],
  ['#274646', 'teal'], ['#6e2440', 'wine'], ['#42371f', 'bronze'],
];
const LIGHTS = [
  ['#e8dcc0', 'cream'], ['#d9c894', 'pale gold'], ['#cfd6d3', 'silver'],
  ['#d8b98a', 'sand'], ['#c9a86a', 'ochre'],
];

export const CHARGES = [
  'wolf', 'stag', 'raven', 'sun', 'moon', 'star', 'tower', 'sword', 'fish',
  'tree', 'rose', 'anchor', 'mountain', 'lightning', 'crown', 'serpent', 'axe', 'ship',
];

const DIVISIONS = ['plain', 'perPale', 'perFess', 'perBend', 'chevron', 'perCross'];

export function makeSigil(rng) {
  const dark = rng.pick(TINCTURES);
  let dark2 = rng.pick(TINCTURES);
  while (dark2[0] === dark[0]) dark2 = rng.pick(TINCTURES);
  const light = rng.pick(LIGHTS);
  return {
    division: rng.pick(DIVISIONS),
    c1: dark[0], c1n: dark[1],
    c2: rng.chance(0.5) ? light[0] : dark2[0],
    c2n: rng.chance(0.5) ? light[1] : dark2[1],
    charge: rng.pick(CHARGES),
    chargeColor: light[0],
  };
}

export function sigilBlazon(s) {
  const chargeNames = {
    wolf: 'a direwolf', stag: 'a stag', raven: 'a raven', sun: 'a blazing sun',
    moon: 'a crescent moon', star: 'a seven-pointed star', tower: 'a stone tower',
    sword: 'a longsword', fish: 'a silver fish', tree: 'an ancient tree',
    rose: 'a rose', anchor: 'an anchor', mountain: 'a mountain', lightning: 'a thunderbolt',
    crown: 'a fallen crown', serpent: 'a coiled serpent', axe: 'a war-axe', ship: 'a longship',
  };
  return `${chargeNames[s.charge] || s.charge}, upon a field of ${s.c1n} and ${s.c2n}`;
}

// --- charge glyphs (drawn in a 100x100 box, centered ~50,52) ---
function glyph(charge, color) {
  const c = color;
  switch (charge) {
    case 'star':
      return `<path fill="${c}" d="M50 18 L57 40 L80 40 L62 54 L69 78 L50 63 L31 78 L38 54 L20 40 L43 40 Z"/>`;
    case 'moon':
      return `<path fill="${c}" d="M62 20 A32 32 0 1 0 62 84 A26 26 0 1 1 62 20 Z"/>`;
    case 'sun':
      return `<circle cx="50" cy="52" r="16" fill="${c}"/>` +
        Array.from({ length: 8 }, (_, i) => {
          const a = (i * Math.PI) / 4;
          const x1 = 50 + Math.cos(a) * 21, y1 = 52 + Math.sin(a) * 21;
          const x2 = 50 + Math.cos(a) * 32, y2 = 52 + Math.sin(a) * 32;
          return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="${c}" stroke-width="5" stroke-linecap="round"/>`;
        }).join('');
    case 'tower':
      return `<path fill="${c}" d="M36 80 L36 36 L32 36 L32 24 L40 24 L40 30 L46 30 L46 24 L54 24 L54 30 L60 30 L60 24 L68 24 L68 36 L64 36 L64 80 Z M46 80 L46 62 L54 62 L54 80 Z" fill-rule="evenodd"/>`;
    case 'sword':
      return `<path fill="${c}" d="M50 14 L56 26 L54 58 L46 58 L44 26 Z M38 60 L62 60 L62 66 L54 66 L54 84 L50 90 L46 84 L46 66 L38 66 Z"/>`;
    case 'fish':
      return `<path fill="${c}" d="M20 52 Q40 32 62 44 L78 30 L74 52 L78 74 L62 60 Q40 72 20 52 Z"/><circle cx="34" cy="49" r="3" fill="#00000055"/>`;
    case 'tree':
      return `<path fill="${c}" d="M50 18 Q72 26 70 46 Q84 52 72 64 L56 64 L56 80 L62 86 L38 86 L44 80 L44 64 L28 64 Q16 52 30 46 Q28 26 50 18 Z"/>`;
    case 'rose':
      return `<circle cx="50" cy="50" r="10" fill="${c}"/>` +
        Array.from({ length: 5 }, (_, i) => {
          const a = (i * 2 * Math.PI) / 5 - Math.PI / 2;
          const x = 50 + Math.cos(a) * 16, y = 50 + Math.sin(a) * 16;
          return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="11" fill="${c}" opacity="0.85"/>`;
        }).join('');
    case 'anchor':
      return `<path fill="none" stroke="${c}" stroke-width="7" stroke-linecap="round" d="M50 26 L50 76 M34 46 L66 46 M26 62 Q34 82 50 78 Q66 82 74 62"/><circle cx="50" cy="22" r="7" fill="none" stroke="${c}" stroke-width="6"/>`;
    case 'mountain':
      return `<path fill="${c}" d="M18 78 L42 34 L52 52 L62 30 L84 78 Z"/><path fill="#ffffff55" d="M42 34 L48 45 L42 48 L38 42 Z M62 30 L68 42 L61 44 L57 38 Z"/>`;
    case 'lightning':
      return `<path fill="${c}" d="M58 14 L34 54 L48 54 L40 88 L70 42 L54 42 Z"/>`;
    case 'crown':
      return `<path fill="${c}" d="M26 70 L24 38 L38 52 L50 28 L62 52 L76 38 L74 70 Z M26 76 L74 76 L74 84 L26 84 Z"/>`;
    case 'serpent':
      return `<path fill="none" stroke="${c}" stroke-width="9" stroke-linecap="round" d="M30 76 Q50 84 60 70 Q70 56 50 52 Q30 48 40 34 Q46 25 60 28"/><circle cx="63" cy="27" r="6" fill="${c}"/>`;
    case 'axe':
      return `<rect x="47" y="26" width="6" height="60" rx="2" fill="${c}"/><path fill="${c}" d="M53 26 Q78 30 76 52 Q64 44 53 46 Z M47 26 Q22 30 24 52 Q36 44 47 46 Z"/>`;
    case 'ship':
      return `<path fill="${c}" d="M22 62 L78 62 L66 80 L34 80 Z"/><rect x="48" y="22" width="4" height="40" fill="${c}"/><path fill="${c}" d="M52 24 L74 44 L52 44 Z"/>`;
    case 'raven':
      return `<path fill="${c}" d="M62 24 Q74 26 72 36 L64 38 Q70 52 58 62 L60 84 L54 84 L52 66 L44 68 L48 84 L42 84 L36 64 Q22 56 28 40 Q34 26 52 28 Q56 22 62 24 Z"/><circle cx="63" cy="30" r="2" fill="#00000066"/>`;
    case 'stag':
      return `<path fill="${c}" d="M40 84 L44 60 Q34 54 36 42 L30 40 Q24 30 28 20 Q34 30 40 30 L42 24 Q36 18 38 12 Q46 16 48 26 L52 26 Q54 16 62 12 Q64 18 58 24 L60 30 Q66 30 72 20 Q76 30 70 40 L64 42 Q66 54 56 60 L60 84 L54 84 L50 64 L46 84 Z"/>`;
    case 'wolf':
    default:
      return `<path fill="${c}" d="M32 22 L42 34 L58 34 L68 22 L70 40 Q78 50 72 62 L60 66 L62 86 L54 86 L52 70 L48 70 L46 86 L38 86 L40 66 L28 62 Q22 50 30 40 Z"/><circle cx="42" cy="46" r="3" fill="#00000066"/><circle cx="58" cy="46" r="3" fill="#00000066"/><path fill="#00000044" d="M46 56 L54 56 L50 62 Z"/>`;
  }
}

const SHIELD_PATH = 'M50 4 C68 10 84 10 94 6 L94 52 C94 76 76 90 50 100 C24 90 6 76 6 52 L6 6 C16 10 32 10 50 4 Z';

export function sigilSVG(s, size = 64) {
  const uid = 'sh' + Math.random().toString(36).slice(2, 8);
  let field = '';
  switch (s.division) {
    case 'perPale':
      field = `<rect x="0" y="0" width="50" height="104" fill="${s.c1}"/><rect x="50" y="0" width="54" height="104" fill="${s.c2}"/>`;
      break;
    case 'perFess':
      field = `<rect x="0" y="0" width="104" height="50" fill="${s.c1}"/><rect x="0" y="50" width="104" height="54" fill="${s.c2}"/>`;
      break;
    case 'perBend':
      field = `<rect x="0" y="0" width="104" height="104" fill="${s.c1}"/><path d="M0 0 L104 104 L0 104 Z" fill="${s.c2}"/>`;
      break;
    case 'chevron':
      field = `<rect x="0" y="0" width="104" height="104" fill="${s.c1}"/><path d="M0 104 L50 48 L104 104 Z" fill="${s.c2}"/>`;
      break;
    case 'perCross':
      field = `<rect x="0" y="0" width="104" height="104" fill="${s.c1}"/><rect x="0" y="0" width="50" height="50" fill="${s.c2}"/><rect x="50" y="50" width="54" height="54" fill="${s.c2}"/>`;
      break;
    default:
      field = `<rect x="0" y="0" width="104" height="104" fill="${s.c1}"/>`;
  }
  return `<svg viewBox="0 0 100 104" width="${size}" height="${size * 1.04}" xmlns="http://www.w3.org/2000/svg" class="sigil-svg">
  <defs><clipPath id="${uid}"><path d="${SHIELD_PATH}"/></clipPath></defs>
  <g clip-path="url(#${uid})">${field}
    <g opacity="0.93">${glyph(s.charge, s.chargeColor)}</g>
    <path d="${SHIELD_PATH}" fill="none" stroke="#00000033" stroke-width="6"/>
  </g>
  <path d="${SHIELD_PATH}" fill="none" stroke="#2b1d0e" stroke-width="2.5"/>
</svg>`;
}

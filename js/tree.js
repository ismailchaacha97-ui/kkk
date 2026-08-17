// Family tree: builds generation rows from the founder down and renders HTML.
import { age, fullName, lawfulHeir } from './world.js';

// Collect the bloodline of a house: roots are members (dead or alive) with no
// parents recorded inside the house lineage.
export function buildTree(state, houseId) {
  const h = state.houses[houseId];
  const all = Object.values(state.characters).filter((c) =>
    c.houseId === houseId || c.birthHouseId === houseId);
  const inSet = new Set(all.map((c) => c.id));
  const roots = all.filter((c) => {
    const f = c.fatherId && inSet.has(c.fatherId);
    const m = c.motherId && inSet.has(c.motherId);
    return !f && !m && c.birthHouseId === houseId;
  }).sort((a, b) => a.birthYear - b.birthYear);
  return { roots, inSet };
}

function nodeHTML(state, c, opts) {
  const h = state.houses[c.houseId] || state.houses[c.birthHouseId];
  const P = state.houses[state.playerHouseId];
  const isLord = h && h.lordId === c.id && c.alive;
  const heirNow = P && c.houseId === P.id && c.alive ? lawfulHeir(state, P) : null;
  const isHeir = heirNow && heirNow.id === c.id;
  const dragon = c.dragonId ? state.dragons[c.dragonId] : null;
  const blood = c.traits && c.traits.includes('Dragonblood');
  const cls = ['tree-node'];
  if (!c.alive) cls.push('dead');
  if (isLord) cls.push('lord');
  if (blood) cls.push('blooded');
  const years = c.alive ? `b. ${c.birthYear} (${age(state, c)})` : `${c.birthYear}–${c.deathYear}`;
  let badges = '';
  if (isLord) badges += '♛ ';
  if (isHeir) badges += '<span class="tree-heir">HEIR</span> ';
  if (dragon) badges += '🜂 ';
  if (blood) badges += '<span class="tree-blood" title="Dragonblood">🩸</span> ';
  return `<div class="${cls.join(' ')}" data-char="${c.id}">
    <div class="tree-name">${badges}${escapeHtml(c.name)}${c.epithet ? ` <em>${escapeHtml(c.epithet)}</em>` : ''}</div>
    <div class="tree-years">${years}${c.alive ? '' : ' ✝'}</div>
    ${opts && opts.spouse ? `<div class="tree-spouse">⚭ ${escapeHtml(opts.spouse)}</div>` : ''}
  </div>`;
}

// Recursive descent: each person renders with their children indented under them.
function renderBranch(state, c, inSet, depth, seen) {
  if (seen.has(c.id) || depth > 8) return '';
  seen.add(c.id);
  const sp = c.spouseId ? state.characters[c.spouseId] : null;
  const spouseName = sp ? sp.name + (sp.alive ? '' : ' ✝') : null;
  let out = `<div class="tree-branch">`;
  out += nodeHTML(state, c, { spouse: spouseName });
  const kids = (c.childrenIds || [])
    .map((i) => state.characters[i])
    .filter((k) => k)
    .sort((a, b) => a.birthYear - b.birthYear);
  if (kids.length) {
    out += `<div class="tree-children">`;
    for (const k of kids) out += renderBranch(state, k, inSet, depth + 1, seen);
    out += `</div>`;
  }
  out += `</div>`;
  return out;
}

export function renderTreeHTML(state, houseId) {
  const { roots, inSet } = buildTree(state, houseId);
  const seen = new Set();
  let out = '';
  for (const r of roots) {
    out += renderBranch(state, r, inSet, 0, seen);
  }
  // catch anyone disconnected (married-in with no recorded kids links etc.) — skip spouses already shown inline
  const h = state.houses[houseId];
  const strays = h.memberIds
    .map((i) => state.characters[i])
    .filter((c) => c && c.alive && !seen.has(c.id) && (!c.spouseId || !seen.has(c.spouseId)));
  if (strays.length) {
    out += `<div class="tree-strays"><div class="tree-strays-label">Of the household, lineage unrecorded:</div>`;
    for (const c of strays) { out += nodeHTML(state, c); seen.add(c.id); }
    out += `</div>`;
  }
  return out || '<p class="dim">The maesters find no records worth drawing.</p>';
}

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

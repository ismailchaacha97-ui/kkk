// The Chronicle: renders the dynasty's history as maester's prose.
import { SEASONS } from './engine.js';
import { age, fullName } from './world.js';

export function buildChronicle(state) {
  const P = state.houses[state.playerHouseId];
  const parts = [];

  parts.push(`<h2 class="chron-title">The Chronicle of House ${P.name}</h2>`);
  parts.push(`<p class="chron-sub">Being a true account, set down by the maesters of ${P.seat}, of the deeds and dooms of the ${P.alive ? 'living' : 'fallen'} House ${P.name} of ${regionOf(state, P)}, in the realm of ${state.realmName}, in the years of ${state.dynastyEra}.</p>`);
  parts.push(`<p class="chron-motto">&ldquo;${P.motto}&rdquo;</p>`);

  // Elder Days: realm history before the record
  if (state.realmHistory && state.realmHistory.length) {
    parts.push(`<h3 class="chron-year">The Elder Days</h3>`);
    parts.push('<p>' + state.realmHistory.map((e) => `<span class="chron-season">[Year ${e.year}]</span> In that year, ${escapeHtml(e.text)}.`).join(' ') + '</p>');
  }

  // The founding
  if (P.lore) {
    parts.push(`<h3 class="chron-year">The Founding</h3>`);
    parts.push(`<p>House ${P.name} was raised in Year ${P.lore.foundingYear} by ${escapeHtml(P.lore.founderName)}, who ${escapeHtml(P.lore.deed)}. ${P.heirloom ? `Of the founder's era the house keeps ${escapeHtml(P.heirloom.name)} — ${escapeHtml(P.heirloom.desc)}.` : 'Of the founder\u2019s era, little survives but the name and the stones.'}</p>`);
  }

  // Opening
  parts.push(`<p>In the year ${state.startYear}, when this record begins, House ${P.name} was counted ${state.startTier === 'minor' ? 'among the minor houses' : 'among the great houses'} of the realm, holding ${P.seat} and swearing its swords where honor demanded. What follows is what the years made of it.</p>`);

  // Year by year
  for (const yr of state.annals) {
    const lines = yr.entries.filter((e) => interesting(e));
    if (!lines.length) continue;
    parts.push(`<h3 class="chron-year">Year ${yr.year}</h3>`);
    // group into a paragraph
    const sentences = lines.map((e) => `<span class="chron-season">[${e.season}]</span> ${escapeHtml(e.text)}`);
    parts.push(`<p>${sentences.join(' ')}</p>`);
  }

  // The Fallen
  const fallen = Object.values(state.characters)
    .filter((c) => !c.alive && c.deathYear && c.deathYear >= state.startYear && wasOfHouse(state, c, P.id))
    .sort((a, b) => a.deathYear - b.deathYear);
  if (fallen.length) {
    parts.push(`<h3 class="chron-year">The Fallen of House ${P.name}</h3>`);
    parts.push('<ul class="chron-fallen">' + fallen.map((c) =>
      `<li><strong>${escapeHtml(fullName(state, c))}</strong> (${c.birthYear}–${c.deathYear}, aged ${c.deathYear - c.birthYear}) — ${escapeHtml(c.causeOfDeath || 'the cause unrecorded')}.</li>`
    ).join('') + '</ul>');
  }

  // The Dragons
  const dragons = Object.values(state.dragons || {});
  const houseTouched = dragons.filter((d) => d.houseId === P.id || (d.kills || []).some((k) => k.includes(P.name) || k.includes(P.seat)));
  const listed = houseTouched.length ? houseTouched : dragons;
  if (listed.length) {
    parts.push(`<h3 class="chron-year">Of the Dragons</h3>`);
    const lines = listed.map((d) => {
      let s = `<strong>${escapeHtml(d.name)}</strong>, ${escapeHtml(d.colorDesc)}`;
      s += d.alive
        ? ` — living still${d.wild ? ', wild and masterless' : d.houseId === P.id ? `, a dragon of House ${escapeHtml(P.name)}` : ''}.`
        : ` — dead in Year ${d.deathYear}; ${escapeHtml(d.causeOfDeath || 'the manner unrecorded')}.`;
      if ((d.kills || []).length) s += ` The record charges it with: ${escapeHtml(d.kills.join('; '))}.`;
      return `<li>${s}</li>`;
    });
    parts.push(`<ul class="chron-fallen">${lines.join('')}</ul>`);
  }

  // Closing
  if (state.gameOver) {
    parts.push(`<p class="chron-end">Here the record ends. In the year ${state.gameOver.year}, the line of ${P.name} was extinguished, and ${P.seat} passed into other hands. ${escapeHtml(state.gameOver.reason)} Let those who read this remember that the house existed, and that for a time it mattered.</p>`);
  } else if (state.wonCrown) {
    parts.push(`<p class="chron-end">And so House ${P.name} came to sit the throne of ${state.realmName} itself — a thing the founders of this record would not have dared write down as a hope. The chronicle continues, for dynasties do not end at a coronation. They only find larger enemies.</p>`);
  } else {
    const lord = state.characters[P.lordId];
    parts.push(`<p class="chron-end">The record continues. As of Year ${state.year}, ${lord ? escapeHtml(fullName(state, lord)) + `, aged ${age(state, lord)},` : 'the house'} holds ${P.seat} still. Whatever comes, it will be written down.</p>`);
  }

  return parts.join('\n');
}

function interesting(e) {
  return !['note'].includes(e.kind);
}

function wasOfHouse(state, c, houseId) {
  return c.houseId === houseId || c.birthHouseId === houseId;
}

function regionOf(state, h) {
  const r = state.regions.find((x) => x.id === h.regionId);
  return r ? r.name : 'the realm';
}

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function chroniclePlainText(state) {
  const html = buildChronicle(state);
  const tmp = document.createElement('div');
  tmp.innerHTML = html.replace(/<h[23][^>]*>/g, '\n\n== ').replace(/<\/h[23]>/g, ' ==\n').replace(/<li>/g, '\n • ').replace(/<\/p>/g, '\n');
  return tmp.textContent.replace(/\n{3,}/g, '\n\n').trim();
}

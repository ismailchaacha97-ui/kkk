// UI rendering and interaction.
import { generateWorld, livingMembers, age, fullName, shortName, regionName } from './world.js';
import { advanceSeason, runAction, resolveDecision, arrangeMarriage, ACTIONS, SEASONS } from './engine.js';
import { sigilSVG, sigilBlazon } from './sigil.js';
import { houseDragons, wildDragons, livingDragons, describeDragon, dragonStageName, dragonMark, hasDragonblood } from './dragons.js';
import { buildChronicle, chroniclePlainText } from './chronicle.js';
import { makeRng } from './rng.js';

let state = null;
let currentTab = 'court';

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, html) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html !== undefined) e.innerHTML = html;
  return e;
};
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// ---------- Setup flow ----------
export function boot() {
  showSetup();
}

function showSetup() {
  const seed = Math.floor(Math.random() * 1e9);
  regenSetup(seed);
}

function regenSetup(seed) {
  state = generateWorld(seed);
  const minors = Object.values(state.houses).filter((h) => h.tier === 'minor');
  const rng = makeRng(seed ^ 0x5f5f5f);
  const picks = rng.shuffle(minors).slice(0, 3);

  const app = $('#app');
  app.innerHTML = '';
  const wrap = el('div', 'setup-wrap');
  wrap.appendChild(el('h1', 'game-title', 'OATHS &amp; BANNERS'));
  wrap.appendChild(el('p', 'subtitle', `A dynasty simulation. The realm of <strong>${esc(state.realmName)}</strong> awaits in the years of ${esc(state.dynastyEra)}.`));
  const wilds = wildDragons(state);
  const crownH = state.houses[state.crownHouseId];
  wrap.appendChild(el('p', 'setup-lead', `Choose the minor house whose story you will write. Guide it across generations: marry well, feed the smallfolk, win tourneys, survive winters — and perhaps, one day, take the throne itself. Know this: House ${esc(crownH.name)} keeps a dragon at ${esc(crownH.seat)}, and ${wilds.length ? (wilds.length > 1 ? wilds.length + ' wild dragons haunt' : 'a wild dragon haunts') + ' the far country' : 'the wild dragons are gone from the maps'}. The old blood still runs in a few unlikely veins. Perhaps yours.`));

  const row = el('div', 'house-pick-row');
  for (const h of picks) {
    const lord = state.characters[h.lordId];
    const card = el('div', 'house-pick-card');
    card.innerHTML = `
      <div class="pick-sigil">${sigilSVG(h.sigil, 84)}</div>
      <div class="pick-name">House ${esc(h.name)}</div>
      <div class="pick-motto">&ldquo;${esc(h.motto)}&rdquo;</div>
      <div class="pick-detail">of ${esc(h.seat)}, ${esc(regionName(state, h.regionId))}</div>
      <div class="pick-detail">Sworn to House ${esc(state.houses[h.liegeId].name)}</div>
      <div class="pick-detail dim">${esc(sigilBlazon(h.sigil))}</div>
      <hr class="rule">
      <div class="pick-detail">${lord ? esc(shortName(state, lord)) + `, ${lord.gender === 'f' ? 'Lady' : 'Lord'} of ${esc(h.seat)}, aged ${age(state, lord)}` : ''}</div>
      <div class="pick-stats">⚔ ${h.troops} &nbsp; 🜚 ${h.gold} gold &nbsp; ★ ${Math.round(h.prestige)} prestige</div>
      <div class="pick-detail dim">${livingMembers(state, h).length} of the blood and household</div>
    `;
    const btn = el('button', 'btn btn-primary', 'Take up these banners');
    btn.onclick = () => startGame(h.id);
    card.appendChild(btn);
    row.appendChild(card);
  }
  wrap.appendChild(row);

  const reroll = el('button', 'btn btn-ghost', '☈ Consult other ravens (new realm)');
  reroll.onclick = () => regenSetup(Math.floor(Math.random() * 1e9));
  wrap.appendChild(reroll);
  app.appendChild(wrap);
}

function startGame(houseId) {
  state.playerHouseId = houseId;
  state.startYear = state.year;
  state.startTier = state.houses[houseId].tier;
  state.annals.push({ year: state.year, entries: [{ season: SEASONS[state.season], kind: 'crown', text: `The chronicle of House ${state.houses[houseId].name} begins. ${SEASONS[state.season]} of Year ${state.year}.` }] });
  state.log = [{ text: `You are ${lordTitle()} of ${state.houses[houseId].seat}. The realm watches, mostly with indifference. Change that.`, kind: 'crown' }];
  renderGame();
}

function lordTitle() {
  const P = state.houses[state.playerHouseId];
  const lord = state.characters[P.lordId];
  if (!lord) return 'steward';
  return `${lord.gender === 'f' ? 'Lady' : 'Lord'} ${lord.name} of House ${P.name}`;
}

// ---------- Main render ----------
function renderGame() {
  const app = $('#app');
  app.innerHTML = '';
  const P = state.houses[state.playerHouseId];

  // Top bar
  const top = el('div', 'topbar');
  top.innerHTML = `
    <div class="topbar-left">
      <span class="tb-sigil">${sigilSVG(P.sigil, 40)}</span>
      <span class="tb-house">House ${esc(P.name)} <span class="tb-tier">${P.tier === 'royal' ? '♛ ROYAL HOUSE' : P.tier === 'great' ? 'GREAT HOUSE' : 'minor house'}</span></span>
    </div>
    <div class="topbar-mid">
      <span class="tb-stat" title="Gold">🜚 ${P.gold}</span>
      <span class="tb-stat" title="Income per season">±${P.income}/s</span>
      <span class="tb-stat" title="Troops">⚔ ${P.troops}</span>
      <span class="tb-stat" title="Prestige">★ ${Math.round(P.prestige)}</span>
      ${houseDragons(state, P.id).length ? `<span class="tb-stat tb-dragon" title="Dragons of your house">${dragonMark(houseDragons(state, P.id)[0], 16)} ${houseDragons(state, P.id).length}</span>` : ''}
      ${state.dragonEggs ? `<span class="tb-stat tb-egg" title="Dragon eggs in your crypt">◉ ${state.dragonEggs} egg${state.dragonEggs > 1 ? 's' : ''}</span>` : ''}
      <span class="tb-stat" title="Actions left this season">◆ ${state.actionsLeft} action${state.actionsLeft === 1 ? '' : 's'}</span>
    </div>
    <div class="topbar-right">
      <span class="tb-date">${SEASONS[state.season]}, Year ${state.year}</span>
    </div>`;
  app.appendChild(top);

  // Tabs
  const tabs = el('div', 'tabs');
  const tabDefs = [['court', 'Court'], ['family', 'Family'], ['realm', 'The Realm'], ['chronicle', 'Chronicle']];
  for (const [key, label] of tabDefs) {
    const b = el('button', 'tab' + (currentTab === key ? ' active' : ''), label);
    b.onclick = () => { currentTab = key; renderGame(); };
    tabs.appendChild(b);
  }
  app.appendChild(tabs);

  const main = el('div', 'main');
  app.appendChild(main);

  if (state.gameOver) {
    renderGameOver(main);
    return;
  }

  if (currentTab === 'court') renderCourt(main);
  else if (currentTab === 'family') renderFamily(main);
  else if (currentTab === 'realm') renderRealm(main);
  else renderChronicle(main);

  // Bottom: end turn
  const bottom = el('div', 'bottombar');
  const warNote = state.war ? `<span class="war-flag">⚔ ${esc(state.war.name)} rages</span>` : '';
  bottom.innerHTML = warNote;
  const endBtn = el('button', 'btn btn-endturn', `Let the season pass ➤`);
  endBtn.onclick = () => {
    advanceSeason(state);
    currentTab = 'court';
    renderGame();
  };
  bottom.appendChild(endBtn);
  app.appendChild(bottom);
}

// ---------- Court tab ----------
function renderCourt(main) {
  const P = state.houses[state.playerHouseId];
  const grid = el('div', 'court-grid');

  // Decisions first
  if (state.pendingDecisions.length) {
    const d = state.pendingDecisions[0];
    const card = el('div', 'panel decision-panel');
    card.appendChild(el('div', 'panel-title', '✉ A Matter Requires Your Word'));
    card.appendChild(el('div', 'decision-title', esc(d.title)));
    card.appendChild(el('p', 'decision-text', esc(d.text)));
    d.options.forEach((opt, i) => {
      const b = el('button', 'btn btn-option', esc(opt.label));
      b.onclick = () => { resolveDecision(state, 0, i); renderGame(); };
      card.appendChild(b);
    });
    grid.appendChild(card);
  }

  // Events log
  const logPanel = el('div', 'panel log-panel');
  logPanel.appendChild(el('div', 'panel-title', `☙ Tidings — ${SEASONS[state.season]}, Year ${state.year}`));
  const list = el('div', 'log-list');
  if (!state.log.length) list.appendChild(el('div', 'log-entry dim', 'The ravens are quiet.'));
  for (const e of state.log) {
    list.appendChild(el('div', `log-entry kind-${e.kind}`, esc(e.text)));
  }
  logPanel.appendChild(list);
  grid.appendChild(logPanel);

  // Actions
  const actPanel = el('div', 'panel');
  actPanel.appendChild(el('div', 'panel-title', `⚜ Deeds of the Season (${state.actionsLeft} remaining)`));
  const actList = el('div', 'action-list');
  for (const [key, act] of Object.entries(ACTIONS)) {
    const row = el('div', 'action-row');
    const canAfford = P.gold >= act.cost && state.actionsLeft > 0;
    const disabled = !canAfford || (act.warAction && state.war);
    row.innerHTML = `<div class="action-info"><div class="action-label">${esc(act.label)} <span class="action-cost">${act.cost} 🜚</span></div><div class="action-desc">${esc(act.desc)}</div></div>`;
    const b = el('button', 'btn btn-small' + (key === 'press_claim' ? ' btn-danger' : ''), act.needsTarget ? 'Choose target…' : 'Do it');
    b.disabled = disabled;
    b.onclick = () => {
      if (act.needsTarget) pickTarget(key);
      else { const r = runAction(state, key); if (r && !r.ok) toast(r.msg); renderGame(); }
    };
    row.appendChild(b);
    actList.appendChild(row);
  }
  // marriage action
  const mrow = el('div', 'action-row');
  mrow.innerHTML = `<div class="action-info"><div class="action-label">Arrange a Marriage <span class="action-cost">free</span></div><div class="action-desc">Bind your blood to another house. Alliances outlive armies.</div></div>`;
  const mb = el('button', 'btn btn-small', 'Choose…');
  mb.disabled = state.actionsLeft <= 0;
  mb.onclick = () => pickMarriage();
  mrow.appendChild(mb);
  actList.appendChild(mrow);

  actPanel.appendChild(actList);
  grid.appendChild(actPanel);

  main.appendChild(grid);
}

function pickTarget(actionKey) {
  const P = state.houses[state.playerHouseId];
  const targets = Object.values(state.houses).filter((h) => h.alive && h.id !== P.id);
  modal(`Choose a target for: ${ACTIONS[actionKey].label}`, (body, close) => {
    for (const t of targets.sort((a, b) => (P.relations[a.id] || 0) - (P.relations[b.id] || 0))) {
      const rel = P.relations[t.id] || 0;
      const row = el('div', 'target-row');
      row.innerHTML = `<span class="tr-sigil">${sigilSVG(t.sigil, 28)}</span>
        <span class="tr-name">House ${esc(t.name)} <em class="dim">(${t.tier}${t.id === state.crownHouseId ? ', THE CROWN' : ''})</em></span>
        <span class="tr-rel ${rel < 0 ? 'neg' : 'pos'}">${rel >= 0 ? '+' : ''}${rel}</span>
        <span class="tr-troops">⚔ ${t.troops}</span>`;
      const b = el('button', 'btn btn-small', 'Select');
      b.onclick = () => { const r = runAction(state, actionKey, t.id); if (r && !r.ok) toast(r.msg); close(); renderGame(); };
      row.appendChild(b);
      body.appendChild(row);
    }
  });
}

function pickMarriage() {
  const P = state.houses[state.playerHouseId];
  const singles = livingMembers(state, P).filter((c) => !c.spouseId && age(state, c) >= 16 && age(state, c) <= 50);
  if (!singles.length) { toast('No one of your house is both unwed and of age.'); return; }
  modal('Whom shall we wed?', (body, close) => {
    for (const c of singles) {
      const row = el('div', 'target-row');
      row.innerHTML = `<span class="tr-name">${esc(shortName(state, c))}, ${c.gender === 'f' ? 'a lady' : 'a man'} of ${age(state, c)}</span>`;
      const b = el('button', 'btn btn-small', 'Find a match…');
      b.onclick = () => {
        body.innerHTML = '';
        const houses = Object.values(state.houses).filter((h) => h.alive && h.id !== P.id)
          .filter((h) => livingMembers(state, h).some((x) => !x.spouseId && x.gender !== c.gender && age(state, x) >= 16 && age(state, x) <= 50));
        if (!houses.length) { body.appendChild(el('p', 'dim', 'No house has a suitable unwed match this season.')); return; }
        body.appendChild(el('p', 'dim', `Seeking a match for ${esc(c.name)}. Higher-tier houses may refuse a lesser name.`));
        for (const h of houses.sort((a, b) => b.prestige - a.prestige)) {
          const rel = P.relations[h.id] || 0;
          const row2 = el('div', 'target-row');
          row2.innerHTML = `<span class="tr-sigil">${sigilSVG(h.sigil, 28)}</span>
            <span class="tr-name">House ${esc(h.name)} <em class="dim">(${h.tier})</em></span>
            <span class="tr-rel ${rel < 0 ? 'neg' : 'pos'}">${rel >= 0 ? '+' : ''}${rel}</span>`;
          const b2 = el('button', 'btn btn-small', 'Propose');
          b2.onclick = () => { const r = arrangeMarriage(state, c.id, h.id); toast(r.msg); close(); renderGame(); };
          row2.appendChild(b2);
          body.appendChild(row2);
        }
      };
      row.appendChild(b);
      body.appendChild(row);
    }
  });
}

// ---------- Family tab ----------
function renderFamily(main) {
  const P = state.houses[state.playerHouseId];
  const panel = el('div', 'panel');
  panel.appendChild(el('div', 'panel-title', `⚘ The Blood of House ${esc(P.name)}`));
  panel.appendChild(el('p', 'dim panel-note', `&ldquo;${esc(P.motto)}&rdquo; — ${esc(sigilBlazon(P.sigil))}. Seat: ${esc(P.seat)}, ${esc(regionName(state, P.regionId))}.`));

  // Dragons of the house
  const myDragons = houseDragons(state, P.id);
  if (myDragons.length || state.dragonEggs) {
    const dPanel = el('div', 'dragon-panel');
    dPanel.appendChild(el('div', 'panel-title dragon-title', '🜂 The Dragons of the House'));
    for (const d of myDragons) {
      const rider = d.riderId ? state.characters[d.riderId] : null;
      const row = el('div', 'dragon-row');
      row.innerHTML = `${dragonMark(d, 26)}
        <div class="dragon-info">
          <div class="dragon-name">${esc(d.name)} <em class="dim">(${esc(dragonStageName(state, d))}, ${state.year - d.birthYear} years)</em></div>
          <div class="dragon-sub dim">${esc(d.colorDesc)}, ${esc(d.temperament)}${rider ? ` · ridden by <strong>${esc(shortName(state, rider))}</strong>` : ' · <span class="neg">unridden</span> — only the old blood may try'}</div>
          ${d.kills.length ? `<div class="dragon-kills dim">Deeds: ${esc(d.kills.slice(-2).join('; '))}</div>` : ''}
        </div>`;
      dPanel.appendChild(row);
    }
    if (state.dragonEggs) {
      dPanel.appendChild(el('div', 'dragon-row dim', `◉ ${state.dragonEggs} dragon egg${state.dragonEggs > 1 ? 's' : ''} warm in the crypt. Winter may quicken them — or reveal them to be very expensive stones.`));
    }
    panel.appendChild(dPanel);
  }

  const members = livingMembers(state, P).sort((a, b) => (P.lordId === a.id ? -1 : P.lordId === b.id ? 1 : a.birthYear - b.birthYear));
  const grid = el('div', 'family-grid');
  for (const c of members) {
    const isLord = P.lordId === c.id;
    const card = el('div', 'char-card' + (isLord ? ' lord' : '') + (c.dragonId ? ' rider' : ''));
    const sp = c.spouseId ? state.characters[c.spouseId] : null;
    const mount = c.dragonId ? state.dragons[c.dragonId] : null;
    card.innerHTML = `
      <div class="char-name">${isLord ? (c.gender === 'f' ? '♛ Lady ' : '♛ Lord ') : ''}${esc(fullName(state, c))}${mount ? ' ' + dragonMark(mount, 15) : ''}</div>
      <div class="char-sub">${c.gender === 'f' ? 'Female' : 'Male'}, aged ${age(state, c)}${c.wounded ? ' · <span class="neg">wounded</span>' : ''}${c.glory ? ` · glory ${'✦'.repeat(Math.min(5, c.glory))}` : ''}${mount ? ` · <span class="dragon-tag">rides ${esc(mount.name)}</span>` : ''}</div>
      <div class="char-traits">${c.traits.map((t) => `<span class="trait${t === 'Dragonblood' ? ' trait-blood' : ''}">${esc(t)}</span>`).join('')}</div>
      <div class="char-skills">
        <span title="War">⚔ ${c.skills.war}</span>
        <span title="Diplomacy">🕊 ${c.skills.dip}</span>
        <span title="Stewardship">🜚 ${c.skills.stew}</span>
        <span title="Intrigue">🗡 ${c.skills.intr}</span>
      </div>
      <div class="char-rel dim">${sp ? (sp.alive ? 'Wed to ' + esc(shortName(state, sp)) : 'Widowed') : age(state, c) >= 16 ? 'Unwed' : 'A child'}${c.childrenIds.length ? ` · ${c.childrenIds.filter((k) => state.characters[k].alive).length} living children` : ''}</div>
    `;
    grid.appendChild(card);
  }
  panel.appendChild(grid);

  // The dead
  const dead = Object.values(state.characters).filter((c) => !c.alive && (c.houseId === P.id || c.birthHouseId === P.id)).sort((a, b) => b.deathYear - a.deathYear);
  if (dead.length) {
    panel.appendChild(el('div', 'panel-title dead-title', '✝ The Crypts'));
    const dl = el('div', 'dead-list');
    for (const c of dead.slice(0, 20)) {
      dl.appendChild(el('div', 'dead-entry', `<strong>${esc(fullName(state, c))}</strong> (${c.birthYear}–${c.deathYear}) — ${esc(c.causeOfDeath || '')}`));
    }
    panel.appendChild(dl);
  }
  main.appendChild(panel);
}

// ---------- Realm tab ----------
function renderRealm(main) {
  const P = state.houses[state.playerHouseId];
  const panel = el('div', 'panel');
  const crown = state.houses[state.crownHouseId];
  panel.appendChild(el('div', 'panel-title', `♛ The Realm of ${esc(state.realmName)}`));
  panel.appendChild(el('p', 'dim panel-note', `House ${esc(crown.name)} holds the throne from ${esc(crown.seat)}. ${state.war ? `The realm bleeds: ${esc(state.war.name)}.` : 'The realm is at peace — for now.'}`));

  // Dragons of the realm
  const allDragons = livingDragons(state);
  if (allDragons.length) {
    const dSec = el('div', 'region-sec');
    dSec.appendChild(el('div', 'region-name dragon-title', '🜂 The Last Dragons'));
    const dl = el('div', 'realm-list');
    for (const d of allDragons) {
      const rider = d.riderId ? state.characters[d.riderId] : null;
      const owner = d.houseId ? state.houses[d.houseId] : null;
      const row = el('div', 'realm-row dragon-realm-row');
      row.innerHTML = `<span class="tr-sigil">${dragonMark(d, 26)}</span>
        <span class="rr-name">${esc(d.name)} <em class="dim">${esc(dragonStageName(state, d))}</em></span>
        <span class="rr-seat dim">${d.wild ? 'WILD — lairs in ' + esc(regionName(state, d.lairRegionId || state.regions[0].id)) : owner ? 'of House ' + esc(owner.name) : '—'}</span>
        <span class="rr-lord dim">${rider ? 'ridden by ' + esc(shortName(state, rider)) : 'unridden'}</span>
        <span class="rr-stats">${esc(d.colorDesc)}</span>
        <span class="tr-rel"></span>`;
      dl.appendChild(row);
    }
    dSec.appendChild(dl);
    panel.appendChild(dSec);
  } else {
    panel.appendChild(el('p', 'dim panel-note', '🜂 No dragon flies in the world. The age of fire is ended — unless an egg somewhere remembers otherwise.'));
  }

  for (const region of state.regions) {
    const rHouses = Object.values(state.houses).filter((h) => h.regionId === region.id && h.tier !== 'royal');
    const sec = el('div', 'region-sec');
    sec.appendChild(el('div', 'region-name', esc(region.name)));
    const list = el('div', 'realm-list');
    for (const h of rHouses.sort((a, b) => (a.tier === 'great' ? -1 : 1) - (b.tier === 'great' ? -1 : 1) || b.prestige - a.prestige)) {
      const rel = P.relations[h.id] || 0;
      const row = el('div', 'realm-row' + (h.alive ? '' : ' extinct') + (h.id === P.id ? ' mine' : ''));
      const lord = h.alive ? state.characters[h.lordId] : null;
      row.innerHTML = `
        <span class="tr-sigil">${sigilSVG(h.sigil, 30)}</span>
        <span class="rr-name">House ${esc(h.name)}${h.id === P.id ? ' ✦ (yours)' : ''} <em class="dim">${h.alive ? h.tier : 'EXTINCT ' + h.extinctYear}</em></span>
        <span class="rr-seat dim">${esc(h.seat)}</span>
        <span class="rr-lord dim">${lord ? esc(shortName(state, lord)) : '—'}</span>
        <span class="rr-stats">★${Math.round(h.prestige)} ⚔${h.alive ? h.troops : 0}</span>
        ${h.id !== P.id && h.alive ? `<span class="tr-rel ${rel < 0 ? 'neg' : 'pos'}">${rel >= 0 ? '+' : ''}${rel}</span>` : '<span class="tr-rel"></span>'}
      `;
      list.appendChild(row);
    }
    sec.appendChild(list);
    panel.appendChild(sec);
  }
  // royal house row
  const sec = el('div', 'region-sec');
  sec.appendChild(el('div', 'region-name', 'The Crownlands'));
  const rel = P.relations[crown.id] || 0;
  const row = el('div', 'realm-row royal-row' + (crown.id === P.id ? ' mine' : ''));
  const clord = state.characters[crown.lordId];
  row.innerHTML = `<span class="tr-sigil">${sigilSVG(crown.sigil, 30)}</span>
    <span class="rr-name">House ${esc(crown.name)} ♛${crown.id === P.id ? ' ✦ (yours)' : ''}</span>
    <span class="rr-seat dim">${esc(crown.seat)}</span>
    <span class="rr-lord dim">${clord ? esc(shortName(state, clord)) : '—'}</span>
    <span class="rr-stats">★${Math.round(crown.prestige)} ⚔${crown.troops}</span>
    ${crown.id !== P.id ? `<span class="tr-rel ${rel < 0 ? 'neg' : 'pos'}">${rel >= 0 ? '+' : ''}${rel}</span>` : '<span class="tr-rel"></span>'}`;
  sec.appendChild(row);
  panel.appendChild(sec);

  main.appendChild(panel);
}

// ---------- Chronicle tab ----------
function renderChronicle(main) {
  const panel = el('div', 'panel chronicle-panel');
  const tools = el('div', 'chron-tools');
  const copyBtn = el('button', 'btn btn-small', '⎘ Copy as text');
  copyBtn.onclick = async () => {
    try { await navigator.clipboard.writeText(chroniclePlainText(state)); toast('Chronicle copied to clipboard.'); }
    catch { toast('Could not copy — your browser refused.'); }
  };
  tools.appendChild(copyBtn);
  panel.appendChild(tools);
  panel.appendChild(el('div', 'chron-body', buildChronicle(state)));
  main.appendChild(panel);
}

// ---------- Game over ----------
function renderGameOver(main) {
  const P = state.houses[state.playerHouseId];
  const panel = el('div', 'panel gameover-panel');
  panel.innerHTML = `
    <div class="go-sigil">${sigilSVG(P.sigil, 100)}</div>
    <h2 class="go-title">HOUSE ${esc(P.name.toUpperCase())} IS NO MORE</h2>
    <p class="go-text">${esc(state.gameOver.reason)}</p>
    <p class="go-text dim">The house endured from Year ${state.startYear} to Year ${state.gameOver.year} — ${state.gameOver.year - state.startYear} years. Its chronicle survives it.</p>`;
  const b1 = el('button', 'btn btn-primary', 'Read the Chronicle');
  b1.onclick = () => { state.gameOver._read = true; modal(`The Chronicle of House ${P.name}`, (body) => { body.appendChild(el('div', 'chron-body', buildChronicle(state))); }, true); };
  const b2 = el('button', 'btn btn-ghost', 'Begin a new dynasty');
  b2.onclick = () => showSetup();
  panel.appendChild(b1); panel.appendChild(b2);
  main.appendChild(panel);
}

// ---------- Widgets ----------
function modal(title, buildBody, wide = false) {
  const back = el('div', 'modal-back');
  const box = el('div', 'modal' + (wide ? ' modal-wide' : ''));
  box.appendChild(el('div', 'modal-title', esc(title)));
  const body = el('div', 'modal-body');
  box.appendChild(body);
  const close = () => back.remove();
  const x = el('button', 'modal-x', '✕');
  x.onclick = close;
  box.appendChild(x);
  back.onclick = (e) => { if (e.target === back) close(); };
  buildBody(body, close);
  back.appendChild(box);
  document.body.appendChild(back);
}

let toastTimer = null;
function toast(msg) {
  let t = $('#toast');
  if (!t) { t = el('div', ''); t.id = 'toast'; document.body.appendChild(t); }
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 3500);
}

boot();

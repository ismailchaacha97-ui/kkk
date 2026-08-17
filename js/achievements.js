// Achievements: titles the dynasty earns. Stored on state.achievements = {id: year}.
import { livingMembers } from './world.js';
import { houseDragons, livingDragons } from './dragons.js';
import { log } from './engine.js';

export const ACHIEVEMENTS = [
  { id: 'great', icon: '⚜', name: 'Raised Banners', desc: 'Become a Great House.' },
  { id: 'crown', icon: '♛', name: 'The Throne', desc: 'Take the crown of the realm.' },
  { id: 'dragonrider', icon: '🜂', name: 'Fire Made Flesh', desc: 'A member of your house rides a dragon.' },
  { id: 'dragonsbane', icon: '☠', name: 'Dragonsbane', desc: 'Slay a wild dragon.' },
  { id: 'oldblood', icon: '🩸', name: 'The Old Blood Restored', desc: '5 living kin with Dragonblood.' },
  { id: 'century', icon: '⌛', name: 'Century House', desc: 'Survive 100 years of play.' },
  { id: 'dynasty', icon: '👑', name: 'Dynasty', desc: 'See the 4th lord of your rule take the seat.' },
  { id: 'kingmaker', icon: '⚖', name: 'Kingmaker', desc: 'A Great Council crowns a dynasty while you hold a vote.' },
  { id: 'rich', icon: '🜚', name: 'Golden Halls', desc: 'Hold 2000 gold at once.' },
  { id: 'full_court', icon: '🏰', name: 'A Court Complete', desc: 'All 4 council seats filled and 12+ living kin.' },
  { id: 'nemesis_down', icon: '🗡', name: 'Vengeance Is Patience', desc: 'Outlive or extinguish your nemesis house.' },
  { id: 'champion', icon: '🏆', name: 'Champion of the Lists', desc: 'Your kin wins a playable tourney.' },
  { id: 'survivor', icon: '❄', name: 'The House That Would Not Die', desc: 'Survive a plague, a cruel winter, and a war.' },
];

export function checkAchievements(state) {
  if (!state.achievements) state.achievements = {};
  const A = state.achievements;
  const P = state.houses[state.playerHouseId];
  if (!P || !P.alive) return;
  const grant = (id) => {
    if (A[id]) return;
    A[id] = state.year;
    const def = ACHIEVEMENTS.find((x) => x.id === id);
    if (def) log(state, `${def.icon} ACHIEVEMENT: "${def.name}" — ${def.desc}`, 'crown');
  };

  if (P.tier === 'great' || P.tier === 'royal') grant('great');
  if (P.id === state.crownHouseId) grant('crown');
  if (livingMembers(state, P).some((c) => c.dragonId)) grant('dragonrider');
  if (livingMembers(state, P).filter((c) => c.traits.includes('Dragonblood')).length >= 5) grant('oldblood');
  if (state.startYear && state.year - state.startYear >= 100) grant('century');
  if ((state.lordCount || 1) >= 4) grant('dynasty');
  if (P.gold >= 2000) grant('rich');
  if (Object.values(P.council).filter(Boolean).length === 4 && livingMembers(state, P).length >= 12) grant('full_court');
  if (state.nemesisDefeated) grant('nemesis_down');
  if (state.tourneyWon) grant('champion');
  if (state.sawPlague && state.sawCruelWinter && state.sawWar) grant('survivor');
  if (state.dragonSlain) grant('dragonsbane');
  if (state.councilVoted) grant('kingmaker');
}

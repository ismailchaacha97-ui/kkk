# Oaths & Banners

**A dynasty simulation in the spirit of *A Song of Ice and Fire*.** Great houses, minor houses, marriages, wars, winters, and a chronicle that writes itself.

Take up the banners of a minor house in a procedurally generated realm. Every season you manage your holdings, arrange marriages, host tourneys, weave schemes, and answer event-card dilemmas — while the whole realm simulates around you: AI houses marry, feud, go to war, and go extinct. Characters age and die permanently. When your lord dies, succession law finds an heir — or your house is extinguished and the game ends.

Everything that happens is written into **The Chronicle**: a maester's prose account of your dynasty, year by year, with a roll of the fallen. Nothing in it is scripted — it is all generated from what actually happened in your game.

## Features

- 🏰 **Procedural realm** — realm name, 6 regions, a royal house, great houses, and 20+ minor houses, each with a generated name, seat, motto, and heraldic sigil (SVG, drawn in code)
- 👥 **Living characters** — traits, four skills (war / diplomacy / stewardship / intrigue), aging, wounds, glory, earned epithets, permadeath
- 💍 **Marriage & alliances** — propose matches; higher houses may refuse a lesser name
- ⚔️ **Wars** — declare war, allies join by oath and friendship, named battles kill named characters, wars end in tribute or white peace. Raise banners against the throne itself and you can found a new royal dynasty
- 🃏 **Event cards** — hedge knights, hungry smallfolk, insults at court, bastard rumors, royal wardships
- 🐉 **The Last Dragons** — a royal dragon chained beneath the throne, wild dragons raiding the countryside, and the rare **Dragonblood** trait passed down bloodlines. Buy eggs from suspicious merchants (some are painted rocks), hatch them in winter, bond riders — or die trying. Dragons burn hosts in battle, duel each other in **Dances of Dragons**, fall to massed scorpion bolts, grieve their dead riders, lay clutches, and go extinct if the realm is careless. You can even mount a dragon-hunt and hang a skull in your hall
- ❄️ **Seasons & winters** — harvest booms, winters of varying severity that kill the old and the young
- 📜 **The Chronicle** — your full history as prose, copyable as plain text to share
- 🎖️ **Rise in standing** — reach 80 prestige as a minor house and be raised to a great house by royal decree

## Run locally

Any static file server works (ES modules require http, not `file://`):

```bash
python3 -m http.server 8000
# open http://localhost:8000
```

## Publish on itch.io

1. Zip the game files: `bash build-itch.sh` → produces `oaths-and-banners-itch.zip`
2. On itch.io: **Upload new project** → Kind of project: **HTML**
3. Upload the zip, check **"This file will be played in the browser"**
4. Viewport: **1080 × 800** (or enable *Mobile friendly* + *Automatically start on page load*)
5. Publish.

No build step, no dependencies — plain HTML/CSS/JS ES modules.

## Structure

```
index.html        entry point
style.css         parchment / manuscript UI
js/rng.js         seeded RNG
js/names.js       people/house/seat/motto name generators
js/sigil.js       procedural heraldry (SVG shields)
js/dragons.js     dragons: stages, power, riders, wild lairs
js/world.js       world generation, characters, succession
js/engine.js      season simulation: economy, mortality, births, marriages, wars, events, actions
js/chronicle.js   prose history generator
js/ui.js          all rendering & interaction
```

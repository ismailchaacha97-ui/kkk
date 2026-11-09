# START HERE — complete beginner's guide

You do **not** need to know how to code. Follow the steps for your computer, in order.
Total time: about 5 minutes, once.

---

## Step 1 — Install Node.js (one time only)

Node.js is the program that runs the floor on your PC. Think of it as the "engine" that
Facebook/Instagram-sized websites run on. You install it once and forget about it.

**On Windows**

1. Go to **https://nodejs.org**
2. Click the big button that says **LTS** (not "Current"). It downloads a `.msi` file.
3. Open the downloaded file → click **Next** → **Next** → **Install** → **Finish**.
4. If Windows asks "Do you want to allow this app to make changes?" click **Yes**.

**On a Mac**

1. Go to **https://nodejs.org**
2. Click the **LTS** button. It downloads a `.pkg` file.
3. Double-click it → **Continue** → **Continue** → **Agree** → **Install**.
4. It may ask for your Mac password — type it (you won't see the letters) and press Enter.

**To check it worked:** after installing, you can run `node -v` in a terminal and you should
see something like `v20.11.0`. But you don't have to — the start file does this check for you.

---

## Step 2 — Put the folder on your PC

The project lives in a folder called `office-terminal`, inside the `kkk` repository.

**If you don't have the folder yet**, open a terminal (see Step 4) and paste these lines one
at a time, pressing Enter after each:

```bash
git clone https://github.com/ismailchaacha97-ui/kkk.git
cd kkk
git checkout arena/dcd582b7-kkk
```

Now the folder `kkk/office-terminal` exists on your computer.

**If you already have the folder**, open a terminal in it and type `git pull` to get the
latest version.

---

## Step 3 — Start it (the easy way)

Inside the `office-terminal` folder there are three files with a green "play" look:

| Your computer | Double-click this file |
|---|---|
| **Windows** | `start.bat` |
| **Mac** | `start.command` |
| **Linux** | `start.sh` |

The first time it will say *"First run detected — downloading the 3D engine"* and take about
30 seconds. Then your browser opens by itself at **http://localhost:8787** and the floor
starts.

> **Mac, first time only:** if double-clicking does nothing or macOS says *"start.command
> cannot be opened because it is from an unidentified developer"*, do this once:
> right-click (or Control-click) `start.command` → **Open** → **Open** again.
> If it still refuses, open **Terminal**, type `cd ` (with a space), drag the
> `office-terminal` folder into the Terminal window, press Enter, then type `./start.command`
> and press Enter.

> **Windows, first time only:** if a blue box says *"Windows protected your PC"*, click
> **More info** → **Run anyway**. That appears for any downloaded `.bat` file.

---

## Step 4 — What a "terminal" is (only if you need it)

A terminal (Windows: *Command Prompt* or *PowerShell*; Mac: *Terminal*) is just a window where
you type commands instead of clicking. To open one:

- **Windows:** press the Windows key, type `powershell`, press Enter.
- **Mac:** press `Cmd + Space`, type `terminal`, press Enter.

To move into the project folder, type `cd ` (c with d, then a space), then **drag the
`office-terminal` folder into the window** — the path appears by itself — and press Enter.

Then `npm start` and press Enter. That's the manual version of Step 3.

---

## Step 5 — What you are looking at

The screen has three columns and a header.

**Header (top)**

- A green dot and **LIVE MARKET DATA · 6/6 instruments** = real prices are streaming in.
- **EQUITY** = the virtual money the office has ($100,000 to start). This is pretend money.
- **SESSION P&L** = how much the traders have made or lost since you opened the page.
- Buttons: **PAUSE**, speed `1× 2× 4×`, **CALL A DEBATE**, **+ HIRE**.

**Left column**

- **LIVE MARKETS** — the six markets they trade (Bitcoin, Ethereum, Euro/USD, Gold, Nasdaq,
  Apple) with the real current price and a tiny sparkline.
- **THE FLOOR** — your employees. Each has a name, a style, a win/loss record, a mood and a
  running P&L. Click one to open her file.

**Middle — the 3D office**

- Drag with the mouse to walk around the room, scroll to zoom in.
- Six desks, each with three monitors showing that trader's live screen.
- The round glowing table in the middle is the **holo-table**: a live price chart.
- The whiteboard on the wall is written by the traders themselves — it shows the latest lesson
  each one learned.
- Some traders get up and walk to the coffee machine or the whiteboard. That's not decoration,
  it's them deciding to take a break.

**Right column**

- **THE ROOM** — the conversation. This is the heart of it: before anyone risks money, the
  traders argue about the trade and you can read every word.
- **LIVE BOOK** — the positions currently open, and which trader owns each one.
- **BLOTTER** — every buy and sell that has happened, with the reason.
- **OPEN MIC** and **FLOOR LOG** — office chatter and the official record.

---

## Step 6 — Ten things to try

1. Click **CALL A DEBATE** and watch the three messages appear, then the big **verdict**.
2. Click a trader's name on the left → read her **Traits**, **what she believes**, and her
   **lessons** (they start empty and fill up as she makes mistakes).
3. Press **4×** and let it run for two minutes. Employees will start going off-script, trading
   on their own, hiring new people, and their generations (`g1`, `g2`) will climb.
4. Set a stop-loss? Not needed — the risk rules are automatic. But try the **HOUSE MANDATE**
   sliders: turn **FREE WILL** off and watch the office become obedient and boring.
5. Click **+ HIRE** and watch a new desk appear in the 3D room.
6. Click a market on the left — the desk monitors and the holo-table switch to it.
7. Leave it running for 10 minutes, reload the page — their memories are saved, and they
   come back smarter and grumpier.
8. Press **RESET MEMORIES** when you want a brand-new team that knows nothing.
9. Hover a **BLOTTER** row — the tiny grey text under it is the sentence that caused the trade.
10. Watch the **FEED** badge. If it turns amber or red, your network can't reach one of the
    exchanges — that's the internet, not a bug. Press **⟳**.

---

## Common problems, in plain words

**"npm is not recognized" / "node is not recognized"**
Node.js isn't installed, or you installed it but this window was already open. Close the window,
open a new one, try again. If it still fails, reinstall from nodejs.org and reboot.

**The browser says "This site can't be reached"**
The little black window running the server got closed. Double-click `start.bat` /
`start.command` again and leave that window alone while you play.

**"Port 8787 is already in use"**
You started it twice. Close the other window, or run `npm run dev -- --port 8790` and open
`http://localhost:8790`.

**The page is black / empty**
Press `F5` to reload. If it stays empty, press `F12`, click **Console**, and look for red text —
usually it means 3D graphics are switched off in your browser. In Chrome:
Settings → System → **Use graphics acceleration when available** → on → restart Chrome.

**The feed says OFFLINE**
Some countries block Binance. The app already tries Coinbase, another Binance address, ECB and
Stooq, so usually a few instruments still stream. It will never show you invented prices.

**"First run detected" takes forever**
It's downloading about 200 MB of 3D library. Normal on slow internet. Only happens once.

---

## The honest part

- **Prices are real.** They come from public exchange feeds on the internet, the same numbers
  you'd see on a trading site.
- **The money is fake.** $100,000 of pretend money, pretend fees. No real broker is connected,
  so nothing is ever bought or sold for real, and no money can be lost.
- **This is not financial advice** and the traders are not magic. What makes them interesting is
  that they are allowed to say *"I don't know"* — which is the rarest thing in trading.
- Nothing leaves your computer except the price requests. No account, no sign-up, no keys.

---

## When you're done

Close the browser tab. Then close the black window (or press `Ctrl + C` inside it) to stop the
server. Your traders' memories stay saved for next time.

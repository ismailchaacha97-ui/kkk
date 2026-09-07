# 🕊️ $COO — Sir Reginald Coo III, Pigeon of Prosperity

A complete, free, launch-ready meme coin for **Base**. Fixed supply, zero tax,
no mint function, non-upgradeable, ownership renounceable — plus the website,
brand assets, listing kit and runbook needed to actually take it live.

```
Name       Sir Reginald Coo III
Symbol     COO
Chain      Base (chainId 8453)
Supply     1,000,000,000 — fixed, minted once
Tax        0% / 0%
Contract   120 lines, 21 passing tests, no proxy, no admin keys after launch
```

> *"He has eaten a cigarette butt and survived. He will survive your candle too."*

## What's in here

```
contracts/Coo.sol         The token. Read it — it's short on purpose.
test/Coo.test.js          21 tests, incl. the honeypot checks scanners run.
scripts/preflight.js      Checks keys, RPC, balance and gas before you spend.
scripts/deploy.js         Deploys + verifies + writes deployments/<network>.json
scripts/add-liquidity.js  Creates the Uniswap V2 pool. This is the "listing".
scripts/renounce.js       Drops limits, renounces ownership. One-way.
scripts/listing-kit.js    Stamps the real address into every listing artifact.
web/                      Static site — buy guide, tokenomics, safety, FAQ.
web/assets/               Logo at 512/256/128/64/32 + favicon, transparent PNG.
docs/LAUNCH.md            Step-by-step runbook, testnet through mainnet.
docs/LISTING.md           Every listing venue, free vs paid, honestly labelled.
docs/TOKENOMICS.md        Distribution, launch pricing, security posture.
docs/SOCIAL.md            Launch tweets, bio, pinned post, TG rules.
```

## Quick start

```bash
npm install
npm test                 # 21 passing
npm run site             # preview the website at :3000
cp .env.example .env     # add a FRESH deployer key + free Basescan API key
npm run preflight
```

Then follow **[docs/LAUNCH.md](docs/LAUNCH.md)**. Rehearse the whole thing on
Base Sepolia for free before spending anything on mainnet.

## Scripts

| Command | What it does |
|---|---|
| `npm test` | Full test suite on a local chain |
| `npm run compile` | Compile contracts |
| `npm run site` | Serve the website locally on :3000 |
| `npm run preflight` | Pre-spend sanity check (add `--network base`) |
| `npm run deploy:testnet` | Deploy to Base Sepolia (free) |
| `npm run deploy:mainnet` | Deploy to Base (~$0.30 of gas) |
| `npm run liquidity` | Create the pool and add liquidity |
| `npm run renounce` | Remove limits + renounce ownership |
| `npm run listing:kit` | Regenerate listing artifacts with the live address |

## Contract properties

| Property | Status |
|---|---|
| Mint function | ❌ does not exist |
| Transfer tax | ❌ no fee code path at all |
| Blacklist / pause | ❌ none |
| Upgradeable / proxy | ❌ no |
| Max wallet | ⏳ 2% at launch, can't be lowered, can't go below 1%, auto-expires after 24h |
| Ownership | ✅ two-step, renounceable, renounced at launch |
| Burnable | ✅ `burn()` / `burnFrom()` |
| EIP-2612 permit | ✅ gasless approvals |
| Built on | OpenZeppelin Contracts 5.0.2, Solidity 0.8.24 |

Builds are hermetic: `hardhat.config.js` resolves solc from the npm `solc`
package rather than downloading a binary, so it compiles offline / behind a
firewall.

## What "free" means here

The code, site, art, tests and listing kit cost nothing. Deploying to a real
blockchain costs gas — about **$1–2 total on Base**, paid to the network, not
to anyone here. Liquidity is your own money and stays at risk. CoinGecko,
CoinMarketCap, DexScreener basic listings and GitHub Pages hosting are all free;
anyone charging you for those is running a scam.

## ⚠️ Disclaimer

$COO is a meme token with no intrinsic value, no revenue, no product, and no
expectation of profit. It is entertainment. It can and probably will go to zero.
Nothing in this repository is financial advice or an offer to sell a security.
You are responsible for your own compliance with the laws where you live.

MIT licensed. The bird belongs to everyone.

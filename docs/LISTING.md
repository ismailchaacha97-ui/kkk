# Getting $COO listed — the free path

Everything in this file that is marked **FREE** costs nothing but time. Anything
that costs money is marked **PAID** and is optional. Skip all of it if you want;
none of it is required for the token to trade.

## The one rule that governs everything

Aggregators do not list tokens. They list **markets**. Until there is a
liquidity pool with real trades in it, every form below will reject you, and
correctly so. So the order is always:

**deploy → verify → add liquidity → lock LP → renounce → submit forms**

Do not submit anything before liquidity is live. A rejected submission puts you
in a manual-review queue that is much slower than a clean first attempt.

---

## Tier 0 — automatic, zero effort (FREE)

These index Base on their own. You do nothing but add liquidity and make one buy.

| Where | When it appears | Notes |
|---|---|---|
| **DexScreener** | Minutes after the first swap | Basic pair listing is automatic once a pool exists and has ≥1 transaction. |
| **GeckoTerminal** | ~10–30 min | CoinGecko's DEX arm. Feeds price into the main CoinGecko site later. |
| **Uniswap interface** | Immediately | Searchable by contract address. Shows an "unknown token" warning until you're on a token list. |
| **Basescan token page** | On first transfer | Becomes a real page once the contract is verified. |
| **DEXTools** | ~30 min | Free basic pair. "Update info" / socials is **PAID**. |
| **Wallet balances** | Immediately | Coinbase Wallet, Rabby, MetaMask all show it by contract address. |

**Your job:** after `add-liquidity.js`, do one tiny buy from a second wallet.
That single transaction is what triggers the indexers.

---

## Tier 1 — the submissions that actually matter (FREE)

### 1. CoinGecko — the big one

Free, no fee, and any "CoinGecko representative" who asks you for money is a
scammer. Form: **https://www.coingecko.com/en/coins/new**

What they check before approving:

- Working website with real information on purpose, team, and socials — **not** a Wix/site-builder page (they reject those explicitly)
- Verified contract on a working block explorer
- Live trading on a DEX they already index (Uniswap on Base qualifies)
- Real liquidity and volume. Realistically: **$5k+ liquidity, $2k+ daily volume, ~7 days of history** before you have a serious chance
- 512×512 PNG logo, transparent background
- 150–500 word description

Paste the answers from `listing/FORM-ANSWERS.md`. Submit **once**. Do not
resubmit; duplicates push you to the back of the queue. Expect 2–8 weeks.

> A token with no volume gets an "Untracked" page at best. This is the honest
> gate: CoinGecko listing follows real trading, it does not create it.

### 2. CoinMarketCap

Form: **https://support.coinmarketcap.com/hc/en-us/requests/new** → "Add
cryptoasset". Same information, stricter reviewers, slower. Submit a week or
two after CoinGecko so you can show a longer trading history.

### 3. Uniswap / wallet token lists

Your `listing/tokenlist.json` is a valid Uniswap token list. Host it at a public
URL (GitHub Pages works — see below) and users can paste that URL into Uniswap
to import COO with the right name and logo. It's also what you submit to
community list repos.

### 4. Trust Wallet assets

The GitHub repo `trustwallet/assets` accepts a PR with
`listing/trustwallet-info.json` plus a 256×256 `logo.png` under
`blockchains/base/assets/<checksummed-address>/`. PRs from unknown tokens are
often closed without merge, and their web submission flow charges a fee
(**PAID**). Cheaper reality: once CoinGecko lists you, most wallets pull the
logo from CoinGecko automatically. Do CoinGecko first.

### 5. Free hosting for the website (FREE)

CoinGecko requires a real website. GitHub Pages is free and is not a site builder:

```bash
git subtree push --prefix web origin gh-pages
# then: repo Settings → Pages → branch gh-pages → /
```

Point a domain at it if you have one; a `github.io` URL works but a real domain
noticeably improves approval odds. Update `SITE` in `scripts/listing-kit.js`
and re-run it so every artifact carries the right URL.

---

## Tier 2 — optional, costs money (PAID)

Listed only so nobody sells them to you as mandatory. **None of these are required.**

| Thing | Price | Verdict |
|---|---|---|
| DexScreener Enhanced Token Info | ~$299 | Adds your logo/socials to the DexScreener page. Purely cosmetic. Verify the current price on their marketplace before paying. |
| DEXTools token info update | ~$100–500 | Same idea, less traffic. Skip. |
| CoinGecko / CMC "fast track" | any price | **Does not exist.** Both are free. Anyone charging you is a scammer. |
| Centralized exchange listing | $10k–$500k+ | Not a thing for a new meme coin. Ignore all DMs offering it. |
| Audit | $2k–$30k | Reasonable for a complex protocol. This contract is 120 lines with a public test suite. |

### The scam filter

Within an hour of your pool going live you will get DMs offering listings,
market making, "CoinGecko fast track", and audits. Rules: CoinGecko and CMC
never charge. Nobody legitimate asks for your seed phrase, ever. Nobody
legitimate needs you to send tokens or ETH "to verify ownership."

---

## Submission checklist

Before you touch a single form:

- [ ] Contract deployed to Base mainnet
- [ ] Source verified and green on Basescan
- [ ] Liquidity added on Uniswap V2
- [ ] LP tokens locked or burned, with the tx link saved
- [ ] Ownership renounced — `owner()` returns `0x000…000`
- [ ] `npm run listing:kit` re-run so every file has the real address
- [ ] Website live on a public URL with that address on it
- [ ] X account and Telegram exist and have posts in them
- [ ] Logo uploaded somewhere public as a 512×512 transparent PNG
- [ ] At least a handful of real trades and holders

Then: DexScreener happens by itself → CoinGecko → wait a week → CoinMarketCap.

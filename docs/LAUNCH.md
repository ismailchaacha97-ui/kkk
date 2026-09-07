# Launch runbook

Every command, in order. Do the whole thing on testnet first — it's free and
identical apart from the chain id.

## 0. One-time setup

```bash
npm install
cp .env.example .env
```

Open `.env` and fill in:

- `PRIVATE_KEY` — **make a brand new wallet for this.** Not your main wallet.
  Export the key from MetaMask/Rabby (Account details → Show private key).
  This file is gitignored. If it ever leaks, the wallet is gone.
- `BASESCAN_API_KEY` — free at https://basescan.org/myapikey

```bash
npm test          # 21 tests, all must pass
npm run preflight # sanity-check keys, RPC, balance and gas
```

## 1. Full dress rehearsal on Base Sepolia (FREE)

Get free testnet ETH from any Base Sepolia faucet (Coinbase Developer Platform,
Alchemy, or QuickNode all run one).

```bash
npx hardhat run scripts/preflight.js --network baseSepolia
npx hardhat run scripts/deploy.js    --network baseSepolia
```

You get `deployments/baseSepolia.json` and a verified contract on
sepolia.basescan.org. Send tokens between two wallets. Confirm the max-wallet
cap rejects a >2% transfer. Nothing here costs real money.

## 2. Mainnet deploy (~$0.30 of gas)

Fund the deployer with about **$5 of ETH on Base** — that covers the deploy,
the pool creation and the approvals, with room to spare. The rest of whatever
you're willing to risk becomes the liquidity.

```bash
npx hardhat run scripts/preflight.js --network base
npx hardhat run scripts/deploy.js    --network base
```

Confirm on Basescan that the contract is verified (green checkmark) before
going further. If verification failed, the command prints the exact retry line.

## 3. Split the supply (optional but honest)

The full 1B mints to the treasury. Send the community/CEX/team buckets to their
own wallets now, before liquidity, so the distribution is legible on-chain from
block one. See `docs/TOKENOMICS.md`. Remember the 2% max wallet is still active —
call `setLimitExempt` for any bucket wallet that needs more, or just do it after
the 24h expiry.

## 4. Add liquidity — this is the actual "listing"

```bash
ETH_LIQUIDITY=0.05 npx hardhat run scripts/add-liquidity.js --network base
```

The moment this confirms, COO is tradable on Uniswap and every Base aggregator.
Set `ETH_LIQUIDITY` to what you can afford to lose entirely. 0.02–0.1 ETH is a
normal small launch. The script prints the opening price and implied FDV before
it commits.

## 5. Lock the LP — do not skip this

The LP tokens are now in your deployer wallet. While you hold them you can pull
the pool, which means you're a rug by definition and no one sane will buy.

Two options:

- **Burn them.** Send the LP tokens to `0x000...dEaD`. Free, instant, irreversible, maximum trust.
- **Lock them.** Team Finance or UNCX, 6–12 months. Costs a small fee but you keep them eventually.

Save the transaction link. Put it on the website and in every form.

## 6. Renounce ownership

```bash
CONFIRM=RENOUNCE npx hardhat run scripts/renounce.js --network base
```

Drops the max-wallet cap permanently and sets `owner()` to the zero address.
Irreversible. After this the contract has no privileged functions at all.

## 7. Make the first buy

From a *different* wallet, buy a tiny amount on Uniswap. That first swap is
what makes DexScreener and GeckoTerminal index the pair.

## 8. Stamp the address everywhere

```bash
npm run listing:kit
```

Rewrites `web/index.html`, `listing/tokenlist.json`,
`listing/trustwallet-info.json` and `listing/FORM-ANSWERS.md` with the real
contract address. Then publish the site:

```bash
git subtree push --prefix web origin gh-pages
```

## 9. Submit the listings

Work through `docs/LISTING.md`. DexScreener happens by itself; CoinGecko is the
one that matters and it wants to see a week of real volume first.

---

## What this costs, end to end

| Item | Cost |
|---|---|
| Contract deploy on Base | ~$0.20–0.50 |
| Pool creation + approve + addLiquidity | ~$0.30–1.00 |
| Basescan verification | Free |
| Website hosting (GitHub Pages) | Free |
| DexScreener / GeckoTerminal / DEXTools basic | Free |
| CoinGecko + CoinMarketCap listing | Free |
| Liquidity itself | Whatever you choose — and it is genuinely at risk |
| **Total unavoidable spend** | **~$1–2 of gas plus your liquidity** |

## Failure modes to avoid

1. **Reusing a wallet that holds real funds.** New wallet. Always.
2. **Committing `.env`.** It's gitignored. Keep it that way.
3. **Adding liquidity before verifying.** Verify first; an unverified contract kills trust instantly.
4. **Keeping the LP tokens.** The single most common reason a launch dies.
5. **Submitting to CoinGecko on day one.** With no volume it's an automatic rejection, and re-submitting is slower than waiting.
6. **Paying anyone for a "fast track".** It does not exist.

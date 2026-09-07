# $COO Tokenomics

**Sir Reginald Coo III, Pigeon of Prosperity**

| | |
|---|---|
| Name | Sir Reginald Coo III |
| Symbol | COO |
| Chain | Base (chainId 8453) |
| Decimals | 18 |
| Total supply | 1,000,000,000 COO — fixed forever |
| Transfer tax | 0% buy / 0% sell |
| Mint function | Does not exist |
| Contract | Non-upgradeable, verified, ownership renounced |

## Distribution

| Bucket | % | Tokens | What actually happens to it |
|---|---|---|---|
| Liquidity pool | 80% | 800,000,000 | Paired with ETH on Uniswap V2. LP tokens locked or burned. |
| Community / airdrop | 10% | 100,000,000 | Given away. Early holders, memes contests, whoever shows up. |
| CEX & market making reserve | 5% | 50,000,000 | Untouched unless a real exchange asks for depth. |
| Team | 5% | 50,000,000 | One wallet, public, announced before launch. |

The full supply mints to a single treasury address at deploy. The split above
happens as plain on-chain transfers immediately afterwards, so every bucket is
auditable on Basescan from block one. Nothing is hidden in a vesting contract.

## Why 80% into liquidity

A meme coin with a thin pool is a rug waiting to happen — the deployer's 40%
bag is a permanent sword over every holder's head. Putting almost everything in
the pool means the price discovers itself and the deployer has nothing large
left to dump.

## The launch price

Opening price is entirely set by how much ETH you pair against the 800M tokens:

| ETH in pool | Price per COO | Starting FDV |
|---|---|---|
| 0.01 ETH | 1.25e-11 ETH | ~0.0125 ETH (~$40) |
| 0.05 ETH | 6.25e-11 ETH | ~0.0625 ETH (~$200) |
| 0.25 ETH | 3.13e-10 ETH | ~0.3125 ETH (~$1,000) |
| 1.00 ETH | 1.25e-09 ETH | ~1.25 ETH (~$4,000) |

Start small. A tiny pool means violent price moves, which is the actual product.

## Security posture

- **No mint.** The word `mint` appears nowhere in the public ABI. Supply is capped by physics, not by promise.
- **No tax.** There is no fee code path at all, so there is nothing to secretly turn up to 99%.
- **No blacklist, no pause.** Nobody can freeze your bag.
- **No proxy.** The bytecode you verify is the bytecode that runs until the sun dies.
- **Temporary max wallet.** 2% cap at launch to stop a single sniper eating the pool. It cannot be lowered, cannot go below 1%, and auto-expires 24 hours after deploy even if the owner vanishes.
- **Ownership renounced.** After launch, `owner()` is `0x000...000`.

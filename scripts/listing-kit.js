/**
 * Reads deployments/base.json and stamps the real contract address into every
 * listing artifact: token list, Trust Wallet info.json, the website, and each
 * submission form's copy-paste answers.
 *
 *   node scripts/listing-kit.js            (defaults to base)
 *   node scripts/listing-kit.js baseSepolia
 */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const net = process.argv[2] || "base";
const depFile = path.join(root, "deployments", `${net}.json`);

const PLACEHOLDER = "0x0000000000000000000000000000000000000000";
let dep = {
  address: PLACEHOLDER,
  chainId: net === "base" ? 8453 : 84532,
  pair: PLACEHOLDER,
  treasury: PLACEHOLDER,
};
if (fs.existsSync(depFile)) {
  dep = { ...dep, ...JSON.parse(fs.readFileSync(depFile)) };
  console.log(`  Using deployments/${net}.json → ${dep.address}`);
} else {
  console.log(`  ⚠️  No deployments/${net}.json yet — writing placeholders.`);
}

const SITE = "https://coocoin.xyz";
const outDir = path.join(root, "listing");
fs.mkdirSync(outDir, { recursive: true });

// ---------- 1. Uniswap-standard token list ----------
const tokenList = {
  name: "COO Token List",
  timestamp: new Date().toISOString(),
  version: { major: 1, minor: 0, patch: 0 },
  logoURI: `${SITE}/assets/coo-logo.png`,
  keywords: ["memecoin", "base", "coo", "pigeon"],
  tokens: [
    {
      chainId: dep.chainId,
      address: dep.address,
      name: "Sir Reginald Coo III",
      symbol: "COO",
      decimals: 18,
      logoURI: `${SITE}/assets/coo-logo.png`,
      tags: ["memecoin"],
    },
  ],
};
fs.writeFileSync(path.join(outDir, "tokenlist.json"), JSON.stringify(tokenList, null, 2));

// ---------- 2. Trust Wallet assets info.json ----------
const trustWallet = {
  name: "Sir Reginald Coo III",
  website: SITE,
  description:
    "COO is a fixed-supply, zero-tax community meme token on Base. No mint function, ownership renounced, liquidity locked. The Pigeon of Prosperity eats what it is given and asks for nothing.",
  explorer: `https://basescan.org/token/${dep.address}`,
  type: "BASE",
  symbol: "COO",
  decimals: 18,
  status: "active",
  id: dep.address,
  links: [
    { name: "twitter", url: "https://x.com/coocoinbase" },
    { name: "telegram", url: "https://t.me/coocoinbase" },
    { name: "github", url: "https://github.com/ismailchaacha97-ui/kkk" },
  ],
  tags: ["memes"],
};
fs.writeFileSync(path.join(outDir, "trustwallet-info.json"), JSON.stringify(trustWallet, null, 2));

// ---------- 3. Copy-paste answers for the submission forms ----------
const forms = `# Listing form answers — paste these verbatim

Generated ${new Date().toISOString()} from deployments/${net}.json

| Field | Value |
|---|---|
| Token name | Sir Reginald Coo III |
| Ticker / symbol | COO |
| Contract address | \`${dep.address}\` |
| Chain / platform | Base (chainId ${dep.chainId}) |
| Decimals | 18 |
| Total supply | 1,000,000,000 |
| Circulating supply | 1,000,000,000 |
| Max supply | 1,000,000,000 (fixed, no mint function) |
| Category | Meme |
| Launch date | ${dep.deployedAt ? dep.deployedAt.slice(0, 10) : "TBD"} |
| Explorer | https://basescan.org/token/${dep.address} |
| DEX pair (Uniswap V2) | \`${dep.pair}\` |
| Chart | https://dexscreener.com/base/${dep.pair} |
| Website | ${SITE} |
| Logo | ${SITE}/assets/coo-logo.png (256x256 PNG, transparent) |
| Source code | https://github.com/ismailchaacha97-ui/kkk |
| Audit | Unaudited. Contract is 120 lines, verified, non-upgradeable, zero-tax. |

## Short description (280 chars, for X bio / DexScreener)

COO is a fixed-supply, zero-tax meme token on Base. No mint function, ownership renounced, LP locked. Sir Reginald Coo III, Pigeon of Prosperity, eats what he is given.

## Long description (for CoinGecko / CMC)

Sir Reginald Coo III (COO) is a community meme token on Base. The contract is
deliberately boring: a fixed supply of 1,000,000,000 minted once at deployment,
no mint function, no transfer tax, no blacklist, no pause switch and no proxy.
The only owner privilege was a temporary anti-sniper max-wallet cap that could
never be lowered and expired automatically 24 hours after deployment; ownership
has since been renounced to the zero address and liquidity is locked.

There is no team allocation vesting schedule to argue about and no roadmap of
promised products. COO is a joke about a bird that cannot be killed, deployed
honestly, and left alone.
`;
fs.writeFileSync(path.join(outDir, "FORM-ANSWERS.md"), forms);

// ---------- 4. Stamp the address into the website ----------
const indexPath = path.join(root, "web", "index.html");
if (fs.existsSync(indexPath)) {
  let html = fs.readFileSync(indexPath, "utf8");
  html = html.replace(/0x[0-9a-fA-F]{40}/g, dep.address);
  fs.writeFileSync(indexPath, html);
  console.log(`  ✅ web/index.html stamped with ${dep.address}`);
}

console.log(`  ✅ listing/tokenlist.json`);
console.log(`  ✅ listing/trustwallet-info.json`);
console.log(`  ✅ listing/FORM-ANSWERS.md`);
console.log(`\n  Now work through docs/LISTING.md — start with DexScreener + CoinGecko.\n`);

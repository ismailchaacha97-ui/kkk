/**
 * Creates the COO/WETH pool on Uniswap V2 (Base) and adds the launch liquidity.
 * This is the moment the token becomes tradable — i.e. "listed" on every
 * Base DEX aggregator, DexScreener, DEXTools and Uniswap at once.
 *
 *   ETH_LIQUIDITY=0.05 npx hardhat run scripts/add-liquidity.js --network base
 *
 * Set LP_TOKENS to how much COO goes in the pool (default: 80% of supply).
 * Opening price = ETH_LIQUIDITY / LP_TOKENS.
 */
const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Uniswap V2 on Base — https://docs.uniswap.org/contracts/v2/reference/smart-contracts
const V2_ROUTER = { 8453: "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24" };
const V2_FACTORY = { 8453: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6" };

const ROUTER_ABI = [
  "function factory() view returns (address)",
  "function WETH() view returns (address)",
  "function addLiquidityETH(address token,uint amountTokenDesired,uint amountTokenMin,uint amountETHMin,address to,uint deadline) payable returns (uint amountToken,uint amountETH,uint liquidity)",
];
const FACTORY_ABI = [
  "function getPair(address,address) view returns (address)",
  "function createPair(address,address) returns (address)",
];

async function main() {
  const chainId = network.config.chainId;
  const router = V2_ROUTER[chainId];
  if (!router) throw new Error(`No Uniswap V2 router configured for chainId ${chainId}. Base mainnet only.`);

  const file = path.join(__dirname, "..", "deployments", `${network.name}.json`);
  if (!fs.existsSync(file)) throw new Error(`Deploy first — ${file} not found.`);
  const dep = JSON.parse(fs.readFileSync(file));

  const [signer] = await ethers.getSigners();
  const coo = await ethers.getContractAt("Coo", dep.address, signer);

  const ethIn = ethers.parseEther(process.env.ETH_LIQUIDITY || "0.05");
  const supply = await coo.totalSupply();
  const tokensIn = process.env.LP_TOKENS
    ? ethers.parseEther(process.env.LP_TOKENS)
    : (supply * 80n) / 100n;

  const bal = await coo.balanceOf(signer.address);
  if (bal < tokensIn) throw new Error(`Signer holds ${ethers.formatEther(bal)} COO, needs ${ethers.formatEther(tokensIn)}.`);

  console.log(`\n  Pool:  ${ethers.formatEther(tokensIn)} COO  +  ${ethers.formatEther(ethIn)} ETH`);
  const priceEth = Number(ethers.formatEther(ethIn)) / Number(ethers.formatEther(tokensIn));
  console.log(`  Opening price: ${priceEth.toExponential(4)} ETH per COO`);
  console.log(`  Implied FDV:   ${(priceEth * 1e9).toFixed(4)} ETH\n`);

  const routerC = new ethers.Contract(router, ROUTER_ABI, signer);
  const weth = await routerC.WETH();
  const factory = new ethers.Contract(V2_FACTORY[chainId], FACTORY_ABI, signer);

  let pair = await factory.getPair(dep.address, weth);
  if (pair === ethers.ZeroAddress) {
    console.log("  Creating COO/WETH pair...");
    await (await factory.createPair(dep.address, weth)).wait();
    pair = await factory.getPair(dep.address, weth);
  }
  console.log(`  Pair: ${pair}`);

  // The pair and router must bypass the max-wallet cap, or addLiquidity reverts.
  if (await coo.limitsActive()) {
    for (const [label, addr] of [["pair", pair], ["router", router]]) {
      if (!(await coo.isLimitExempt(addr))) {
        console.log(`  Exempting ${label} from max wallet...`);
        await (await coo.setLimitExempt(addr, true)).wait();
      }
    }
  }

  console.log("  Approving router...");
  await (await coo.approve(router, tokensIn)).wait();

  console.log("  Adding liquidity...");
  const deadline = Math.floor(Date.now() / 1000) + 20 * 60;
  const tx = await routerC.addLiquidityETH(
    dep.address,
    tokensIn,
    (tokensIn * 99n) / 100n,
    (ethIn * 99n) / 100n,
    signer.address,
    deadline,
    { value: ethIn }
  );
  const rc = await tx.wait();

  console.log(`\n  ✅ Liquidity live — tx ${rc.hash}`);
  console.log(`  Chart:  https://dexscreener.com/base/${pair}`);
  console.log(`  Trade:  https://app.uniswap.org/swap?outputCurrency=${dep.address}&chain=base`);

  dep.pair = pair;
  dep.router = router;
  dep.liquidityTx = rc.hash;
  dep.dexscreenerPair = `https://dexscreener.com/base/${pair}`;
  fs.writeFileSync(file, JSON.stringify(dep, null, 2));

  console.log(`\n  ⚠️  NOW, in this order:`);
  console.log(`     1. Lock or burn the LP tokens at ${pair}`);
  console.log(`     2. npx hardhat run scripts/renounce.js --network ${network.name}`);
  console.log(`     3. npm run listing:kit  → submit the forms\n`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

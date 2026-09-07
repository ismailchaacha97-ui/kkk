/**
 * Deploys $COO and writes the artifact needed by every listing form.
 *
 *   npx hardhat run scripts/deploy.js --network baseSepolia   (free, do this first)
 *   npx hardhat run scripts/deploy.js --network base          (real, ~$0.30 of gas)
 */
const { ethers, network, run } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();
  if (!deployer) throw new Error("No PRIVATE_KEY in .env — nothing to deploy with.");

  const treasury = process.env.TREASURY_ADDRESS || deployer.address;
  const balance = await ethers.provider.getBalance(deployer.address);

  console.log(`\n  Network   ${network.name} (chainId ${network.config.chainId})`);
  console.log(`  Deployer  ${deployer.address}`);
  console.log(`  Balance   ${ethers.formatEther(balance)} ETH`);
  console.log(`  Treasury  ${treasury}\n`);

  if (balance === 0n) throw new Error("Deployer has 0 ETH. Fund it first.");

  const Coo = await ethers.getContractFactory("Coo");
  const coo = await Coo.deploy(treasury, deployer.address);
  console.log(`  tx sent   ${coo.deploymentTransaction().hash}`);
  await coo.waitForDeployment();

  const address = await coo.getAddress();
  const receipt = await coo.deploymentTransaction().wait();

  console.log(`\n  ✅ $COO live at ${address}`);
  console.log(`  gas used  ${receipt.gasUsed.toString()}`);
  console.log(`  supply    ${ethers.formatEther(await coo.totalSupply())} COO -> ${treasury}`);

  const explorer =
    network.config.chainId === 8453
      ? "https://basescan.org"
      : "https://sepolia.basescan.org";

  const out = {
    name: await coo.name(),
    symbol: await coo.symbol(),
    decimals: 18,
    address,
    chainId: network.config.chainId,
    network: network.name,
    deployer: deployer.address,
    treasury,
    totalSupply: (await coo.totalSupply()).toString(),
    deployTx: coo.deploymentTransaction().hash,
    blockNumber: receipt.blockNumber,
    deployedAt: new Date().toISOString(),
    explorer: `${explorer}/token/${address}`,
    dexscreener: `https://dexscreener.com/base/${address}`,
    uniswap: `https://app.uniswap.org/swap?outputCurrency=${address}&chain=base`,
  };

  const dir = path.join(__dirname, "..", "deployments");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${network.name}.json`), JSON.stringify(out, null, 2));
  console.log(`\n  📝 saved deployments/${network.name}.json`);

  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("\n  ⏳ waiting 6 blocks before verifying...");
    await coo.deploymentTransaction().wait(6);
    try {
      await run("verify:verify", { address, constructorArguments: [treasury, deployer.address] });
      console.log("  ✅ source verified on Basescan");
    } catch (e) {
      console.log(`  ⚠️  verify failed (${e.message.split("\n")[0]}) — rerun:`);
      console.log(`     npx hardhat verify --network ${network.name} ${address} ${treasury} ${deployer.address}`);
    }
  }

  console.log(`\n  Next: npx hardhat run scripts/add-liquidity.js --network ${network.name}\n`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

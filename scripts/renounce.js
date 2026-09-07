/**
 * The trust ritual: drop the max-wallet cap, then renounce ownership forever.
 * Run this AFTER liquidity is in and LP is locked. It cannot be undone.
 *
 *   CONFIRM=RENOUNCE npx hardhat run scripts/renounce.js --network base
 */
const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  if (process.env.CONFIRM !== "RENOUNCE") {
    throw new Error('Safety catch. Rerun with CONFIRM=RENOUNCE prefixed to the command.');
  }

  const file = path.join(__dirname, "..", "deployments", `${network.name}.json`);
  const dep = JSON.parse(fs.readFileSync(file));
  const [signer] = await ethers.getSigners();
  const coo = await ethers.getContractAt("Coo", dep.address, signer);

  if ((await coo.owner()) === ethers.ZeroAddress) {
    console.log("  Already renounced. Nothing to do.");
    return;
  }

  if ((await coo.maxWallet()) !== 0n) {
    console.log("  Removing limits forever...");
    await (await coo.removeLimits()).wait();
  }

  console.log("  Renouncing ownership...");
  const rc = await (await coo.renounceOwnership()).wait();

  console.log(`\n  ✅ Owner is now 0x000...000 — tx ${rc.hash}`);
  console.log(`     maxWallet:     ${await coo.maxWallet()}`);
  console.log(`     limitsActive:  ${await coo.limitsActive()}`);
  console.log(`     owner:         ${await coo.owner()}`);

  dep.renounceTx = rc.hash;
  dep.renouncedAt = new Date().toISOString();
  fs.writeFileSync(file, JSON.stringify(dep, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

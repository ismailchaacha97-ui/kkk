/**
 * Preflight. Run this before spending a cent.
 *   npx hardhat run scripts/preflight.js --network base
 */
const { ethers, network } = require("hardhat");

const ok = (m) => console.log(`  ✅ ${m}`);
const bad = (m) => console.log(`  ❌ ${m}`);
const warn = (m) => console.log(`  ⚠️  ${m}`);

async function main() {
  console.log(`\n  Preflight — ${network.name}\n`);
  let fatal = 0;

  if (!process.env.PRIVATE_KEY) {
    bad("PRIVATE_KEY missing from .env"); fatal++;
  } else if (!/^0x[0-9a-fA-F]{64}$/.test(process.env.PRIVATE_KEY)) {
    bad("PRIVATE_KEY must be 0x + 64 hex chars"); fatal++;
  } else ok("PRIVATE_KEY looks well formed");

  if (!process.env.BASESCAN_API_KEY) warn("BASESCAN_API_KEY missing — contract won't auto-verify");
  else ok("BASESCAN_API_KEY present");

  let block;
  try {
    block = await ethers.provider.getBlockNumber();
    ok(`RPC reachable, head block ${block}`);
  } catch (e) {
    bad(`RPC unreachable: ${e.message.split("\n")[0]}`); fatal++;
  }

  const [signer] = await ethers.getSigners();
  if (signer && block !== undefined) {
    const bal = await ethers.provider.getBalance(signer.address);
    console.log(`\n  Deployer ${signer.address}`);
    console.log(`  Balance  ${ethers.formatEther(bal)} ETH`);

    const Coo = await ethers.getContractFactory("Coo");
    const data = (await Coo.getDeployTransaction(signer.address, signer.address)).data;
    try {
      const gas = await ethers.provider.estimateGas({ from: signer.address, data });
      const fee = await ethers.provider.getFeeData();
      const cost = gas * (fee.maxFeePerGas ?? fee.gasPrice ?? 0n);
      console.log(`  Deploy gas ~${gas} → ~${ethers.formatEther(cost)} ETH`);
      if (bal < cost * 2n) { bad("Balance too thin. Top up."); fatal++; }
      else ok("Balance covers deployment with headroom");
    } catch {
      warn("Could not estimate gas (usually means 0 balance)");
      if (bal === 0n) fatal++;
    }
  }

  const bytecode = (await ethers.getContractFactory("Coo")).bytecode;
  const kb = (bytecode.length / 2 - 1) / 1024;
  console.log(`\n  Bytecode ${kb.toFixed(2)} KB / 24.00 KB limit`);
  kb < 24 ? ok("Under EIP-170 size limit") : bad("Over size limit");

  console.log(fatal === 0 ? "\n  🕊️  Cleared for launch.\n" : `\n  🛑 ${fatal} blocker(s). Fix before deploying.\n`);
  if (fatal) process.exitCode = 1;
}

main().catch((e) => { console.error(e); process.exitCode = 1; });

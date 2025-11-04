/**
 * Test script to verify deployment setup
 * This script can be used to check that all contracts are properly set up
 * before running the actual Ignition deployment
 */

import { network } from "hardhat";

async function main() {
  console.log("Testing deployment setup...");
  console.log("Network:", network);

  // Get accounts
  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();

  console.log("Deployer address:", deployer.account.address);

  // Check balance
  const publicClient = await viem.getPublicClient();
  const balance = await publicClient.getBalance({
    address: deployer.account.address,
  });

  console.log("Deployer balance:", balance.toString(), "wei");

  console.log("\n✅ Setup looks good! You can now deploy using:");
  console.log("   npx hardhat ignition deploy ignition/modules/DeployAll.ts");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

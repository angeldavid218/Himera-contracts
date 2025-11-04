import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("RouterModule", (m) => {
  // Get deployer address
  const deployer = m.getAccount(0);

  // Deploy all contracts in order
  // 1. Deploy HimeraToken
  const himeraToken = m.contract("HimeraToken", [deployer, deployer]);

  // 2. Deploy LiquidityPool (depends on HimeraToken)
  const liquidityPool = m.contract("LiquidityPool", [himeraToken, deployer]);

  // 3. Deploy Router (depends on LiquidityPool)
  // Constructor parameters: (address _pool, address _initialOwner)
  const router = m.contract("Router", [liquidityPool, deployer]);

  return { himeraToken, liquidityPool, router };
});

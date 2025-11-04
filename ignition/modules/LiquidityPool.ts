import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("LiquidityPoolModule", (m) => {
  // Get deployer address
  const deployer = m.getAccount(0);

  // First deploy HimeraToken
  const himeraToken = m.contract("HimeraToken", [deployer, deployer]);

  // Then deploy LiquidityPool with token address and owner
  // Constructor parameters: (address _token, address _initialOwner)
  const liquidityPool = m.contract("LiquidityPool", [himeraToken, deployer]);

  return { himeraToken, liquidityPool };
});

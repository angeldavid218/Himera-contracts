import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HimeraTokenModule", (m) => {
  // Get deployer address - will be set automatically by Hardhat
  const deployer = m.getAccount(0);

  // Deploy HimeraToken
  // Constructor parameters: (address recipient, address initialOwner)
  // For testing, we'll mint initial tokens to the deployer and set deployer as owner
  const himeraToken = m.contract("HimeraToken", [deployer, deployer]);

  return { himeraToken };
});

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Comprehensive deployment module for the entire DEX system
 * Deploys: HimeraToken -> LiquidityPool -> Router
 * Optionally adds initial liquidity to the pool
 */
export default buildModule("DeployAllModule", (m) => {
  // Get deployer address
  const deployer = m.getAccount(0);

  // Step 1: Deploy HimeraToken
  // Constructor: (address recipient, address initialOwner)
  // Mint 1000 tokens to deployer and set deployer as owner
  const himeraToken = m.contract("HimeraToken", [deployer, deployer]);

  // Step 2: Deploy LiquidityPool
  // Constructor: (address _token, address _initialOwner)
  const liquidityPool = m.contract("LiquidityPool", [himeraToken, deployer]);

  // Step 3: Deploy Router
  // Constructor: (address _pool, address _initialOwner)
  const router = m.contract("Router", [liquidityPool, deployer]);

  // Optional: Add initial liquidity to the pool
  // Uncomment and adjust amounts as needed for testing
  // Note: This requires the deployer to have approved the router for tokens
  // and sent ETH with the transaction

  // Example: Add 1 ETH and equivalent tokens
  // 1 ETH = 1 * 10^18 wei
  const initialETH = 1n * 10n ** 18n; // 1 ETH in wei
  // 1000 tokens (assuming 18 decimals)
  const initialTokens = 1000n * 10n ** 18n; // Adjust based on your desired ratio

  // Approve router to spend tokens (if needed)
  m.call(himeraToken, "approve", [router, initialTokens]);

  // Add liquidity through router
  // Note: addLiquidity is payable, so we pass value in the options
  m.call(
    router,
    "addLiquidity",
    [initialTokens, 0n, 0n], // tokenAmount, minTokenAmount, minETHAmount
    {
      value: initialETH, // Send ETH with the transaction
    }
  );

  return {
    himeraToken,
    liquidityPool,
    router,
  };
});

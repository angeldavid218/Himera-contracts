// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./LiquidityPool.sol";

/**
 * @title Router
 * @dev Router contract for interacting with LiquidityPool
 * Handles token approvals, calculates minimum amounts, and provides convenient swap/liquidity functions
 */
contract Router is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Events
    event LiquidityAdded(
        address indexed provider,
        address indexed pool,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityTokens
    );

    event LiquidityRemoved(
        address indexed provider,
        address indexed pool,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityTokens
    );

    event SwapExecuted(
        address indexed user,
        address indexed pool,
        uint256 amountIn,
        uint256 amountOut
    );

    // Immutable pool address
    LiquidityPool public immutable pool;
    IERC20 public immutable token;

    /**
     * @dev Constructor
     * @param _pool Address of the LiquidityPool contract
     * @param _initialOwner Address of the initial owner
     */
    constructor(address _pool, address _initialOwner) Ownable(_initialOwner) {
        require(_pool != address(0), "Router: invalid pool address");
        pool = LiquidityPool(payable(_pool));
        token = IERC20(LiquidityPool(payable(_pool)).token());
    }

    /**
     * @dev Add liquidity to the pool
     * @param tokenAmount Desired amount of tokens to add
     * @param minTokenAmount Minimum token amount to add (slippage protection)
     * @param minETHAmount Minimum ETH amount to add (slippage protection)
     * @return ethAmount Actual ETH amount added
     * @return actualTokenAmount Actual token amount added
     * @return liquidityTokens Amount of LP tokens minted
     */
    function addLiquidity(
        uint256 tokenAmount,
        uint256 minTokenAmount,
        uint256 minETHAmount
    )
        external
        payable
        nonReentrant
        returns (
            uint256 ethAmount,
            uint256 actualTokenAmount,
            uint256 liquidityTokens
        )
    {
        require(msg.value > 0, "Router: ETH amount must be greater than 0");
        require(tokenAmount > 0, "Router: token amount must be greater than 0");

        // Transfer tokens from user to this contract
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Approve pool to spend tokens
        uint256 currentAllowance = token.allowance(address(this), address(pool));
        if (currentAllowance < tokenAmount) {
            if (currentAllowance > 0) {
                token.safeDecreaseAllowance(address(pool), currentAllowance);
            }
            token.safeIncreaseAllowance(address(pool), tokenAmount);
        }

        // Calculate optimal token amount based on reserves
        (uint256 reserveETH, uint256 reserveToken) = pool.getReserves();
        
        if (reserveETH == 0 && reserveToken == 0) {
            // First liquidity provision - use full amounts
            actualTokenAmount = tokenAmount;
            ethAmount = msg.value;
        } else {
            // Calculate optimal amounts to maintain ratio
            uint256 optimalTokenAmount = (msg.value * reserveToken) / reserveETH;
            
            if (tokenAmount >= optimalTokenAmount) {
                actualTokenAmount = optimalTokenAmount;
                ethAmount = msg.value;
            } else {
                actualTokenAmount = tokenAmount;
                ethAmount = (actualTokenAmount * reserveETH) / reserveToken;
                require(ethAmount <= msg.value, "Router: insufficient ETH");
                
                // Refund excess ETH
                if (ethAmount < msg.value) {
                    payable(msg.sender).transfer(msg.value - ethAmount);
                }
            }
        }

        require(actualTokenAmount >= minTokenAmount, "Router: insufficient token amount");
        require(ethAmount >= minETHAmount, "Router: insufficient ETH amount");

        // Call pool's addLiquidity
        (ethAmount, actualTokenAmount, liquidityTokens) = pool.addLiquidity{value: ethAmount}(
            actualTokenAmount
        );

        // Refund unused tokens if any
        uint256 remainingTokens = tokenAmount - actualTokenAmount;
        if (remainingTokens > 0) {
            token.safeTransfer(msg.sender, remainingTokens);
        }

        // Reset approval
        uint256 remainingAllowance = token.allowance(address(this), address(pool));
        if (remainingAllowance > 0) {
            token.safeDecreaseAllowance(address(pool), remainingAllowance);
        }

        emit LiquidityAdded(msg.sender, address(pool), ethAmount, actualTokenAmount, liquidityTokens);
    }

    /**
     * @dev Remove liquidity from the pool
     * Note: Users must approve this router as an operator in the pool before calling this function
     * Call pool.approveOperator(routerAddress, true) first
     * @param liquidityTokens Amount of LP tokens to burn
     * @param minETHAmount Minimum ETH amount expected (slippage protection)
     * @param minTokenAmount Minimum token amount expected (slippage protection)
     * @return ethAmount Amount of ETH returned
     * @return tokenAmount Amount of tokens returned
     */
    function removeLiquidity(
        uint256 liquidityTokens,
        uint256 minETHAmount,
        uint256 minTokenAmount
    ) external nonReentrant returns (uint256 ethAmount, uint256 tokenAmount) {
        require(liquidityTokens > 0, "Router: liquidity amount must be greater than 0");

        // Check user has enough LP tokens
        require(
            pool.balanceOf(msg.sender) >= liquidityTokens,
            "Router: insufficient liquidity tokens"
        );

        // Calculate expected amounts for slippage protection
        (uint256 reserveETH, uint256 reserveToken) = pool.getReserves();
        uint256 totalSupply = pool.totalSupply();
        
        uint256 expectedETH = (liquidityTokens * reserveETH) / totalSupply;
        uint256 expectedToken = (liquidityTokens * reserveToken) / totalSupply;

        require(expectedETH >= minETHAmount, "Router: insufficient ETH amount");
        require(expectedToken >= minTokenAmount, "Router: insufficient token amount");

        // Call pool's removeLiquidityFor to remove liquidity on behalf of the user
        // This requires the user to have approved this router as an operator
        (ethAmount, tokenAmount) = pool.removeLiquidityFor(
            msg.sender,
            liquidityTokens,
            msg.sender
        );
        
        require(ethAmount >= minETHAmount, "Router: insufficient ETH returned");
        require(tokenAmount >= minTokenAmount, "Router: insufficient token returned");

        emit LiquidityRemoved(msg.sender, address(pool), ethAmount, tokenAmount, liquidityTokens);
    }

    /**
     * @dev Swap exact tokens for tokens (HIM -> ETH or ETH -> HIM)
     * This function handles the swap and calculates amountOutMin automatically with slippage
     * @param amountIn Exact amount of input tokens
     * @param amountOutMin Minimum amount of output tokens expected (slippage protection)
     * @param swapETHForToken If true, swap ETH for tokens; if false, swap tokens for ETH
     * @return amountOut Amount of tokens/ETH received
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool swapETHForToken
    ) external payable nonReentrant returns (uint256 amountOut) {
        if (swapETHForToken) {
            // Swap ETH for tokens
            require(msg.value == amountIn, "Router: ETH amount mismatch");
            require(msg.value > 0, "Router: ETH amount must be greater than 0");
            
            // Get quote to validate amountOutMin is reasonable
            uint256 quote = pool.getETHToTokenQuote(msg.value);
            require(quote >= amountOutMin, "Router: amountOutMin too high");
            
            // Execute swap
            amountOut = pool.swapETHForTokens{value: msg.value}(amountOutMin);
        } else {
            // Swap tokens for ETH
            require(msg.value == 0, "Router: should not send ETH for token->ETH swap");
            require(amountIn > 0, "Router: token amount must be greater than 0");
            
            // Transfer tokens from user to this contract
            token.safeTransferFrom(msg.sender, address(this), amountIn);
            
            // Approve pool to spend tokens
            uint256 currentAllowance = token.allowance(address(this), address(pool));
            if (currentAllowance < amountIn) {
                if (currentAllowance > 0) {
                    token.safeDecreaseAllowance(address(pool), currentAllowance);
                }
                token.safeIncreaseAllowance(address(pool), amountIn);
            }
            
            // Get quote to validate amountOutMin is reasonable
            uint256 quote = pool.getTokenToETHQuote(amountIn);
            require(quote >= amountOutMin, "Router: amountOutMin too high");
            
            // Execute swap
            amountOut = pool.swapTokensForETH(amountIn, amountOutMin);
            
            // Reset approval
            uint256 remainingAllowance2 = token.allowance(address(this), address(pool));
            if (remainingAllowance2 > 0) {
                token.safeDecreaseAllowance(address(pool), remainingAllowance2);
            }
            
            // Transfer ETH to user
            payable(msg.sender).transfer(amountOut);
        }

        emit SwapExecuted(msg.sender, address(pool), amountIn, amountOut);
    }

    /**
     * @dev Swap exact ETH for tokens with automatic slippage calculation
     * @param amountOutMin Minimum tokens expected (calculated with slippage tolerance)
     * @return amountOut Amount of tokens received
     */
    function swapExactETHForTokens(uint256 amountOutMin)
        external
        payable
        nonReentrant
        returns (uint256 amountOut)
    {
        require(msg.value > 0, "Router: ETH amount must be greater than 0");
        
        amountOut = pool.swapETHForTokens{value: msg.value}(amountOutMin);
        
        emit SwapExecuted(msg.sender, address(pool), msg.value, amountOut);
    }

    /**
     * @dev Swap exact tokens for ETH with automatic slippage calculation
     * @param amountIn Exact amount of tokens to swap
     * @param amountOutMin Minimum ETH expected (calculated with slippage tolerance)
     * @return amountOut Amount of ETH received
     */
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "Router: token amount must be greater than 0");
        
        // Transfer tokens from user to this contract
        token.safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Approve pool to spend tokens
        uint256 currentAllowance = token.allowance(address(this), address(pool));
        if (currentAllowance < amountIn) {
            if (currentAllowance > 0) {
                token.safeDecreaseAllowance(address(pool), currentAllowance);
            }
            token.safeIncreaseAllowance(address(pool), amountIn);
        }
        
        // Execute swap
        amountOut = pool.swapTokensForETH(amountIn, amountOutMin);
        
        // Reset approval
        uint256 remainingAllowance = token.allowance(address(this), address(pool));
        if (remainingAllowance > 0) {
            token.safeDecreaseAllowance(address(pool), remainingAllowance);
        }
        
        // Transfer ETH to user
        payable(msg.sender).transfer(amountOut);
        
        emit SwapExecuted(msg.sender, address(pool), amountIn, amountOut);
    }

    /**
     * @dev Calculate minimum output amount based on slippage tolerance
     * @param amountIn Input amount
     * @param slippageBps Slippage tolerance in basis points (100 = 1%)
     * @param swapETHForToken If true, calculate for ETH->Token swap; if false, Token->ETH
     * @return amountOutMin Minimum output amount
     */
    function calculateAmountOutMin(
        uint256 amountIn,
        uint256 slippageBps,
        bool swapETHForToken
    ) external view returns (uint256 amountOutMin) {
        require(slippageBps <= 10000, "Router: slippage too high");
        require(amountIn > 0, "Router: amountIn must be greater than 0");

        uint256 quote;
        if (swapETHForToken) {
            quote = pool.getETHToTokenQuote(amountIn);
        } else {
            quote = pool.getTokenToETHQuote(amountIn);
        }

        require(quote > 0, "Router: insufficient liquidity");
        
        // Calculate minimum with slippage: amountOutMin = quote * (10000 - slippageBps) / 10000
        amountOutMin = (quote * (10000 - slippageBps)) / 10000;
    }

    /**
     * @dev Get quote for swap with automatic slippage calculation
     * @param amountIn Input amount
     * @param slippageBps Slippage tolerance in basis points
     * @param swapETHForToken If true, quote ETH->Token; if false, Token->ETH
     * @return quote Expected output amount
     * @return amountOutMin Minimum output amount with slippage
     */
    function getQuoteWithSlippage(
        uint256 amountIn,
        uint256 slippageBps,
        bool swapETHForToken
    ) external view returns (uint256 quote, uint256 amountOutMin) {
        require(slippageBps <= 10000, "Router: slippage too high");
        require(amountIn > 0, "Router: amountIn must be greater than 0");

        if (swapETHForToken) {
            quote = pool.getETHToTokenQuote(amountIn);
        } else {
            quote = pool.getTokenToETHQuote(amountIn);
        }

        if (quote > 0) {
            amountOutMin = (quote * (10000 - slippageBps)) / 10000;
        }
    }

    /**
     * @dev Calculate optimal amounts for adding liquidity
     * @param ethAmount Desired ETH amount
     * @param tokenAmount Desired token amount
     * @return optimalETH Optimal ETH amount to use
     * @return optimalToken Optimal token amount to use
     */
    function calculateOptimalAmounts(uint256 ethAmount, uint256 tokenAmount)
        external
        view
        returns (uint256 optimalETH, uint256 optimalToken)
    {
        (uint256 reserveETH, uint256 reserveToken) = pool.getReserves();
        
        if (reserveETH == 0 || reserveToken == 0) {
            // First liquidity provision
            optimalETH = ethAmount;
            optimalToken = tokenAmount;
        } else {
            // Calculate optimal amounts to maintain ratio
            uint256 optimalTokenAmount = (ethAmount * reserveToken) / reserveETH;
            
            if (tokenAmount >= optimalTokenAmount) {
                optimalETH = ethAmount;
                optimalToken = optimalTokenAmount;
            } else {
                optimalETH = (tokenAmount * reserveETH) / reserveToken;
                optimalToken = tokenAmount;
            }
        }
    }

    /**
     * @dev Receive ETH
     */
    receive() external payable {
        // Allow receiving ETH for swaps
    }
}

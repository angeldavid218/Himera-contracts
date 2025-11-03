// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LiquidityPool
 * @dev A simple liquidity pool implementing constant product formula (x * y = k)
 * Allows swapping between ETH and HIM token, and adding/removing liquidity
 */
contract LiquidityPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Events
    event LiquidityAdded(
        address indexed provider,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityTokens
    );
    
    event LiquidityRemoved(
        address indexed provider,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityTokens
    );
    
    event Swap(
        address indexed sender,
        uint256 ethIn,
        uint256 tokenIn,
        uint256 ethOut,
        uint256 tokenOut
    );

    // Token contract address (HIM token)
    IERC20 public immutable token;
    
    // Reserve balances
    uint256 public reserveETH;
    uint256 public reserveToken;
    
    // Total liquidity tokens (LP tokens)
    uint256 public totalSupply;
    
    // Mapping of LP token balances
    mapping(address => uint256) public balanceOf;

    /**
     * @dev Constructor
     * @param _token Address of the ERC20 token (HIM token)
     * @param _initialOwner Address of the initial owner
     */
    constructor(address _token, address _initialOwner) Ownable(_initialOwner) {
        require(_token != address(0), "LiquidityPool: invalid token address");
        token = IERC20(_token);
    }

    /**
     * @dev Adds liquidity to the pool
     * @param tokenAmount Desired amount of tokens to add
     * @return ethAmount Actual ETH amount added
     * @return actualTokenAmount Actual token amount added
     * @return liquidityTokens Amount of LP tokens minted
     */
    function addLiquidity(uint256 tokenAmount)
        external
        payable
        nonReentrant
        returns (
            uint256 ethAmount,
            uint256 actualTokenAmount,
            uint256 liquidityTokens
        )
    {
        require(msg.value > 0, "LiquidityPool: ETH amount must be greater than 0");
        require(tokenAmount > 0, "LiquidityPool: token amount must be greater than 0");

        uint256 _reserveETH = reserveETH;
        uint256 _reserveToken = reserveToken;

        if (_reserveETH == 0 && _reserveToken == 0) {
            // First liquidity provision
            ethAmount = msg.value;
            actualTokenAmount = tokenAmount;
            
            // Transfer tokens from user
            token.safeTransferFrom(msg.sender, address(this), actualTokenAmount);
            
            // Mint initial LP tokens (sqrt(ethAmount * tokenAmount) - MINIMUM_LIQUIDITY)
            // Following Uniswap V2 pattern with minimum liquidity
            liquidityTokens = _sqrt(ethAmount * actualTokenAmount) - 1000; // MINIMUM_LIQUIDITY = 1000
            require(liquidityTokens > 0, "LiquidityPool: insufficient liquidity minted");
            
            // Update reserves
            reserveETH = ethAmount;
            reserveToken = actualTokenAmount;
            
            // Mint LP tokens (send MINIMUM_LIQUIDITY to zero address to lock it)
            _mint(address(0), 1000);
            _mint(msg.sender, liquidityTokens);
        } else {
            // Calculate optimal amounts based on current ratio
            ethAmount = msg.value;
            uint256 optimalTokenAmount = (ethAmount * _reserveToken) / _reserveETH;
            
            if (tokenAmount >= optimalTokenAmount) {
                // Use optimal amount
                actualTokenAmount = optimalTokenAmount;
                ethAmount = msg.value;
                
                // Refund excess ETH if any (shouldn't happen but safety check)
                if (ethAmount < msg.value) {
                    payable(msg.sender).transfer(msg.value - ethAmount);
                }
            } else {
                // Token amount is limiting factor
                actualTokenAmount = tokenAmount;
                ethAmount = (actualTokenAmount * _reserveETH) / _reserveToken;
                require(ethAmount <= msg.value, "LiquidityPool: insufficient ETH");
                
                // Refund excess ETH
                if (ethAmount < msg.value) {
                    payable(msg.sender).transfer(msg.value - ethAmount);
                }
            }
            
            // Transfer tokens from user
            token.safeTransferFrom(msg.sender, address(this), actualTokenAmount);
            
            // Calculate liquidity tokens to mint
            uint256 liquidityETH = (ethAmount * totalSupply) / _reserveETH;
            uint256 liquidityToken = (actualTokenAmount * totalSupply) / _reserveToken;
            liquidityTokens = liquidityETH < liquidityToken ? liquidityETH : liquidityToken;
            
            require(liquidityTokens > 0, "LiquidityPool: insufficient liquidity minted");
            
            // Update reserves
            reserveETH += ethAmount;
            reserveToken += actualTokenAmount;
            
            // Mint LP tokens
            _mint(msg.sender, liquidityTokens);
        }

        emit LiquidityAdded(msg.sender, ethAmount, actualTokenAmount, liquidityTokens);
    }

    /**
     * @dev Removes liquidity from the pool
     * @param liquidityTokens Amount of LP tokens to burn
     * @return ethAmount Amount of ETH returned
     * @return tokenAmount Amount of tokens returned
     */
    function removeLiquidity(uint256 liquidityTokens)
        external
        nonReentrant
        returns (uint256 ethAmount, uint256 tokenAmount)
    {
        require(liquidityTokens > 0, "LiquidityPool: liquidity amount must be greater than 0");
        require(balanceOf[msg.sender] >= liquidityTokens, "LiquidityPool: insufficient liquidity tokens");

        uint256 _totalSupply = totalSupply;
        require(_totalSupply > 0, "LiquidityPool: no liquidity to remove");

        // Calculate amounts to return
        ethAmount = (liquidityTokens * reserveETH) / _totalSupply;
        tokenAmount = (liquidityTokens * reserveToken) / _totalSupply;

        require(ethAmount > 0 && tokenAmount > 0, "LiquidityPool: insufficient liquidity burned");

        // Burn LP tokens
        _burn(msg.sender, liquidityTokens);

        // Update reserves
        reserveETH -= ethAmount;
        reserveToken -= tokenAmount;

        // Transfer ETH and tokens to user
        payable(msg.sender).transfer(ethAmount);
        token.safeTransfer(msg.sender, tokenAmount);

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount, liquidityTokens);
    }

    /**
     * @dev Swaps ETH for tokens
     * @param minTokensOut Minimum tokens expected (slippage protection)
     * @return tokensOut Amount of tokens received
     */
    function swapETHForTokens(uint256 minTokensOut)
        external
        payable
        nonReentrant
        returns (uint256 tokensOut)
    {
        require(msg.value > 0, "LiquidityPool: ETH amount must be greater than 0");
        
        uint256 _reserveETH = reserveETH;
        uint256 _reserveToken = reserveToken;
        
        require(_reserveETH > 0 && _reserveToken > 0, "LiquidityPool: insufficient liquidity");

        // Calculate tokens out using constant product formula
        // k = reserveETH * reserveToken
        // newReserveETH = reserveETH + ethIn
        // newReserveToken = k / newReserveETH
        // tokensOut = reserveToken - newReserveToken
        uint256 ethIn = msg.value;
        uint256 ethInWithFee = ethIn * 997; // 0.3% fee (1000 - 3 = 997)
        uint256 numerator = ethInWithFee * _reserveToken;
        uint256 denominator = (_reserveETH * 1000) + ethInWithFee;
        tokensOut = numerator / denominator;

        require(tokensOut >= minTokensOut, "LiquidityPool: insufficient output amount");
        require(tokensOut <= _reserveToken, "LiquidityPool: insufficient liquidity");

        // Update reserves
        reserveETH = _reserveETH + ethIn;
        reserveToken = _reserveToken - tokensOut;

        // Transfer tokens to user
        token.safeTransfer(msg.sender, tokensOut);

        emit Swap(msg.sender, ethIn, 0, 0, tokensOut);
    }

    /**
     * @dev Swaps tokens for ETH
     * @param tokenAmountIn Amount of tokens to swap
     * @param minETHOut Minimum ETH expected (slippage protection)
     * @return ethOut Amount of ETH received
     */
    function swapTokensForETH(uint256 tokenAmountIn, uint256 minETHOut)
        external
        nonReentrant
        returns (uint256 ethOut)
    {
        require(tokenAmountIn > 0, "LiquidityPool: token amount must be greater than 0");
        
        uint256 _reserveETH = reserveETH;
        uint256 _reserveToken = reserveToken;
        
        require(_reserveETH > 0 && _reserveToken > 0, "LiquidityPool: insufficient liquidity");

        // Transfer tokens from user
        token.safeTransferFrom(msg.sender, address(this), tokenAmountIn);

        // Calculate ETH out using constant product formula
        // k = reserveETH * reserveToken
        // newReserveToken = reserveToken + tokenIn
        // newReserveETH = k / newReserveToken
        // ethOut = reserveETH - newReserveETH
        uint256 tokenInWithFee = tokenAmountIn * 997; // 0.3% fee
        uint256 numerator = tokenInWithFee * _reserveETH;
        uint256 denominator = (_reserveToken * 1000) + tokenInWithFee;
        ethOut = numerator / denominator;

        require(ethOut >= minETHOut, "LiquidityPool: insufficient output amount");
        require(ethOut <= _reserveETH, "LiquidityPool: insufficient liquidity");

        // Update reserves
        reserveETH = _reserveETH - ethOut;
        reserveToken = _reserveToken + tokenAmountIn;

        // Transfer ETH to user
        payable(msg.sender).transfer(ethOut);

        emit Swap(msg.sender, 0, tokenAmountIn, ethOut, 0);
    }

    /**
     * @dev Get the current reserves
     * @return _reserveETH Current ETH reserve
     * @return _reserveToken Current token reserve
     */
    function getReserves() external view returns (uint256 _reserveETH, uint256 _reserveToken) {
        _reserveETH = reserveETH;
        _reserveToken = reserveToken;
    }

    /**
     * @dev Get quote for ETH to token swap (without fees, for estimation)
     * @param ethAmount Amount of ETH to swap
     * @return tokenAmount Amount of tokens that would be received
     */
    function getETHToTokenQuote(uint256 ethAmount) external view returns (uint256 tokenAmount) {
        if (reserveETH == 0 || reserveToken == 0) {
            return 0;
        }
        
        uint256 ethInWithFee = ethAmount * 997;
        uint256 numerator = ethInWithFee * reserveToken;
        uint256 denominator = (reserveETH * 1000) + ethInWithFee;
        tokenAmount = numerator / denominator;
    }

    /**
     * @dev Get quote for token to ETH swap (without fees, for estimation)
     * @param tokenAmount Amount of tokens to swap
     * @return ethAmount Amount of ETH that would be received
     */
    function getTokenToETHQuote(uint256 tokenAmount) external view returns (uint256 ethAmount) {
        if (reserveETH == 0 || reserveToken == 0) {
            return 0;
        }
        
        uint256 tokenInWithFee = tokenAmount * 997;
        uint256 numerator = tokenInWithFee * reserveETH;
        uint256 denominator = (reserveToken * 1000) + tokenInWithFee;
        ethAmount = numerator / denominator;
    }

    /**
     * @dev Internal function to mint LP tokens
     */
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    /**
     * @dev Internal function to burn LP tokens
     */
    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    /**
     * @dev Internal function to calculate square root (Babylonian method)
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /**
     * @dev Allow contract to receive ETH
     */
    receive() external payable {
        // Allow direct ETH transfers to the contract
    }
}

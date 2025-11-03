// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract HimeraToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable {
    constructor(address recipient, address initialOwner)
        ERC20("HimeraToken", "HIM")
        Ownable(initialOwner)
    {
        _mint(recipient, 1000 * 10 ** decimals());
    }

    /**
     * @dev Mints new tokens to the specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the caller's address
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) public override {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Burns tokens from a specified address if caller has sufficient allowance
     * Uses the standard ERC20Burnable burnFrom which checks allowance
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) public override {
        super.burnFrom(from, amount);
    }

    /**
     * @dev Pauses all token transfers (useful for emergency situations)
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Returns the allowance for a given owner-spender pair
     * @param owner The address that owns the tokens
     * @param spender The address that is allowed to spend the tokens
     * @return The remaining allowance
     */
    function getAllowance(address owner, address spender) 
        public 
        view 
        returns (uint256) 
    {
        return allowance(owner, spender);
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * Overrides to add pausable functionality
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

/**
 * @title ERC20 Token
 * @author Dann Wee
 * @notice This contract is a simple ERC20 token with a minting and burning function.
 */
contract Token is ERC20, Ownable {
    uint256 public immutable initialSupply;
    uint8 private immutable _decimals;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, uint8 decimals_, address _owner)
        ERC20(_name, _symbol)
        Ownable(_owner)
    {
        initialSupply = _initialSupply;
        _decimals = decimals_;
        _mint(_owner, initialSupply);
    }

    /**
     * @notice Function to mint tokens.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /**
     * @notice Function to burn tokens.
     * @param _amount The amount of tokens to burn.
     */
    function burn(uint256 _amount) public onlyOwner {
        _burn(_msgSender(), _amount);
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Function to specify the token's decimals.
     * @return The number of decimals.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockRegistry {
    uint256 private upkeepCounter;
    mapping(uint256 => uint96) public upkeepBalances;

    function registerUpkeep(
        address target,
        uint32 gasLimit,
        address admin,
        bytes calldata checkData,
        bytes calldata offchainConfig
    ) external returns (uint256) {
        upkeepCounter++;
        return upkeepCounter;
    }

    function addFunds(uint256 id, uint96 amount) external {
        upkeepBalances[id] += amount;
    }
}

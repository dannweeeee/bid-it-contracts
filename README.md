# Team Bid It Contracts

Dutch Auction Contracts

## Deployments

- Auctioneer: [0x3f3976bc2b8458b05c7914a277b4497998604c8c](https://sepolia.etherscan.io/address/0x3F3976BC2b8458b05C7914A277b4497998604c8C)

## Contracts

- Auctioneer.sol
- DutchAuction.sol
- Token.sol

## Tests

- ReentrancyAttackTest.t.sol

## Commands

### Deploy Auctioneer

```bash
forge script script/deployAuctioneer.sol:DeployAuctioneer --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

### Test Reentrancy Attack

```bash
forge test --match-contract ReentrancyAttackTest -vvvvv
```

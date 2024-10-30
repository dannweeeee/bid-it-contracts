# Team Bid It Contracts

Dutch Auction Contracts

## Deployments

- DutchAuction: [0x7C70eD6e6c5C081d255a0234292aF5DF3fad7851](https://sepolia.etherscan.io/address/0x7C70eD6e6c5C081d255a0234292aF5DF3fad7851)

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

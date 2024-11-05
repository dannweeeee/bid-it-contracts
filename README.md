# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation

## Deployments

- Auctioneer: [0x6989330e429E73920F1077aAd0079504d7aA5772](https://sepolia.etherscan.io/address/0x6989330e429E73920F1077aAd0079504d7aA5772)

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

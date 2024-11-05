# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation

## Deployments

- Auctioneer: [0xAdc4345d5906ab030f27188a13AC4e5eA4684592](https://sepolia.etherscan.io/address/0xAdc4345d5906ab030f27188a13AC4e5eA4684592)

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

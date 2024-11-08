# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation

## Deployments

- Auctioneer: [0xb7225cC897166aF0e19f61C07bF73746c9D19b91](https://sepolia.basescan.org/address/0xb7225cC897166aF0e19f61C07bF73746c9D19b91)

## Contracts

- Auctioneer.sol
- DutchAuction.sol
- Token.sol

## Tests

- DutchAuctionTest.t.sol
- ReentrancyAttackTest.t.sol

## Commands

### Deploy Auctioneer

```bash
forge script script/deployAuctioneer.sol:DeployAuctioneer --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

### Test Dutch Auction

```bash
forge test --match-contract DutchAuctionTest -vvvvv
```

### Test Reentrancy Attack

```bash
forge test --match-contract ReentrancyAttackTest -vvvvv
```

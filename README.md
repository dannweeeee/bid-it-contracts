# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation

## Deployments

- Auctioneer: [0xABd4Db4dDdc4FCdA1FEaae61b423f3be948218F9](https://sepolia.basescan.org/address/0xABd4Db4dDdc4FCdA1FEaae61b423f3be948218F9)

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

# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation

## Deployments

- Auctioneer: [0x166BdC0429fd448b4370733d0Be058e84c56DF4C](https://sepolia.basescan.org/address/0x166BdC0429fd448b4370733d0Be058e84c56DF4C)

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

# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation

## Deployments

- Auctioneer: [0x2515c7967A15Fb090395D0586a450adeFD1072DE](https://sepolia.etherscan.io/address/0x2515c7967A15Fb090395D0586a450adeFD1072DE)

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

# Team Bid It Contracts

Dutch Auction Contracts

## Deployments

- DutchAuction: [0x9F3857Dbb6728D58752939d4Be0B367dae1dc772](https://sepolia.etherscan.io/address/0x9F3857Dbb6728D58752939d4Be0B367dae1dc772)

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

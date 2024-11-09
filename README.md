# Team Bid It Contracts

Dutch Auction Contracts powered by Chainlink Automation. Live Website on https://usebidit.vercel.app

## System Design

![image](https://github.com/user-attachments/assets/77e88fad-ca2e-4f80-8a53-96666b1214bd)


## Deployments

- Auctioneer: [0x166BdC0429fd448b4370733d0Be058e84c56DF4C](https://sepolia.basescan.org/address/0x166BdC0429fd448b4370733d0Be058e84c56DF4C)

## Contracts

- Auctioneer.sol: Factory contract for creating and managing Dutch auctions
- DutchAuction.sol: A Dutch auction contract for token ICOs (similar to Liquidity Bootstrapping Pools)
- Token.sol: An ERC20 token contract for the auction

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

## Links

- [Bid It dApp](https://github.com/dannweeeee/bid-it-dapp)
- [Bid It Contracts](https://github.com/dannweeeee/bid-it-contracts)

# NftAuctionMarket

A Solidity-based NFT marketplace that supports both fixed-price listings and auction listings. The contract is designed for ERC721 NFTs and manages listing creation, direct purchases, auction conversion, auction purchases, cancellation flows, and view helpers for marketplace state.

## Project Scope

This project focuses on building a marketplace contract for ERC721 assets with two sale flows:

- Fixed-price listing and purchase.
- Auction-style listing with timed price reduction.

The repository is suitable for:

- Learning Solidity marketplace design.
- Practicing Foundry-based smart contract development and testing.
- Understanding NFT approval checks, ownership validation, and listing lifecycle handling.
- Extending into more advanced marketplace features like bidding, fees, royalties, and operator tooling.

## Features

- Register NFT listings after ownership and approval checks.
- Buy listed NFTs through direct payment.
- Convert active listings into auctions.
- Buy auction listings at the current auction price.
- Update auction prices over time using a price-drop interval.
- Cancel active listings and auction listings.
- Preview stored listing and auction data.
- Clear stale listing state when NFT ownership changes outside the marketplace.

## Sale Flow Overview

### Fixed-price flow

1. NFT owner approves the marketplace contract.
2. NFT owner registers the NFT with a sale price.
3. Buyer calls `buyListing` with enough ETH.
4. Contract transfers the NFT to the receiver and clears the listing.

### Auction flow

1. NFT owner creates a normal listing.
2. NFT owner converts that listing into an auction using `grantForAuction`.
3. Auction price can be reduced over time through `updateAuctionListings`.
4. Buyer calls `buyAuctoinListings` with enough ETH.
5. Contract transfers the NFT and clears the auction data.
6. This auction system follows the dutch Auction method.

## Contract Responsibilities

The `NftAuctionMarket` contract currently handles:

- Listing registration.
- Listing purchases.
- Auction creation from an existing listing.
- Auction purchases.
- Auction cancellation.
- Listing cancellation.
- Listing and auction previews.
- Internal cleanup of inactive or stale state.

## Tech Stack

- **Solidity** `^0.8.24`
- **Foundry** for build, test, and deployment workflow
- **OpenZeppelin** contracts for:
  - `Ownable`
  - `AccessControl`
  - `ReentrancyGuard`
  - `IERC721`
  - `Math`
  - `Strings`

## Project Structure

Example structure:

```text
.
├── src/
│   └── NftAuctionMarket.sol
├── test/
├── script/
├── lib/
├── foundry.toml
└── README.md
```

## Getting Started

### Prerequisites

Make sure the following are installed:

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git
- A code editor such as VS Code
- An RPC URL and funded wallet for live deployment

### Installation

```bash
git clone https://github.com/sivity123/NftAuctionMarket
cd NftAuctionMarket
forge install
```

If  dependencies are already committed in `lib/`, you may not need to run `forge install` again.

### Build

```bash
forge build
```

### Test

```bash
forge test
```

For verbose traces:

```bash
forge test -vvv
```

### Format

```bash
forge fmt
```

### Deploy

Example deployment command:

1) `Sepolia` In Order to deploy the contract to sepolia you must have you sepolia wallet address in you .env file as `SEPOLIA_PRIMARY_ADDRESS`, for the script to load your address and use it at the time of deployment.

2) For `Anvil` you can just deploy as your anvil running, for that you should run `anvil` in your terminal and must copy the `rpc_endpoint` and format it like `http://127.0.0.1:8545` while pasting in `--rpc-url`.


```bash
forge script \
script/DeployNftAuctionMarket.s.sol:DeployNftAuctionMarket \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast 
```

## Basic Usage

### 1. Approve the marketplace

Approve the marketplace contract from your ERC721 contract before listing the NFT.

### 2. Register a listing

Call:

```solidity
registerListings(address _nft, uint256 _tokenId, uint256 _price)
```

### 3. Buy a fixed-price listing

Call:

```solidity
buyListing(address _to, uint256 _listingId)
```

Send at least the listed price as `msg.value`.

### 4. Convert listing to auction

Call:

```solidity
grantForAuction(
    uint256 _listingId,
    uint256 _auctionPrice,
    uint256 _minAuctionPrice,
    uint256 _totalDuration,
    uint256 _durationForPriceDrop,
    uint256 _priceDropPercentage
)
```

### 5. Update auction price

Call:

```solidity
updateAuctionListings()
```

### 6. Buy an auction listing
*** Follows the dutch auction method ***
Call:

```solidity
buyAuctoinListings(uint256 _auctionId)
```

Send at least the current auction price as `msg.value`.

## Notes

- The marketplace only works with ERC721 NFTs.
- The NFT must remain approved to the marketplace for transfer operations.
- Overpayment is refunded back to the sender.
- If ownership changes outside the marketplace, stale listing state can be cleared during buy operations.
- Auction pricing follows the values configured at auction creation.

## Future Improvements

This project can be extended with:

- Bid-based auctions.
- Marketplace fees.
- Royalty support.
- Better event indexing and analytics support.
- Frontend integration.
- More complete test coverage for edge cases.

## License

MIT

//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IERC721
} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {
    ReentrancyGuard
} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {
    AccessControl
} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import {Math} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Strings} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/Strings.sol";

/// @title NftAuctionMarket
/// @author Sivanesh S
/// @notice Marketplace for direct NFT listings and auction-based sales.
/// @dev Uses ERC721 approvals, role-based auction access, and internal listing/auction bookkeeping.
contract NftAuctionMarket is Ownable, AccessControl, ReentrancyGuard {
    using Math for uint256;
    using Strings for uint256;
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the caller is not the NFT owner.
    error NftAuctionMarket__NotAnOwner();

    /// @notice Thrown when a listing is already active or already auctioned.
    error NftAuctionMarket__ListingIsAlreadyActive();

    /// @notice Thrown when a listing is already marked as auctioned.
    error NftAuctionMarket__ListingIsAlreadyAuctioned();

    /// @notice Thrown when the marketplace is not approved to transfer the NFT.
    error NftAuctionMarket__NftNotApprovedToTheMarketPlace();

    /// @notice Thrown when the sent ETH is less than the required price.
    error NftAuctionMarket__InsufficientPayment();

    /// @notice Thrown when a refund transfer fails.
    error NftAuctionMarket__PaymentTransferFailed();

    /// @notice Thrown when trying to buy a listing that is currently in auction.
    error NftAuctionMarket__ListingIsInTheAuction();

    /// @notice Thrown when the provided listing id does not exist.
    error NftAuctionMarket__InvalidListingId();

    /// @notice Thrown when a listing id has no linked auction id.
    error NftAuctionMarket__ListingIdDoesNotMatchAnyAuctionId();

    /// @notice Thrown when the provided auction id does not exist.
    error NftAuctionMarket__InvalidAuctionId();

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Defines whether a listing is direct-sale only or can be auctioned.
    enum SALE_TYPE {
        ONLY_TRADABLE,
        AUCTIONABLE
    }

    /// @notice Represents the lifecycle state of a listing.
    enum LISTING_STATUS {
        YET_TO_BE_ADDED,
        ACTIVE,
        SOLD,
        CANCELLED,
        AUCTIONED
    }

    /// @notice Represents the lifecycle state of an auction.
    enum AUCTION_STATUS {
        ONGOING,
        SOLD,
        UNSOLD,
        CANCELLED
    }

    /// @notice Stores base listing details.
    /// @param nft NFT contract address.
    /// @param tokenId NFT token id.
    /// @param price Fixed sale price.
    struct LISTING_TRAITS {
        address nft;
        uint256 tokenId;
        uint256 price;
    }

    /// @notice Stores auction configuration and timing data.
    /// @param listingId Related listing id.
    /// @param auctionPrice Current auction price.
    /// @param minAuctionPrice Minimum floor price for the auction.
    /// @param totalDuration Auction end timestamp.
    /// @param durationForPriceDrop Time interval between price updates.
    /// @param priceDropPercentage Percentage reduced on each update.
    /// @param lastUpdatedAt Last price update timestamp.
    struct AUCTION_TRAITS {
        uint256 listingId;
        uint256 auctionPrice;
        uint256 minAuctionPrice;
        uint256 totalDuration;
        uint256 durationForPriceDrop;
        uint256 priceDropPercentage;
        uint256 lastUpdatedAt;
    }

    mapping(uint256 listingId => LISTING_TRAITS traits) private s_listingIdToTraits;
    mapping(uint256 listingId => uint256 listingIndex) private s_listingIdToIndex;
    mapping(address nft => mapping(uint256 tokenId => LISTING_STATUS status)) private s_nftTokenToStatus;
    mapping(address nft => mapping(uint256 tokenId => address owner)) private s_nftToListingOwner;
    mapping(uint256 listingId => uint256 auction_id) private s_listingIdToAuctionId;
    mapping(uint256 auctionId => AUCTION_TRAITS traits) private s_auctionIdToTraits;
    mapping(uint256 auctionId => uint256 auctionIndex) private s_auctionIdToIndex;
    // index 0 will reserved for deleted listings.

    uint256 s_listingId = 1; // avoiding the listingId of 0.
    uint256[] s_listings;
    uint256 s_auctionId;
    uint256[] s_auctionListings;
    bytes32 private constant LISTER_ROLE = keccak256("LISTER ROLE");

    /*//////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new listing is registered.
    event ListingHasRegistered();

    /// @notice Emitted when a listed NFT is purchased.
    /// @param _to Receiver of the NFT.
    /// @param _listingId Purchased listing id.
    event ListingHasBought(address indexed _to, uint256 indexed _listingId);

    /// @notice Emitted when an auction price is reduced.
    /// @param auctionId Updated auction id.
    /// @param updatedAuctionPrice New auction price.
    event AuctionListingPriceUpdated(uint256 indexed auctionId, uint256 indexed updatedAuctionPrice);

    /// @notice Emitted when a listing is cancelled.
    /// @param nft NFT contract address.
    /// @param tokenId NFT token id.
    /// @param listingId Cancelled listing id.
    event ListingHasCancelled(address indexed nft, uint256 indexed tokenId, uint256 indexed listingId);

    /// @notice Emitted when an auction listing is cleared.
    /// @param owner Owner of the NFT listing.
    /// @param auctionId Cleared auction id.
    event AuctionListingHasCleared(address owner, uint256 auctionId);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract owner.
    /// @param _initialOwner Address set as the initial owner.
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /// @notice Registers an NFT for direct listing.
    /// @dev Caller must own the NFT and approve this marketplace.
    /// @param _nft NFT contract address.
    /// @param _tokenId NFT token id.
    /// @param _price Fixed listing price.
    /// @return The created listing id.
    function registerListings(address _nft, uint256 _tokenId, uint256 _price) external returns (uint256) {
        if (msg.sender != IERC721(_nft).ownerOf(_tokenId)) revert NftAuctionMarket__NotAnOwner();

        if (
            s_nftTokenToStatus[_nft][_tokenId] == LISTING_STATUS.ACTIVE
                || s_nftTokenToStatus[_nft][_tokenId] == LISTING_STATUS.AUCTIONED
        ) {
            revert NftAuctionMarket__ListingIsAlreadyActive();
        }

        if (
            IERC721(_nft).getApproved(_tokenId) != address(this)
                && !IERC721(_nft).isApprovedForAll(msg.sender, address(this))
        ) revert NftAuctionMarket__NftNotApprovedToTheMarketPlace();

        s_listingIdToTraits[s_listingId] = LISTING_TRAITS({nft: _nft, tokenId: _tokenId, price: _price});

        s_listings.push(s_listingId);
        s_listingIdToIndex[s_listingId] = s_listings.length; // here the listingINdex of listingId will be 1
        s_nftTokenToStatus[_nft][_tokenId] = LISTING_STATUS.ACTIVE;
        s_nftToListingOwner[_nft][_tokenId] = msg.sender;

        s_listingId += 1;
        _grantRole(LISTER_ROLE, msg.sender);

        emit ListingHasRegistered();

        return s_listingId - 1; // returns listing id of the current listing.
    }

    /// @notice Buys an active fixed-price listing.
    /// @dev Clears stale listings if the recorded owner no longer owns the NFT.
    /// @param _to Address that will receive the NFT.
    /// @param _listingId Listing id to purchase.
    /// @return True if the purchase succeeds, false if the listing was stale and cleared.
    function buyListing(address _to, uint256 _listingId) external payable returns (bool) {
        if (s_listingIdToIndex[_listingId] == 0) revert NftAuctionMarket__InvalidListingId();

        LISTING_TRAITS memory t = s_listingIdToTraits[_listingId];

        address nft = t.nft;
        uint256 tokenId = t.tokenId;
        uint256 price = t.price;
        address registeredOwner = s_nftToListingOwner[nft][tokenId];

        if (s_nftTokenToStatus[nft][tokenId] == LISTING_STATUS.AUCTIONED) {
            revert NftAuctionMarket__ListingIsInTheAuction();
        }

        if (IERC721(nft).ownerOf(tokenId) != registeredOwner) {
            _clearListing(nft, tokenId, _listingId);
            return false;
        }

        if (
            IERC721(nft).getApproved(tokenId) != address(this)
                && !IERC721(nft).isApprovedForAll(registeredOwner, address(this))
        ) revert NftAuctionMarket__NftNotApprovedToTheMarketPlace();

        if (msg.value < price) revert NftAuctionMarket__InsufficientPayment();

        if (msg.value > price) {
            _handleOverPayment(msg.sender, msg.value, price);
        }

        emit ListingHasBought(_to, _listingId);
        _clearListing(nft, tokenId, _listingId);
        s_nftTokenToStatus[nft][tokenId] = LISTING_STATUS.SOLD;

        IERC721(nft).safeTransferFrom(registeredOwner, _to, tokenId);

        return true;
    }

    /// @notice Converts an existing listing into an auction listing.
    /// @dev Caller must have the lister role and still own the NFT.
    /// @param _listingId Listing id to move into auction.
    /// @param _auctionPrice Starting auction price.
    /// @param _minAuctionPrice Minimum allowed auction price.
    /// @param _totalDuration Auction duration from now.
    /// @param _durationForPriceDrop Interval for each price reduction.
    /// @param _priceDropPercentage Percentage reduced each interval.
    /// @return The created auction id.
    function grantForAuction(
        uint256 _listingId,
        uint256 _auctionPrice,
        uint256 _minAuctionPrice,
        uint256 _totalDuration,
        uint256 _durationForPriceDrop,
        uint256 _priceDropPercentage
    ) external onlyRole(LISTER_ROLE) returns (uint256) {
        if (s_listingIdToIndex[_listingId] == 0) {
            revert NftAuctionMarket__InvalidListingId();
        }
        LISTING_TRAITS memory t = s_listingIdToTraits[_listingId];
        address nft = t.nft;
        uint256 tokenId = t.tokenId;
        address registeredOwner = s_nftToListingOwner[nft][tokenId];
        if (IERC721(nft).ownerOf(tokenId) != registeredOwner || msg.sender != registeredOwner) {
            revert NftAuctionMarket__NotAnOwner();
        }

        if (s_nftTokenToStatus[nft][tokenId] == LISTING_STATUS.AUCTIONED) {
            revert NftAuctionMarket__ListingIsAlreadyAuctioned();
        }
        (, uint256 totalDuration) = (block.timestamp).tryAdd(_totalDuration);
        s_nftTokenToStatus[nft][tokenId] = LISTING_STATUS.AUCTIONED;

        s_auctionId = ++s_auctionId; // this avoids auction id with 0
        s_listingIdToAuctionId[_listingId] = s_auctionId;
        s_auctionListings.push(s_auctionId);
        s_auctionIdToIndex[s_auctionId] = s_auctionListings.length;

        s_auctionIdToTraits[s_auctionId] = AUCTION_TRAITS({
            listingId: _listingId,
            auctionPrice: _auctionPrice,
            minAuctionPrice: _minAuctionPrice,
            totalDuration: totalDuration,
            durationForPriceDrop: _durationForPriceDrop,
            priceDropPercentage: _priceDropPercentage,
            lastUpdatedAt: block.timestamp
        });

        return s_auctionId;
    }

    /// @notice Buys an NFT from an active auction listing.
    /// @dev Clears stale auction and listing data if ownership changed.
    /// @param _auctionId Auction id to purchase from.
    /// @return True if the purchase succeeds, false if stale state was cleared.
    function buyAuctoinListings(uint256 _auctionId) external payable returns (bool) {
        uint256 auctionIdIndex = s_auctionIdToIndex[_auctionId];
        if (auctionIdIndex == 0) revert NftAuctionMarket__InvalidAuctionId();

        AUCTION_TRAITS memory t = s_auctionIdToTraits[_auctionId];

        LISTING_TRAITS memory lt = s_listingIdToTraits[t.listingId];
        address nft = lt.nft;
        uint256 tokenId = lt.tokenId;
        address registeredOwner = s_nftToListingOwner[nft][tokenId];

        if (IERC721(nft).ownerOf(tokenId) != registeredOwner) {
            _clearAuctionListing(_auctionId);
            _clearListing(nft, tokenId, t.listingId);
            return false;
        }

        if (
            IERC721(nft).getApproved(tokenId) != address(this)
                && !IERC721(nft).isApprovedForAll(registeredOwner, address(this))
        ) revert NftAuctionMarket__NftNotApprovedToTheMarketPlace();

        if (msg.value < t.auctionPrice) revert NftAuctionMarket__InsufficientPayment();

        if (msg.value > t.auctionPrice) {
            _handleOverPayment(msg.sender, msg.value, t.auctionPrice);
        }

        s_nftTokenToStatus[nft][tokenId] = LISTING_STATUS.SOLD;
        _clearAuctionListing(_auctionId);
        _clearListing(nft, tokenId, t.listingId);

        IERC721(nft).safeTransferFrom(registeredOwner, msg.sender, tokenId);

        return true;
        // uint256 auctionPrice =
        // if(msg.value < )
        //approval check owner check
    }

    /// @notice Updates auction prices based on configured drop intervals.
    /// @dev Lowers price only when the next reduced price remains above or equal to the minimum price.
    function updateAuctionListings() external {
        uint256 auctionId;
        uint256 lastUpdatedAt;
        uint256 totalDuration;
        uint256 durationForPriceDrop;
        uint256 priceDropPercentage;
        uint256 auctionPrice;
        uint256 minAuctionPrice;
        uint256[] memory auctionListings = s_auctionListings;
        for (uint256 index = 0; index < auctionListings.length; index++) {
            auctionId = s_auctionListings[index];
            AUCTION_TRAITS memory t = s_auctionIdToTraits[auctionId];
            totalDuration = t.totalDuration;
            durationForPriceDrop = t.durationForPriceDrop;
            priceDropPercentage = t.priceDropPercentage;
            lastUpdatedAt = t.lastUpdatedAt;
            auctionPrice = t.auctionPrice;
            minAuctionPrice = t.minAuctionPrice;

            if (block.timestamp < totalDuration) {
                if (block.timestamp >= (lastUpdatedAt + durationForPriceDrop)) {
                    (, uint256 updatedAuctionPrice) =
                        auctionPrice.trySub(auctionPrice.mulDiv(priceDropPercentage, 100, Math.Rounding.Floor));
                    if (updatedAuctionPrice >= minAuctionPrice) {
                        s_auctionIdToTraits[auctionId].auctionPrice = updatedAuctionPrice;
                        s_auctionIdToTraits[auctionId].lastUpdatedAt = block.timestamp;
                        emit AuctionListingPriceUpdated(auctionId, updatedAuctionPrice);
                    }
                }
            }
        }
    }

    // bidForAuctionedListing -- external func();

    /// @notice Refunds excess ETH to the sender.
    /// @param _sender Address receiving the refund.
    /// @param _paymentComingIn Total ETH sent.
    /// @param _expectedPayment Required ETH amount.
    function _handleOverPayment(address _sender, uint256 _paymentComingIn, uint256 _expectedPayment) private {
        (, uint256 amountToRefund) = (_paymentComingIn).trySub(_expectedPayment);
        (bool success,) = _sender.call{value: amountToRefund}("");
        if (!success) revert NftAuctionMarket__PaymentTransferFailed();
    }

    /// @notice Removes a listing from storage and index tracking.
    /// @param _nft NFT contract address.
    /// @param _tokenId NFT token id.
    /// @param _listingId Listing id to clear.
    function _clearListing(address _nft, uint256 _tokenId, uint256 _listingId) private {
        if (s_listings.length > 1) {
            uint256 index = s_listingIdToIndex[_listingId];
            uint256 lastListingId = s_listings[s_listings.length - 1];
            s_listings[index - 1] = lastListingId;
            s_listingIdToIndex[lastListingId] = index;
        }
        delete s_listingIdToIndex[_listingId];
        s_listings.pop();

        delete s_listingIdToTraits[_listingId];
        delete s_nftTokenToStatus[_nft][_tokenId];
        delete s_nftToListingOwner[_nft][_tokenId];
    }

    /// @notice Removes an auction listing from storage and index tracking.
    /// @param _auctionId Auction id to clear.
    function _clearAuctionListing(uint256 _auctionId) private {
        AUCTION_TRAITS memory t = s_auctionIdToTraits[_auctionId];
        uint256 listingId = t.listingId;

        if (s_auctionListings.length > 1) {
            uint256 index = s_auctionIdToIndex[_auctionId];
            uint256 lastAuctionId = s_auctionListings[s_auctionListings.length - 1];
            s_auctionListings[index - 1] = lastAuctionId;
            s_auctionIdToIndex[lastAuctionId] = index;
        }

        delete s_auctionIdToIndex[_auctionId];
        s_auctionListings.pop();

        delete s_auctionIdToTraits[_auctionId];
        delete s_listingIdToAuctionId[listingId];
    }

    /// @notice Returns the auction id linked to a listing.
    /// @param _listingId Listing id to query.
    /// @return The mapped auction id.
    function getAuctionId(uint256 _listingId) external view returns (uint256) {
        if (s_listingIdToAuctionId[_listingId] == 0) revert NftAuctionMarket__ListingIdDoesNotMatchAnyAuctionId();
        return s_listingIdToAuctionId[_listingId];
    }

    /// @notice Cancels an active auction and restores the listing to active sale state.
    /// @param _auctionId Auction id to cancel.
    function cancelAuctionListing(uint256 _auctionId) external {
        uint256 auctionIdIndex = s_auctionIdToIndex[_auctionId];
        if (auctionIdIndex == 0) revert NftAuctionMarket__InvalidAuctionId();
        AUCTION_TRAITS memory t = s_auctionIdToTraits[_auctionId];
        LISTING_TRAITS memory lt = s_listingIdToTraits[t.listingId];
        address nft = lt.nft;
        uint256 tokenId = lt.tokenId;
        address registeredOwner = s_nftToListingOwner[nft][tokenId];
        if (IERC721(nft).ownerOf(tokenId) != registeredOwner || msg.sender != registeredOwner) {
            revert NftAuctionMarket__NotAnOwner();
        }
        _clearAuctionListing(_auctionId);
        s_nftTokenToStatus[nft][tokenId] = LISTING_STATUS.ACTIVE;
        emit AuctionListingHasCleared(registeredOwner, _auctionId);
    }

    /// @notice Cancels a listing and clears linked auction data if present.
    /// @param _listingId Listing id to cancel.
    function cancelListing(uint256 _listingId) external {
        if (s_listingIdToIndex[_listingId] == 0) revert NftAuctionMarket__InvalidListingId();
        LISTING_TRAITS memory lt = s_listingIdToTraits[_listingId];
        address nft = lt.nft;
        uint256 tokenId = lt.tokenId;
        address registeredOwner = s_nftToListingOwner[nft][tokenId];
        uint256 auctionId = s_listingIdToAuctionId[_listingId];
        if (IERC721(nft).ownerOf(tokenId) != registeredOwner || msg.sender != registeredOwner) {
            revert NftAuctionMarket__NotAnOwner();
        }

        if (s_nftTokenToStatus[nft][tokenId] == LISTING_STATUS.AUCTIONED) {
            _clearAuctionListing(auctionId);
        }
        _clearListing(nft, tokenId, _listingId);
        s_nftTokenToStatus[nft][tokenId] = LISTING_STATUS.CANCELLED;

        emit ListingHasCancelled(nft, tokenId, _listingId);
    }

    /// @notice Checks whether a listing id is valid.
    /// @param _listingId Listing id to verify.
    /// @return True if the listing exists.
    /// @return The internal stored index for the listing.
    function checkForValidListingId(uint256 _listingId) external view returns (bool, uint256) {
        return (s_listingIdToIndex[_listingId] != 0 ? true : false, s_listingIdToIndex[_listingId]);
    }

    /// @notice Returns listing details for a given listing id.
    /// @param _listingId Listing id to inspect.
    /// @return Listing traits of the given listing.
    function previewListing(uint256 _listingId) external view returns (LISTING_TRAITS memory) {
        return s_listingIdToTraits[_listingId];
    }

    /// @notice Returns auction details for a given auction id.
    /// @param _auctionId Auction id to inspect.
    /// @return Auction traits of the given auction.
    function previewAuctionListing(uint256 _auctionId) external view returns (AUCTION_TRAITS memory) {
        return s_auctionIdToTraits[_auctionId];
    }
}
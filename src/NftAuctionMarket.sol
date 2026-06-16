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

contract NftAuctionMarket is Ownable, AccessControl, ReentrancyGuard {
    using Math for uint256;
    using Strings for uint256;
    /*//////////////////////////////////////////////////////////////
                                  ERRORS
     //////////////////////////////////////////////////////////////*/

    error NftAuctionMarket__NotAnOwner();
    error NftAuctionMarket__ListingIsAlreadyActive();
    error NftAuctionMarket__ListingIsAlreadyAuctioned();
    error NftAuctionMarket__NftNotApprovedToTheMarketPlace();
    error NftAuctionMarket__InsufficientPayment();
    error NftAuctionMarket__PaymentTransferFailed();
    error NftAuctionMarket__ListingIsInTheAuction();
    error NftAuctionMarket__InvalidListingId();
    error NftAuctionMarket__ListingIdDoesNotMatchAnyAuctionId();
    error NftAuctionMarket__InvalidAuctionId();


    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATION
    //////////////////////////////////////////////////////////////*/

    enum SALE_TYPE {
        ONLY_TRADABLE,
        AUCTIONABLE
    }

    enum LISTING_STATUS {
        YET_TO_BE_ADDED,
        ACTIVE,
        SOLD,
        CANCELLED,
        AUCTIONED
    }

    enum AUCTION_STATUS {
        ONGOING,
        SOLD,
        UNSOLD,
        CANCELLED
    }

    struct LISTING_TRAITS {
        address nft;
        uint256 tokenId;
        uint256 price;
    }

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
    event ListingHasRegistered();
    event ListingHasBought(address indexed _to, uint256 indexed _listingId);
    event AuctionListingPriceUpdated(uint256 indexed auctionId, uint256 indexed updatedAuctionPrice);
    event ListingHasCancelled(address indexed nft, uint256 indexed tokenId, uint256 indexed listingId);
    event AuctionListingHasCleared(address owner, uint256 auctionId);
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
      //////////////////////////////////////////////////////////////*/
    constructor(address _initialOwner) Ownable(_initialOwner) {}

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

    function _handleOverPayment(address _sender, uint256 _paymentComingIn, uint256 _expectedPayment) private {
        (, uint256 amountToRefund) = (_paymentComingIn).trySub(_expectedPayment);
        (bool success,) = _sender.call{value: amountToRefund}("");
        if (!success) revert NftAuctionMarket__PaymentTransferFailed();
    }

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

    function getAuctionId(uint256 _listingId) external view returns (uint256) {
        if (s_listingIdToAuctionId[_listingId] == 0) revert NftAuctionMarket__ListingIdDoesNotMatchAnyAuctionId();
        return s_listingIdToAuctionId[_listingId];
    }

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

    function checkForValidListingId(uint256 _listingId) external view returns (bool, uint256) {
        return (s_listingIdToIndex[_listingId] != 0 ? true : false, s_listingIdToIndex[_listingId]);
    }

    function previewListing(uint256 _listingId) external view returns (LISTING_TRAITS memory) {
        return s_listingIdToTraits[_listingId];
    }

    function previewAuctionListing(uint256 _auctionId) external view returns (AUCTION_TRAITS memory) {
        return s_auctionIdToTraits[_auctionId];
    }
}

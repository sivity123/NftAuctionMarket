//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NftAuctionMarket} from "src/NftAuctionMarket.sol";
import {MinimalNft} from "src/MinimalNft.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAccessControl
} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {Vm} from "lib/forge-std/src/Vm.sol";
import {DeployNftAuctionMarket} from "script/DeployNftAuctionMarket.s.sol";

contract NftAuctionMarketTest is Test {
    NftAuctionMarket auctionMarket;
    MinimalNft nft;

    uint256 constant USER1_TOKENID = 0;
    uint256 constant USER2_TOKENID = 1;
    uint256 constant USER3_TOKENID = 2;
    uint256 constant FIRST_LISTING_ID = 1;
    uint256 constant LISTING_PRICE = 1 ether;
    uint256 constant ADJUSTED_AUCTION_PRICE = 1 ether - 0.2 ether;
    uint256 constant MIN_AUCTION_PRICE = 1 ether - 0.5 ether;
    uint256 constant TOTAL_AUCTION_DURATION = 1 minutes;
    uint256 constant DURATION_FOR_PRICE_DROP = 10 seconds;
    uint256 constant PERCENTAGE_OF_PRICE_DROP = 2; // price - (price * 2/100)
    bytes32 private constant LISTER_ROLE = keccak256("LISTER ROLE");

    address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    address buyer1 = makeAddr("buyer1");
    address buyer2 = makeAddr("buyer2");
    address buyer3 = makeAddr("buyer3");

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ListingHasRegistered();
    event ListingHasBought();

    modifier mintNft() {
        vm.startPrank(owner);
        nft.mint(user1);
        nft.mint(user2);
        nft.mint(user3);
        vm.stopPrank();
        _;
    }

    modifier registerListing() {
        vm.startPrank(user1);
        nft.approve(address(auctionMarket), USER1_TOKENID);
        auctionMarket.registerListings(address(nft), USER1_TOKENID, LISTING_PRICE);
        vm.stopPrank();
        _;
    }

    modifier registerListings() {
        address[3] memory users = [user1, user2, user3];
        for (uint8 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            nft.approve(address(auctionMarket), i);
            auctionMarket.registerListings(address(nft), i, LISTING_PRICE);
            vm.stopPrank();
        }
        _;
    }

    modifier grantForAuction() {
        vm.prank(user1);
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
        _;
    }

    function setUp() public {
        vm.deal(user1, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(owner, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(buyer3, 100 ether);

        DeployNftAuctionMarket deployer = new DeployNftAuctionMarket(); 
        (address aMarketAddress,address nftAddress) = deployer.run();
        nft = MinimalNft(nftAddress);
        auctionMarket = NftAuctionMarket(aMarketAddress);

    }

    /*//////////////////////////////////////////////////////////////
                               TEST OWNER
    //////////////////////////////////////////////////////////////*/
    function test_Owner() public view {
        assert(auctionMarket.owner() == owner);
    }

    function test_onlyNftOwnerCanMint() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nft.mint(user1);
    }

    function test_ownerCanMint() public {
        vm.prank(owner);
        nft.mint(user1);
    }

    /*//////////////////////////////////////////////////////////////
                         TEST REGISTER LISTING
    //////////////////////////////////////////////////////////////*/

    function test_userCanRegisterListing() public mintNft {
        vm.startPrank(user1);
        nft.approve(address(auctionMarket), USER1_TOKENID);
        emit ListingHasRegistered();
        uint256 listingId = auctionMarket.registerListings(address(nft), USER1_TOKENID, LISTING_PRICE);
        (bool valid,) = auctionMarket.checkForValidListingId(listingId);
        assert(listingId == 1);
        assert(valid == true);
    }

    function test_registerListingRevertOnNonOwner() public mintNft {
        vm.prank(user1);
        nft.approve(address(auctionMarket), USER1_TOKENID);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.registerListings(address(nft), USER1_TOKENID, LISTING_PRICE);
    }

    function test_registerListingRevertsOnActiveListing() public mintNft registerListing {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__ListingIsAlreadyActive.selector));
        auctionMarket.registerListings(address(nft), USER1_TOKENID, LISTING_PRICE);
    }

    function test_registerListingRevertsOnNonApprovedTokens() public mintNft {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NftNotApprovedToTheMarketPlace.selector)
        );
        auctionMarket.registerListings(address(nft), USER1_TOKENID, LISTING_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                         TEST GRANT FOR AUCTION
    //////////////////////////////////////////////////////////////*/

    function test_registeredListingCanGrantForAuction() public mintNft registerListing {
        uint256 expectedAuctionId = 1;
        vm.prank(user1);
        uint256 auctionId = auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
        uint256 listingIdToAuctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);

        assert(auctionId == expectedAuctionId);
        assert(listingIdToAuctionId == expectedAuctionId);
    }

    function test_grantForAuctionRevertsOnInvalidListingId() public mintNft registerListing {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InvalidListingId.selector));
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID + 1,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
    }

    function test_grantForAuctionRevertOnNonOwner() public mintNft registerListing {
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, USER1_TOKENID);
        vm.prank(user1); // current owner is not the registered owner
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
    }

    function test_grantForAuctionRevertOnSenderIsNotTheRegisteredOwner() public mintNft registerListings {
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, USER1_TOKENID);
        vm.prank(user2); // current owner is not the registered owner
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
    }

    function test_grantForAuctionRevertsOnAuctionedListings() public mintNft registerListings grantForAuction {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__ListingIsAlreadyAuctioned.selector));
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
    }

    function test_grantForAuctionRevertOnSenderWithNoListerRole() public mintNft registerListing {
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user2, LISTER_ROLE)
        );
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            MIN_AUCTION_PRICE,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
    }

    /*//////////////////////////////////////////////////////////////
                            TEST BUY LISTING
    //////////////////////////////////////////////////////////////*/

    function test_registerNonAuctionedListingCanBuy() public mintNft registerListing {
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        bool success = auctionMarket.buyListing{value: t.price}(buyer1, FIRST_LISTING_ID);
        assert(success == true);
    }

    function test_buyListingRevertsOnInvalidListingId() public mintNft registerListing {
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InvalidListingId.selector));
        auctionMarket.buyListing{value: t.price}(buyer1, 0); // invalid ListingId
    }

    function test_buyListingRevertsOnAuctionedListing() public mintNft registerListing grantForAuction {
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__ListingIsInTheAuction.selector));
        auctionMarket.buyListing{value: t.price}(buyer1, FIRST_LISTING_ID);
    }

    function test_buyListingClearsListingOnTransferOfOwnership() public mintNft registerListing {
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, USER1_TOKENID);
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        // vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__ListingIsInTheAuction.selector));
        bool success = auctionMarket.buyListing{value: t.price}(buyer1, FIRST_LISTING_ID);
        assert(success == false);
    }

    function test_buyListingRevertsOnUnApprovedNft() public mintNft registerListing {
        vm.prank(user1);
        nft.approve(user2, USER1_TOKENID);
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NftNotApprovedToTheMarketPlace.selector)
        );
        auctionMarket.buyListing{value: t.price}(buyer1, FIRST_LISTING_ID);
    }

    function test_buyListingRevertOnInsufficientPayment() public mintNft registerListing {
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InsufficientPayment.selector));
        auctionMarket.buyListing{value: t.price - 1}(buyer1, FIRST_LISTING_ID); //underpayment
    }

    function test_buyListingHandlesOverPayment() public mintNft registerListing {
        uint256 buyerInitialBalance = buyer1.balance;
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.prank(buyer1);
        auctionMarket.buyListing{value: t.price + t.price}(buyer1, FIRST_LISTING_ID);
        // doubling the price for overPayment
        uint256 buyersFinalBalance = buyer1.balance;
        assert(buyersFinalBalance == (buyerInitialBalance - t.price));
    }

    function test_buyListingEmitsLog() public mintNft registerListing {
        NftAuctionMarket.LISTING_TRAITS memory t = auctionMarket.previewListing(FIRST_LISTING_ID);
        vm.recordLogs();
        vm.prank(buyer1);
        auctionMarket.buyListing{value: t.price}(buyer1, FIRST_LISTING_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 toAddress = logs[0].topics[1];
        bytes32 id = logs[0].topics[2];
        address to = address(uint160(uint256(toAddress)));
        uint256 listingId = uint256(id);
        console.log(to, buyer1);
        console.log(listingId, FIRST_LISTING_ID);
        assert(to == buyer1);
        assert(listingId == FIRST_LISTING_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST BUY AUCTION LISTING
    //////////////////////////////////////////////////////////////*/
    function test_AuctoinedListingCanBeBoughtByBuyAuctionListing() public mintNft registerListing grantForAuction {
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        vm.prank(buyer1);
        auctionMarket.buyAuctoinListings{value: t.auctionPrice}(auctionId);
    }

    function test_buyAuctionListingRevertsOnInValidAuctionId() public mintNft registerListing grantForAuction {
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InvalidAuctionId.selector));
        auctionMarket.buyAuctoinListings(auctionId + 1); // invalid auction Id
    }

    function test_buyAuctionListingClearsListingsOnDifferentOwner() public mintNft registerListing grantForAuction {
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, 0);
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        vm.prank(buyer1);
        bool success = auctionMarket.buyAuctoinListings{value: t.auctionPrice}(auctionId);
        console.log("listing cleared :", success);
        assertEq(success, false);
    }

    function test_buyAuctionListingRevertsOnNonApprovalTokens() public mintNft registerListing grantForAuction {
        vm.prank(user1);
        nft.approve(user2, 0);
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NftNotApprovedToTheMarketPlace.selector)
        );
        auctionMarket.buyAuctoinListings{value: t.auctionPrice}(auctionId);
    }

    function test_buyAuctionListingRevertsOnInsufficientPayment() public mintNft registerListing grantForAuction {
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InsufficientPayment.selector));
        auctionMarket.buyAuctoinListings{value: t.auctionPrice - 1}(auctionId);// insufficient Payment
    }

    function test_buyAuctionListingHandlesOverPayment() public mintNft registerListing grantForAuction{
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        uint256 intialBalanceOfBuyer = buyer1.balance;
        vm.prank(buyer1);
        auctionMarket.buyAuctoinListings{value: t.auctionPrice + 1 ether}(auctionId);
        uint256 finalBalanceOfBuyer = buyer1.balance;
        (bool valid,) = auctionMarket.checkForValidListingId(FIRST_LISTING_ID);
        assertEq(finalBalanceOfBuyer,(intialBalanceOfBuyer - t.auctionPrice));
        assertEq(valid,false);

    }

    /*//////////////////////////////////////////////////////////////
                      TEST UPDATE AUCTION LISTING
    //////////////////////////////////////////////////////////////*/

    function test_updateAuctionListingFollowsDutchRules() public mintNft registerListing grantForAuction {
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        uint256 initialAuctionPrice = t.auctionPrice;
        vm.warp(block.timestamp + t.durationForPriceDrop);
        vm.roll(block.number + 1);
        auctionMarket.updateAuctionListings();
        NftAuctionMarket.AUCTION_TRAITS memory newT = auctionMarket.previewAuctionListing(auctionId);
        uint256 updatedAuctionPrice = newT.auctionPrice;
        console.log("initialAuctionPrice:", initialAuctionPrice);
        console.log("updatedAuctionPrice:", updatedAuctionPrice);

        assertLt(updatedAuctionPrice, initialAuctionPrice);
        //7,84,00,00,00,00,00,00,000
        //7,84,00,00,00,00,00,00,000
    }

    function test_updateAuctionListingDoesNotUpdateWithoutRequirements1() public mintNft registerListing grantForAuction{
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        uint256 initialAuctionPrice = t.auctionPrice;
        vm.warp(block.timestamp + t.totalDuration);
        vm.roll(block.number + 1);
        auctionMarket.updateAuctionListings();
        NftAuctionMarket.AUCTION_TRAITS memory newT = auctionMarket.previewAuctionListing(auctionId);
        uint256 updatedAuctionPrice = newT.auctionPrice;
        console.log("initialAuctionPrice:", initialAuctionPrice);
        console.log("updatedAuctionPrice:", updatedAuctionPrice);
    }

    function test_updateAuctionListingDoesNotUpdateWithoutRequirements2() public mintNft registerListing grantForAuction{
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        uint256 initialAuctionPrice = t.auctionPrice;
        vm.warp(block.timestamp + (t.durationForPriceDrop - 3 seconds));
        vm.roll(block.number + 1);
        auctionMarket.updateAuctionListings();
        NftAuctionMarket.AUCTION_TRAITS memory newT = auctionMarket.previewAuctionListing(auctionId);
        uint256 updatedAuctionPrice = newT.auctionPrice;
        console.log("initialAuctionPrice:", initialAuctionPrice);
        console.log("updatedAuctionPrice:", updatedAuctionPrice);
    }
    //784000000000000000

    function test_updateAuctionListingDoesNotUpdateWithoutRequirements3() public mintNft registerListing {
         vm.prank(user1);
        auctionMarket.grantForAuction(
            FIRST_LISTING_ID,
            ADJUSTED_AUCTION_PRICE,
            784000000000000001,
            TOTAL_AUCTION_DURATION,
            DURATION_FOR_PRICE_DROP,
            PERCENTAGE_OF_PRICE_DROP
        );
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        NftAuctionMarket.AUCTION_TRAITS memory t = auctionMarket.previewAuctionListing(auctionId);
        uint256 initialAuctionPrice = t.auctionPrice;
        vm.warp(block.timestamp + (t.durationForPriceDrop));
        vm.roll(block.number + 1);
        auctionMarket.updateAuctionListings();
        NftAuctionMarket.AUCTION_TRAITS memory newT = auctionMarket.previewAuctionListing(auctionId);
        uint256 updatedAuctionPrice = newT.auctionPrice;
        console.log("initialAuctionPrice:", initialAuctionPrice);
        console.log("updatedAuctionPrice:", updatedAuctionPrice);
    }



    


    /*//////////////////////////////////////////////////////////////
                          TEST CANCEL LISTING
    //////////////////////////////////////////////////////////////*/

    function test_cancelListingWorksOnValidListing() public mintNft registerListing {
        vm.prank(user1);
        auctionMarket.cancelListing(FIRST_LISTING_ID);
        (bool valid, uint256 listingIndex) = auctionMarket.checkForValidListingId(FIRST_LISTING_ID);
        console.log("Listing Index for listing id 1 : ", listingIndex);
        assert(valid == false);
    }

    function test_cancelListingRevertsOnInvalidListingId() public mintNft registerListing {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InvalidListingId.selector));
        auctionMarket.cancelListing(FIRST_LISTING_ID+1);
    }
    
    function test_cancelListingRevertsOnChangeOfOwner() public mintNft registerListing {
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, USER1_TOKENID);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.cancelListing(FIRST_LISTING_ID);
    }

    function test_cancelListingRevertsOnNonOwner() public mintNft registerListing {
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.cancelListing(FIRST_LISTING_ID);
    }

    function test_cancelListingCancelsTheAuctionedListingsIfAuctioned() public mintNft registerListing grantForAuction{
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        assert(auctionId == 1);
        vm.prank(user1);
        auctionMarket.cancelListing(FIRST_LISTING_ID);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__ListingIdDoesNotMatchAnyAuctionId.selector));
        auctionMarket.getAuctionId(FIRST_LISTING_ID);
    }

    function test_cancelListingCancelsTheListing() public mintNft registerListing {
        vm.prank(user1);
        auctionMarket.cancelListing(FIRST_LISTING_ID);
        (bool valid,) = auctionMarket.checkForValidListingId(FIRST_LISTING_ID);
        assert(valid == false);

    }



    /*//////////////////////////////////////////////////////////////
                          TEST CANCEL AUCTION LISTING
    //////////////////////////////////////////////////////////////*/

    function test_cancelAuctionListingWorksOnValidAuctionListing() public mintNft registerListing grantForAuction{
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        vm.prank(user1);
        auctionMarket.cancelAuctionListing(auctionId);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__ListingIdDoesNotMatchAnyAuctionId.selector));
        auctionMarket.getAuctionId(FIRST_LISTING_ID);
    }

  function test_cancelAuctionListingRevertsOnInValidAuctionListing() public mintNft registerListing grantForAuction{
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__InvalidAuctionId.selector));
        auctionMarket.cancelAuctionListing(auctionId+1);
        
    }

    function test_cancelAuctionListingRevertsOnChangeOfOwner() public mintNft registerListing grantForAuction{
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, USER1_TOKENID);
        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.cancelAuctionListing(auctionId);
    }

     function test_cancelAuctionListingRevertsOnNonOwner() public mintNft registerListing grantForAuction{

        uint256 auctionId = auctionMarket.getAuctionId(FIRST_LISTING_ID);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(NftAuctionMarket.NftAuctionMarket__NotAnOwner.selector));
        auctionMarket.cancelAuctionListing(auctionId);
    }



}

//need to crack the clear listing weired behaviour.Looks like it changing the input parameter too

/* ╭------------------------------------------------------------------+------------╮
| Method                                                           | Identifier |
+===============================================================================+
| DEFAULT_ADMIN_ROLE()                                             | a217fddf   |
|------------------------------------------------------------------+------------|
| buyAuctoinListings(uint256)                                      | 5e38d3db   |
|------------------------------------------------------------------+------------|
| buyListing(address,uint256)                                      | 0c97fa64   |
|------------------------------------------------------------------+------------|
| cancelAuctionListing(uint256)                                    | 2a5a9435   |
|------------------------------------------------------------------+------------|
| cancelListing(uint256)                                           | 305a67a8   |
|------------------------------------------------------------------+------------|
| checkForValidListingId(uint256)                                  | 65fe5a95   |
|------------------------------------------------------------------+------------|
| getAuctionId(uint256)                                            | 12f4ea2e   |
|------------------------------------------------------------------+------------|
| getRoleAdmin(bytes32)                                            | 248a9ca3   |
|------------------------------------------------------------------+------------|
| grantForAuction(uint256,uint256,uint256,uint256,uint256,uint256) | 8ad99890   |
|------------------------------------------------------------------+------------|
| grantRole(bytes32,address)                                       | 2f2ff15d   |
|------------------------------------------------------------------+------------|
| hasRole(bytes32,address)                                         | 91d14854   |
|------------------------------------------------------------------+------------|
| owner()                                                          | 8da5cb5b   |
|------------------------------------------------------------------+------------|
| previewAuctionListing(uint256)                                   | 9edd6551   |
|------------------------------------------------------------------+------------|
| previewListing(uint256)                                          | 2e05e55c   |
|------------------------------------------------------------------+------------|
| registerListings(address,uint256,uint256)                        | 6dee5fd4   |
|------------------------------------------------------------------+------------|
| renounceOwnership()                                              | 715018a6   |
|------------------------------------------------------------------+------------|
| renounceRole(bytes32,address)                                    | 36568abe   |
|------------------------------------------------------------------+------------|
| revokeRole(bytes32,address)                                      | d547741f   |
|------------------------------------------------------------------+------------|
| supportsInterface(bytes4)                                        | 01ffc9a7   |
|------------------------------------------------------------------+------------|
| transferOwnership(address)                                       | f2fde38b   |
|------------------------------------------------------------------+------------|
| updateAuctionListings()                                          | 74f471c0   |
╰------------------------------------------------------------------+------------╯ */

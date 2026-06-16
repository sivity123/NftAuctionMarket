//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {NftAuctionMarket} from "src/NftAuctionMarket.sol";
import {MinimalNft} from "src/MinimalNft.sol";

contract DeployNftAuctionMarket is Script {
    address deployerAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // anvil primary ac

    function run() external returns (address, address) {
        if (block.chainid == 11155111) {
            deployerAddress = vm.envAddress("SEPOLIA_PRIMARY_ADDRESS");
        }

        vm.startBroadcast();
        NftAuctionMarket nftAuctionMarket = new NftAuctionMarket(deployerAddress);
        MinimalNft nft = new MinimalNft(deployerAddress);
        vm.stopBroadcast();

        return (address(nftAuctionMarket), address(nft));
    }
}

//SPDX-License-Identifier:MIT

pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract MinimalNft is ERC721,Ownable {

    uint256 s_nextTokenId;
    constructor(address _initialOwner) ERC721("MinimalNFt","MNFT") Ownable(_initialOwner){}


    function mint(address _to)external onlyOwner{
        _safeMint(_to,s_nextTokenId);
        s_nextTokenId +=1;
    }

}
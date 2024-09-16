// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721("MockERC721", "ME721") {
  function mint(address to, uint256 tokenId) external {
    _mint(to, tokenId);
  }

  function isApprovedForAll(address, address) public pure override returns (bool) {
    return true;
  }
}

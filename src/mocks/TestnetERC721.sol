// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestnetERC721 is ERC721 {
  uint256 public nextIdToMint;

  constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {
    nextIdToMint = 1;
  }

  function mint(address _to) external {
    _mint(_to, nextIdToMint);
    nextIdToMint++;
  }
}

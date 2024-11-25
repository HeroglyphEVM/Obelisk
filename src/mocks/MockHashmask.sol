// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IHashmask } from "src/vendor/IHashmask.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @custom:export abi
 */
contract MockHashmask is ERC721, IHashmask {
  uint256 public nextIdToMint;

  mapping(uint256 => string) public tokenNames;

  event NameChanged(uint256 indexed tokenId, string name);

  constructor() ERC721("Mockmask", "MHM") {
    nextIdToMint = 1;
  }

  function mint(address _to) external {
    _mint(_to, nextIdToMint);
    nextIdToMint++;
  }

  function changeName(uint256 _tokenId, string memory _name) external {
    tokenNames[_tokenId] = _name;
    emit NameChanged(_tokenId, _name);
  }

  function tokenNameByIndex(uint256 _tokenId) external view returns (string memory) {
    return tokenNames[_tokenId];
  }
}

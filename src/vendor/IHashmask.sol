// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IHashmask is IERC721 {
  function tokenNameByIndex(uint256 _tokenId) external view returns (string memory);
}

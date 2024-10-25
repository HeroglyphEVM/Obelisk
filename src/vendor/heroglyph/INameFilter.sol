// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface INameFilter {
  function isNameValid(string calldata _str) external pure returns (bool valid_);

  function isNameValidWithIndexError(string calldata _str)
    external
    pure
    returns (bool, uint256 index);
}

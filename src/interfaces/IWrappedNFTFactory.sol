// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IWrappedNFTFactory {
  error NotRegistry();

  function createWrappedNFT(
    address _collection,
    address _obeliskRegistry,
    uint256 _totalSupply,
    uint32 _unixTimeCreation,
    bool _premium
  ) external returns (address addr_);
}

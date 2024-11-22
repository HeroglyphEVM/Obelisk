// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IWrappedNFTFactory {
  error NotRegistry();

  event WrappedNFTCreated(
    uint256 indexed id, address indexed addr, address indexed collection
  );

  function createWrappedNFT(
    address _collection,
    address _obeliskRegistry,
    uint256 _totalSupply,
    uint32 _unixTimeCreation,
    bool _premium
  ) external returns (address addr_);
}

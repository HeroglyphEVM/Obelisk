pragma solidity ^0.8.25;

import { WrappedNFTHero } from "src/services/nft/WrappedNFTHero.sol";
import { IWrappedNFTFactory } from "src/interfaces/IWrappedNFTFactory.sol";

contract WrappedNFTFactory is IWrappedNFTFactory {
  address public immutable HCT_ADDRESS;
  address public immutable NFT_PASS;
  address public immutable REGISTRY;

  mapping(address => bool) public generators;

  constructor(address _hctAddress, address _nftPass) {
    REGISTRY = msg.sender;
    HCT_ADDRESS = _hctAddress;
    NFT_PASS = _nftPass;
  }

  function createWrappedNFT(
    address _collection,
    address _obeliskRegistry,
    uint256 _totalSupply,
    uint32 _unixTimeCreation,
    bool _premium
  ) external override returns (address addr_) {
    if (msg.sender != REGISTRY) revert NotRegistry();

    addr_ = address(
      new WrappedNFTHero(
        HCT_ADDRESS,
        NFT_PASS,
        _collection,
        _obeliskRegistry,
        _totalSupply,
        _unixTimeCreation,
        _premium
      )
    );

    return addr_;
  }
}

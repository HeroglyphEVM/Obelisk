// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";

abstract contract LiteTicker is ILiteTicker {
  uint256 internal constant DEPOSIT_AMOUNT = 1e18;

  IObeliskRegistry public immutable registry;
  mapping(address service => mapping(uint256 tokenId => bool)) public isTokenDeposited;

  constructor(address _registry) {
    registry = IObeliskRegistry(_registry);
  }

  modifier onlyWrappedNFT() {
    if (!registry.isWrappedNFT(msg.sender)) revert NotWrappedNFT();
    _;
  }

  function virtualDeposit(uint256 _tokenId, address _holder) external override onlyWrappedNFT {
    if (isTokenDeposited[msg.sender][_tokenId]) revert AlreadyDeposited();
    isTokenDeposited[msg.sender][_tokenId] = true;
    _afterVirtualDeposit(_holder);

    emit Deposited(_holder, msg.sender, _tokenId);
  }

  function virtualWithdraw(uint256 _tokenId, address _holder, bool _ignoreRewards) external override onlyWrappedNFT {
    if (!isTokenDeposited[msg.sender][_tokenId]) revert NotDeposited();
    isTokenDeposited[msg.sender][_tokenId] = false;
    _afterVirtualWithdraw(_holder, _ignoreRewards);

    emit Withdrawn(_holder, msg.sender, _tokenId);
  }

  function claim(uint256 _tokenId, address _holder, bool _ignoreRewards) external override onlyWrappedNFT {
    if (!isTokenDeposited[msg.sender][_tokenId]) revert NotDeposited();
    _onClaimTriggered(_holder, _ignoreRewards);
  }

  function _afterVirtualDeposit(address _holder) internal virtual;
  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal virtual;
  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal virtual;
}

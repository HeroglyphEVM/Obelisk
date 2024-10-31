// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { IObeliskNFT } from "src/interfaces/IObeliskNFT.sol";
/**
 * @title LiteTicker
 * @notice Base Ticker logic for Obelisk.
 */

abstract contract LiteTicker is ILiteTicker {
  uint256 internal constant DEPOSIT_AMOUNT = 1e18;

  IObeliskRegistry public immutable registry;
  mapping(address service => mapping(uint256 tokenId => bool)) public isDeposited;

  constructor(address _registry) {
    registry = IObeliskRegistry(_registry);
  }

  modifier onlyWrappedNFT() {
    if (!registry.isWrappedNFT(msg.sender)) revert NotWrappedNFT();
    _;
  }

  function virtualDeposit(bytes32 _identity, uint256 _tokenId, address _receiver)
    external
    override
    onlyWrappedNFT
  {
    if (isDeposited[msg.sender][_tokenId]) revert AlreadyDeposited();
    isDeposited[msg.sender][_tokenId] = true;

    _afterVirtualDeposit(_identity, _receiver);

    emit Deposited(msg.sender, _tokenId);
  }

  function virtualWithdraw(
    bytes32 _identity,
    uint256 _tokenId,
    address _receiver,
    bool _ignoreRewards
  ) external override onlyWrappedNFT {
    if (!isDeposited[msg.sender][_tokenId]) revert NotDeposited();
    isDeposited[msg.sender][_tokenId] = false;

    _afterVirtualWithdraw(_identity, _receiver, _ignoreRewards);

    emit Withdrawn(msg.sender, _tokenId);
  }

  function claim(
    bytes32 _identity,
    uint256 _tokenId,
    address _receiver,
    bool _ignoreRewards
  ) external override onlyWrappedNFT {
    if (!isDeposited[msg.sender][_tokenId]) revert NotDeposited();

    _onClaimTriggered(_identity, _receiver, _ignoreRewards);
  }

  function _afterVirtualDeposit(bytes32 _identity, address _receiver) internal virtual;

  function _afterVirtualWithdraw(
    bytes32 _identity,
    address _receiver,
    bool _ignoreRewards
  ) internal virtual;

  function _onClaimTriggered(bytes32 _identity, address _receiver, bool _ignoreRewards)
    internal
    virtual;
}

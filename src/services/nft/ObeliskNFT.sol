// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskNFT } from "src/interfaces/IObeliskNFT.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";

import { strings } from "src/lib/strings.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ObeliskNFT
 * @notice Base contract for Obelisk NFTs. It contains the staking logic via name.
 */
abstract contract ObeliskNFT is IObeliskNFT, ReentrancyGuard {
  using strings for string;
  using strings for strings.slice;

  string public constant TICKER_START_INDICE = "#";
  string public constant TICKER_SPLIT_STRING = ",";
  string public constant TICKER_START_IDENTITY = "@";
  uint32 public constant MAX_NAME_BYTES_LENGTH = 29;
  IObeliskRegistry public immutable obeliskRegistry;
  INFTPass public immutable NFT_PASS;

  mapping(uint256 => address[]) internal linkedTickers;
  mapping(uint256 => string) public names;
  mapping(uint256 => address) internal identityReceivers;

  constructor(address _obeliskRegistry, address _nftPass) {
    obeliskRegistry = IObeliskRegistry(_obeliskRegistry);
    NFT_PASS = INFTPass(_nftPass);
  }

  function rename(uint256 _tokenId, string memory _newName) external {
    uint256 nameBytesLength = bytes(_newName).length;
    if (nameBytesLength == 0 || nameBytesLength > MAX_NAME_BYTES_LENGTH) revert InvalidNameLength();
    _renameRequirements(_tokenId);

    address registeredUserAddress = identityReceivers[_tokenId];
    _removeOldTickers(registeredUserAddress, _tokenId, false);

    address newReceiver = _updateIdentity(_tokenId, _newName);
    _addNewTickers(newReceiver, _tokenId, _newName);

    emit NameChanged(_tokenId, _newName);
    names[_tokenId] = _newName;
  }

  function _renameRequirements(uint256 _tokenId) internal virtual;

  function updateIdentityReceiver(uint256 _tokenId) external {
    string memory currentName = names[_tokenId];

    address registeredUserAddress = identityReceivers[_tokenId];
    _removeOldTickers(registeredUserAddress, _tokenId, false);

    address newReceiver = _updateIdentity(_tokenId, currentName);
    _addNewTickers(newReceiver, _tokenId, currentName);
  }

  function _removeOldTickers(address _registeredUserAddress, uint256 _tokenId, bool _ignoreRewards)
    internal
    nonReentrant
  {
    address[] memory activePools = linkedTickers[_tokenId];
    delete linkedTickers[_tokenId];

    for (uint256 i = 0; i < activePools.length; i++) {
      ILiteTicker(activePools[i]).virtualWithdraw(_tokenId, _registeredUserAddress, _ignoreRewards);
      emit TickerDeactivated(_tokenId, activePools[i]);
    }
  }

  function _addNewTickers(address _registeredUserAddress, uint256 _tokenId, string memory _name) internal virtual {
    strings.slice memory nameSlice = _name.toSlice();
    strings.slice memory needle = TICKER_START_INDICE.toSlice();
    strings.slice memory substring = nameSlice.find(needle).beyond(needle).split(string(" ").toSlice());
    strings.slice memory delim = TICKER_SPLIT_STRING.toSlice();

    address[] memory poolTargets = new address[](substring.count(delim) + 1);

    address poolTarget;
    for (uint256 i = 0; i < poolTargets.length; i++) {
      poolTarget = obeliskRegistry.getTickerLogic(substring.split(delim).toString());
      if (poolTarget == address(0)) continue;

      poolTargets[i] = poolTarget;

      ILiteTicker(poolTarget).virtualDeposit(_tokenId, _registeredUserAddress);
      emit TickerActivated(_tokenId, poolTarget);
    }

    linkedTickers[_tokenId] = poolTargets;
  }

  function _updateIdentity(uint256 _tokenId, string memory _name) internal virtual returns (address receiver_) {
    strings.slice memory nameSlice = _name.toSlice();
    strings.slice memory needle = TICKER_START_IDENTITY.toSlice();
    strings.slice memory substring = nameSlice.find(needle).beyond(needle).split(string(" ").toSlice());

    receiver_ = NFT_PASS.getMetadata(0, substring.toString()).walletReceiver;

    if (receiver_ == address(0)) revert InvalidWalletReceiver();
    identityReceivers[_tokenId] = receiver_;

    return receiver_;
  }

  function claim(uint256 _tokenId) external {
    address[] memory activePools = linkedTickers[_tokenId];
    bool canClaim = _claimRequirements(_tokenId);

    for (uint256 i = 0; i < activePools.length; i++) {
      ILiteTicker(activePools[i]).claim(_tokenId, identityReceivers[_tokenId], !canClaim);
      emit TickerClaimed(_tokenId, activePools[i]);
    }
  }

  function _claimRequirements(uint256 _tokenId) internal view virtual returns (bool);

  function getLinkedTickers(uint256 _tokenId) external view returns (address[] memory) {
    return linkedTickers[_tokenId];
  }

  function getIdentityReceiver(uint256 _tokenId) external view returns (address) {
    return identityReceivers[_tokenId];
  }
}

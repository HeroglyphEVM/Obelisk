// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IdentityERC721 } from "src/vendor/heroglyph/IdentityERC721.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract NFTPass is INFTPass, IdentityERC721 {
  uint256 internal constant MAX_BPS = 10_000;

  uint32 public resetCounterTimestamp;
  uint32 public boughtToday;
  uint32 public maxIdentityPerDayAtInitialPrice;
  uint32 public priceIncreaseThreshold;
  uint32 public priceDecayBPS;
  uint256 public currentPrice;

  mapping(uint256 => Metadata) internal metadataPasses;

  constructor(
    address _owner,
    address _treasury,
    address _nameFilter,
    uint256 _cost, //0.05
    string memory _name,
    string memory _symbol
  ) IdentityERC721(_owner, _treasury, _nameFilter, _cost, _name, _symbol) {
    resetCounterTimestamp = uint32(block.timestamp + 1 days);
    currentPrice = cost;
    maxIdentityPerDayAtInitialPrice = 25;
    priceIncreaseThreshold = 10;
    priceDecayBPS = 2500;
  }

  function create(string calldata _name, address _receiverWallet) external payable {
    if (cost == 0 && msg.value != 0) revert NoNeedToPay();
    if (_receiverWallet == address(0)) _receiverWallet = msg.sender;

    uint256 id = _create(_name, _updateCost());
    metadataPasses[id] = Metadata({ name: _name, walletReceiver: _receiverWallet });

    emit NFTPassCreated(id, _name, _receiverWallet);
  }

  function updateReceiverAddress(uint256 _nftId, string calldata _name, address _receiver) external {
    if (_nftId == 0) {
      _nftId = identityIds[_name];
    }

    if (ownerOf(_nftId) != msg.sender) revert NotIdentityOwner();

    Metadata storage metadata = metadataPasses[_nftId];
    metadata.walletReceiver = _receiver;

    emit NFTPassUpdated(_nftId, _name, _receiver);
  }

  function _updateCost() internal returns (uint256 userCost_) {
    (resetCounterTimestamp, boughtToday, currentPrice, userCost_) = _getCostDetails();
    return userCost_;
  }

  function getCost() external view returns (uint256 userCost_) {
    (,,, userCost_) = _getCostDetails();
    return userCost_;
  }

  function _getCostDetails()
    internal
    view
    returns (
      uint32 resetCounterTimestampReturn_,
      uint32 boughtTodayReturn_,
      uint256 currentCostReturn_,
      uint256 userCost_
    )
  {
    uint32 maxPerDayCached = maxIdentityPerDayAtInitialPrice;
    resetCounterTimestampReturn_ = resetCounterTimestamp;
    boughtTodayReturn_ = boughtToday;
    currentCostReturn_ = currentPrice;

    if (block.timestamp >= resetCounterTimestampReturn_) {
      uint256 totalDayPassed = (block.timestamp - resetCounterTimestampReturn_) / 1 days + 1;
      resetCounterTimestampReturn_ += uint32(1 days * totalDayPassed);
      boughtTodayReturn_ = 0;

      for (uint256 i = 0; i < totalDayPassed; ++i) {
        currentCostReturn_ =
          Math.max(cost, currentCostReturn_ - Math.mulDiv(currentCostReturn_, priceDecayBPS, MAX_BPS));

        if (currentCostReturn_ <= cost) break;
      }
    }

    bool boughtExceedsMaxPerDay = boughtTodayReturn_ > maxPerDayCached;

    if (boughtExceedsMaxPerDay && (boughtTodayReturn_ - maxPerDayCached) % priceIncreaseThreshold == 0) {
      currentCostReturn_ += cost / 2;
    }

    userCost_ = !boughtExceedsMaxPerDay ? cost : currentCostReturn_;
    boughtTodayReturn_++;

    return (resetCounterTimestampReturn_, boughtTodayReturn_, currentCostReturn_, userCost_);
  }

  function getMetadata(uint256 _nftId) external view returns (Metadata memory) {
    return metadataPasses[_nftId];
  }

  function getMetadataWithName(string calldata _name) external view override returns (Metadata memory) {
    return metadataPasses[identityIds[_name]];
  }
}

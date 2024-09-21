// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IdentityERC721 } from "src/vendor/heroglyph/IdentityERC721.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";

import { FixedPointMathLib as Math } from "src/vendor/solmate/FixedPointMathLib.sol";

contract NFTPass is INFTPass, IdentityERC721 {
  uint256 internal constant MAX_BPS = 10_000;

  uint32 public immutable MAX_IDENTITY_PER_DAY_AT_INITIAL_PRICE;
  uint32 public immutable PRICE_INCREASE_THRESHOLD;
  uint32 public immutable PRICE_DECAY_BPS;
  uint32 public resetCounterTimestamp;
  uint32 public boughtToday;
  uint256 public currentPrice;

  mapping(uint256 => Metadata) internal metadataPasses;

  constructor(address _owner, address _treasury, address _nameFilter, uint256 _cost)
    IdentityERC721(_owner, _treasury, _nameFilter, _cost, "Obelisk NFT Pass", "OPASS")
  {
    resetCounterTimestamp = uint32(block.timestamp + 1 days);
    currentPrice = cost;
    MAX_IDENTITY_PER_DAY_AT_INITIAL_PRICE = 25;
    PRICE_INCREASE_THRESHOLD = 10;
    PRICE_DECAY_BPS = 2500;
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
    uint32 maxPerDayCached = MAX_IDENTITY_PER_DAY_AT_INITIAL_PRICE;
    resetCounterTimestampReturn_ = resetCounterTimestamp;
    boughtTodayReturn_ = boughtToday;
    currentCostReturn_ = currentPrice;

    if (block.timestamp >= resetCounterTimestampReturn_) {
      uint256 totalDayPassed = (block.timestamp - resetCounterTimestampReturn_) / 1 days + 1;
      resetCounterTimestampReturn_ += uint32(1 days * totalDayPassed);
      boughtTodayReturn_ = 0;

      for (uint256 i = 0; i < totalDayPassed; ++i) {
        currentCostReturn_ =
          Math.max(cost, currentCostReturn_ - Math.mulDivDown(currentCostReturn_, PRICE_DECAY_BPS, MAX_BPS));

        if (currentCostReturn_ <= cost) break;
      }
    }

    bool boughtExceedsMaxPerDay = boughtTodayReturn_ > maxPerDayCached;

    if (boughtExceedsMaxPerDay && (boughtTodayReturn_ - maxPerDayCached) % PRICE_INCREASE_THRESHOLD == 0) {
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

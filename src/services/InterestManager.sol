// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

import { IInterestManager } from "src/interfaces/IInterestManager.sol";

contract InterestManager is IInterestManager, Ownable {
  uint256 public constant PRECISION = 1e18;

  uint64 public epochId;
  address public gaugeController;

  IDripVault public dripVault;
  mapping(address => uint128) internal pendingRewards;
  mapping(uint64 => Epoch) public epochs;

  constructor(address _owner, address _gaugeController) Ownable(_owner) {
    gaugeController = _gaugeController;
  }

  function applyGauges(address[] memory _megapools, uint128[] memory _weights) external override {
    if (msg.sender != gaugeController) revert NotGaugeController();

    _endEpoch();
    Epoch storage epoch = epochs[epochId];

    uint256 megapoolsLength = _megapools.length;
    if (megapoolsLength != _weights.length) revert InvalidInputLength();

    uint128 weight;
    uint128 totalWeight;
    address megapool;

    for (uint256 i = 0; i < megapoolsLength; ++i) {
      megapool = _megapools[i];
      weight = _weights[i];

      epoch.megapools.push(megapool);
      epoch.megapoolToWeight[megapool] += weight;
      totalWeight += weight;
    }

    epoch.totalWeight = totalWeight;
    emit EpochIntialized(epochId, _megapools, _weights, totalWeight);
  }

  function _endEpoch() internal {
    Epoch storage epoch = epochs[epochId];

    for (uint256 i = 0; i < epoch.megapools.length; ++i) {
      _claim(epoch, epoch.megapools[i]);
    }

    epochId++;
  }

  function claim() external override returns (uint256 rewards_) {
    Epoch storage epoch = epochs[epochId];
    return _claim(epoch, msg.sender);
  }

  function _claim(Epoch storage _epoch, address _megapool) internal returns (uint128 rewards_) {
    rewards_ = _getRewards(_epoch, _megapool);

    _epoch.totalRewards += uint128(dripVault.claim());
    _epoch.megapoolClaims[_megapool] += rewards_;
    pendingRewards[_megapool] += rewards_;

    return rewards_;
  }

  function setGaugeController(address _gaugeController) external onlyOwner {
    gaugeController = _gaugeController;
    emit GaugeControllerSet(gaugeController);
  }

  function getRewards(address _megapool) external view override returns (uint256) {
    return _getRewards(epochs[epochId], _megapool);
  }

  function _getRewards(Epoch storage epoch, address _megapool) internal view returns (uint128 rewards_) {
    uint128 remainingRewards = epoch.totalRewards;
    uint256 weight = epoch.megapoolToWeight[_megapool];
    uint256 totalClaimed = epoch.megapoolClaims[_megapool];
    uint256 ratio = Math.mulDiv(weight, PRECISION, epoch.totalWeight);

    rewards_ = pendingRewards[_megapool];
    if (weight == 0) return rewards_;

    uint256 totalRewards = uint128(Math.mulDiv(remainingRewards, PRECISION, ratio));
    rewards_ += uint128(totalRewards - totalClaimed);

    return rewards_;
  }
}

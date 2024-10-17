// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IInterestManager } from "src/interfaces/IInterestManager.sol";

/**
 * @title Megapool
 * @notice It receives yield from the deposited ETH from unlocking a collection.
 * @dev Megapool has a max entry limit.
 */
contract Megapool is LiteTicker, Ownable, ReentrancyGuard {
  error MaxEntryExceeded();

  event MaxEntryUpdated(uint256 newMaxEntry);

  ERC20 public immutable REWARD_TOKEN;

  uint256 public yieldPerTokenInRay;
  uint256 public yieldBalance;
  uint256 public totalVirtualBalance;
  uint256 public maxEntry;

  IInterestManager public immutable INTEREST_MANAGER;

  mapping(address => uint256) internal userYieldSnapshot;
  mapping(address => uint256) private virtualBalances;

  constructor(address _owner, address _registry, address _tokenReward, address _interestManager)
    LiteTicker(_registry)
    Ownable(_owner)
  {
    REWARD_TOKEN = ERC20(_tokenReward);
    INTEREST_MANAGER = IInterestManager(_interestManager);
    maxEntry = 1000e18;
  }

  function _afterVirtualDeposit(address _holder) internal override {
    _claim(_holder, false);

    uint256 userVirtualBalance = virtualBalances[_holder] + DEPOSIT_AMOUNT;

    virtualBalances[_holder] = userVirtualBalance;

    totalVirtualBalance += DEPOSIT_AMOUNT;

    if (totalVirtualBalance > maxEntry) {
      revert MaxEntryExceeded();
    }

    userYieldSnapshot[_holder] = ShareableMath.rmulup(userVirtualBalance, yieldPerTokenInRay);
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);

    uint256 userVirtualBalance = virtualBalances[_holder] - DEPOSIT_AMOUNT;
    virtualBalances[_holder] = userVirtualBalance;

    totalVirtualBalance -= DEPOSIT_AMOUNT;
    userYieldSnapshot[_holder] = ShareableMath.rmulup(userVirtualBalance, yieldPerTokenInRay);
  }

  function _getNewYield() internal view returns (uint256) {
    return REWARD_TOKEN.balanceOf(address(this)) - yieldBalance;
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);
  }

  function _claim(address _holder, bool _ignoreRewards) internal nonReentrant {
    INTEREST_MANAGER.claim();
    uint256 currentYieldBalance = REWARD_TOKEN.balanceOf(address(this));

    if (totalVirtualBalance > 0) {
      yieldPerTokenInRay = yieldPerTokenInRay + ShareableMath.rdiv(_getNewYield(), totalVirtualBalance);
    } else if (currentYieldBalance != 0) {
      REWARD_TOKEN.transfer(owner(), currentYieldBalance);
    }

    uint256 last = userYieldSnapshot[_holder];
    uint256 curr = ShareableMath.rmul(virtualBalances[_holder], yieldPerTokenInRay);

    if (curr > last && !_ignoreRewards) {
      uint256 sendingReward = curr - last;
      REWARD_TOKEN.transfer(_holder, sendingReward);
    }

    yieldBalance = REWARD_TOKEN.balanceOf(address(this));
  }

  function updateMaxEntry(uint256 _newMaxEntry) external onlyOwner {
    maxEntry = _newMaxEntry;
    emit MaxEntryUpdated(_newMaxEntry);
  }

  function getVirtualBalanceOf(address _holder) external view returns (uint256) {
    return virtualBalances[_holder];
  }

  function getYieldSnapshotOf(address _target) external view returns (uint256) {
    return userYieldSnapshot[_target];
  }
}

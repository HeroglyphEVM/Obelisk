// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Megapool is LiteTicker, Ownable, ReentrancyGuard {
  error MaxEntryExceeded();

  event MaxEntryUpdated(uint256 newMaxEntry);

  uint256 private constant WAD = 1e18;
  ERC20 public immutable REWARD_TOKEN;

  uint256 public yieldPerTokenInRay;
  uint256 public yieldBalance;
  uint256 public totalShares;
  uint256 public totalVirtualBalance;
  uint256 public maxEntry;

  mapping(address => uint256) internal userYieldSnapshot;
  mapping(address => uint256) internal userShares;
  mapping(address => uint256) private virtualBalances;

  constructor(address _owner, address _registry, address _tokenReward) LiteTicker(_registry) Ownable(_owner) {
    REWARD_TOKEN = ERC20(_tokenReward);
    maxEntry = 1000e18;
  }

  function _afterVirtualDeposit(address _holder) internal override {
    _claim(_holder, false);
    uint256 addedShare = 1e18;

    virtualBalances[_holder] += DEPOSIT_AMOUNT;

    if (totalShares > 0) {
      addedShare = (totalShares * DEPOSIT_AMOUNT) / totalVirtualBalance;
    }

    totalVirtualBalance += DEPOSIT_AMOUNT;

    if (totalVirtualBalance > maxEntry) {
      revert MaxEntryExceeded();
    }

    _addShare(_holder, addedShare);
  }

  function _addShare(address _wallet, uint256 _value) internal virtual {
    if (_value > 0) {
      totalShares += _value;
      userShares[_wallet] += _value;
    }

    userYieldSnapshot[_wallet] = ShareableMath.rmulup(userShares[_wallet], yieldPerTokenInRay);
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);
    virtualBalances[_holder] -= DEPOSIT_AMOUNT;

    uint256 newShare = 0;
    uint256 holderBalance = virtualBalances[_holder];

    if (totalShares > 0 && holderBalance > 0) {
      newShare = (totalShares * holderBalance) / totalVirtualBalance;
    }

    totalVirtualBalance -= DEPOSIT_AMOUNT;
    _exit(_holder, newShare);
  }

  function _exit(address _wallet, uint256 _newShare) internal virtual {
    _deleteShare(_wallet);

    if (_newShare > 0) {
      _addShare(_wallet, _newShare);
    }
  }

  function _deleteShare(address _wallet) private {
    uint256 value = userShares[_wallet];

    if (value > 0) {
      totalShares -= value;
      userShares[_wallet] -= value;
    }

    userYieldSnapshot[_wallet] = ShareableMath.rmulup(userShares[_wallet], yieldPerTokenInRay);
  }

  function _getNewYield() internal view returns (uint256) {
    return REWARD_TOKEN.balanceOf(address(this)) - yieldBalance;
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);
  }

  function _claim(address _holder, bool _ignoreRewards) internal nonReentrant {
    uint256 currentYieldBalance = REWARD_TOKEN.balanceOf(address(this));

    if (totalShares > 0) {
      yieldPerTokenInRay = yieldPerTokenInRay + ShareableMath.rdiv(_getNewYield(), totalShares);
    } else if (currentYieldBalance != 0) {
      REWARD_TOKEN.transfer(owner(), currentYieldBalance);
    }

    uint256 last = userYieldSnapshot[_holder];
    uint256 curr = ShareableMath.rmul(userShares[_holder], yieldPerTokenInRay);

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

  function getShareOf(address owner) public view returns (uint256) {
    return userShares[owner];
  }
}

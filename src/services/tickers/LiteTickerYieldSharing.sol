// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Shareable, ShareableMath } from "src/lib/Shareable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiteTickerYieldSharing is LiteTicker, Shareable, ReentrancyGuard {
  ERC20 public immutable REWARD_TOKEN;

  uint256 public systemBalance;
  mapping(address => uint256) private balances;

  constructor(address _owner, address _registry, address _tokenReward) LiteTicker(_owner, _registry) {
    REWARD_TOKEN = ERC20(_tokenReward);
  }

  function _afterVirtualDeposit(address _holder) internal override {
    _claim(_holder, false);
    uint256 value = 1e18;
    uint256 newShare = 1e18;

    balances[_holder] += value;

    if (totalWeight > 0) {
      newShare = (totalWeight * value) / systemBalance;
    }

    systemBalance += value;

    _addShare(_holder, newShare);
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);
    uint256 value = 1e18;

    uint256 newShare = 0;
    uint256 balanceTotal = balances[_holder] -= value;

    if (totalWeight > 0 && balanceTotal > 0) {
      newShare = (totalWeight * balanceTotal) / systemBalance;
    }

    systemBalance -= value;
    _partialExitShare(_holder, newShare);
  }

  function _crop() internal view override returns (uint256) {
    return REWARD_TOKEN.balanceOf(address(this)) - stock;
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);
  }

  function _claim(address _holder, bool _ignoreRewards) internal nonReentrant {
    if (totalWeight > 0) {
      share = share + ShareableMath.rdiv(_crop(), totalWeight);
    }

    uint256 last = crops[_holder];
    uint256 curr = ShareableMath.rmul(userShares[_holder], share);

    if (curr > last && !_ignoreRewards) {
      uint256 sendingReward = curr - last;
      REWARD_TOKEN.transfer(_holder, sendingReward);
    }

    stock = REWARD_TOKEN.balanceOf(address(this));
  }

  function getBalanceOf(address _holder) external view returns (uint256) {
    return balances[_holder];
  }
}

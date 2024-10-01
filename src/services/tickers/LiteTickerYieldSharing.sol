// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";

contract LiteTickerYieldSharing is LiteTicker, ReentrancyGuard {
  uint256 private constant DEPOSIT_AMOUNT = 1e18;
  ERC20 public immutable REWARD_TOKEN;

  uint256 public yieldPerTokenInRay;
  uint256 public yieldBalance;
  uint256 public totalCollateral;

  mapping(address => uint256) internal userYield;
  mapping(address => uint256) internal userShares;

  uint256 public systemBalance;
  mapping(address => uint256) private balances;

  constructor(address _owner, address _registry, address _tokenReward) LiteTicker(_owner, _registry) {
    REWARD_TOKEN = ERC20(_tokenReward);
  }

  function _afterVirtualDeposit(address _holder) internal override {
    _claim(_holder, false);
    uint256 newShare = 1e18;

    balances[_holder] += DEPOSIT_AMOUNT;

    if (totalCollateral > 0) {
      newShare = (totalCollateral * DEPOSIT_AMOUNT) / systemBalance;
    }

    systemBalance += DEPOSIT_AMOUNT;

    _addShare(_holder, newShare);
  }

  function _addShare(address _wallet, uint256 _value) internal virtual {
    if (_value > 0) {
      uint256 wad = ShareableMath.wdiv(_value, netAssetsPerShareWAD());
      require(int256(wad) > 0);

      totalCollateral += wad;
      userShares[_wallet] += wad;
    }
    userYield[_wallet] = ShareableMath.rmulup(userShares[_wallet], yieldPerTokenInRay);
    emit ShareUpdated(_wallet, _value);
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);

    uint256 newShare = 0;
    uint256 balanceTotal = balances[_holder] -= DEPOSIT_AMOUNT;

    if (totalCollateral > 0 && balanceTotal > 0) {
      newShare = (totalCollateral * balanceTotal) / systemBalance;
    }

    systemBalance -= DEPOSIT_AMOUNT;
    _partialExitShare(_holder, newShare);
  }

  function _exit(address _wallet, uint256 _value) internal virtual {
    _claim(_wallet, false);

    if (_value > 0) {
      uint256 wad = ShareableMath.wdivup(_value, netAssetsPerShareWAD());
      assert(int256(wad) > 0);

      totalCollateral -= wad;
      userShares[_wallet] -= wad;
    }

    userYield[_wallet] = ShareableMath.rmulup(userShares[_wallet], yieldPerTokenInRay);
  }

  function _partialExitShare(address _wallet, uint256 _newShare) internal virtual { }

  function _deleteShare(address _wallet) private {
    uint256 value = userShares[_wallet];

    if (value > 0) {
      uint256 wad = ShareableMath.wdivup(value, netAssetsPerShareWAD());

      require(int256(wad) > 0);

      totalCollateral -= wad;
      userShares[_wallet] -= wad;
    }

    userYield[_wallet] = ShareableMath.rmulup(userShares[_wallet], yieldPerTokenInRay);
  }

  function _crop() internal view override returns (uint256) {
    return REWARD_TOKEN.balanceOf(address(this)) - yieldBalance;
  }

  function netAssetsPerShareWAD() public view returns (uint256) {
    return (totalCollateral == 0) ? ShareableMath.WAD : ShareableMath.wdiv(systemBalance, totalCollateral);
  }

  function getCropsOf(address _target) external view returns (uint256) {
    return userYield[_target];
  }

  function getShareOf(address owner) public view returns (uint256) {
    return userShares[owner];
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    _claim(_holder, _ignoreRewards);
  }

  function _claim(address _holder, bool _ignoreRewards) internal nonReentrant {
    if (totalCollateral > 0) {
      yieldPerTokenInRay = yieldPerTokenInRay + ShareableMath.rdiv(_crop(), totalCollateral);
    }

    uint256 last = userYield[_holder];
    uint256 curr = ShareableMath.rmul(userShares[_holder], yieldPerTokenInRay);

    if (curr > last && !_ignoreRewards) {
      uint256 sendingReward = curr - last;
      REWARD_TOKEN.transfer(_holder, sendingReward);
    }

    yieldBalance = REWARD_TOKEN.balanceOf(address(this));
  }

  function getBalanceOf(address _holder) external view returns (uint256) {
    return balances[_holder];
  }
}

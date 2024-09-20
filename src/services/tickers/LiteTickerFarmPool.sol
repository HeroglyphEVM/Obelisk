// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ILiteTickerFarmPool } from "src/interfaces/ILiteTickerFarmPool.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title TickerPool
 * @notice Modified version of Playpen by Zefram -- Removed noises and modified to fit our system.
 */
contract LiteTickerFarmPool is LiteTicker, ILiteTickerFarmPool {
  uint256 internal constant PRECISION = 1e30;

  uint64 public immutable DISTRIBUTION_DURATION;
  IERC721 public immutable GENESIS_KEY;
  ERC20 public immutable REWARD_TOKEN;

  uint64 public lastUpdateUnixTime;
  uint64 public unixPeriodFinish;

  uint256 public rewardRatePerSecond;
  uint256 public latestRewardPerTokenStored;
  uint256 public totalSupply;

  mapping(address user => uint256) public balanceOf;
  mapping(address user => uint256) public userRewardPerTokenPaid;
  mapping(address user => uint256) public rewards;

  modifier onlyCanRefillReward() {
    if (msg.sender != address(REWARD_TOKEN) && msg.sender != owner()) revert NotAuthorized();
    _;
  }

  constructor(address _owner, address _registry, address _wrappedReward, address _genesisKey)
    LiteTicker(_owner, _registry)
  {
    GENESIS_KEY = IERC721(_genesisKey);
    REWARD_TOKEN = ERC20(_wrappedReward);
    DISTRIBUTION_DURATION = 30 days;
  }

  function _afterVirtualDeposit(address _holder) internal override {
    if (address(GENESIS_KEY) != address(0) && GENESIS_KEY.balanceOf(_holder) == 0) revert MissingKey();
    uint256 amount = 1e18;

    uint256 accountBalance = balanceOf[_holder];
    uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
    uint256 totalSupply_ = totalSupply;
    uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, lastTimeRewardApplicable_, rewardRatePerSecond);

    latestRewardPerTokenStored = rewardPerToken_;
    lastUpdateUnixTime = lastTimeRewardApplicable_;
    rewards[_holder] = _earned(_holder, accountBalance, rewardPerToken_, rewards[_holder]);
    userRewardPerTokenPaid[_holder] = rewardPerToken_;

    totalSupply = totalSupply_ + amount;
    balanceOf[_holder] = accountBalance + amount;
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    uint256 amount = 1e18;

    uint256 accountBalance = balanceOf[_holder];
    uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
    uint256 totalSupply_ = totalSupply;
    uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, lastTimeRewardApplicable_, rewardRatePerSecond);

    latestRewardPerTokenStored = rewardPerToken_;
    lastUpdateUnixTime = lastTimeRewardApplicable_;
    rewards[_holder] = _earned(_holder, accountBalance, rewardPerToken_, rewards[_holder]);
    userRewardPerTokenPaid[_holder] = rewardPerToken_;

    balanceOf[_holder] = accountBalance - amount;
    unchecked {
      totalSupply = totalSupply_ - amount;
    }

    REWARD_TOKEN.transfer(_holder, amount);
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    uint256 accountBalance = balanceOf[_holder];
    uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
    uint256 totalSupply_ = totalSupply;
    uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, lastTimeRewardApplicable_, rewardRatePerSecond);
    uint256 reward = _earned(_holder, accountBalance, rewardPerToken_, rewards[_holder]);

    latestRewardPerTokenStored = rewardPerToken_;
    lastUpdateUnixTime = lastTimeRewardApplicable_;
    userRewardPerTokenPaid[_holder] = rewardPerToken_;

    if (reward == 0) return;

    rewards[_holder] = 0;

    if (_ignoreRewards) {
      REWARD_TOKEN.transfer(owner(), reward);
      return;
    }

    REWARD_TOKEN.transfer(_holder, reward);
    emit RewardPaid(_holder, reward);
  }

  function notifyRewardAmount(uint256 reward) external override onlyCanRefillReward {
    if (reward == 0) return;

    uint256 rewardRate_ = rewardRatePerSecond;
    uint64 unixPeriodFinish_ = unixPeriodFinish;
    uint64 lastTimeRewardApplicable_ = block.timestamp < unixPeriodFinish_ ? uint64(block.timestamp) : unixPeriodFinish_;
    uint64 DURATION_ = DISTRIBUTION_DURATION;
    uint256 totalSupply_ = totalSupply;

    latestRewardPerTokenStored = _rewardPerToken(totalSupply_, lastTimeRewardApplicable_, rewardRate_);
    lastUpdateUnixTime = lastTimeRewardApplicable_;

    uint256 newRewardRate;
    if (block.timestamp >= unixPeriodFinish_) {
      newRewardRate = reward / DURATION_;
    } else {
      uint256 remaining = unixPeriodFinish_ - block.timestamp;
      uint256 leftover = remaining * rewardRate_;
      newRewardRate = (reward + leftover) / DURATION_;
    }
    if (newRewardRate >= ((type(uint256).max / PRECISION) / DURATION_)) {
      revert AmountTooLarge();
    }
    rewardRatePerSecond = newRewardRate;
    lastUpdateUnixTime = uint64(block.timestamp);
    unixPeriodFinish = uint64(block.timestamp + DURATION_);

    emit RewardAdded(reward);
  }

  function rewardPerToken() external view override returns (uint256) {
    return _rewardPerToken(totalSupply, lastTimeRewardApplicable(), rewardRatePerSecond);
  }

  function earned(address account) external view override returns (uint256) {
    return _earned(
      account,
      balanceOf[account],
      _rewardPerToken(totalSupply, lastTimeRewardApplicable(), rewardRatePerSecond),
      rewards[account]
    );
  }

  function _earned(address account, uint256 accountBalance, uint256 rewardPerToken_, uint256 accountRewards)
    internal
    view
    returns (uint256)
  {
    return Math.mulDiv(accountBalance, rewardPerToken_ - userRewardPerTokenPaid[account], PRECISION) + accountRewards;
  }

  function _rewardPerToken(uint256 totalSupply_, uint256 lastTimeRewardApplicable_, uint256 rewardRate_)
    internal
    view
    returns (uint256)
  {
    if (totalSupply_ == 0) {
      return latestRewardPerTokenStored;
    }
    return latestRewardPerTokenStored
      + Math.mulDiv((lastTimeRewardApplicable_ - lastUpdateUnixTime) * PRECISION, rewardRate_, totalSupply_);
  }

  function lastTimeRewardApplicable() public view returns (uint64) {
    return block.timestamp < unixPeriodFinish ? uint64(block.timestamp) : unixPeriodFinish;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { IGenesisTokenPool } from "src/interfaces/IGenesisTokenPool.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GenesisTokenPool
 * @notice Time-based rewards distribution for Heroglyph's Genesis tokens. It uses wrapped version to simplify LayerZero
 * issue in the genesis tokens.
 */
contract GenesisTokenPool is IGenesisTokenPool, LiteTicker, Ownable {
  uint256 internal constant PRECISION = 1e18;
  uint256 internal constant REAL_VALUE_PRECISION = PRECISION * PRECISION;
  uint256 internal constant RATIO_DENOMINATOR = 1000;

  uint64 public immutable DISTRIBUTION_DURATION;
  IERC721 public immutable GENESIS_KEY;
  ERC20 public immutable REWARD_TOKEN;

  uint64 public lastUpdateUnixTime;
  uint64 public unixPeriodFinish;

  uint256 public rewardRatePerSecond;
  uint256 public latestRewardPerTokenStored;
  uint256 public totalSupply;
  uint256 public queuedReward;

  mapping(address user => uint256) public balanceOf;
  mapping(address user => uint256) public userRewardPerTokenPaid;
  mapping(address user => uint256) public rewards;

  constructor(address _owner, address _registry, address _wrappedReward, address _genesisKey)
    LiteTicker(_registry)
    Ownable(_owner)
  {
    GENESIS_KEY = IERC721(_genesisKey);
    REWARD_TOKEN = ERC20(_wrappedReward);
    DISTRIBUTION_DURATION = 30 days;
  }

  function _afterVirtualDeposit(address _holder) internal override {
    _queueNewRewards(0);

    if (address(GENESIS_KEY) != address(0) && GENESIS_KEY.balanceOf(_holder) == 0) revert MissingKey();
    uint256 accountBalance = balanceOf[_holder];

    _updateReward(_holder, accountBalance);

    totalSupply += DEPOSIT_AMOUNT;
    accountBalance += DEPOSIT_AMOUNT;

    balanceOf[_holder] = accountBalance;
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    _queueNewRewards(0);
    _onClaimTriggered(_holder, _ignoreRewards);

    totalSupply -= DEPOSIT_AMOUNT;
    balanceOf[_holder] -= DEPOSIT_AMOUNT;
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    uint256 reward = _updateReward(_holder, balanceOf[_holder]);

    if (reward == 0) return;
    rewards[_holder] = 0;

    if (_ignoreRewards) {
      _queueNewRewards(reward);
      emit RewardIgnored(_holder, reward);
      return;
    }

    REWARD_TOKEN.transfer(_holder, reward);
    emit RewardPaid(_holder, reward);
  }

  function notifyRewardAmount(uint256 reward) external override {
    if (msg.sender != address(REWARD_TOKEN) && msg.sender != owner()) revert NotAuthorized();

    _queueNewRewards(reward);
  }

  function _queueNewRewards(uint256 _rewards) internal {
    _rewards = _rewards + queuedReward;
    if (_rewards == 0) return;

    if (block.timestamp >= unixPeriodFinish) {
      _notifyRewardAmount(_rewards);
      queuedReward = 0;
      return;
    }

    uint256 elapsedTime = unixPeriodFinish - block.timestamp;
    uint256 currentAtNow = _getTimeBasedValue(elapsedTime, rewardRatePerSecond);
    uint256 queuedRatio = Math.mulDiv(currentAtNow, RATIO_DENOMINATOR, _rewards);

    //If the rewardRatePerSecond is lower than the current one, we queue the rewards
    if (queuedRatio < RATIO_DENOMINATOR) {
      _notifyRewardAmount(_rewards);
      queuedReward = 0;
    } else {
      queuedReward = _rewards;
    }
  }

  function _notifyRewardAmount(uint256 reward) internal {
    _updateReward(address(0), 0);

    uint64 unixPeriodFinishCached = unixPeriodFinish;
    uint256 cachedRewardRatePerSecond = rewardRatePerSecond;

    if (block.timestamp < unixPeriodFinishCached) {
      reward += _getTimeBasedValue(unixPeriodFinishCached - block.timestamp, cachedRewardRatePerSecond);
    }

    rewardRatePerSecond = Math.mulDiv(reward, PRECISION, DISTRIBUTION_DURATION);

    lastUpdateUnixTime = uint64(block.timestamp);
    unixPeriodFinish = uint64(block.timestamp + DISTRIBUTION_DURATION);

    emit RewardAdded(reward);
  }

  function _getTimeBasedValue(uint256 _timePassed, uint256 _scaledRatePerSecond) private pure returns (uint256) {
    return Math.mulDiv(_timePassed, _scaledRatePerSecond, PRECISION);
  }

  function _updateReward(address _holder, uint256 _accountBalance) internal returns (uint256 reward_) {
    uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
    uint256 rewardPerToken_ = _rewardPerToken(totalSupply, lastTimeRewardApplicable_, rewardRatePerSecond);

    latestRewardPerTokenStored = rewardPerToken_;
    lastUpdateUnixTime = lastTimeRewardApplicable_;

    if (_holder == address(0)) return 0;

    reward_ = _earned(_holder, _accountBalance, rewardPerToken_, rewards[_holder]);
    rewards[_holder] = reward_;
    userRewardPerTokenPaid[_holder] = rewardPerToken_;

    return reward_;
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
    return Math.mulDiv(accountBalance, rewardPerToken_ - userRewardPerTokenPaid[account], REAL_VALUE_PRECISION)
      + accountRewards;
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
      + Math.mulDiv((lastTimeRewardApplicable_ - lastUpdateUnixTime) * rewardRate_, PRECISION, totalSupply_);
  }

  function lastTimeRewardApplicable() public view returns (uint64) {
    return uint64(Math.min(block.timestamp, unixPeriodFinish));
  }
}

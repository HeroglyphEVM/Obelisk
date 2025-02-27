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
 * @notice Time-based rewards distribution for Heroglyph's Genesis tokens. It uses wrapped
 * version to simplify LayerZero
 * issue in the genesis tokens.
 * @custom:export abi
 */
contract GenesisTokenPool is IGenesisTokenPool, LiteTicker, Ownable {
  uint256 internal constant PRECISION = 1e18;
  uint256 internal constant REAL_VALUE_PRECISION = PRECISION * PRECISION;

  uint64 public immutable DISTRIBUTION_DURATION;
  IERC721 public immutable GENESIS_KEY;
  ERC20 public immutable REWARD_TOKEN;

  uint64 public lastUpdateUnixTime;
  uint64 public unixPeriodFinish;

  uint256 public rewardRatePerSecond;
  uint256 public latestRewardPerTokenStored;
  uint256 public totalSupply;
  uint256 public queuedReward;

  mapping(bytes32 identity => uint256) public balanceOf;
  mapping(bytes32 identity => uint256) public userRewardPerTokenPaid;
  mapping(bytes32 identity => uint256) public rewards;

  constructor(
    address _owner,
    address _registry,
    address _wrappedReward,
    address _genesisKey
  ) LiteTicker(_registry) Ownable(_owner) {
    GENESIS_KEY = IERC721(_genesisKey);
    REWARD_TOKEN = ERC20(_wrappedReward);
    DISTRIBUTION_DURATION = 365 days;
  }

  function _afterVirtualDeposit(bytes32 _identity, address _receiver) internal override {
    if (address(GENESIS_KEY) != address(0) && GENESIS_KEY.balanceOf(_receiver) == 0) {
      revert MissingKey();
    }

    uint256 cachedTotalSupply = totalSupply;
    bool isFirstDeposit = latestRewardPerTokenStored == 0 && rewardRatePerSecond > 0;
    if (cachedTotalSupply == 0 && isFirstDeposit) {
      unixPeriodFinish = uint64(block.timestamp + DISTRIBUTION_DURATION);
    }

    _queueNewRewards(0);

    uint256 accountBalance = balanceOf[_identity];

    _updateReward(_identity, accountBalance);

    totalSupply = cachedTotalSupply + DEPOSIT_AMOUNT;
    accountBalance += DEPOSIT_AMOUNT;

    balanceOf[_identity] = accountBalance;
  }

  function _afterVirtualWithdraw(
    bytes32 _identity,
    address _receiver,
    bool _ignoreRewards
  ) internal override {
    _queueNewRewards(0);
    _onClaimTriggered(_identity, _receiver, _ignoreRewards);

    totalSupply -= DEPOSIT_AMOUNT;
    balanceOf[_identity] -= DEPOSIT_AMOUNT;
  }

  function _onClaimTriggered(bytes32 _identity, address _receiver, bool _ignoreRewards)
    internal
    override
  {
    if (address(GENESIS_KEY) != address(0) && GENESIS_KEY.balanceOf(_receiver) == 0) {
      revert MissingKey();
    }

    uint256 reward = _updateReward(_identity, balanceOf[_identity]);

    if (reward == 0) return;
    rewards[_identity] = 0;

    if (_ignoreRewards) {
      _queueNewRewards(reward);
      emit RewardIgnored(_identity, _receiver, reward);
      return;
    }

    REWARD_TOKEN.transfer(_receiver, reward);
    emit RewardPaid(_identity, _receiver, reward);
  }

  function notifyRewardAmount(uint256 reward) external override {
    if (msg.sender != address(REWARD_TOKEN) && msg.sender != owner()) {
      revert NotAuthorized();
    }

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

    if (_rewards > currentAtNow) {
      _notifyRewardAmount(_rewards);
      queuedReward = 0;
    } else {
      queuedReward = _rewards;
    }
  }

  function _notifyRewardAmount(uint256 reward) internal {
    _updateReward("", 0);

    uint64 unixPeriodFinishCached = unixPeriodFinish;
    uint256 cachedRewardRatePerSecond = rewardRatePerSecond;

    if (block.timestamp < unixPeriodFinishCached) {
      reward += _getTimeBasedValue(
        unixPeriodFinishCached - block.timestamp, cachedRewardRatePerSecond
      );
    }

    rewardRatePerSecond = Math.mulDiv(reward, PRECISION, DISTRIBUTION_DURATION);

    lastUpdateUnixTime = uint64(block.timestamp);
    unixPeriodFinish = uint64(block.timestamp + DISTRIBUTION_DURATION);

    emit RewardAdded(reward);
  }

  function _getTimeBasedValue(uint256 _timePassed, uint256 _scaledRatePerSecond)
    private
    pure
    returns (uint256)
  {
    return Math.mulDiv(_timePassed, _scaledRatePerSecond, PRECISION);
  }

  function _updateReward(bytes32 _identity, uint256 _accountBalance)
    internal
    returns (uint256 reward_)
  {
    uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
    uint256 rewardPerToken_ = _rewardPerToken(totalSupply, lastTimeRewardApplicable_);

    latestRewardPerTokenStored = rewardPerToken_;
    lastUpdateUnixTime = lastTimeRewardApplicable_;

    if (_identity == bytes32(0)) return 0;

    reward_ = _earned(_identity, _accountBalance, rewardPerToken_, rewards[_identity]);
    rewards[_identity] = reward_;
    userRewardPerTokenPaid[_identity] = rewardPerToken_;

    return reward_;
  }

  function rewardPerToken() external view override returns (uint256) {
    return _rewardPerToken(totalSupply, lastTimeRewardApplicable());
  }

  function getClaimableRewards(bytes32 _identity, uint256)
    external
    view
    override
    returns (uint256 rewards_, address rewardsToken_)
  {
    return (
      _earned(
        _identity,
        balanceOf[_identity],
        _rewardPerToken(totalSupply, lastTimeRewardApplicable()),
        rewards[_identity]
      ),
      address(REWARD_TOKEN)
    );
  }

  function _earned(
    bytes32 _identity,
    uint256 accountBalance,
    uint256 rewardPerToken_,
    uint256 accountRewards
  ) internal view returns (uint256) {
    return Math.mulDiv(
      accountBalance,
      rewardPerToken_ - userRewardPerTokenPaid[_identity],
      REAL_VALUE_PRECISION
    ) + accountRewards;
  }

  function _rewardPerToken(uint256 _totalSupply, uint256 _lastTimeRewardApplicable)
    internal
    view
    returns (uint256)
  {
    if (_totalSupply == 0) {
      return latestRewardPerTokenStored;
    }

    return latestRewardPerTokenStored
      + Math.mulDiv(
        (_lastTimeRewardApplicable - lastUpdateUnixTime) * rewardRatePerSecond,
        PRECISION,
        _totalSupply
      );
  }

  function lastTimeRewardApplicable() public view returns (uint64) {
    return uint64(Math.min(block.timestamp, unixPeriodFinish));
  }
}

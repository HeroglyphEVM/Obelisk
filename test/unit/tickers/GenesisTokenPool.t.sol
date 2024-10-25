// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";
import {
  GenesisTokenPool, IGenesisTokenPool
} from "src/services/tickers/GenesisTokenPool.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

contract GenesisTokenPoolTest is BaseTest {
  uint256 private constant PRECISION = 1e18;
  uint256 private constant REAL_VALUE_PRECISION = PRECISION * PRECISION;
  uint256 private constant REWARD_AMOUNT = 889e30;

  address private owner;
  address private user_A;
  address private user_B;
  address private registry;
  MockERC20 private wrappedReward;
  MockERC721 private genesisKey;

  GenesisTokenPoolHarness underTest;

  function setUp() external {
    _setUpVariables();
    underTest = new GenesisTokenPoolHarness(
      owner, registry, address(wrappedReward), address(genesisKey)
    );

    wrappedReward.mint(address(underTest), REWARD_AMOUNT);
    vm.prank(owner);
    underTest.notifyRewardAmount(REWARD_AMOUNT);
  }

  function _setUpVariables() internal {
    owner = generateAddress("Owner");
    user_A = generateAddress("User A");
    user_B = generateAddress("User B");
    registry = generateAddress("Registry");
    wrappedReward = new MockERC20("Wrapped Reward", "WR", 18);
    genesisKey = new MockERC721();

    vm.label(address(wrappedReward), "Wrapped Reward");
    vm.label(address(genesisKey), "Genesis Key");

    genesisKey.mint(user_A, 1);
    genesisKey.mint(user_B, 2);
  }

  function test_constructor_thenSetsVariables() external {
    underTest = new GenesisTokenPoolHarness(
      owner, registry, address(wrappedReward), address(genesisKey)
    );

    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.registry()), registry);
    assertEq(address(underTest.REWARD_TOKEN()), address(wrappedReward));
    assertEq(address(underTest.GENESIS_KEY()), address(genesisKey));
  }

  function test_afterVirtualDeposit_whenGenesisKeyNotFound_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IGenesisTokenPool.MissingKey.selector));
    underTest.exposed_afterVirtualDeposit(generateAddress("Missing Key"));
  }

  function test_afterVirtualDeposit_thenUpdatesRewards() external {
    underTest.exposed_afterVirtualDeposit(user_A);

    assertEq(underTest.latestRewardPerTokenStored(), 0);
    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(underTest.rewards(user_A), 0);
    assertEq(underTest.userRewardPerTokenPaid(user_A), 0);
    assertEq(underTest.totalSupply(), 1e18);
    assertEq(underTest.balanceOf(user_A), 1e18);
  }

  function test_afterVirtualDeposit_whenFirstDepositAndTimePassed_thenResetUnixEndTime()
    external
    prankAs(owner)
  {
    skip(underTest.DISTRIBUTION_DURATION());
    underTest.exposed_afterVirtualDeposit(user_A);

    assertEq(
      underTest.rewardRatePerSecond(),
      Math.mulDiv(REWARD_AMOUNT, PRECISION, underTest.DISTRIBUTION_DURATION())
    );
    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(
      underTest.unixPeriodFinish(), block.timestamp + underTest.DISTRIBUTION_DURATION()
    );
    assertEq(underTest.totalSupply(), 1e18);
    assertEq(underTest.balanceOf(user_A), 1e18);
  }

  function test_afterVirtualDeposit_whenRefillCanHappen_thenRefillsAndDeposits()
    external
    prankAs(owner)
  {
    uint256 queuedReward = REWARD_AMOUNT / 2;

    wrappedReward.mint(address(underTest), queuedReward);
    underTest.notifyRewardAmount(queuedReward);
    underTest.exposed_afterVirtualDeposit(user_A);

    skip(underTest.DISTRIBUTION_DURATION());
    underTest.exposed_afterVirtualWithdraw(user_A, false);
    underTest.exposed_afterVirtualDeposit(user_A);

    assertEq(
      underTest.rewardRatePerSecond(),
      Math.mulDiv(queuedReward, PRECISION, underTest.DISTRIBUTION_DURATION())
    );
    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(underTest.totalSupply(), 1e18);
    assertEq(underTest.balanceOf(user_A), 1e18);
  }

  function test_afterVritualWithdraw_thenWithdraw() external {
    underTest.exposed_afterVirtualDeposit(user_A);
    underTest.exposed_afterVirtualDeposit(user_B);
    underTest.exposed_afterVirtualWithdraw(user_A, false);

    assertEq(underTest.latestRewardPerTokenStored(), 0);
    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(underTest.rewards(user_A), 0);
    assertEq(underTest.userRewardPerTokenPaid(user_A), 0);
    assertEq(underTest.totalSupply(), 1e18);
    assertEq(underTest.balanceOf(user_A), 0);
  }

  function test_afterVritualWithdraw_whenRefillCanHappen_thenRefillsAndWithdraw()
    external
    pranking
  {
    uint256 queuedReward = 25.3e18;

    changePrank(owner);
    wrappedReward.mint(address(underTest), queuedReward);
    underTest.notifyRewardAmount(queuedReward);

    changePrank(user_A);
    underTest.exposed_afterVirtualDeposit(user_A);

    skip(underTest.DISTRIBUTION_DURATION());
    assertEqTolerance(underTest.earned(user_A), REWARD_AMOUNT, 1);

    underTest.exposed_afterVirtualWithdraw(user_A, false);

    assertEqTolerance(wrappedReward.balanceOf(address(underTest)), queuedReward, 1); //0.001%
      // difference
    assertEq(
      underTest.rewardRatePerSecond(),
      Math.mulDiv(queuedReward, PRECISION, underTest.DISTRIBUTION_DURATION())
    );
    assertEqTolerance(wrappedReward.balanceOf(user_A), REWARD_AMOUNT, 1);
  }

  function test_onClaimTriggered_thenUpdatesRewards() external {
    underTest.exposed_afterVirtualDeposit(user_A);

    skip(underTest.DISTRIBUTION_DURATION());

    vm.expectEmit(true, false, false, false);
    emit IGenesisTokenPool.RewardPaid(user_A, REWARD_AMOUNT);
    underTest.exposed_onClaimTriggered(user_A, false);

    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(underTest.rewards(user_A), 0);
    assertEqTolerance(
      underTest.latestRewardPerTokenStored(), REWARD_AMOUNT * PRECISION, 1
    );
    assertEqTolerance(
      underTest.userRewardPerTokenPaid(user_A), REWARD_AMOUNT * PRECISION, 1
    );
    assertEqTolerance(wrappedReward.balanceOf(user_A), REWARD_AMOUNT, 1);
  }

  function test_onClaimTriggered_whenIgnoreRewardsAndNewPeriodCanStart_thenQueuesRewards()
    external
    prankAs(owner)
  {
    underTest.exposed_afterVirtualDeposit(user_A);
    uint256 rate = underTest.rewardRatePerSecond();

    skip(underTest.DISTRIBUTION_DURATION());

    vm.expectEmit(true, false, false, false);
    emit IGenesisTokenPool.RewardIgnored(user_A, REWARD_AMOUNT);
    underTest.exposed_onClaimTriggered(user_A, true);

    assertEq(wrappedReward.balanceOf(user_A), 0);
    assertEqTolerance(underTest.rewardRatePerSecond(), rate, 1);
    assertEq(
      underTest.unixPeriodFinish(), block.timestamp + underTest.DISTRIBUTION_DURATION()
    );
  }

  function test_onClaimTriggered_whenIgnoreRewardsAndCantStartNewPeriod_thenQueuesRewards(
  ) external prankAs(owner) {
    underTest.exposed_afterVirtualDeposit(user_A);

    skip(underTest.DISTRIBUTION_DURATION());
    underTest.notifyRewardAmount(REWARD_AMOUNT + 100e18);

    vm.expectEmit(true, false, false, false);
    emit IGenesisTokenPool.RewardIgnored(user_A, REWARD_AMOUNT);
    underTest.exposed_onClaimTriggered(user_A, true);

    assertEq(wrappedReward.balanceOf(user_A), 0);
    assertEqTolerance(underTest.queuedReward(), REWARD_AMOUNT, 1);
  }

  function test_notifyRewardAmount_whenNotAuthorized_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IGenesisTokenPool.NotAuthorized.selector));
    underTest.notifyRewardAmount(REWARD_AMOUNT);
  }

  function test_notifyRewardAmount_whenLastFinished_thenStartsNewPeriod()
    external
    prankAs(address(wrappedReward))
  {
    uint256 duration = underTest.DISTRIBUTION_DURATION();

    skip(duration);

    uint256 reward = 993.1e18;
    underTest.notifyRewardAmount(reward);

    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(underTest.unixPeriodFinish(), block.timestamp + duration);
    assertEq(underTest.rewardRatePerSecond(), Math.mulDiv(reward, PRECISION, duration));
  }

  function test_notifyRewardAmount_whenNotFinishedEpoch_thenAddsToQueuedReward()
    external
    prankAs(owner)
  {
    uint256 reward = 993.1e18;
    uint256 lastUpdateUnixTime = underTest.lastUpdateUnixTime();

    skip(underTest.DISTRIBUTION_DURATION() - 1);

    underTest.notifyRewardAmount(reward);

    assertEq(underTest.queuedReward(), reward);
    assertEq(
      underTest.rewardRatePerSecond(),
      Math.mulDiv(REWARD_AMOUNT, PRECISION, underTest.DISTRIBUTION_DURATION())
    );
    assertEq(underTest.lastUpdateUnixTime(), lastUpdateUnixTime);
  }

  function test_fizz_onCalimTriggered(uint8 stakeTimeAsDurationPercentage) public {
    vm.assume(stakeTimeAsDurationPercentage > 0);
    uint256 amount0 = 1e18;
    uint256 amount1 = 1e18;
    uint64 duration = underTest.DISTRIBUTION_DURATION();

    address user2 = generateAddress("User 2");
    genesisKey.mint(user2, 3);

    underTest.exposed_afterVirtualDeposit(user2);
    underTest.exposed_afterVirtualDeposit(user_A);

    uint256 stakeTime = (duration * uint256(stakeTimeAsDurationPercentage)) / 100;
    skip(stakeTime);

    uint256 beforeBalance = wrappedReward.balanceOf(user_A);
    underTest.exposed_onClaimTriggered(user_A, false);
    uint256 rewardAmount = wrappedReward.balanceOf(user_A) - beforeBalance;

    uint256 expectedRewardAmount;

    if (stakeTime >= duration) {
      expectedRewardAmount = (REWARD_AMOUNT * amount1) / (amount0 + amount1);
    } else {
      expectedRewardAmount = (
        ((REWARD_AMOUNT * stakeTimeAsDurationPercentage) / 100) * amount1
      ) / (amount0 + amount1);
    }

    assertEqTolerance(rewardAmount, expectedRewardAmount, 1);
  }

  function test_fizz_notifyRewardAmount(
    uint56 warpTime,
    uint8 stakeTimeAsDurationPercentage,
    uint256 extraReward
  ) public prankAs(owner) {
    uint64 duration = underTest.DISTRIBUTION_DURATION();
    address fizzUser = generateAddress("Fizz User");

    genesisKey.mint(fizzUser, 33);

    extraReward = bound(extraReward, REWARD_AMOUNT, type(uint128).max);
    vm.assume(warpTime > 0);
    vm.assume(stakeTimeAsDurationPercentage > 0);

    uint256 expectedRatePerSecond = Math.mulDiv(REWARD_AMOUNT, PRECISION, duration);

    underTest.exposed_afterVirtualDeposit(fizzUser);
    skip(warpTime);

    underTest.exposed_onClaimTriggered(fizzUser, false);

    uint256 expectedRewardAmount;
    uint256 leftoverRewardAmount;

    if (warpTime >= duration) {
      expectedRewardAmount = REWARD_AMOUNT;
    } else {
      expectedRewardAmount = Math.mulDiv(warpTime, expectedRatePerSecond, PRECISION);
      leftoverRewardAmount = REWARD_AMOUNT - expectedRewardAmount;
    }

    wrappedReward.mint(address(underTest), extraReward);
    underTest.notifyRewardAmount(extraReward);

    extraReward += leftoverRewardAmount;
    expectedRatePerSecond = Math.mulDiv(extraReward, PRECISION, duration);

    uint256 stakeTime = (duration * uint256(stakeTimeAsDurationPercentage)) / 100;
    skip(stakeTime);

    underTest.exposed_onClaimTriggered(fizzUser, false);

    if (stakeTime >= duration) {
      expectedRewardAmount += extraReward;
    } else {
      expectedRewardAmount += Math.mulDiv(stakeTime, expectedRatePerSecond, PRECISION);
    }

    assertEqTolerance(wrappedReward.balanceOf(fizzUser), expectedRewardAmount, 1);
  }
}

contract GenesisTokenPoolHarness is GenesisTokenPool {
  constructor(
    address _owner,
    address _registry,
    address _wrappedReward,
    address _genesisKey
  ) GenesisTokenPool(_owner, _registry, _wrappedReward, _genesisKey) { }

  function exposed_afterVirtualDeposit(address _holder) external {
    _afterVirtualDeposit(_holder);
  }

  function exposed_afterVirtualWithdraw(address _holder, bool _ignoreRewards) external {
    _afterVirtualWithdraw(_holder, _ignoreRewards);
  }

  function exposed_onClaimTriggered(address _holder, bool _ignoreRewards) external {
    _onClaimTriggered(_holder, _ignoreRewards);
  }
}

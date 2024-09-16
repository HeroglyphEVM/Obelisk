// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";
import { LiteTickerFarmPool, ILiteTickerFarmPool } from "src/services/tickers/LiteTickerFarmPool.sol";

import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

/**
 * @notice Lazy Testing, since it's a copy, we just took the tests from playpen even though they are weak but it's good
 * enough.
 */
contract LiteTickerFarmPoolTest is BaseTest {
  uint256 private constant REWARD_AMOUNT = 882e18;

  address private owner;
  address private user;
  address private registry;
  MockERC20 private wrappedReward;
  MockERC721 private genesisKey;

  LiteTickerFarmPoolHarness underTest;

  function setUp() external {
    _setUpVariables();
    underTest = new LiteTickerFarmPoolHarness(owner, registry, address(wrappedReward), address(genesisKey));

    wrappedReward.mint(address(underTest), REWARD_AMOUNT);
    vm.prank(owner);
    underTest.notifyRewardAmount(REWARD_AMOUNT);
  }

  function _setUpVariables() internal {
    owner = generateAddress("Owner");
    user = generateAddress("User");
    registry = generateAddress("Registry");
    wrappedReward = new MockERC20("Wrapped Reward", "WR", 18);
    genesisKey = new MockERC721();

    vm.label(address(wrappedReward), "Wrapped Reward");
    vm.label(address(genesisKey), "Genesis Key");

    genesisKey.mint(user, 1);
  }

  function test_constructor_thenSetsVariables() external {
    underTest = new LiteTickerFarmPoolHarness(owner, registry, address(wrappedReward), address(genesisKey));

    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.registry()), registry);
    assertEq(address(underTest.rewardToken()), address(wrappedReward));
    assertEq(address(underTest.genesisKey()), address(genesisKey));
  }

  function test_afterVirtualDeposit_whenGenesisKeyNotFound_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(ILiteTickerFarmPool.MissingKey.selector));
    underTest.exposed_afterVirtualDeposit(generateAddress("Missing Key"));
  }

  function test_afterVirtualDeposit_thenUpdatesRewards() external {
    underTest.exposed_afterVirtualDeposit(user);

    assertEq(underTest.latestRewardPerTokenStored(), 0);
    assertEq(underTest.lastUpdateUnixTime(), block.timestamp);
    assertEq(underTest.rewards(user), 0);
    assertEq(underTest.userRewardPerTokenPaid(user), 0);
  }

  function testCorrectness_stake(uint56 warpTime) public {
    vm.assume(warpTime > 0);
    uint256 amount = 1e18;

    skip(warpTime);

    underTest.exposed_afterVirtualDeposit(user);

    assertEqDecimal(underTest.balanceOf(user), amount, 18);
  }

  function testCorrectness_withdraw(uint56 warpTime, uint56 stakeTime) public {
    vm.assume(warpTime > 0);
    vm.assume(stakeTime > 0);

    skip(warpTime);
    underTest.exposed_afterVirtualDeposit(user);
    skip(uint256(warpTime) + uint256(stakeTime));

    underTest.exposed_afterVirtualWithdraw(user, false);

    assertEqDecimal(underTest.balanceOf(user), 0, 18);
  }

  function testCorrectness_getReward(uint8 stakeTimeAsDurationPercentage) public prankAs(user) {
    vm.assume(stakeTimeAsDurationPercentage > 0);
    uint256 amount0 = 1e18;
    uint256 amount1 = 1e18;
    uint64 duration = underTest.distributionDuration();

    address user2 = generateAddress("User 2");
    genesisKey.mint(user2, 3);

    underTest.exposed_afterVirtualDeposit(user2);
    underTest.exposed_afterVirtualDeposit(user);

    uint256 stakeTime = (duration * uint256(stakeTimeAsDurationPercentage)) / 100;
    skip(stakeTime);

    uint256 beforeBalance = wrappedReward.balanceOf(user);
    underTest.getReward();
    uint256 rewardAmount = wrappedReward.balanceOf(user) - beforeBalance;

    uint256 expectedRewardAmount;

    if (stakeTime >= duration) {
      expectedRewardAmount = (REWARD_AMOUNT * amount1) / (amount0 + amount1);
    } else {
      expectedRewardAmount = (((REWARD_AMOUNT * stakeTimeAsDurationPercentage) / 100) * amount1) / (amount0 + amount1);
    }

    assertEqDecimalEpsilonBelow(rewardAmount, expectedRewardAmount, 18, 1e4);
  }

  function testCorrectness_notifyRewardAmount(uint56 warpTime, uint8 stakeTimeAsDurationPercentage)
    public
    prankAs(user)
  {
    vm.assume(warpTime > 0);
    vm.assume(stakeTimeAsDurationPercentage > 0);
    uint256 amount = 1e18;
    uint64 duration = underTest.distributionDuration();

    underTest.exposed_afterVirtualDeposit(user);
    skip(warpTime);

    uint256 beforeBalance = wrappedReward.balanceOf(user);
    underTest.getReward();
    uint256 rewardAmount = wrappedReward.balanceOf(user) - beforeBalance;

    uint256 expectedRewardAmount;
    if (warpTime >= duration) {
      expectedRewardAmount = REWARD_AMOUNT;
    } else {
      expectedRewardAmount = (REWARD_AMOUNT * warpTime) / duration;
    }

    uint256 leftoverRewardAmount = REWARD_AMOUNT - expectedRewardAmount;

    changePrank(owner);
    wrappedReward.mint(address(underTest), amount);
    underTest.notifyRewardAmount(amount);

    changePrank(user);

    uint256 stakeTime = (duration * uint256(stakeTimeAsDurationPercentage)) / 100;
    skip(stakeTime);

    beforeBalance = wrappedReward.balanceOf(user);
    underTest.getReward();
    rewardAmount += wrappedReward.balanceOf(user) - beforeBalance;

    if (stakeTime >= duration) {
      expectedRewardAmount += leftoverRewardAmount + amount;
    } else {
      expectedRewardAmount += ((leftoverRewardAmount + amount) * stakeTimeAsDurationPercentage) / 100;
    }

    assertEqDecimalEpsilonBelow(rewardAmount, expectedRewardAmount, 18, 1e4);
  }
}

contract LiteTickerFarmPoolHarness is LiteTickerFarmPool {
  constructor(address _owner, address _registry, address _wrappedReward, address _genesisKey)
    LiteTickerFarmPool(_owner, _registry, _wrappedReward, _genesisKey)
  { }

  function exposed_afterVirtualDeposit(address _holder) external {
    _afterVirtualDeposit(_holder);
  }

  function exposed_afterVirtualWithdraw(address _holder, bool _ignoreRewards) external {
    _afterVirtualWithdraw(_holder, _ignoreRewards);
  }

  function getReward() external {
    _onClaimTriggered(msg.sender, false);
  }
}

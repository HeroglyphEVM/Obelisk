// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { BaseTest } from "test/base/BaseTest.t.sol";
import {
  StreamingPool,
  IStreamingPool,
  IInterestManager,
  Ownable
} from "src/services/StreamingPool.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract StreamingPoolTest is BaseTest {
  uint256 private constant SCALED_PRECISION = 1e18;
  uint256 private constant EPOCH_TIME = 7 days;

  address private owner;
  address private interestManager;
  MockERC20 private inputToken;
  StreamingPoolHarness private underTest;

  function setUp() external {
    owner = generateAddress("owner");
    interestManager = generateAddress("interestManager");
    inputToken = new MockERC20("InputToken", "IT", 18);

    vm.mockCall(
      interestManager,
      abi.encodeWithSelector(IInterestManager.epochDuration.selector),
      abi.encode(EPOCH_TIME)
    );

    inputToken.mint(owner, 100_000e18);

    underTest = new StreamingPoolHarness(owner, interestManager, address(inputToken));
  }

  function test_claim_whenNoPendingRewards_thenReturnZero()
    external
    prankAs(interestManager)
  {
    vm.mockCall(
      address(inputToken),
      abi.encodeWithSelector(MockERC20.transfer.selector),
      "Shouldn't be called"
    );
    assertEq(underTest.claim(), 0);
  }

  function test_claim_whenPendingRewards_thenGivesAndReturnsAmount() external pranking {
    changePrank(owner);
    uint256 amount = 10e18;
    underTest.notifyRewardAmount(amount);

    changePrank(generateAddress("random"));
    skip(EPOCH_TIME + 1);

    assertEq(underTest.claim(), amount);
    assertEq(inputToken.balanceOf(interestManager), amount);
    assertEq(underTest.pendingToBeClaimed(), 0);
    assertEq(underTest.rewardBalance(), 0);
    assertEq(underTest.lastClaimedUnix(), block.timestamp);
  }

  function test_notifyRewardAmount_asNotOwner_thenReverts()
    external
    prankAs(interestManager)
  {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, interestManager)
    );
    underTest.notifyRewardAmount(10e18);
  }

  function test_notifyRewardAmount_whenZeroAmount_thenReverts() external prankAs(owner) {
    vm.expectRevert(IStreamingPool.InvalidAmount.selector);
    underTest.notifyRewardAmount(0);
  }

  function test_notifyRewardAmount_whenEpochNotFinished_thenReverts()
    external
    prankAs(owner)
  {
    underTest.notifyRewardAmount(10e18);

    skip(EPOCH_TIME - 1);

    vm.expectRevert(IStreamingPool.EpochNotFinished.selector);
    underTest.notifyRewardAmount(10e18);
  }

  function test_notifyRewardAmount_whenValidAmount_thenUpdatesRewardBalance()
    external
    prankAs(owner)
  {
    uint256 amount = 10e18;

    expectExactEmit();
    emit IStreamingPool.ApyBoosted(amount, block.timestamp + EPOCH_TIME);
    underTest.notifyRewardAmount(amount);

    assertEq(underTest.rewardBalance(), amount);
    assertEq(underTest.endEpoch(), block.timestamp + EPOCH_TIME);
    assertEq(underTest.lastClaimedUnix(), block.timestamp);
    assertEq(
      underTest.ratePerSecondInRay(), Math.mulDiv(amount, SCALED_PRECISION, EPOCH_TIME)
    );
    assertEq(inputToken.balanceOf(address(underTest)), amount);
  }

  function test_updateReward_thenUpdatesCorrectly() external prankAs(owner) {
    vm.mockCall(
      interestManager,
      abi.encodeWithSelector(IInterestManager.epochDuration.selector),
      abi.encode(EPOCH_TIME)
    );

    uint256 amount = 333.333e18;
    uint256 expectedRate = Math.mulDiv(amount, SCALED_PRECISION, EPOCH_TIME);
    uint256 expectedPending = 0;
    uint256 expectedLastClaimedUnix = uint32(block.timestamp) + 1 days;

    underTest.notifyRewardAmount(amount);

    skip(1 days);
    expectedPending += 1 days * expectedRate / SCALED_PRECISION;
    underTest.exposed_updateRewards();

    assertEq(underTest.pendingToBeClaimed(), expectedPending);
    assertEq(underTest.rewardBalance(), amount - expectedPending);
    assertEq(underTest.lastClaimedUnix(), expectedLastClaimedUnix);

    skip(1 days);
    expectedPending += 1 days * expectedRate / SCALED_PRECISION;
    expectedLastClaimedUnix += 1 days;
    underTest.exposed_updateRewards();

    assertEq(underTest.pendingToBeClaimed(), expectedPending);
    assertEq(underTest.rewardBalance(), amount - expectedPending);
    assertEq(underTest.lastClaimedUnix(), expectedLastClaimedUnix);

    skip(EPOCH_TIME + 2 days);
    expectedLastClaimedUnix += EPOCH_TIME + 2 days;
    underTest.exposed_updateRewards();

    assertEq(underTest.pendingToBeClaimed(), amount);
    assertEq(underTest.rewardBalance(), 0);
    assertEq(underTest.lastClaimedUnix(), expectedLastClaimedUnix);
  }
}

contract StreamingPoolHarness is StreamingPool {
  constructor(address _owner, address _interestManager, address _inputToken)
    StreamingPool(_owner, _interestManager, _inputToken)
  { }

  function exposed_updateRewards() external {
    _updateRewards();
  }
}

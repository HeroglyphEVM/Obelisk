// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";

import { Megapool } from "src/services/tickers/Megapool.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { IInterestManager } from "src/interfaces/IInterestManager.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";

contract MegapoolTest is BaseTest {
  address private owner;
  address private registry;
  MockERC20 private rewardToken;
  address private user_01;
  address private user_02;
  address private interestManager;

  MegapoolHarness private underTest;

  function setUp() public {
    owner = generateAddress("owner");
    registry = generateAddress("registry");
    user_01 = generateAddress("user_01");
    user_02 = generateAddress("user_02");
    interestManager = generateAddress("interestManager");
    rewardToken = new MockERC20("Reward Token", "RT", 18);
    vm.label(address(rewardToken), "rewardToken");

    vm.mockCall(interestManager, abi.encodeWithSelector(IInterestManager.claim.selector), abi.encode(0));

    underTest = new MegapoolHarness(owner, registry, address(rewardToken), interestManager);
  }

  function test_constructor_thenContractIsInitialized() external {
    underTest = new MegapoolHarness(owner, registry, address(rewardToken), interestManager);

    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.registry()), registry);
    assertEq(address(underTest.REWARD_TOKEN()), address(rewardToken));
    assertEq(address(underTest.INTEREST_MANAGER()), address(interestManager));
  }

  function test_afterVirtualDeposit_whenMaxEntry_thenReverts() external {
    uint256 maxEntry = 1e18;
    underTest.exposed_setMaxEntry(maxEntry);

    underTest.exposed_afterVirtualDeposit(user_01);
    vm.expectRevert(Megapool.MaxEntryExceeded.selector);
    underTest.exposed_afterVirtualDeposit(user_02);
  }

  function test_afterVirtualDeposit_whenPendingClaim_thenClaims() external {
    uint256 expectedReward = 3.32e18;

    underTest.exposed_afterVirtualDeposit(user_01);
    rewardToken.mint(address(underTest), expectedReward);

    uint256 rewardBalanceBefore = rewardToken.balanceOf(user_01);
    underTest.exposed_afterVirtualDeposit(user_01);
    uint256 reward = rewardToken.balanceOf(user_01) - rewardBalanceBefore;

    assertEq(reward, expectedReward);
  }

  function test_afterVirtualWithdraw_whenOnlyActor_thenEmptySystem() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);

    assertEq(underTest.totalVirtualBalance(), 0);
  }

  function test_afterVirtualWithdraw_whenStillHasBalance_thenUpdateShares() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);

    assertEq(underTest.totalVirtualBalance(), 1e18);
  }

  function test_afterVirtualWithdraw_whenPendingClaim_thenClaims() external {
    uint256 expectedReward = 3.32e18;

    underTest.exposed_afterVirtualDeposit(user_01);
    rewardToken.mint(address(underTest), expectedReward);

    uint256 rewardBalanceBefore = rewardToken.balanceOf(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);
    uint256 reward = rewardToken.balanceOf(user_01) - rewardBalanceBefore;

    assertEq(reward, expectedReward);
  }

  function test_claim_01() external {
    rewardToken.mint(address(underTest), 1e18);
    underTest.exposed_afterVirtualDeposit(user_01);

    vm.expectCall(interestManager, abi.encodeWithSelector(IInterestManager.claim.selector));
    underTest.exposed_claim(user_01);

    assertEq(rewardToken.balanceOf(user_01), 0);
    assertEq(rewardToken.balanceOf(owner), 1e18);
    assertEq(rewardToken.balanceOf(address(underTest)), 0);

    rewardToken.mint(address(underTest), 1e18);
    underTest.exposed_claim(user_01);

    assertEq(rewardToken.balanceOf(user_01), 1e18);
    assertEq(rewardToken.balanceOf(owner), 1e18);
    assertEq(rewardToken.balanceOf(address(underTest)), 0);
  }

  function test_claim_02() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualDeposit(user_02);

    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_claim(user_01);
    underTest.exposed_claim(user_02);

    assertEq(rewardToken.balanceOf(user_01), 0.5e18);
    assertEq(rewardToken.balanceOf(user_02), 0.5e18);
    assertEq(underTest.getYieldSnapshotOf(user_01), 0.5e18);
  }

  function test_claim_03() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_afterVirtualDeposit(user_02);
    underTest.exposed_afterVirtualDeposit(user_02);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_claim(user_01);
    underTest.exposed_claim(user_02);

    assertEq(rewardToken.balanceOf(user_01), 1_333_333_333_333_333_333);
    assertEq(rewardToken.balanceOf(user_02), 666_666_666_666_666_666);
  }
}

contract MegapoolHarness is Megapool {
  constructor(address _owner, address _registry, address _tokenReward, address _interestManager)
    Megapool(_owner, _registry, _tokenReward, _interestManager)
  { }

  function exposed_afterVirtualDeposit(address _holder) external {
    _afterVirtualDeposit(_holder);
  }

  function exposed_afterVirtualWithdraw(address _holder, bool _ignoreRewards) external {
    _afterVirtualWithdraw(_holder, _ignoreRewards);
  }

  function exposed_claim(address _holder) external {
    _claim(_holder, false);
  }

  function exposed_setMaxEntry(uint256 _maxEntry) external {
    maxEntry = _maxEntry;
  }
}

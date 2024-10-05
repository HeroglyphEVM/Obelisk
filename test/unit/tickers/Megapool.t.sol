// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";

import { Megapool } from "src/services/tickers/Megapool.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { IInterestManager } from "src/interfaces/IInterestManager.sol";

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

  function test_afterVirtualDeposit_whenFirstCaller_thenShareIsOne() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    assertEq(underTest.getShareOf(user_01), 1e18);
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

  function test_fizz_afterVirtualDeposit(address[13] calldata _randoms) external {
    uint256 totalVirtualBalance = 0;
    address random;
    uint256 expectedShares;
    uint256 randomBalance;

    for (uint256 i = 0; i < _randoms.length; i++) {
      random = _randoms[i];
      vm.assume(random != VM_ADDRESS && random != address(0));

      randomBalance = underTest.getVirtualBalanceOf(random) + 1e18;

      expectedShares = (i == 0) ? 1e18 : (underTest.totalShares() * randomBalance) / totalVirtualBalance;
      totalVirtualBalance += 1e18;

      underTest.exposed_afterVirtualDeposit(random);

      assertEq(underTest.getShareOf(random), expectedShares);
    }

    assertEq(underTest.totalShares(), 1e18 * _randoms.length);
    assertEq(underTest.totalVirtualBalance(), 1e18 * _randoms.length);
  }

  function test_afterVirtualWithdraw_whenOnlyActor_thenEmptySystem() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);

    assertEq(underTest.getShareOf(user_01), 0);
    assertEq(underTest.totalVirtualBalance(), 0);
    assertEq(underTest.totalShares(), 0);
  }

  function test_afterVirtualWithdraw_whenStillHasBalance_thenUpdateShares() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);

    assertEq(underTest.getShareOf(user_01), 1e18);
    assertEq(underTest.totalVirtualBalance(), 1e18);
    assertEq(underTest.totalShares(), 1e18);
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

  function test_fizz_afterVirtualWithdraw(address[13] memory _randoms) external {
    uint256 totalVirtualBalance = 0;
    address random;
    uint256 expectedShares;
    uint256 randomBalance;

    for (uint256 i = 0; i < _randoms.length; i++) {
      random = _randoms[i];
      vm.assume(random != VM_ADDRESS && random != address(0));
      _randoms[i] = random;

      randomBalance = underTest.getVirtualBalanceOf(random) + 1e18;

      expectedShares = (i == 0) ? 1e18 : (underTest.totalShares() * randomBalance) / totalVirtualBalance;
      totalVirtualBalance += 1e18;

      underTest.exposed_afterVirtualDeposit(random);
    }

    for (uint256 i = 5; i < _randoms.length; i++) {
      random = _randoms[i];

      randomBalance = underTest.getVirtualBalanceOf(random) - 1e18;

      expectedShares = (underTest.totalShares() * randomBalance) / totalVirtualBalance;
      totalVirtualBalance -= 1e18;

      underTest.exposed_afterVirtualWithdraw(random, false);
      assertEq(underTest.getShareOf(random), expectedShares);
    }
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

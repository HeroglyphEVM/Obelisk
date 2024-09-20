// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";

import { LiteTickerYieldSharing } from "src/services/tickers/LiteTickerYieldSharing.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

contract LiteTickerYieldSharingTest is BaseTest {
  address private owner;
  address private registry;
  MockERC20 private rewardToken;
  address private user_01;
  address private user_02;

  LiteTickerYieldSharingHarness private underTest;

  function setUp() public {
    owner = generateAddress("owner");
    registry = generateAddress("registry");
    user_01 = generateAddress("user_01");
    user_02 = generateAddress("user_02");

    rewardToken = new MockERC20("Reward Token", "RT", 18);
    vm.label(address(rewardToken), "rewardToken");

    underTest = new LiteTickerYieldSharingHarness(owner, registry, address(rewardToken));
  }

  function test_constructor_thenContractIsInitialized() external {
    underTest = new LiteTickerYieldSharingHarness(owner, registry, address(rewardToken));

    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.registry()), registry);
    assertEq(address(underTest.REWARD_TOKEN()), address(rewardToken));
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
    uint256 systemBalance = 0;
    address random;
    uint256 expectedShares;
    uint256 randomBalance;

    for (uint256 i = 0; i < _randoms.length; i++) {
      random = _randoms[i];
      vm.assume(random != VM_ADDRESS && random != address(0));

      randomBalance = underTest.getBalanceOf(random) + 1e18;

      expectedShares = (i == 0) ? 1e18 : (underTest.totalWeight() * randomBalance) / systemBalance;
      systemBalance += 1e18;

      underTest.exposed_afterVirtualDeposit(random);

      assertEq(underTest.getShareOf(random), expectedShares);
      console.log(underTest.totalWeight());
    }

    assertEq(underTest.totalWeight(), 1e18 * _randoms.length);
    assertEq(underTest.systemBalance(), 1e18 * _randoms.length);
  }

  function test_afterVirtualWithdraw_whenOnlyActor_thenEmptySystem() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);

    assertEq(underTest.getShareOf(user_01), 0);
    assertEq(underTest.systemBalance(), 0);
    assertEq(underTest.totalWeight(), 0);
  }

  function test_afterVirtualWithdraw_whenStillHasBalance_thenUpdateShares() external {
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualDeposit(user_01);
    underTest.exposed_afterVirtualWithdraw(user_01, false);

    assertEq(underTest.getShareOf(user_01), 1e18);
    assertEq(underTest.systemBalance(), 1e18);
    assertEq(underTest.totalWeight(), 1e18);
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

  function test_fizz_afterVirtualWithdraw(address[13] memory _randoms) external {
    uint256 systemBalance = 0;
    address random;
    uint256 expectedShares;
    uint256 randomBalance;

    for (uint256 i = 0; i < _randoms.length; i++) {
      random = _randoms[i];
      vm.assume(random != VM_ADDRESS && random != address(0));
      _randoms[i] = random;

      randomBalance = underTest.getBalanceOf(random) + 1e18;

      expectedShares = (i == 0) ? 1e18 : (underTest.totalWeight() * randomBalance) / systemBalance;
      systemBalance += 1e18;

      underTest.exposed_afterVirtualDeposit(random);
    }

    for (uint256 i = 5; i < _randoms.length; i++) {
      random = _randoms[i];

      randomBalance = underTest.getBalanceOf(random) - 1e18;

      expectedShares = (underTest.totalWeight() * randomBalance) / systemBalance;
      systemBalance -= 1e18;

      underTest.exposed_afterVirtualWithdraw(random, false);
      assertEq(underTest.getShareOf(random), expectedShares);
    }
  }
}

contract LiteTickerYieldSharingHarness is LiteTickerYieldSharing {
  constructor(address _owner, address _registry, address _tokenReward)
    LiteTickerYieldSharing(_owner, _registry, _tokenReward)
  { }

  function exposed_afterVirtualDeposit(address _holder) external {
    _afterVirtualDeposit(_holder);
  }

  function exposed_afterVirtualWithdraw(address _holder, bool _ignoreRewards) external {
    _afterVirtualWithdraw(_holder, _ignoreRewards);
  }
}

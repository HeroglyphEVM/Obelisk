// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";

import { Megapool } from "src/services/tickers/Megapool.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { IInterestManager } from "src/interfaces/IInterestManager.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

contract MegapoolTest is BaseTest {
  address private owner;
  address private registry;
  MockERC20 private rewardToken;
  address private user_01;
  address private user_02;
  address private interestManager;

  bytes32 private user01_identity;
  bytes32 private user02_identity;

  MegapoolHarness private underTest;

  function setUp() public {
    owner = generateAddress("owner");
    registry = generateAddress("registry");
    user_01 = generateAddress("user_01");
    user_02 = generateAddress("user_02");

    user01_identity = keccak256(abi.encode(user_01));
    user02_identity = keccak256(abi.encode(user_02));

    interestManager = generateAddress("interestManager");
    rewardToken = new MockERC20("Reward Token", "RT", 18);

    vm.label(address(rewardToken), "rewardToken");

    vm.mockCall(
      registry,
      abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector),
      abi.encode(false)
    );

    vm.mockCall(
      interestManager,
      abi.encodeWithSelector(IInterestManager.claim.selector),
      abi.encode(0)
    );

    underTest = new MegapoolHarness(
      owner, registry, address(rewardToken), interestManager, new address[](0)
    );
  }

  function test_constructor_whenAllowedCollectionsIsNotWrappedNFT_thenReverts() external {
    address[] memory allowedCollections = new address[](1);
    allowedCollections[0] = generateAddress("notWrappedNFT");

    vm.expectRevert(
      abi.encodeWithSelector(
        Megapool.InvalidWrappedCollection.selector, allowedCollections[0]
      )
    );
    new MegapoolHarness(
      owner, registry, address(rewardToken), interestManager, allowedCollections
    );
  }

  function test_constructor_thenContractIsInitialized() external {
    underTest = new MegapoolHarness(
      owner, registry, address(rewardToken), interestManager, new address[](0)
    );

    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.registry()), registry);
    assertEq(address(underTest.REWARD_TOKEN()), address(rewardToken));
    assertEq(address(underTest.INTEREST_MANAGER()), address(interestManager));
  }

  function test_constructor_whenAllowedCollectionsIsWrappedNFT_thenContractIsInitialized()
    external
  {
    address[] memory allowedCollections = new address[](1);
    allowedCollections[0] = generateAddress("wrappedNFT");

    vm.mockCall(
      registry,
      abi.encodeWithSelector(
        IObeliskRegistry.isWrappedNFT.selector, allowedCollections[0]
      ),
      abi.encode(true)
    );

    underTest = new MegapoolHarness(
      owner, registry, address(rewardToken), interestManager, allowedCollections
    );

    assertEq(underTest.allowedWrappedCollections(allowedCollections[0]), true);
    assertTrue(underTest.hasReservedCollections());
  }

  function test_afterVirtualDeposit_whenNotAllowedCollection_thenReverts() external {
    address[] memory allowedCollections = new address[](1);
    allowedCollections[0] = generateAddress("wrappedNFT");

    vm.mockCall(
      registry,
      abi.encodeWithSelector(
        IObeliskRegistry.isWrappedNFT.selector, allowedCollections[0]
      ),
      abi.encode(true)
    );

    underTest = new MegapoolHarness(
      owner, registry, address(rewardToken), interestManager, allowedCollections
    );

    vm.expectRevert(Megapool.NotAllowedCollection.selector);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
  }

  function test_afterVirtualDeposit_whenMaxEntry_thenReverts() external {
    uint256 maxEntry = 1e18;
    underTest.exposed_setMaxEntry(maxEntry);

    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    vm.expectRevert(Megapool.MaxEntryExceeded.selector);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
  }

  function test_afterVirtualDeposit_asAllowedCollection_thenUpdateVirtualBalance()
    external
  {
    address[] memory allowedCollections = new address[](1);
    allowedCollections[0] = generateAddress("wrappedNFT");

    vm.mockCall(
      registry,
      abi.encodeWithSelector(
        IObeliskRegistry.isWrappedNFT.selector, allowedCollections[0]
      ),
      abi.encode(true)
    );

    underTest = new MegapoolHarness(
      owner, registry, address(rewardToken), interestManager, allowedCollections
    );

    vm.prank(allowedCollections[0]);
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);

    assertEq(underTest.virtualBalances(user01_identity), 1e18);
  }

  function test_afterVirtualDeposit_whenPendingClaim_thenClaims() external {
    uint256 expectedReward = 3.32e18;

    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    rewardToken.mint(address(underTest), expectedReward);

    uint256 rewardBalanceBefore = rewardToken.balanceOf(user_01);
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    uint256 reward = rewardToken.balanceOf(user_01) - rewardBalanceBefore;

    assertEq(reward, expectedReward);
  }

  function test_afterVirtualWithdraw_whenOnlyActor_thenEmptySystem() external {
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    underTest.exposed_afterVirtualWithdraw(user01_identity, user_01, false);

    assertEq(underTest.totalVirtualBalance(), 0);
  }

  function test_afterVirtualWithdraw_whenStillHasBalance_thenUpdateShares() external {
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    underTest.exposed_afterVirtualWithdraw(user01_identity, user_01, false);

    assertEq(underTest.totalVirtualBalance(), 1e18);
  }

  function test_afterVirtualWithdraw_whenPendingClaim_thenClaims() external {
    uint256 expectedReward = 3.32e18;

    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    rewardToken.mint(address(underTest), expectedReward);

    uint256 rewardBalanceBefore = rewardToken.balanceOf(user_01);
    underTest.exposed_afterVirtualWithdraw(user01_identity, user_01, false);
    uint256 reward = rewardToken.balanceOf(user_01) - rewardBalanceBefore;

    assertEq(reward, expectedReward);
  }

  function test_claim_whenOneDepositor_thenGiveAllRewardToDepositorCorrectly() external {
    rewardToken.mint(address(underTest), 1e18);
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);

    vm.expectCall(
      interestManager, abi.encodeWithSelector(IInterestManager.claim.selector)
    );
    underTest.exposed_onClaimTriggered(user01_identity, user_01, false);

    assertEq(rewardToken.balanceOf(user_01), 0);
    assertEq(rewardToken.balanceOf(owner), 1e18);
    assertEq(rewardToken.balanceOf(address(underTest)), 0);

    rewardToken.mint(address(underTest), 1e18);
    underTest.exposed_onClaimTriggered(user01_identity, user_01, false);

    assertEq(rewardToken.balanceOf(user_01), 1e18);
    assertEq(rewardToken.balanceOf(owner), 1e18);
    assertEq(rewardToken.balanceOf(address(underTest)), 0);
  }

  function test_claim_whenTwoDepositorsSameWeight_thenGiveHalfRewardToEach() external {
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);

    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_onClaimTriggered(user01_identity, user_01, false);
    underTest.exposed_onClaimTriggered(user02_identity, user_02, false);

    assertEq(rewardToken.balanceOf(user_01), 0.5e18);
    assertEq(rewardToken.balanceOf(user_02), 0.5e18);
    assertEq(underTest.userYieldSnapshot(user01_identity), 0.5e18);
  }

  function test_claim_whenOneDepositorRewardedBeforeBiggerDepositor_thenGiveFullFirstRewardToDepositor01(
  ) external {
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_onClaimTriggered(user01_identity, user_01, false);
    underTest.exposed_onClaimTriggered(user02_identity, user_02, false);

    assertEq(rewardToken.balanceOf(user_01), 1_333_333_333_333_333_333);
    assertEq(rewardToken.balanceOf(user_02), 666_666_666_666_666_666);
  }

  function test_claim_whenOneIgnoreRewards_thenReturnRewardToPool() external {
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_onClaimTriggered(user01_identity, user_01, true);
    underTest.exposed_onClaimTriggered(user02_identity, user_02, false);

    // Note this will never happen, ignoring rewards only happens on withdraw
    // So the queued reward would be sent to user 2
    underTest.exposed_onClaimTriggered(user01_identity, user_01, false);

    assertEq(rewardToken.balanceOf(user_01), 444_444_444_444_444_443);
    assertEq(rewardToken.balanceOf(user_02), 1_555_555_555_555_555_555);
  }

  function test_claim_whenOneIgnoreRewardsAndExit_thenGiveAllRewardToDepositor02()
    external
  {
    underTest.exposed_afterVirtualDeposit(user01_identity, user_01);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    underTest.exposed_afterVirtualDeposit(user02_identity, user_02);
    rewardToken.mint(address(underTest), 1e18);

    underTest.exposed_afterVirtualWithdraw(user01_identity, user_01, true);
    underTest.exposed_onClaimTriggered(user02_identity, user_02, false);

    assertEq(rewardToken.balanceOf(user_01), 0);
    assertEqTolerance(rewardToken.balanceOf(user_02), 2e18, 1);
  }
}

contract MegapoolHarness is Megapool {
  constructor(
    address _owner,
    address _registry,
    address _tokenReward,
    address _interestManager,
    address[] memory _allowedCollections
  ) Megapool(_owner, _registry, _tokenReward, _interestManager, _allowedCollections) { }

  function exposed_afterVirtualDeposit(bytes32 _identity, address _holder) external {
    _afterVirtualDeposit(_identity, _holder);
  }

  function exposed_afterVirtualWithdraw(
    bytes32 _identity,
    address _holder,
    bool _ignoreRewards
  ) external {
    _afterVirtualWithdraw(_identity, _holder, _ignoreRewards);
  }

  function exposed_onClaimTriggered(
    bytes32 _identity,
    address _holder,
    bool _ignoreRewards
  ) external {
    _onClaimTriggered(_identity, _holder, _ignoreRewards);
  }

  function exposed_setMaxEntry(uint256 _maxEntry) external {
    maxEntry = _maxEntry;
  }
}

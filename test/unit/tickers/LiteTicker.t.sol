// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";
import {
  LiteTicker, ILiteTicker, IObeliskRegistry
} from "src/services/tickers/LiteTicker.sol";

contract LiteTickerTest is BaseTest {
  address private registry;
  address private user;
  address private mockWrappedNFT;

  bytes32 private USER_IDENTITY;

  LiteTickerHarness private underTest;

  function setUp() public {
    _setUpMockVariables();
    _setUpMockCalls();

    underTest = new LiteTickerHarness(registry);
  }

  function _setUpMockVariables() internal {
    registry = generateAddress("registry");
    user = generateAddress("user");
    USER_IDENTITY = keccak256(abi.encode(user));
    mockWrappedNFT = generateAddress("mockWrappedNFT");
  }

  function _setUpMockCalls() internal {
    vm.mockCall(
      registry,
      abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector),
      abi.encode(false)
    );
    vm.mockCall(
      registry,
      abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector, mockWrappedNFT),
      abi.encode(true)
    );
  }

  function test_constructor_thenSetsVariables() external {
    underTest = new LiteTickerHarness(registry);

    assertEq(address(underTest.registry()), registry);
  }

  function test_virtualDeposit_asNonWrappedNFT_reverts() external {
    vm.expectRevert(ILiteTicker.NotWrappedNFT.selector);
    underTest.virtualDeposit(USER_IDENTITY, 0, user);
  }

  function test_virtualDeposit_whenAlreadyDeposited_reverts()
    external
    prankAs(mockWrappedNFT)
  {
    underTest.virtualDeposit(USER_IDENTITY, 0, user);
    vm.expectRevert(ILiteTicker.AlreadyDeposited.selector);
    underTest.virtualDeposit(USER_IDENTITY, 0, user);
  }

  function test_virtualDeposit_whenNotDeposited_thenSucceeds()
    external
    prankAs(mockWrappedNFT)
  {
    uint256 tokenId = 923;

    expectExactEmit();
    emit LiteTickerHarness.AfterVirtualDeposit(USER_IDENTITY, user);
    expectExactEmit();
    emit ILiteTicker.Deposited(mockWrappedNFT, tokenId);
    underTest.virtualDeposit(USER_IDENTITY, tokenId, user);

    assertTrue(underTest.isDeposited(mockWrappedNFT, tokenId));
  }

  function test_virtualWithdraw_asNonWrappedNFT_reverts() external {
    vm.expectRevert(ILiteTicker.NotWrappedNFT.selector);
    underTest.virtualWithdraw(USER_IDENTITY, 0, user, false);
  }

  function test_virtualWithdraw_whenNotDeposited_reverts()
    external
    prankAs(mockWrappedNFT)
  {
    vm.expectRevert(ILiteTicker.NotDeposited.selector);
    underTest.virtualWithdraw(USER_IDENTITY, 0, user, false);
  }

  function test_virtualWithdraw_whenDeposited_thenSucceeds()
    external
    prankAs(mockWrappedNFT)
  {
    uint256 tokenId = 923;

    underTest.virtualDeposit(USER_IDENTITY, tokenId, user);
    expectExactEmit();
    emit LiteTickerHarness.AfterVirtualWithdraw(USER_IDENTITY, user, false);
    expectExactEmit();
    emit ILiteTicker.Withdrawn(mockWrappedNFT, tokenId);
    underTest.virtualWithdraw(USER_IDENTITY, tokenId, user, false);

    assertFalse(underTest.isDeposited(mockWrappedNFT, tokenId));
  }

  function test_claim_whenNotDeposited_reverts() external prankAs(mockWrappedNFT) {
    vm.expectRevert(ILiteTicker.NotDeposited.selector);
    underTest.claim(USER_IDENTITY, 0, user, false);
  }

  function test_claim_whenDeposited_thenCallsOnClaimTriggered()
    external
    prankAs(mockWrappedNFT)
  {
    uint256 tokenId = 923;

    underTest.virtualDeposit(USER_IDENTITY, tokenId, user);
    expectExactEmit();
    emit LiteTickerHarness.OnClaimTriggered(USER_IDENTITY, user, false);
    underTest.claim(USER_IDENTITY, tokenId, user, false);
  }
}

contract LiteTickerHarness is LiteTicker {
  event AfterVirtualDeposit(bytes32 identity, address holder);
  event AfterVirtualWithdraw(bytes32 identity, address holder, bool ignoreRewards);
  event OnClaimTriggered(bytes32 identity, address holder, bool ignoreRewards);

  constructor(address _registry) LiteTicker(_registry) { }

  function _afterVirtualDeposit(bytes32 _identity, address _holder) internal override {
    emit AfterVirtualDeposit(_identity, _holder);
  }

  function _afterVirtualWithdraw(bytes32 _identity, address _holder, bool _ignoreRewards)
    internal
    override
  {
    emit AfterVirtualWithdraw(_identity, _holder, _ignoreRewards);
  }

  function _onClaimTriggered(bytes32 _identity, address _holder, bool _ignoreRewards)
    internal
    override
  {
    emit OnClaimTriggered(_identity, _holder, _ignoreRewards);
  }

  function getClaimableRewards(bytes32 _identity, uint256 _extraRewards)
    external
    pure
    override
    returns (uint256 rewards_, address rewardsToken_)
  {
    return (0, address(0));
  }
}

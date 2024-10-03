// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";
import { LiteTicker, ILiteTicker, IObeliskRegistry } from "src/services/tickers/LiteTicker.sol";

contract LiteTickerTest is BaseTest {
  address private registry;
  address private user;
  address private mockWrappedNFT;

  LiteTickerHarness private underTest;

  function setUp() public {
    _setUpMockVariables();
    _setUpMockCalls();

    underTest = new LiteTickerHarness(registry);
  }

  function _setUpMockVariables() internal {
    registry = generateAddress("registry");
    user = generateAddress("user");
    mockWrappedNFT = generateAddress("mockWrappedNFT");
  }

  function _setUpMockCalls() internal {
    vm.mockCall(registry, abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector), abi.encode(false));
    vm.mockCall(
      registry, abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector, mockWrappedNFT), abi.encode(true)
    );
  }

  function test_constructor_thenSetsVariables() external {
    underTest = new LiteTickerHarness(registry);

    assertEq(address(underTest.registry()), registry);
  }

  function test_virtualDeposit_asNonWrappedNFT_reverts() external {
    vm.expectRevert(ILiteTicker.NotWrappedNFT.selector);
    underTest.virtualDeposit(0, user);
  }

  function test_virtualDeposit_whenAlreadyDeposited_reverts() external prankAs(mockWrappedNFT) {
    underTest.virtualDeposit(0, user);
    vm.expectRevert(ILiteTicker.AlreadyDeposited.selector);
    underTest.virtualDeposit(0, user);
  }

  function test_virtualDeposit_whenNotDeposited_thenSucceeds() external prankAs(mockWrappedNFT) {
    uint256 tokenId = 923;

    expectExactEmit();
    emit LiteTickerHarness.AfterVirtualDeposit(user);
    expectExactEmit();
    emit ILiteTicker.Deposited(user, mockWrappedNFT, tokenId);
    underTest.virtualDeposit(tokenId, user);

    assertTrue(underTest.isTokenDeposited(mockWrappedNFT, tokenId));
  }

  function test_virtualWithdraw_asNonWrappedNFT_reverts() external {
    vm.expectRevert(ILiteTicker.NotWrappedNFT.selector);
    underTest.virtualWithdraw(0, user, false);
  }

  function test_virtualWithdraw_whenNotDeposited_reverts() external prankAs(mockWrappedNFT) {
    vm.expectRevert(ILiteTicker.NotDeposited.selector);
    underTest.virtualWithdraw(0, user, false);
  }

  function test_virtualWithdraw_whenDeposited_thenSucceeds() external prankAs(mockWrappedNFT) {
    uint256 tokenId = 923;

    underTest.virtualDeposit(tokenId, user);
    expectExactEmit();
    emit LiteTickerHarness.AfterVirtualWithdraw(user, false);
    expectExactEmit();
    emit ILiteTicker.Withdrawn(user, mockWrappedNFT, tokenId);
    underTest.virtualWithdraw(tokenId, user, false);

    assertFalse(underTest.isTokenDeposited(mockWrappedNFT, tokenId));
  }
}

contract LiteTickerHarness is LiteTicker {
  event AfterVirtualDeposit(address holder);
  event AfterVirtualWithdraw(address holder, bool ignoreRewards);
  event OnClaimTriggered(address holder, bool ignoreRewards);

  constructor(address _registry) LiteTicker(_registry) { }

  function _afterVirtualDeposit(address _holder) internal override {
    emit AfterVirtualDeposit(_holder);
  }

  function _afterVirtualWithdraw(address _holder, bool _ignoreRewards) internal override {
    emit AfterVirtualWithdraw(_holder, _ignoreRewards);
  }

  function _onClaimTriggered(address _holder, bool _ignoreRewards) internal override {
    emit OnClaimTriggered(_holder, _ignoreRewards);
  }
}

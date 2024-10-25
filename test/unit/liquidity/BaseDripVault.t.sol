// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseDripVault, IDripVault } from "src/services/liquidity/BaseDripVault.sol";
import "test/base/BaseTest.t.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract BaseDripVaultTest is BaseTest {
  address private owner;
  address private registry;
  address private rateReceiver;
  address private user;

  BaseDripVaultHarness private underTest;

  function setUp() public {
    _setUpVariables();
    underTest = new BaseDripVaultHarness(address(0), owner, registry, rateReceiver);
  }

  function _setUpVariables() internal {
    owner = generateAddress("owner", 100e18);
    registry = generateAddress("registry", 100e18);
    rateReceiver = generateAddress("rateReceiver");
    user = generateAddress("user", 100e18);
  }

  function test_deposit_whenNotObeliskRegistry_reverts() public {
    vm.expectRevert(IDripVault.NotObeliskRegistry.selector);
    underTest.deposit{ value: 1 ether }(0);
  }

  function test_deposit_whenZeroAmount_reverts() public prankAs(registry) {
    vm.expectRevert(IDripVault.InvalidAmount.selector);
    underTest.deposit{ value: 0 }(0);
  }

  function test_deposit_whenValidAmount_thenDeposits() public prankAs(registry) {
    uint256 amount = 1 ether;

    expectExactEmit();
    emit BaseDripVaultHarness.AfterDeposit(amount);
    underTest.deposit{ value: amount }(0);

    assertEq(underTest.getTotalDeposit(), amount);
  }

  function test_withdraw_whenNotObeliskRegistry_reverts() public {
    vm.expectRevert(IDripVault.NotObeliskRegistry.selector);
    underTest.withdraw(address(0), 1 ether);
  }

  function test_withdraw_thenWithdraws() public prankAs(registry) {
    uint256 amount = 1 ether;
    underTest.deposit{ value: amount }(0);

    expectExactEmit();
    emit BaseDripVaultHarness.BeforeWithdrawal(address(0), amount);
    underTest.withdraw(address(0), amount);

    assertEq(underTest.getTotalDeposit(), 0);
  }

  function test_setObeliskRegistry_whenNotOwner_reverts() public prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.setObeliskRegistry(generateAddress("newRegistry"));
  }

  function test_setObeliskRegistry_whenValid_thenSets() public prankAs(owner) {
    address newRegistry = generateAddress("newRegistry");

    expectExactEmit();
    emit IDripVault.ObeliskRegistryUpdated(newRegistry);

    underTest.setObeliskRegistry(newRegistry);
    assertEq(underTest.obeliskRegistry(), newRegistry);
  }

  function test_setInterestRateReceiver_whenNotOwner_reverts() public prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.setInterestRateReceiver(generateAddress("newRateReceiver"));
  }

  function test_setInterestRateReceiver_whenValid_thenSets() public prankAs(owner) {
    address newRateReceiver = generateAddress("newRateReceiver");

    expectExactEmit();
    emit IDripVault.InterestRateReceiverUpdated(newRateReceiver);

    underTest.setInterestRateReceiver(newRateReceiver);
    assertEq(underTest.interestRateReceiver(), newRateReceiver);
  }
}

contract BaseDripVaultHarness is BaseDripVault {
  event AfterDeposit(uint256 amount);
  event BeforeWithdrawal(address to, uint256 amount);

  constructor(
    address _inputToken,
    address _owner,
    address _registry,
    address _rateReceiver
  ) BaseDripVault(_inputToken, _owner, _registry, _rateReceiver) { }

  function _afterDeposit(uint256 _amount) internal override {
    emit AfterDeposit(_amount);
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    emit BeforeWithdrawal(_to, _amount);
  }

  function claim() external pure returns (uint256) {
    return 0;
  }

  function getOutputToken() external view override returns (address) {
    return INPUT_TOKEN;
  }
}

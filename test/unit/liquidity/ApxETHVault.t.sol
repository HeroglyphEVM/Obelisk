// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "test/base/BaseTest.t.sol";

import { ApxETHVault, IApxETH, IPirexEth } from "src/services/liquidity/ApxETHVault.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

contract ApxETHVaultTest is BaseTest {
  address private owner;
  address private obeliskRegistry;
  address private apxETH;
  address private pirexEth;
  address private rateReceiver;
  address private user;

  ApxETHVault private underTest;

  function setUp() external {
    _setupVariables();

    vm.mockCall(
      apxETH, abi.encodeWithSelector(IApxETH.pirexEth.selector), abi.encode(pirexEth)
    );

    underTest = new ApxETHVault(owner, obeliskRegistry, apxETH, rateReceiver);
  }

  function _setupVariables() internal {
    owner = generateAddress("owner");
    obeliskRegistry = generateAddress("obeliskRegistry", 100e18);
    rateReceiver = generateAddress("rateReceiver");
    user = generateAddress("user");

    apxETH = address(new MockERC20("apxETH", "auto", 18));
    pirexEth = address(new MockPirexETH(MockERC20(apxETH)));
  }

  function test_afterDeposit_thenDepositsInPirexETH() public prankAs(obeliskRegistry) {
    uint256 amount = 2.32e18;

    vm.expectCall(
      pirexEth,
      amount,
      abi.encodeWithSelector(IPirexEth.deposit.selector, address(underTest), true)
    );
    underTest.deposit{ value: amount }(0);
  }

  function test_beforeWithdrawal_whenTotalBalanceIsNotZero_thenWithdrawsTransferEverything(
  ) public prankAs(obeliskRegistry) {
    uint256 depositAmount = 7.32e18;
    uint256 withdrawAmount = 2.11e18;

    uint256 apxAmount = MockPirexETH(pirexEth).toRatio(depositAmount);
    uint256 withdrawAmountApx = MockPirexETH(pirexEth).toRatio(withdrawAmount);

    uint256 interestETH = 0.23e18;
    uint256 interestInAPX = MockPirexETH(pirexEth).toRatio(interestETH);

    uint256 totalValueETH = depositAmount + interestETH;

    MockERC20(apxETH).mint(address(underTest), interestInAPX);

    underTest.deposit{ value: depositAmount }(0);

    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.maxRedeem.selector, address(underTest)),
      abi.encode(apxAmount)
    );
    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.convertToAssets.selector, apxAmount),
      abi.encode(totalValueETH)
    );
    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.convertToShares.selector, interestETH),
      abi.encode(interestInAPX)
    );

    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.convertToShares.selector, withdrawAmount),
      abi.encode(withdrawAmountApx)
    );

    underTest.withdraw(user, withdrawAmount);

    assertEq(MockERC20(apxETH).balanceOf(user), withdrawAmountApx);
    assertEq(
      MockERC20(apxETH).balanceOf(address(underTest)),
      (interestInAPX + apxAmount) - withdrawAmountApx
    );
  }

  function test_beforeWithdrawal_whenWithdrawAmountIsEqualToTotalDeposit_thenTransfersInterestAndApxETH(
  ) public prankAs(obeliskRegistry) {
    uint256 depositAmount = 7.32e18;
    uint256 withdrawAmount = depositAmount;

    uint256 apxAmount = MockPirexETH(pirexEth).toRatio(depositAmount);
    uint256 withdrawAmountApx = apxAmount;

    uint256 interestETH = 0.23e18;
    uint256 interestInAPX = MockPirexETH(pirexEth).toRatio(interestETH);

    uint256 totalValueETH = depositAmount + interestETH;

    MockERC20(apxETH).mint(address(underTest), interestInAPX);

    underTest.deposit{ value: depositAmount }(0);

    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.maxRedeem.selector, address(underTest)),
      abi.encode(apxAmount)
    );
    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.convertToAssets.selector, apxAmount),
      abi.encode(totalValueETH)
    );
    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.convertToShares.selector, interestETH),
      abi.encode(interestInAPX)
    );

    vm.mockCall(
      apxETH,
      abi.encodeWithSelector(IERC4626.convertToShares.selector, withdrawAmount),
      abi.encode(withdrawAmountApx)
    );

    underTest.withdraw(user, withdrawAmount);

    assertEq(MockERC20(apxETH).balanceOf(user), withdrawAmountApx);
    assertEq(MockERC20(apxETH).balanceOf(address(underTest)), interestInAPX);
  }
}

contract MockPirexETH is IPirexEth {
  MockERC20 private pxETH;

  constructor(MockERC20 _pxETH) {
    pxETH = _pxETH;
  }

  function deposit(address receiver, bool)
    external
    payable
    override
    returns (uint256 postFeeAmount, uint256 feeAmount)
  {
    pxETH.mint(receiver, toRatio(msg.value));
    return (msg.value, 0);
  }

  function ratio() public pure returns (uint256) {
    return 0.133e18;
  }

  function toRatio(uint256 _raw) public pure returns (uint256) {
    return _raw * 1e18 / ratio();
  }
}

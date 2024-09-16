// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "test/base/BaseTest.t.sol";

import { apxETHVault, IApxETH, IPirexEth } from "src/services/liquidity/apxETHVault.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

contract apxETHVaultTest is BaseTest {
  address private owner;
  address private obeliskRegistry;
  address private apxETH;
  address private pirexEth;
  address private rateReceiver;
  address private user;
  MockERC20 private pxETH;

  apxETHVault private underTest;

  function setUp() external {
    _setupVariables();

    vm.mockCall(apxETH, abi.encodeWithSelector(IApxETH.pirexEth.selector), abi.encode(pirexEth));
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(pxETH)));
    vm.mockCall(pirexEth, abi.encodeWithSelector(IPirexEth.deposit.selector), abi.encode(0, 0));

    underTest = new apxETHVault(owner, obeliskRegistry, apxETH, rateReceiver);
    pxETH.mint(address(underTest), 10_000e18);
  }

  function _setupVariables() internal {
    owner = generateAddress("owner");
    obeliskRegistry = generateAddress("obeliskRegistry", 100e18);
    apxETH = generateAddress("apxETH");
    pirexEth = generateAddress("pirexEth");
    rateReceiver = generateAddress("rateReceiver");
    user = generateAddress("user");

    pxETH = new MockERC20("pxETH", "pxETH", 18);
  }

  function test_afterDeposit_thenDepositsInPirexETH() public prankAs(obeliskRegistry) {
    uint256 amount = 2.32e18;

    vm.expectCall(pirexEth, amount, abi.encodeWithSelector(IPirexEth.deposit.selector, address(underTest), true));
    underTest.deposit{ value: amount }();
  }

  function test_beforeWithdrawal_whenTotalBalanceIsNotZero_thenWithdrawsFromPirexETHAndTransfersInterest()
    public
    prankAs(obeliskRegistry)
  {
    uint256 deposit = 7.32e18 + 1e18;

    uint256 withdrawAmount = 7.32e18;
    uint256 interest = 0.23e18;
    uint256 interestInPx = 0.11e18;

    uint256 redeemAmount = 1.23e18;
    uint256 amountInPx = 2.21e18;
    uint256 exitedPx = 5.11e18;
    uint256 exitedInETH = deposit + interest;

    underTest.deposit{ value: deposit }();

    uint256 pxBalance = pxETH.balanceOf(address(underTest));

    vm.mockCall(
      apxETH, abi.encodeWithSelector(IERC4626.maxRedeem.selector, address(underTest)), abi.encode(redeemAmount)
    );
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.redeem.selector, redeemAmount), abi.encode(exitedPx));

    vm.mockCall(
      apxETH, abi.encodeWithSelector(IERC4626.convertToShares.selector, withdrawAmount), abi.encode(amountInPx)
    );
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.convertToAssets.selector, exitedPx), abi.encode(exitedInETH));
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.convertToShares.selector, interest), abi.encode(interestInPx));

    vm.mockCall(
      apxETH, abi.encodeWithSelector(IERC4626.deposit.selector, pxBalance - amountInPx - interestInPx), abi.encode(0)
    );

    underTest.withdraw(user, withdrawAmount);

    assertEq(pxETH.balanceOf(user), amountInPx);
    assertEq(pxETH.balanceOf(rateReceiver), interestInPx);
  }

  function test_beforeWithdrawal_whenWithdrawAmountIsEqualToTotalDeposit_thenTransfersInterestAndPxETH()
    public
    prankAs(obeliskRegistry)
  {
    uint256 amount = 7.32e18;
    uint256 interest = 0.23e18;
    uint256 interestInPx = 0.11e18;

    uint256 redeemAmount = 1.23e18;
    uint256 amountInPx = 2.21e18;
    uint256 exitedPx = 5.11e18;
    uint256 exitedInETH = amount + interest;

    underTest.deposit{ value: amount }();

    uint256 pxBalance = pxETH.balanceOf(address(underTest));
    uint256 remainingPxBalance = pxBalance - amountInPx - interestInPx;

    vm.mockCall(
      apxETH, abi.encodeWithSelector(IERC4626.maxRedeem.selector, address(underTest)), abi.encode(redeemAmount)
    );
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.redeem.selector, redeemAmount), abi.encode(exitedPx));

    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.convertToShares.selector, amount), abi.encode(amountInPx));
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.convertToAssets.selector, exitedPx), abi.encode(exitedInETH));
    vm.mockCall(apxETH, abi.encodeWithSelector(IERC4626.convertToShares.selector, interest), abi.encode(interestInPx));

    underTest.withdraw(user, amount);

    assertEq(pxETH.balanceOf(user), amountInPx);
    assertEq(pxETH.balanceOf(rateReceiver), remainingPxBalance + interestInPx);
  }
}

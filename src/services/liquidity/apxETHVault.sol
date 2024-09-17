// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault } from "./BaseDripVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IApxETH } from "src/vendor/dinero/IApxETH.sol";
import { IPirexEth } from "src/vendor/dinero/IPirexEth.sol";

contract apxETHVault is BaseDripVault {
  IApxETH public apxETH;
  IPirexEth public pirexEth;
  IERC20 public pxETH;

  constructor(address _owner, address _obeliskRegistry, address _apxETH, address _rateReceiver)
    BaseDripVault(address(0), _owner, _obeliskRegistry, _rateReceiver)
  {
    apxETH = IApxETH(_apxETH);
    pirexEth = IPirexEth(apxETH.pirexEth());
    pxETH = IERC20(apxETH.asset());

    pxETH.approve(address(apxETH), type(uint256).max);
  }

  function _afterDeposit(uint256 _amount) internal override {
    pirexEth.deposit{ value: _amount }(address(this), true);
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    uint128 exitedPx = uint128(apxETH.redeem(apxETH.maxRedeem(address(this)), address(this), address(this)));
    uint256 interestInPx;
    uint256 cachedTotalDeposit = getTotalDeposit();

    uint256 amountInPx = apxETH.convertToShares(_amount);
    uint256 exitedInETH = apxETH.convertToAssets(exitedPx);

    //Shares scales down, in full exit, we might find less than the total deposit
    if (exitedInETH > cachedTotalDeposit) {
      interestInPx = apxETH.convertToShares(exitedInETH - cachedTotalDeposit);
    }

    _transfer(address(pxETH), interestRateReceiver, interestInPx);
    _transfer(address(pxETH), _to, amountInPx);

    if (cachedTotalDeposit - _amount != 0) {
      apxETH.deposit(pxETH.balanceOf(address(this)), address(this));
    } else {
      // Transfer the remaining balance of pxETH to the interestRateReceiver, left over from shares conversion
      _transfer(address(pxETH), interestRateReceiver, pxETH.balanceOf(address(this)));
    }
  }

  function claim() external override returns (uint256 interestInPx_) {
    uint128 exitedPx = uint128(apxETH.redeem(apxETH.maxRedeem(address(this)), address(this), address(this)));
    uint256 exitedInETH = apxETH.convertToAssets(exitedPx);

    interestInPx_ = apxETH.convertToShares(exitedInETH - getTotalDeposit());
    _transfer(address(pxETH), interestRateReceiver, interestInPx_);

    apxETH.deposit(pxETH.balanceOf(address(this)), address(this));
  }
}

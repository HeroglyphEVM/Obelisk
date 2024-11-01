// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault } from "./BaseDripVault.sol";

import { IApxETH } from "src/vendor/dinero/IApxETH.sol";
import { IPirexEth } from "src/vendor/dinero/IPirexEth.sol";

contract ApxETHVault is BaseDripVault {
  IApxETH public immutable APXETH;
  IPirexEth public immutable PIREX_ETH;

  constructor(
    address _owner,
    address _obeliskRegistry,
    address _apxETH,
    address _rateReceiver
  ) BaseDripVault(address(0), _owner, _obeliskRegistry, _rateReceiver) {
    APXETH = IApxETH(_apxETH);
    PIREX_ETH = IPirexEth(IApxETH(_apxETH).pirexEth());
  }

  function _afterDeposit(uint256 _amount)
    internal
    override
    returns (uint256 depositAmount_)
  {
    uint256 fee;
    (depositAmount_, fee) = PIREX_ETH.deposit{ value: _amount }(address(this), true);

    totalDeposit -= fee;

    return depositAmount_;
  }

  function _beforeWithdrawal(address _to, uint256 _amount)
    internal
    override
    returns (uint256 withdrawalAmount_)
  {
    withdrawalAmount_ = APXETH.convertToShares(_amount);
    _transfer(address(APXETH), _to, withdrawalAmount_);

    return withdrawalAmount_;
  }

  function claim() external override returns (uint256 interestInApx_) {
    interestInApx_ = _getPendingClaiming();
    _transfer(address(APXETH), interestRateReceiver, interestInApx_);

    return interestInApx_;
  }

  function getPendingClaiming() external view returns (uint256) {
    return _getPendingClaiming();
  }

  function _getPendingClaiming() internal view returns (uint256 interestInApx_) {
    uint256 cachedTotalDeposit = getTotalDeposit();
    uint256 maxRedeemInETH = APXETH.convertToAssets(APXETH.maxRedeem(address(this)));

    if (maxRedeemInETH > cachedTotalDeposit) {
      interestInApx_ = APXETH.convertToShares(maxRedeemInETH - cachedTotalDeposit);
    }

    return interestInApx_;
  }

  function getOutputToken() external view returns (address) {
    return address(APXETH);
  }
}

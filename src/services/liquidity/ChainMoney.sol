// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault } from "./BaseDripVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IChaiMoney } from "src/vendor/chai/IChaiMoney.sol";

contract ChaiMoneyVault is BaseDripVault {
  IChaiMoney public immutable CHAIN_MONEY;
  IERC20 public immutable DAI;

  constructor(address _owner, address _obeliskRegistry, address _chaiMoney, address _dai, address _rateReceiver)
    BaseDripVault(_dai, _owner, _obeliskRegistry, _rateReceiver)
  {
    CHAIN_MONEY = IChaiMoney(_chaiMoney);
    DAI = IERC20(_dai);
    DAI.approve(address(CHAIN_MONEY), type(uint256).max);
  }

  function _afterDeposit(uint256 _amount) internal override {
    CHAIN_MONEY.join(address(this), _amount);
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    CHAIN_MONEY.exit(address(this), CHAIN_MONEY.balanceOf(address(this)));
    uint256 totalBalance = DAI.balanceOf(address(this));
    uint256 cachedTotalDeposit = getTotalDeposit();
    uint256 leftOver = totalBalance - _amount;
    uint256 interest;

    if (totalBalance > cachedTotalDeposit) {
      interest = totalBalance - cachedTotalDeposit;
    }
    if (leftOver != 0) {
      CHAIN_MONEY.join(address(this), leftOver);
    }

    _transfer(inputToken, interestRateReceiver, interest);
    _transfer(inputToken, _to, _amount);
  }

  function claim() external override returns (uint256 interest_) {
    uint256 cachedTotalDeposit = getTotalDeposit();
    if (cachedTotalDeposit == 0) return 0;

    CHAIN_MONEY.exit(address(this), CHAIN_MONEY.balanceOf(address(this)));
    uint256 totalBalance = DAI.balanceOf(address(this));

    if (totalBalance > cachedTotalDeposit) {
      interest_ = totalBalance - cachedTotalDeposit;
    }

    CHAIN_MONEY.join(address(this), totalBalance);
    _transfer(inputToken, interestRateReceiver, interest_);

    return interest_;
  }
}

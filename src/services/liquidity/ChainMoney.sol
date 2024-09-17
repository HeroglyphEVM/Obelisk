// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault } from "./BaseDripVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IChaiMoney } from "src/vendor/chai/IChaiMoney.sol";

contract ChaiMoneyVault is BaseDripVault {
  IChaiMoney public chaiMoney;
  IERC20 public dai;

  constructor(address _owner, address _obeliskRegistry, address _chaiMoney, address _dai, address _rateReceiver)
    BaseDripVault(_dai, _owner, _obeliskRegistry, _rateReceiver)
  {
    chaiMoney = IChaiMoney(_chaiMoney);
    dai = IERC20(_dai);
    dai.approve(address(chaiMoney), type(uint256).max);
  }

  function _afterDeposit(uint256 _amount) internal override {
    IERC20(inputToken).transferFrom(msg.sender, address(this), _amount);
    chaiMoney.join(address(this), _amount);
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    chaiMoney.exit(address(this), chaiMoney.balanceOf(address(this)));
    uint256 totalBalance = dai.balanceOf(address(this));
    uint256 cachedTotalDeposit = getTotalDeposit();
    uint256 leftOver = totalBalance - _amount;
    uint256 interest;

    if (totalBalance > cachedTotalDeposit) {
      interest = totalBalance - cachedTotalDeposit;
    }
    if (leftOver != 0) {
      chaiMoney.join(address(this), leftOver);
    }

    _transfer(inputToken, interestRateReceiver, interest);
    _transfer(inputToken, _to, _amount);
  }

  function claim() external override returns (uint256 interest_) {
    uint256 cachedTotalDeposit = getTotalDeposit();
    if (cachedTotalDeposit == 0) return 0;

    chaiMoney.exit(address(this), chaiMoney.balanceOf(address(this)));
    uint256 totalBalance = dai.balanceOf(address(this));

    if (totalBalance > cachedTotalDeposit) {
      interest_ = totalBalance - cachedTotalDeposit;
    }

    chaiMoney.join(address(this), totalBalance);
    _transfer(inputToken, interestRateReceiver, interest_);

    return interest_;
  }
}

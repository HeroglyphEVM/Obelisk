// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault, IERC20 } from "./BaseDripVault.sol";

import { IChaiMoney } from "src/vendor/chai/IChaiMoney.sol";

contract ChaiMoneyVault is BaseDripVault {
  IChaiMoney public immutable CHAIN_MONEY;

  constructor(address _owner, address _obeliskRegistry, address _chaiMoney, address _dai, address _rateReceiver)
    BaseDripVault(_dai, _owner, _obeliskRegistry, _rateReceiver)
  {
    CHAIN_MONEY = IChaiMoney(_chaiMoney);
    IERC20(INPUT_TOKEN).approve(address(CHAIN_MONEY), type(uint256).max);
  }

  function _afterDeposit(uint256 _amount) internal override {
    CHAIN_MONEY.join(address(this), _amount);
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    CHAIN_MONEY.exit(address(this), CHAIN_MONEY.balanceOf(address(this)));
    uint256 totalBalance = IERC20(INPUT_TOKEN).balanceOf(address(this));
    uint256 cachedTotalDeposit = getTotalDeposit();
    uint256 leftOver = totalBalance - _amount;
    uint256 interest = 0;

    if (totalBalance > cachedTotalDeposit) {
      interest = totalBalance - cachedTotalDeposit;
    }
    if (leftOver != 0) {
      CHAIN_MONEY.join(address(this), leftOver);
    }

    _transfer(INPUT_TOKEN, interestRateReceiver, interest);
    _transfer(INPUT_TOKEN, _to, _amount);
  }

  function claim() external override returns (uint256 interest_) {
    uint256 cachedTotalDeposit = getTotalDeposit();
    if (cachedTotalDeposit == 0) return 0;

    CHAIN_MONEY.exit(address(this), CHAIN_MONEY.balanceOf(address(this)));
    uint256 totalBalance = IERC20(INPUT_TOKEN).balanceOf(address(this));

    if (totalBalance > cachedTotalDeposit) {
      interest_ = totalBalance - cachedTotalDeposit;
    }

    CHAIN_MONEY.join(address(this), totalBalance);
    _transfer(INPUT_TOKEN, interestRateReceiver, interest_);

    return interest_;
  }

  function getOutputToken() external view returns (address) {
    return INPUT_TOKEN;
  }
}

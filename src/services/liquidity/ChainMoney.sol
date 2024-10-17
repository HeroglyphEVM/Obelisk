// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault, IERC20 } from "./BaseDripVault.sol";

import { IChaiMoney } from "src/vendor/chai/IChaiMoney.sol";
import { IPot } from "src/vendor/chai/IPot.sol";

contract ChaiMoneyVault is BaseDripVault {
  uint256 constant RAY = 10 ** 27;
  IChaiMoney public immutable CHAIN_MONEY;
  IPot public immutable POT;

  constructor(address _owner, address _obeliskRegistry, address _chaiMoney, address _dai, address _rateReceiver)
    BaseDripVault(_dai, _owner, _obeliskRegistry, _rateReceiver)
  {
    CHAIN_MONEY = IChaiMoney(_chaiMoney);
    POT = IPot(IChaiMoney(_chaiMoney).pot());

    IERC20(INPUT_TOKEN).approve(address(CHAIN_MONEY), type(uint256).max);
  }

  function _afterDeposit(uint256 _amount) internal override {
    CHAIN_MONEY.join(address(this), _amount);
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    CHAIN_MONEY.draw(address(this), _amount);
    IERC20(INPUT_TOKEN).transfer(_to, _amount);
  }

  function claim() external override returns (uint256 interest_) {
    IChaiMoney cachedChaiMoney = CHAIN_MONEY;
    IERC20 cachedDai = IERC20(INPUT_TOKEN);

    uint256 cachedTotalDeposit = getTotalDeposit();

    uint256 totalDepositInChai = _convertToChai(cachedTotalDeposit);
    interest_ = cachedChaiMoney.balanceOf(address(this)) - totalDepositInChai;

    if (interest_ != 0) {
      cachedChaiMoney.exit(address(this), interest_);
    }

    interest_ = cachedDai.balanceOf(address(this));

    if (interest_ != 0) {
      cachedDai.transfer(interestRateReceiver, interest_);
    }

    return interest_;
  }

  function _convertToChai(uint256 _amount) internal returns (uint256) {
    if (_amount == 0) return 0;

    IPot cachedPot = POT;

    uint256 chi = (block.timestamp > cachedPot.rho()) ? cachedPot.drip() : cachedPot.chi();
    return ((_amount * RAY) + (chi - 1)) / chi;
  }

  function getOutputToken() external view returns (address) {
    return INPUT_TOKEN;
  }
}

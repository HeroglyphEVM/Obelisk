// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault, IERC20 } from "../services/liquidity/BaseDripVault.sol";
import { DaiMock } from "./DaiMock.sol";

contract MockDripVault is BaseDripVault {
  uint256 constant RAY = 10 ** 27;

  uint256 private generatedInterest;

  constructor(
    address _owner,
    address _obeliskRegistry,
    address _inputToken,
    address _rateReceiver
  ) BaseDripVault(_inputToken, _owner, _obeliskRegistry, _rateReceiver) { }

  function _afterDeposit(uint256 _amount) internal override { }

  function _beforeWithdrawal(address _to, uint256 _amount) internal override {
    if (INPUT_TOKEN == address(0)) {
      (bool success,) = _to.call{ value: _amount }("");
      if (!success) revert("Failed to send ETH");
    } else {
      IERC20(INPUT_TOKEN).transfer(_to, _amount);
    }
  }

  function claim() external override returns (uint256 interest_) {
    if (INPUT_TOKEN == address(0)) return 0;

    interest_ = generatedInterest;
    generatedInterest = 0;

    DaiMock(INPUT_TOKEN).mint(address(this), interest_);
    return interest_;
  }

  function generateInterest(uint256 _amount) external {
    if (INPUT_TOKEN == address(0)) revert("Cannot generate interest for ETH");

    generatedInterest += _amount;
    DaiMock(INPUT_TOKEN).mint(address(this), _amount);
  }

  function getOutputToken() external view returns (address) {
    return INPUT_TOKEN;
  }
}

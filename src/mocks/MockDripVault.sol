// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseDripVault, IERC20 } from "../services/liquidity/BaseDripVault.sol";

contract MockDripVault is BaseDripVault {
  uint256 constant RAY = 10 ** 27;

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

  function claim() external pure override returns (uint256 interest_) {
    return 0;
  }

  function getOutputToken() external view returns (address) {
    return INPUT_TOKEN;
  }
}

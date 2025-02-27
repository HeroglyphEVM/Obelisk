// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPirexEth {
  function deposit(address receiver, bool shouldCompound)
    external
    payable
    returns (uint256 postFeeAmount, uint256 feeAmount);

  function fees(uint8 _feeType) external view returns (uint32);
}

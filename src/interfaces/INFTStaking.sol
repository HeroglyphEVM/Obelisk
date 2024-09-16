// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INFTStaking {
  struct DepositData {
    uint256 pairNftId;
    uint256 depositedEth;
  }

  error UnknownGenesis();
  error NotKeyOwner();
  error InsufficientETH();
  error AlreadyStaked();
  error NotStaked();
  error WithdrawFailed();
}

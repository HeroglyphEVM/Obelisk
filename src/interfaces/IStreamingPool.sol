// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IStreamingPool {
  error NotInterestManager();
  error InvalidAmount();
  error EpochNotFinished();

  event Claimed(uint256 amount);
  event ApyBoosted(uint256 amount, uint256 until);

  function claim() external returns (uint256 amount_);
}

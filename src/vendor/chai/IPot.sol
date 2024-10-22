// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPot {
  function chi() external view returns (uint256);
  function rho() external view returns (uint256);
  function drip() external returns (uint256);
}

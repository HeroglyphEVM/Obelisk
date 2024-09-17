// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IChaiMoney {
  function join(address src, uint256 wad) external;
  function draw(address dst, uint256 wad) external payable;
  function exit(address src, uint256 wad) external;
  function balanceOf(address src) external view returns (uint256);
}

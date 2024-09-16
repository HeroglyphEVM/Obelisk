// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IApxETH is IERC4626 {
  function pirexEth() external view returns (address);
  function harvest() external;
  function assetsPerShare() external view returns (uint256);
}

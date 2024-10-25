// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockProtocol {
  address public dripVaultETH;
  address public dripVaultDAI;

  constructor() {
    dripVaultETH =
      address(new MockDripVault(address(this), address(0), address(0), address(0)));
    dripVaultDAI =
      address(new MockDripVault(address(this), address(0), address(0), address(0)));
  }
}

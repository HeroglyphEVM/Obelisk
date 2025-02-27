// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @custom:export abi
 */
contract TestnetERC20 is ERC20 {
  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) { }

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function pirexEth() external view returns (address) {
    return address(this);
  }
}

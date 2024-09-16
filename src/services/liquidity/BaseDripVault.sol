// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BaseDripVault is IDripVault, Ownable {
  address public interestRateReceiver;
  address public heroglyphRegistry;
  uint256 private totalDeposit;

  modifier onlyHeroglyphRegistry() {
    if (msg.sender != heroglyphRegistry) revert NotHeroglyphRegistry();
    _;
  }

  constructor(address _owner, address _heroglyphRegistry, address _rateReceiver) Ownable(_owner) {
    heroglyphRegistry = _heroglyphRegistry;
    interestRateReceiver = _rateReceiver;
  }

  function deposit() external payable override onlyHeroglyphRegistry {
    if (msg.value == 0) revert InvalidAmount();
    totalDeposit += msg.value;

    _afterDeposit(msg.value);
  }

  function _afterDeposit(uint256 _amount) internal virtual;

  function withdraw(address _to, uint256 _amount) external override onlyHeroglyphRegistry {
    _beforeWithdrawal(_to, _amount);
    totalDeposit -= _amount;
  }

  function _beforeWithdrawal(address _to, uint256 _amount) internal virtual;

  function _transfer(address _asset, address _to, uint256 _amount) internal {
    if (_amount == 0) return;

    if (_asset == address(0)) {
      (bool success,) = _to.call{ value: _amount }("");
      if (!success) revert FailedToSendETH();
    } else {
      IERC20(_asset).transfer(_to, _amount);
    }
  }

  function setHeroglyphRegistry(address _heroglyphRegistry) external onlyOwner {
    heroglyphRegistry = _heroglyphRegistry;
    emit HeroglyphRegistryUpdated(_heroglyphRegistry);
  }

  function setInterestRateReceiver(address _interestRateReceiver) external onlyOwner {
    interestRateReceiver = _interestRateReceiver;
    emit InterestRateReceiverUpdated(_interestRateReceiver);
  }

  function getTotalDeposit() public view override returns (uint256) {
    return totalDeposit;
  }

  receive() external payable { }
}

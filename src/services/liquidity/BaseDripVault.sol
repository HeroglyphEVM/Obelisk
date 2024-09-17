// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BaseDripVault is IDripVault, Ownable {
  address public interestRateReceiver;
  address public obeliskRegistry;
  uint256 private totalDeposit;
  address public inputToken;

  modifier onlyObeliskRegistry() {
    if (msg.sender != obeliskRegistry) revert NotObeliskRegistry();
    _;
  }

  constructor(address _inputToken, address _owner, address _obeliskRegistry, address _rateReceiver) Ownable(_owner) {
    obeliskRegistry = _obeliskRegistry;
    interestRateReceiver = _rateReceiver;
    inputToken = _inputToken;
  }

  function deposit(uint256 _amount) external payable override onlyObeliskRegistry {
    if (inputToken == address(0) && msg.value == 0) revert InvalidAmount();
    if (inputToken != address(0) && _amount == 0) revert InvalidAmount();
    if (inputToken != address(0) && msg.value != 0) revert NativeNotAccepted();

    _amount = inputToken == address(0) ? msg.value : _amount;
    totalDeposit += _amount;
    _afterDeposit(_amount);
  }

  function _afterDeposit(uint256 _amount) internal virtual;

  function withdraw(address _to, uint256 _amount) external override onlyObeliskRegistry {
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

  function setObeliskRegistry(address _obeliskRegistry) external onlyOwner {
    obeliskRegistry = _obeliskRegistry;
    emit ObeliskRegistryUpdated(_obeliskRegistry);
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

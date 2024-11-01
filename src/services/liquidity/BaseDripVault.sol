// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";
import {
  SafeERC20, IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract BaseDripVault is IDripVault, Ownable, ReentrancyGuard {
  address public immutable INPUT_TOKEN;

  address public interestRateReceiver;
  address public obeliskRegistry;
  uint256 internal totalDeposit;

  modifier onlyObeliskRegistry() {
    if (msg.sender != obeliskRegistry) revert NotObeliskRegistry();
    _;
  }

  constructor(
    address _inputToken,
    address _owner,
    address _obeliskRegistry,
    address _rateReceiver
  ) Ownable(_owner) {
    interestRateReceiver = _rateReceiver;
    obeliskRegistry = _obeliskRegistry;
    INPUT_TOKEN = _inputToken;
  }

  function deposit(uint256 _amount)
    external
    payable
    override
    nonReentrant
    onlyObeliskRegistry
    returns (uint256 depositAmount_)
  {
    address cachedInputToken = INPUT_TOKEN;
    uint256 cachedTotalBalance = totalDeposit;

    if (msg.value != 0) _amount = msg.value;

    if (cachedInputToken == address(0) && msg.value == 0) revert InvalidAmount();
    if (cachedInputToken != address(0) && msg.value != 0) revert NativeNotAccepted();

    totalDeposit = cachedTotalBalance + _amount;
    return _afterDeposit(_amount);
  }

  function _afterDeposit(uint256 _amount)
    internal
    virtual
    returns (uint256 depositAmount_);

  function withdraw(address _to, uint256 _amount)
    external
    override
    nonReentrant
    onlyObeliskRegistry
    returns (uint256 withdrawAmount_)
  {
    withdrawAmount_ = _beforeWithdrawal(_to, _amount);
    totalDeposit -= _amount;

    return withdrawAmount_;
  }

  function _beforeWithdrawal(address _to, uint256 _amount)
    internal
    virtual
    returns (uint256 withdrawalAmount_);

  function _transfer(address _asset, address _to, uint256 _amount) internal {
    if (_amount == 0) return;

    if (_asset == address(0)) {
      (bool success,) = _to.call{ value: _amount }("");
      if (!success) revert FailedToSendETH();
    } else {
      SafeERC20.safeTransfer(IERC20(_asset), _to, _amount);
    }
  }

  function setObeliskRegistry(address _obeliskRegistry) external onlyOwner {
    if (_obeliskRegistry == address(0)) revert ZeroAddress();

    obeliskRegistry = _obeliskRegistry;
    emit ObeliskRegistryUpdated(_obeliskRegistry);
  }

  function setInterestRateReceiver(address _interestRateReceiver) external onlyOwner {
    if (_interestRateReceiver == address(0)) revert ZeroAddress();
    interestRateReceiver = _interestRateReceiver;
    emit InterestRateReceiverUpdated(_interestRateReceiver);
  }

  function getTotalDeposit() public view override returns (uint256) {
    return totalDeposit;
  }

  function getInputToken() external view returns (address) {
    return INPUT_TOKEN;
  }
}

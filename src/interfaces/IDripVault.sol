// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IDripVault {
  error FailedToSendETH();
  error InvalidAmount();
  error NotObeliskRegistry();

  event ObeliskRegistryUpdated(address indexed obeliskRegistry);
  event InterestRateReceiverUpdated(address indexed interestRateReceiver);

  function deposit() external payable;
  function withdraw(address _to, uint256 _amount) external;
  function getTotalDeposit() external view returns (uint256);
  function claim() external returns (uint256);
}

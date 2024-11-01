// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IDripVault {
  error FailedToSendETH();
  error InvalidAmount();
  error NotObeliskRegistry();
  error NativeNotAccepted();
  error ZeroAddress();

  event ObeliskRegistryUpdated(address indexed obeliskRegistry);
  event InterestRateReceiverUpdated(address indexed interestRateReceiver);

  /**
   * @notice Deposits ETH or a specified amount of ERC20 token into the vault.
   * @dev ERC20 has to be transferred before calling this function
   */
  function deposit(uint256 _amount) external payable returns (uint256 depositAmount_);

  /**
   * @notice Withdraws ETH or a specified amount of ERC20 token from the vault.
   * @param _to The address to withdraw the funds to.
   * @param _amount The amount of ETH or ERC20 token to withdraw. Use 0 for ETH.
   */
  function withdraw(address _to, uint256 _amount)
    external
    returns (uint256 withdrawAmount_);

  /**
   * @notice Claims any accrued interest in the vault.
   * @return The amount of interest claimed.
   */
  function claim() external returns (uint256);

  /**
   * @notice Gets the total deposit amount in the vault.
   * @return The total deposit amount.
   */
  function getTotalDeposit() external view returns (uint256);

  /**
   * @notice Gets the input token of the vault.
   * @return The input token address.
   */
  function getInputToken() external view returns (address);

  /**
   * @notice Gets the output token of the vault.
   * @return The output token address.
   */
  function getOutputToken() external view returns (address);
}

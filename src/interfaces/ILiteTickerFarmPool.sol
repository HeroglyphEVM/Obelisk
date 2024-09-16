// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ILiteTicker } from "./ILiteTicker.sol";

interface ILiteTickerFarmPool is ILiteTicker {
  error AmountTooLarge();
  error NotAuthorized();

  event RewardAdded(uint256 reward);
  event RewardPaid(address indexed user, uint256 reward);

  error MissingKey();

  /**
   * @dev Notify the reward amount.
   * @param reward The amount of reward to notify.
   */
  function notifyRewardAmount(uint256 reward) external;

  /**
   * @dev Get the reward per token.
   * @return The reward per token.
   */
  function rewardPerToken() external view returns (uint256);

  /**
   * @dev Get the earned reward for the user.
   * @param account The address of the user.
   * @return The earned reward.
   */
  function earned(address account) external view returns (uint256);

  /**
   * @dev Get the last time reward applicable.
   * @return The last time reward applicable.
   */
  function lastTimeRewardApplicable() external view returns (uint64);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IInterestManager {
  error InvalidInputLength();
  error NotGaugeController();

  event EpochIntialized(uint64 indexed epochId, address[] megapools, uint128[] weights, uint128 totalWeight);
  event GaugeControllerSet(address indexed gaugeController);

  struct Epoch {
    uint128 totalRewards;
    uint128 totalWeight;
    address[] megapools;
    mapping(address => uint128) megapoolToWeight;
    mapping(address => uint128) megapoolClaims;
  }

  /**
   * @notice Applies gauges to the interest manager
   * @param _megapools The megapools to apply the gauges to
   * @param _weights The weights of the megapools
   */
  function applyGauges(address[] memory _megapools, uint128[] memory _weights) external;

  /**
   * @notice Claims rewards for the caller
   * @return rewards_ The amount of rewards claimed
   */
  function claim() external returns (uint256 rewards_);

  /**
   * @notice Gets the rewards for a megapool
   * @param _megapool The megapool to get the rewards for
   * @return rewards_ The amount of rewards for the megapool
   */
  function getRewards(address _megapool) external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IInterestManager {
  error InvalidInputLength();
  error NotGaugeController();
  error EpochNotFinished();
  error InvalidEpochDuration();

  event EpochInitialized(
    uint64 indexed epochId, address[] megapools, uint128[] weights, uint128 totalWeight
  );
  event GaugeControllerSet(address indexed gaugeController);
  event EpochEnded(uint64 indexed epochId);
  event RewardAssigned(
    address indexed megapool, uint256 addedRewards, uint256 totalRewards
  );
  event RewardClaimed(address indexed megapool, uint256 rewards);
  event EpochDurationSet(uint32 epochDuration);
  event StreamingPoolSet(address indexed streamingPool);

  struct Epoch {
    uint32 endOfEpoch;
    uint128 totalRewards;
    uint128 totalWeight;
    address[] megapools;
    mapping(address => uint128) megapoolToWeight;
    mapping(address => uint128) megapoolClaims;
  }

  function epochDuration() external view returns (uint32);

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

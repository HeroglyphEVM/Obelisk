// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IStreamingPool } from "../interfaces/IStreamingPool.sol";
import { IInterestManager } from "../interfaces/IInterestManager.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StreamingPool
 * @notice A way to boost APY for megapools by streaming donations rewards.
 */
contract StreamingPool is IStreamingPool, Ownable {
  uint256 private constant SCALED_PRECISION = 1e18;

  address public immutable inputToken;
  address public immutable interestManager;

  uint32 public startEpoch;
  uint32 public endEpoch;
  uint32 public lastClaimedUnix;
  uint256 public ratePerSecondInRay;

  uint256 public rewardBalance;
  uint256 public pendingToBeClaimed;

  constructor(address _owner, address _interestManager, address _inputToken) Ownable(_owner) {
    interestManager = _interestManager;
    inputToken = _inputToken;
  }

  function claim() external override returns (uint256 amount_) {
    if (msg.sender != interestManager) revert NotInterestManager();
    _updateRewards();

    amount_ = pendingToBeClaimed;
    pendingToBeClaimed = 0;

    if (amount_ == 0) return 0;

    IERC20(inputToken).transfer(msg.sender, amount_);

    emit Claimed(amount_);
  }

  function notifyRewardAmount(uint256 _amount) external onlyOwner {
    if (_amount == 0) revert InvalidAmount();
    if (endEpoch > block.timestamp) revert EpochNotFinished();
    _updateRewards();

    IERC20(inputToken).transferFrom(msg.sender, address(this), _amount);

    uint32 epochDuration = IInterestManager(interestManager).epochDuration();

    rewardBalance += _amount;
    endEpoch = uint32(block.timestamp) + epochDuration;
    ratePerSecondInRay = Math.mulDiv(_amount, SCALED_PRECISION, epochDuration);

    emit ApyBoosted(_amount, endEpoch);
  }

  function _updateRewards() internal {
    uint32 currentUnix = uint32(block.timestamp);
    uint32 secondsSinceLastClaim = currentUnix - lastClaimedUnix;

    uint256 rewardsSinceLastClaim = Math.mulDiv(ratePerSecondInRay, secondsSinceLastClaim, SCALED_PRECISION);
    rewardsSinceLastClaim = Math.min(rewardsSinceLastClaim, rewardBalance);

    pendingToBeClaimed += rewardsSinceLastClaim;
    rewardBalance -= rewardsSinceLastClaim;
    lastClaimedUnix = currentUnix;
  }
}

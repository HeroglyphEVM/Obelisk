// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IDripVault } from "src/interfaces/IDripVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStreamingPool } from "src/interfaces/IStreamingPool.sol";
import { IInterestManager } from "src/interfaces/IInterestManager.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { IPirexEth } from "src/vendor/dinero/IPirexEth.sol";
import { IApxETH } from "src/vendor/dinero/IApxETH.sol";

/**
 * @title InterestManager
 * @notice It manages the rewards distribution to the megapools based on people votes with their HCT.
 */
contract InterestManager is IInterestManager, Ownable {
  uint256 public constant PRECISION = 1e18;
  uint24 private constant DAI_POOL_FEE = 500;

  mapping(address => uint128) internal pendingRewards;
  mapping(uint64 => Epoch) public epochs;

  address public gaugeController;
  uint64 public epochId;
  uint32 public override epochDuration;
  IStreamingPool public streamingPool;

  address public immutable SWAP_ROUTER;
  IDripVault public immutable DRIP_VAULT_ETH;
  IDripVault public immutable DRIP_VAULT_DAI;

  IERC20 public immutable DAI;
  IWETH public immutable WETH;
  IERC20 public immutable APX_ETH;
  IPirexEth public immutable PIREX_ETH;

  constructor(
    address _owner,
    address _gaugeController,
    address _dripVaultETH,
    address _dripVaultDAI,
    address _swapRouter,
    address _weth
  ) Ownable(_owner) {
    gaugeController = _gaugeController;
    DRIP_VAULT_ETH = IDripVault(_dripVaultETH);
    DRIP_VAULT_DAI = IDripVault(_dripVaultDAI);
    SWAP_ROUTER = _swapRouter;
    WETH = IWETH(_weth);
    DAI = IERC20(IDripVault(_dripVaultDAI).getInputToken());
    APX_ETH = IERC20(IDripVault(_dripVaultETH).getOutputToken());
    PIREX_ETH = IPirexEth(IApxETH(address(APX_ETH)).pirexEth());

    epochDuration = 7 days;
  }

  function applyGauges(address[] memory _megapools, uint128[] memory _weights) external override {
    uint256 megapoolsLength = _megapools.length;

    if (msg.sender != gaugeController) revert NotGaugeController();
    if (megapoolsLength != _weights.length) revert InvalidInputLength();

    _endEpoch();
    Epoch storage epoch = epochs[epochId];

    uint128 weight;
    uint128 totalWeight;
    address megapool;

    for (uint256 i = 0; i < megapoolsLength; ++i) {
      megapool = _megapools[i];
      weight = _weights[i];

      epoch.megapools.push(megapool);
      epoch.megapoolToWeight[megapool] += weight;
      totalWeight += weight;
    }

    epoch.totalWeight = totalWeight;
    epoch.endOfEpoch = uint32(block.timestamp + epochDuration);

    emit EpochInitialized(epochId, _megapools, _weights, totalWeight);
  }

  function _endEpoch() internal {
    uint64 currentEpoch = epochId;
    Epoch storage epoch = epochs[currentEpoch];

    if (epoch.endOfEpoch > block.timestamp) revert EpochNotFinished();

    epoch.totalRewards += uint128(_claimFromServices());

    for (uint256 i = 0; i < epoch.megapools.length; ++i) {
      _assignRewardToMegapool(epoch, epoch.megapools[i]);
    }

    emit EpochEnded(currentEpoch);
    epochId = currentEpoch + 1;
  }

  function claim() external override returns (uint256 rewards_) {
    Epoch storage epoch = epochs[epochId];
    epoch.totalRewards += uint128(_claimFromServices());

    _assignRewardToMegapool(epoch, msg.sender);

    rewards_ = pendingRewards[msg.sender];

    if (rewards_ == 0) return 0;

    pendingRewards[msg.sender] = 0;
    APX_ETH.transfer(msg.sender, rewards_);

    emit RewardClaimed(msg.sender, rewards_);

    return rewards_;
  }

  function getRealTimeRewards_Reverting(address _megapool) external {
    Epoch storage epoch = epochs[epochId];
    epoch.totalRewards += uint128(_claimFromServices());

    _assignRewardToMegapool(epoch, _megapool);
    uint256 rewards = pendingRewards[_megapool];

    revert RealTimeRewards(rewards);
  }

  function _claimFromServices() internal returns (uint256 rewards_) {
    rewards_ += address(streamingPool) != address(0) ? streamingPool.claim() : 0;
    rewards_ += _claimDaiAndConvertToApxETH();
    rewards_ += DRIP_VAULT_ETH.claim();

    return rewards_;
  }

  function _claimDaiAndConvertToApxETH() internal returns (uint256 apxOut_) {
    DRIP_VAULT_DAI.claim();
    uint256 daiBalance = DAI.balanceOf(address(this));
    if (daiBalance == 0) return 0;

    TransferHelper.safeApprove(address(DAI), SWAP_ROUTER, daiBalance);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(DAI),
      tokenOut: address(WETH),
      fee: DAI_POOL_FEE,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: daiBalance,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    uint256 amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);

    WETH.withdraw(amountOut);
    (apxOut_,) = PIREX_ETH.deposit{ value: amountOut }(address(this), true);

    return apxOut_;
  }

  function _assignRewardToMegapool(Epoch storage _epoch, address _megapool) internal {
    (uint128 totalRewards, uint128 addedRewards) = _getRewards(_epoch, _megapool);
    if (addedRewards == 0) return;

    _epoch.megapoolClaims[_megapool] += addedRewards;
    pendingRewards[_megapool] = totalRewards;

    emit RewardAssigned(_megapool, addedRewards, totalRewards);
  }

  function setGaugeController(address _gaugeController) external onlyOwner {
    gaugeController = _gaugeController;
    emit GaugeControllerSet(gaugeController);
  }

  function setEpochDuration(uint32 _epochDuration) external onlyOwner {
    epochDuration = _epochDuration;
    emit EpochDurationSet(_epochDuration);
  }

  function setStreamingPool(address _streamingPool) external onlyOwner {
    streamingPool = IStreamingPool(_streamingPool);
    emit StreamingPoolSet(_streamingPool);
  }

  function getRewards(address _megapool) external view override returns (uint256 totalRewards_) {
    (totalRewards_,) = _getRewards(epochs[epochId], _megapool);
    return totalRewards_;
  }

  function _getRewards(Epoch storage epoch, address _megapool)
    internal
    view
    returns (uint128 totalRewards_, uint128 addedRewards_)
  {
    totalRewards_ = pendingRewards[_megapool];

    uint128 totalServiceRewards = epoch.totalRewards;
    uint256 weight = epoch.megapoolToWeight[_megapool];
    uint256 totalClaimedByPool = epoch.megapoolClaims[_megapool];
    if (weight == 0 || epoch.totalWeight == 0) return (totalRewards_, 0);

    uint256 weightRatioOfPool = Math.mulDiv(weight, PRECISION, epoch.totalWeight);
    uint256 totalRewardsToPool = uint128(Math.mulDiv(totalServiceRewards, weightRatioOfPool, PRECISION));

    addedRewards_ = uint128(totalRewardsToPool - totalClaimedByPool);
    totalRewards_ += addedRewards_;
    return (totalRewards_, addedRewards_);
  }

  function getEpochData(uint64 _epochId)
    external
    view
    returns (uint128 totalRewards_, uint128 totalWeight_, uint32 endOfEpoch_, address[] memory megapools_)
  {
    Epoch storage epoch = epochs[_epochId];

    totalRewards_ = epoch.totalRewards;
    totalWeight_ = epoch.totalWeight;
    megapools_ = epoch.megapools;
    endOfEpoch_ = epoch.endOfEpoch;

    return (totalRewards_, totalWeight_, endOfEpoch_, megapools_);
  }

  function getMegapoolWeight(uint64 _epochId, address _megapool) external view returns (uint128 weight_) {
    return epochs[_epochId].megapoolToWeight[_megapool];
  }

  receive() external payable { }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IInterestManager } from "src/interfaces/IInterestManager.sol";

/**
 * @title Megapool
 * @notice It receives yield from the deposited ETH from unlocking a collection.
 * @dev Megapool has a max entry limit.
 * @custom:export abi
 */
contract Megapool is LiteTicker, Ownable, ReentrancyGuard {
  error MaxEntryExceeded();

  event MaxEntryUpdated(uint256 newMaxEntry);

  ERC20 public immutable REWARD_TOKEN;

  uint256 public yieldPerTokenInRay;
  uint256 public yieldBalance;
  uint256 public totalVirtualBalance;
  uint256 public maxEntry;

  IInterestManager public immutable INTEREST_MANAGER;

  mapping(bytes32 => uint256) internal userYieldSnapshot;
  mapping(bytes32 => uint256) private virtualBalances;

  constructor(
    address _owner,
    address _registry,
    address _tokenReward,
    address _interestManager
  ) LiteTicker(_registry) Ownable(_owner) {
    REWARD_TOKEN = ERC20(_tokenReward);
    INTEREST_MANAGER = IInterestManager(_interestManager);
    maxEntry = 1000e18;
  }

  function _afterVirtualDeposit(bytes32 _identity, address _receiver) internal override {
    _claim(_identity, _receiver, false);

    uint256 userVirtualBalance = virtualBalances[_identity] + DEPOSIT_AMOUNT;

    virtualBalances[_identity] = userVirtualBalance;
    totalVirtualBalance += DEPOSIT_AMOUNT;

    if (totalVirtualBalance > maxEntry) {
      revert MaxEntryExceeded();
    }

    userYieldSnapshot[_identity] =
      ShareableMath.rmulup(userVirtualBalance, yieldPerTokenInRay);
  }

  function _afterVirtualWithdraw(
    bytes32 _identity,
    address _receiver,
    bool _ignoreRewards
  ) internal override {
    _claim(_identity, _receiver, _ignoreRewards);

    uint256 userVirtualBalance = virtualBalances[_identity] - DEPOSIT_AMOUNT;
    virtualBalances[_identity] = userVirtualBalance;

    totalVirtualBalance -= DEPOSIT_AMOUNT;
    userYieldSnapshot[_identity] =
      ShareableMath.rmulup(userVirtualBalance, yieldPerTokenInRay);
  }

  function _onClaimTriggered(bytes32 _identity, address _receiver, bool _ignoreRewards)
    internal
    override
  {
    _claim(_identity, _receiver, _ignoreRewards);

    userYieldSnapshot[_identity] =
      ShareableMath.rmulup(virtualBalances[_identity], yieldPerTokenInRay);
  }

  function _claim(bytes32 _identity, address _receiver, bool _ignoreRewards)
    internal
    nonReentrant
  {
    INTEREST_MANAGER.claim();
    uint256 currentYieldBalance = REWARD_TOKEN.balanceOf(address(this));
    uint256 holderVirtualBalance = virtualBalances[_identity];
    uint256 yieldPerTokenInRayCached = yieldPerTokenInRay;
    uint256 totalVirtualBalanceCached = totalVirtualBalance;

    if (totalVirtualBalanceCached > 0) {
      yieldPerTokenInRayCached += ShareableMath.rdiv(
        REWARD_TOKEN.balanceOf(address(this)) - yieldBalance, totalVirtualBalanceCached
      );
    } else if (currentYieldBalance != 0) {
      REWARD_TOKEN.transfer(owner(), currentYieldBalance);
    }

    uint256 last = userYieldSnapshot[_identity];
    uint256 curr = ShareableMath.rmul(holderVirtualBalance, yieldPerTokenInRayCached);

    if (curr > last && !_ignoreRewards) {
      uint256 sendingReward = curr - last;
      REWARD_TOKEN.transfer(_receiver, sendingReward);
    }

    yieldBalance = REWARD_TOKEN.balanceOf(address(this));
    yieldPerTokenInRay = yieldPerTokenInRayCached;
  }

  function updateMaxEntry(uint256 _newMaxEntry) external onlyOwner {
    maxEntry = _newMaxEntry;
    emit MaxEntryUpdated(_newMaxEntry);
  }

  function getVirtualBalanceOf(bytes32 _identity) external view returns (uint256) {
    return virtualBalances[_identity];
  }

  function getYieldSnapshotOf(bytes32 _identity) external view returns (uint256) {
    return userYieldSnapshot[_identity];
  }
}

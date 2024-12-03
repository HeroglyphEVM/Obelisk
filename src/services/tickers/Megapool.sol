// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { LiteTicker } from "./LiteTicker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IInterestManager } from "src/interfaces/IInterestManager.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

import { Initializable } from
  "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Megapool
 * @notice It receives yield from the deposited ETH from unlocking a collection.
 * @dev Megapool has a max entry limit.
 * @custom:export abi
 */
contract Megapool is LiteTicker, Ownable, ReentrancyGuard {
  error MaxEntryExceeded();
  error NotAllowedCollection();
  error InvalidWrappedCollection(address collection);

  event MaxEntryUpdated(uint256 newMaxEntry);

  IInterestManager public immutable INTEREST_MANAGER;
  ERC20 public immutable REWARD_TOKEN;

  bool public hasReservedCollections;

  uint256 public yieldPerTokenInRay;
  uint256 public yieldBalance;
  uint256 public totalVirtualBalance;
  uint256 public maxEntry;

  mapping(bytes32 => uint256) public virtualBalances;
  mapping(bytes32 => uint256) public userYieldSnapshot;
  mapping(address => bool) public allowedWrappedCollections;
  address[] public allowedWrappedCollectionsList;

  constructor(
    address _owner,
    address _registry,
    address _tokenReward,
    address _interestManager,
    address[] memory _allowedWrappedCollections
  ) LiteTicker(_registry) Ownable(_owner) {
    REWARD_TOKEN = ERC20(_tokenReward);
    INTEREST_MANAGER = IInterestManager(_interestManager);
    maxEntry = 1000e18;

    uint256 collectionCount = _allowedWrappedCollections.length;
    if (collectionCount == 0) return;

    hasReservedCollections = true;
    allowedWrappedCollectionsList = _allowedWrappedCollections;

    address collection;
    for (uint256 i = 0; i < collectionCount; ++i) {
      collection = _allowedWrappedCollections[i];

      if (!IObeliskRegistry(_registry).isWrappedNFT(collection)) {
        revert InvalidWrappedCollection(collection);
      }

      allowedWrappedCollections[collection] = true;
    }
  }

  function _afterVirtualDeposit(bytes32 _identity, address _receiver) internal override {
    if (hasReservedCollections && !allowedWrappedCollections[msg.sender]) {
      revert NotAllowedCollection();
    }

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
    uint256 queued = 0;

    uint256 holderVirtualBalance = virtualBalances[_identity];
    uint256 yieldPerTokenInRayCached = yieldPerTokenInRay;
    uint256 totalVirtualBalanceCached = totalVirtualBalance;

    if (totalVirtualBalanceCached > 0) {
      yieldPerTokenInRayCached +=
        ShareableMath.rdiv(currentYieldBalance - yieldBalance, totalVirtualBalanceCached);
    } else if (currentYieldBalance != 0) {
      REWARD_TOKEN.transfer(owner(), currentYieldBalance);
    }

    uint256 last = userYieldSnapshot[_identity];
    uint256 curr = ShareableMath.rmul(holderVirtualBalance, yieldPerTokenInRayCached);

    if (curr > last) {
      uint256 sendingReward = curr - last;

      if (!_ignoreRewards) {
        REWARD_TOKEN.transfer(_receiver, sendingReward);
      } else {
        queued += sendingReward;
      }
    }

    yieldBalance = REWARD_TOKEN.balanceOf(address(this)) - queued;
    yieldPerTokenInRay = yieldPerTokenInRayCached;
  }

  function updateMaxEntry(uint256 _newMaxEntry) external onlyOwner {
    maxEntry = _newMaxEntry;
    emit MaxEntryUpdated(_newMaxEntry);
  }

  function getClaimableRewards(bytes32 _identity, uint256 _extraRewards)
    external
    view
    override
    returns (uint256 rewards_, address rewardsToken_)
  {
    uint256 currentYieldBalance = REWARD_TOKEN.balanceOf(address(this)) + _extraRewards;

    uint256 holderVirtualBalance = virtualBalances[_identity];
    uint256 yieldPerTokenInRayCached = yieldPerTokenInRay;
    uint256 totalVirtualBalanceCached = totalVirtualBalance;

    if (totalVirtualBalanceCached > 0) {
      yieldPerTokenInRayCached +=
        ShareableMath.rdiv(currentYieldBalance - yieldBalance, totalVirtualBalanceCached);
    }

    uint256 last = userYieldSnapshot[_identity];
    uint256 curr = ShareableMath.rmul(holderVirtualBalance, yieldPerTokenInRayCached);

    if (curr > last) {
      rewards_ = curr - last;
    }

    return (rewards_, address(REWARD_TOKEN));
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ShareableMath } from "src/lib/ShareableMath.sol";

contract HCT is ERC20, IHCT {
  uint128 public constant NAME_COST = 90e18;
  uint256 public constant PRE_MINT_AMOUNT = 10_000e18;

  IObeliskRegistry public immutable obeliskRegistry;
  mapping(address => UserInfo) internal usersInfo;

  uint256 public productionRate;
  uint256 internal totalMultiplier;
  uint256 internal totalRewards;
  uint256 public yieldPerTokenInRay;
  uint32 internal lastUnixTimeRewards;

  constructor(address _treasury) ERC20("Heroglyph Name Change Token", "HCT") {
    obeliskRegistry = IObeliskRegistry(msg.sender);
    productionRate = 1e18;
    _mint(_treasury, PRE_MINT_AMOUNT);
  }

  modifier onlyHeroglyphWrappedNFT() {
    if (!obeliskRegistry.isWrappedNFT(msg.sender)) revert NotWrappedNFT();
    _;
  }

  function addPower(address _user, uint128 _addMultiplier)
    external
    override
    onlyHeroglyphWrappedNFT
  {
    UserInfo storage userInfo = usersInfo[_user];
    uint256 totalMultiplierCached = totalMultiplier;

    if (totalMultiplierCached == 0) {
      lastUnixTimeRewards = uint32(block.timestamp);
    }

    _claim(_user, userInfo, false);

    uint256 userMultiplier = userInfo.multiplier + _addMultiplier;
    userInfo.multiplier = userMultiplier;
    totalMultiplier = totalMultiplierCached + _addMultiplier;

    userInfo.userRates += ShareableMath.rmulup(userMultiplier, yieldPerTokenInRay);

    emit PowerAdded(msg.sender, _user, _addMultiplier);
  }

  function removePower(address _user, uint128 _removeMultiplier)
    external
    override
    onlyHeroglyphWrappedNFT
  {
    UserInfo storage userInfo = usersInfo[_user];
    _claim(_user, userInfo, false);

    uint256 userMultiplier = userInfo.multiplier - _removeMultiplier;

    userInfo.multiplier = userMultiplier;
    totalMultiplier -= _removeMultiplier;

    userInfo.userRates -= ShareableMath.rmulup(userMultiplier, yieldPerTokenInRay);

    emit PowerRemoved(msg.sender, _user, _removeMultiplier);
  }

  function usesForRenaming(address _user) external override onlyHeroglyphWrappedNFT {
    _claim(_user, usersInfo[_user], true);
    _burn(_user, NAME_COST);

    emit BurnedForRenaming(msg.sender, _user, NAME_COST);
  }

  function claim() external {
    uint128 amount_ = _claim(msg.sender, usersInfo[msg.sender], true);
    if (amount_ == 0) revert NothingToClaim();
  }

  function _claim(address _user, UserInfo storage _userInfo, bool _updateUserRate)
    internal
    returns (uint128 amount_)
  {
    uint256 nextTotalRewards = totalRewards;

    nextTotalRewards += _getSystemPendingRewards(uint32(block.timestamp));
    lastUnixTimeRewards = uint32(block.timestamp);

    uint256 yieldPerTokenInRayCached = yieldPerTokenInRay;
    uint256 totalMultiplierCached = totalMultiplier;

    if (totalMultiplierCached > 0) {
      yieldPerTokenInRayCached +=
        ShareableMath.rdiv(nextTotalRewards - totalRewards, totalMultiplierCached);
    }

    uint256 last = _userInfo.userRates;
    uint256 curr = ShareableMath.rmulup(_userInfo.multiplier, yieldPerTokenInRayCached);

    if (curr > last) {
      amount_ = uint128(curr - last);
      _mint(_user, amount_);
      nextTotalRewards -= amount_;

      emit Claimed(_user, amount_);
    }

    totalRewards = nextTotalRewards;
    yieldPerTokenInRay = yieldPerTokenInRayCached;

    if (_updateUserRate) {
      _userInfo.userRates =
        uint128(ShareableMath.rmulup(_userInfo.multiplier, yieldPerTokenInRayCached));
    }

    return amount_;
  }

  function balanceOf(address _user) public view override returns (uint256) {
    return super.balanceOf(_user) + _getUserPendingRewards(_user);
  }

  function getUserPendingRewards(address _user) external view override returns (uint256) {
    return _getUserPendingRewards(_user);
  }

  function _getUserPendingRewards(address _user) internal view returns (uint256 amount_) {
    if (totalMultiplier == 0) return 0;

    UserInfo memory userInfo = usersInfo[_user];
    uint256 nextTotalRewards = totalRewards;

    nextTotalRewards += _getSystemPendingRewards(uint32(block.timestamp));

    uint256 yieldPerTokenInRayCached = yieldPerTokenInRay;
    uint256 totalMultiplierCached = totalMultiplier;

    yieldPerTokenInRayCached +=
      ShareableMath.rdiv(nextTotalRewards - totalRewards, totalMultiplierCached);

    uint256 last = userInfo.userRates;
    uint256 curr = ShareableMath.rmulup(userInfo.multiplier, yieldPerTokenInRayCached);

    if (curr > last) {
      amount_ = uint128(curr - last);
    }

    return amount_;
  }

  function getSystemPendingRewards() external view override returns (uint256) {
    return _getSystemPendingRewards(uint32(block.timestamp));
  }

  function getTotalRewardsGenerated() external view override returns (uint256) {
    return totalRewards + _getSystemPendingRewards(uint32(block.timestamp));
  }

  function _getSystemPendingRewards(uint32 _currentTime) internal view returns (uint256) {
    uint32 timePassed = _currentTime - lastUnixTimeRewards;
    if (timePassed == 0) return 0;

    uint256 rateReward = Math.sqrt(totalMultiplier * productionRate) / 1 days;

    return uint256(timePassed * rateReward);
  }

  function getUserInfo(address _user) external view override returns (UserInfo memory) {
    return usersInfo[_user];
  }
}

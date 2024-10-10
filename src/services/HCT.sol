// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract HCT is ERC20, IHCT {
  uint256 private constant PRECISION = 1e18;
  uint128 public constant NAME_COST = 90e18;

  bool private isInitialized;
  IObeliskRegistry public obeliskRegistry;
  mapping(address => UserInfo) internal usersInfo;

  constructor() ERC20("Heroglyph Name Change Token", "HCT") { }

  function initHCT(address _obeliskRegistry) external {
    if (isInitialized) revert AlreadyInitialized();

    isInitialized = true;
    obeliskRegistry = IObeliskRegistry(_obeliskRegistry);
  }

  modifier onlyHeroglyphWrappedNFT() {
    if (!obeliskRegistry.isWrappedNFT(msg.sender)) revert NotWrappedNFT();
    _;
  }

  function addPower(address _user, uint128 _addMultiplier) external override onlyHeroglyphWrappedNFT {
    UserInfo storage userInfo = usersInfo[_user];
    _claim(_user, userInfo);
    userInfo.multiplier += _addMultiplier;

    emit PowerAdded(msg.sender, _user, _addMultiplier);
  }

  function removePower(address _user, uint128 _removeMultiplier) external override onlyHeroglyphWrappedNFT {
    UserInfo storage userInfo = usersInfo[_user];
    _claim(_user, userInfo);
    userInfo.multiplier -= uint128(_removeMultiplier);

    emit PowerRemoved(msg.sender, _user, _removeMultiplier);
  }

  function usesForRenaming(address _user) external override onlyHeroglyphWrappedNFT {
    _claim(_user, usersInfo[_user]);
    _burn(_user, NAME_COST);

    emit BurnedForRenaming(msg.sender, _user, NAME_COST);
  }

  function claim() external {
    uint128 amount_ = _claim(msg.sender, usersInfo[msg.sender]);
    if (amount_ == 0) revert NothingToClaim();
  }

  function _claim(address _user, UserInfo storage _userInfo) internal returns (uint128 amount_) {
    amount_ = _getPendingToBeClaimed(uint32(block.timestamp), _userInfo);
    _userInfo.lastUnixTimeClaim = uint32(block.timestamp);

    if (amount_ == 0) return amount_;

    _mint(_user, amount_);
    emit Claimed(_user, amount_);

    return amount_;
  }

  function balanceOf(address _user) public view override returns (uint256) {
    return super.balanceOf(_user) + _getPendingToBeClaimed(uint32(block.timestamp), usersInfo[_user]);
  }

  function getPendingToBeClaimed(address _user) external view returns (uint256) {
    return _getPendingToBeClaimed(uint32(block.timestamp), usersInfo[_user]);
  }

  function _getPendingToBeClaimed(uint32 _currentTime, UserInfo memory _userInfo) internal pure returns (uint128) {
    uint32 timePassed = _currentTime - _userInfo.lastUnixTimeClaim;
    if (timePassed == 0) return 0;

    uint256 rateReward = Math.sqrt(_userInfo.multiplier * PRECISION) / 1 days;

    return uint128(timePassed * rateReward);
  }

  function getUserInfo(address _user) external view override returns (UserInfo memory) {
    return usersInfo[_user];
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

import { FixedPointMathLib as Math } from "src/vendor/solmate/FixedPointMathLib.sol";

contract HCT is ERC20, IHCT {
  uint256 private constant PRECISION = 1e18;
  uint128 private constant POWER_BY_NFT = 1e18;
  uint128 public constant NAME_COST = 90e18;
  uint128 public constant ONE_MONTH_IN_SECOND = 2_629_800;

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
    _increasePowerAndMultiplier(userInfo, POWER_BY_NFT, _addMultiplier);

    emit PowerAdded(msg.sender, _user, POWER_BY_NFT, _addMultiplier);
  }

  function removePower(address _user, uint128 _removeMultiplier) external override onlyHeroglyphWrappedNFT {
    UserInfo storage userInfo = usersInfo[_user];
    _claim(_user, userInfo);
    _reducePowerAndMultiplier(userInfo, POWER_BY_NFT, _removeMultiplier);

    emit PowerRemoved(msg.sender, _user, POWER_BY_NFT, _removeMultiplier);
  }

  function onNFTTransfer(address _from, address _to, uint128 _multiplierToRemove, uint128 _multiplierToAdd)
    external
    override
    onlyHeroglyphWrappedNFT
  {
    UserInfo storage fromUserInfo = usersInfo[_from];
    UserInfo storage toUserInfo = usersInfo[_to];

    _claim(_from, fromUserInfo);
    _claim(_to, toUserInfo);

    _reducePowerAndMultiplier(fromUserInfo, POWER_BY_NFT, _multiplierToRemove);
    _increasePowerAndMultiplier(toUserInfo, POWER_BY_NFT, _multiplierToAdd);

    emit Transferred(msg.sender, _from, _to, _multiplierToAdd);
  }

  function _increasePowerAndMultiplier(UserInfo storage _userInfo, uint128 _addingPower, uint128 _addMultiplier)
    internal
  {
    uint256 totalMultiplier = _userInfo.totalMultiplier + _addMultiplier;
    uint256 totalPower = _userInfo.power + _addingPower;

    _userInfo.power = uint128(totalPower);
    _userInfo.totalMultiplier = uint128(totalMultiplier);
    _userInfo.multiplier = uint128(Math.mulDivDown(totalMultiplier, PRECISION, totalPower));
  }

  function _reducePowerAndMultiplier(UserInfo storage _userInfo, uint128 _removingPower, uint128 _removeMultiplier)
    internal
  {
    uint256 totalMultiplier = _userInfo.totalMultiplier - _removeMultiplier;
    uint256 totalPower = _userInfo.power - _removingPower;

    _userInfo.power = uint128(totalPower);
    _userInfo.totalMultiplier = uint128(totalMultiplier);
    _userInfo.multiplier = uint128(Math.mulDivDown(totalMultiplier, PRECISION, totalPower));
  }

  function usesForRenaming(address _user) external override onlyHeroglyphWrappedNFT {
    _claim(_user, usersInfo[_user]);
    _burn(_user, NAME_COST);

    emit BurnedForRenaming(msg.sender, _user, NAME_COST);
  }

  function _claim(address _user, UserInfo storage _userInfo) internal {
    uint128 amount = _getPendingToBeClaimed(uint32(block.timestamp), _userInfo);
    _userInfo.lastUnixTimeClaim = uint32(block.timestamp);

    if (amount == 0) return;

    _mint(_user, amount);
    emit Claimed(_user, amount);
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

    uint256 rateReward = Math.sqrt(_userInfo.power * _userInfo.multiplier) / 1 days;

    return uint128(timePassed * rateReward);
  }

  function getUserInfo(address _user) external view override returns (UserInfo memory) {
    return usersInfo[_user];
  }
}

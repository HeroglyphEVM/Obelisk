// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IHCT {
  error AlreadyInitialized();
  error NotWrappedNFT();
  error NotActive();
  error InsufficientBalance();

  event PowerAdded(address indexed wrappedNFT, address indexed user, uint256 power, uint128 multiplier);
  event PowerRemoved(address indexed wrappedNFT, address indexed user, uint256 power, uint128 multiplier);
  event Transferred(address indexed wrappedNFT, address indexed from, address indexed to, uint128 multiplier);
  event Claimed(address indexed user, uint256 amount);
  event BurnedForRenaming(address indexed wrappedNFT, address indexed user, uint256 amount);

  struct UserInfo {
    uint128 power;
    uint128 multiplier;
    uint128 totalMultiplier;
    uint32 lastUnixTimeClaim;
  }

  function addPower(address _user, uint128 _addMultiplier) external;
  function removePower(address _user, uint128 _removeMultiplier) external;
  function usesForRenaming(address _user) external;
  function getPendingToBeClaimed(address _user) external view returns (uint256);
  function getUserInfo(address _user) external view returns (UserInfo memory);
}

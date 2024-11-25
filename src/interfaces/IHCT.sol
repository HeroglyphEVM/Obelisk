// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IHCT {
  error NotWrappedNFT();
  error NothingToClaim();

  event TotalNFTWrapped(uint256 totalWrappedNFT);
  event PowerAdded(address indexed wrappedNFT, address indexed user, uint128 multiplier);
  event PowerRemoved(
    address indexed wrappedNFT, address indexed user, uint128 multiplier
  );
  event Transferred(
    address indexed wrappedNFT,
    address indexed from,
    address indexed to,
    uint128 multiplier
  );
  event Claimed(address indexed user, uint256 amount);
  event BurnedForRenaming(
    address indexed wrappedNFT, address indexed user, uint256 amount
  );
  event InflationRateSet(uint256 inflationRate);
  event BaseRateSet(uint256 baseRate);
  event InflationThresholdSet(uint256 inflationThreshold);

  struct UserInfo {
    uint256 multiplier;
    uint256 userRates;
  }

  function addPower(address _user, uint128 _addMultiplier, bool _newNFT) external;
  function removePower(address _user, uint128 _removeMultiplier) external;
  function burn(address _user, uint256 _amount) external;
  function usesForRenaming(address _user) external;
  function getUserPendingRewards(address _user) external view returns (uint256);
  function getSystemPendingRewards() external view returns (uint256);
  function getTotalRewardsGenerated() external view returns (uint256);
  function getUserInfo(address _user) external view returns (UserInfo memory);
}

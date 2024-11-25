// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IObeliskNFT {
  event TickerDeactivated(uint256 indexed tokenId, address indexed stakedPool);
  event TickerActivated(uint256 indexed tokenId, address indexed stakedPool);
  event TickerClaimed(uint256 indexed tokenId, address indexed stakedPool);
  event NameUpdated(uint256 indexed tokenId, string name);

  /**
   * @notice Claims the rewards for a given token ID.
   * @param _tokenId The ID of the token to claim rewards for.
   */
  function claim(uint256 _tokenId) external;

  /**
   * @notice Returns the identity information for a given token ID.
   * @param _tokenId The ID of the token to get identity information for.
   * @return identityInTicker_ The identity id in the ticker pools.
   * @return rewardReceiver_ The address that will receive the rewards.
   */
  function getIdentityInformation(uint256 _tokenId)
    external
    view
    returns (bytes32 identityInTicker_, address rewardReceiver_);
}

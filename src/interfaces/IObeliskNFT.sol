// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IObeliskNFT {
  event TickerDeactivated(uint256 indexed tokenId, address indexed stakedPool);
  event TickerActivated(uint256 indexed tokenId, address indexed stakedPool);
  event TickerClaimed(uint256 indexed tokenId, address indexed stakedPool);

  /**
   * @notice Claims the rewards for a given token ID.
   * @param _tokenId The ID of the token to claim rewards for.
   */
  function claim(uint256 _tokenId) external;
}

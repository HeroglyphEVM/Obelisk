// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILiteTicker {
  error NotWrappedNFT();
  error NotDeposited();
  error AlreadyDeposited();

  event Deposited(address indexed wrappedNFT, uint256 indexed nftId);
  event Withdrawn(address indexed wrappedNFT, uint256 indexed nftId);

  /**
   * @dev Virtual deposit and withdraw functions for the wrapped NFTs.
   * @param _tokenId The ID of the NFT to deposit or withdraw.
   */
  function virtualDeposit(bytes32 _identity, uint256 _tokenId, address _receiver)
    external;

  /**
   * @dev Virtual withdraw function for the wrapped NFTs.
   * @param _tokenId The ID of the NFT to withdraw.
   * @param _ignoreRewards Whether to ignore the rewards and withdraw the NFT.
   * @dev The `_ignoreRewards` parameter is primarily used for Hashmasks. When
   * transferring or renaming their NFTs, any
   * claims made will result in the rewards being canceled and returned to the pool. This
   * mechanism is in place to
   * prevent exploitative farming.
   */
  function virtualWithdraw(
    bytes32 _identity,
    uint256 _tokenId,
    address _receiver,
    bool _ignoreRewards
  ) external;

  /**
   * @dev Claim function for the wrapped NFTs.
   * @param _tokenId The ID of the NFT to claim.
   */
  function claim(
    bytes32 _identity,
    uint256 _tokenId,
    address _receiver,
    bool _ignoreRewards
  ) external;
}

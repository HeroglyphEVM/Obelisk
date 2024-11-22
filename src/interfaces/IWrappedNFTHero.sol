// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IWrappedNFTHero {
  error AlreadyMinted();
  error NotMinted();
  error NotNFTHolder();
  error NoFreeSlots();
  error FreeSlotAvailable();
  error CannotTransferUnwrapFirst();
  error SameMultiplier();
  error InvalidNameLength();
  error InvalidWalletReceiver();
  error EmergencyWithdrawDisabled();
  error EmergencyModeIsActive();
  error NotObeliskRegistry();
  error NotNFTPassHolder();

  event Wrapped(uint256 indexed tokenId);
  event Unwrapped(uint256 indexed tokenId);
  event SlotBought(address indexed user, uint256 indexed inputCollectionNFTId);
  event FreeSlotUsed(uint256 freeSlotLeft);
  event EmergencyWithdrawEnabled();
  event MultiplierUpdated(uint256 indexed tokenId, uint128 newMultiplier);

  struct NFTData {
    bool isMinted;
    bool hasBeenRenamed;
    bool wrappedOnce;
    uint128 assignedMultiplier;
  }

  /**
   * @notice Wraps an NFT from the input collection into a Wrapped NFT Hero.
   * @param _inputCollectionNFTId The ID of the NFT to wrap.
   */
  function wrap(uint256 _inputCollectionNFTId) external payable;

  /**
   * @notice Renames a Wrapped NFT Hero.
   * @param _tokenId The ID of the Wrapped NFT Hero to rename.
   * @param _newName The new name for the Wrapped NFT Hero.
   */
  function rename(uint256 _tokenId, string memory _newName) external;

  /**
   * @notice Unwraps a Wrapped NFT Hero back into the original NFT from the input
   * collection.
   * @param _tokenId The ID of the Wrapped NFT Hero to unwrap.
   */
  function unwrap(uint256 _tokenId) external;

  /**
   * @notice Updates the multiplier of a Wrapped NFT Hero.
   * @param _tokenId The ID of the Wrapped NFT Hero to update the multiplier.
   * @dev Since the multiplier increases over-time, the user needs to update the
   * multiplier on their side. Not ideal, but good enough for the time we have.
   */
  function updateMultiplier(uint256 _tokenId) external;

  /**
   * @notice Returns the multiplier of the Wrapped NFT Hero.
   */
  function getWrapperMultiplier() external view returns (uint128);

  /**
   * @notice Returns the data of a Wrapped NFT Hero.
   * @param _tokenId The ID of the Wrapped NFT Hero to get the data.
   */
  function getNFTData(uint256 _tokenId) external view returns (NFTData memory);

  /**
   * @notice Enables emergency withdraw for the Wrapped NFT Hero.
   */
  function enableEmergencyWithdraw() external;
}

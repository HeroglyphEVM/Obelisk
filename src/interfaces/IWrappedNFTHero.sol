// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IWrappedNFTHero {
  error AlreadyMinted();
  error NotMinted();
  error NotNFTHolder();
  error NoFreeSlots();
  error FreeSlotAvailable();

  event Wrapped(uint256 indexed tokenId);
  event Unwrapped(uint256 indexed tokenId);
  event SlotBought(address indexed user, uint256 indexed inputCollectionNFTId);
  event FreeSlotUsed(uint256 freeSlotLeft);

  struct NFTData {
    bool isMinted;
    bool firstRename;
    bool wrappedOnce;
    uint128 assignedMultiplier;
  }

  function wrap(uint256 _inputCollectionNFTId) external payable;

  function unwrap(uint256 _tokenId) external;
}

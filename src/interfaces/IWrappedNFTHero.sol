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
  event SlotBought(address indexed user, uint256 amount);
  event FreeSlotUsed(uint256 freeSlotLeft);

  function wrap(uint256 _attachedCollectionNFTId) external payable;

  function unwrap(uint256 _tokenId) external;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IObeliskNFT {
  error InvalidNameLength();
  error InvalidWalletReceiver();
  error NotAuthorized();

  event TickerDeactivated(uint256 indexed tokenId, address indexed stakedPool);
  event TickerActivated(uint256 indexed tokenId, address indexed stakedPool);
  event NameChanged(uint256 indexed tokenId, string indexed newName);
  event TickerClaimed(uint256 indexed tokenId, address indexed stakedPool);
}

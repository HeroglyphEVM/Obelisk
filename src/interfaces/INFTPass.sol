// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INFTPass {
  error NoNeedToPay();
  error InvalidBPS();
  error MsgValueTooLow();

  event NFTPassCreated(uint256 indexed nftId, string indexed name, address indexed receiver, uint256 cost);
  event NFTPassUpdated(uint256 indexed nftId, string indexed name, address indexed receiver);
  event MaxIdentityPerDayAtInitialPriceUpdated(uint32 newMaxIdentityPerDayAtInitialPrice);
  event PriceIncreaseThresholdUpdated(uint32 newPriceIncreaseThreshold);
  event PriceDecayBPSUpdated(uint32 newPriceDecayBPS);

  struct Metadata {
    string name;
    address walletReceiver;
  }

  function getMetadata(uint256 _nftId, string calldata _name) external view returns (Metadata memory);
}

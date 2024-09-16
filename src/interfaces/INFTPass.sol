// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INFTPass {
  error NoNeedToPay();

  event NFTPassCreated(uint256 indexed nftId, string indexed name, address indexed receiver);
  event NFTPassUpdated(uint256 indexed nftId, string indexed name, address indexed receiver);

  struct Metadata {
    string name;
    address walletReceiver;
  }

  function getMetadata(uint256 _nftId) external view returns (Metadata memory);
  function getMetadataWithName(string calldata _name) external view returns (Metadata memory);
}

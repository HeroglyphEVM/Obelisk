// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INFTPass {
  error NoNeedToPay();
  error InvalidBPS();
  error MsgValueTooLow();
  error AlreadyClaimed();
  error InvalidProof();
  error NameTooLong();
  error ClaimingEnded();

  event NFTPassCreated(
    uint256 indexed nftId, string indexed name, address indexed receiver, uint256 cost
  );
  event NFTPassUpdated(
    uint256 indexed nftId, string indexed name, address indexed receiver
  );
  event MaxIdentityPerDayAtInitialPriceUpdated(uint32 newMaxIdentityPerDayAtInitialPrice);
  event PriceIncreaseThresholdUpdated(uint32 newPriceIncreaseThreshold);
  event PriceDecayBPSUpdated(uint32 newPriceDecayBPS);

  struct Metadata {
    string name;
    address walletReceiver;
    uint8 imageIndex;
  }

  /**
   * @param _name The name of the NFT Pass
   * @param _receiverWallet The wallet address that will receive the NFT Pass
   * @param merkleProof The Merkle proof for the NFT Pass
   */
  function claimPass(
    string calldata _name,
    address _receiverWallet,
    bytes32[] calldata merkleProof
  ) external;

  /**
   * @param _name The name of the NFT Pass
   * @param _receiverWallet The wallet address that will receive the NFT Pass
   */
  function create(string calldata _name, address _receiverWallet) external payable;

  /**
   * @param _nftId The ID of the NFT Pass
   * @param _name The name of the NFT Pass
   * @param _receiver The wallet address that will receive the NFT Pass
   * @dev It's nftId or Name, if nftId is 0, it will use the name to find the nftId
   */
  function updateReceiverAddress(uint256 _nftId, string calldata _name, address _receiver)
    external;

  /**
   * @return The cost of the NFT Pass
   */
  function getCost() external view returns (uint256);

  /**
   * @param _nftId The ID of the NFT Pass
   * @param _name The name of the NFT Pass
   */
  function getMetadata(uint256 _nftId, string calldata _name)
    external
    view
    returns (Metadata memory);
}

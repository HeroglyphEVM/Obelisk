// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IdentityERC721 } from "src/vendor/heroglyph/IdentityERC721.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
/**
 * @title NFTPass
 * @notice A contract that allows users to buy NFT passes to create their own identity.
 * Without a pass, the user can't
 * use Obelisk.
 */

contract NFTPass is INFTPass, IdentityERC721 {
  uint256 internal constant MAX_BPS = 10_000;
  uint256 internal constant SEND_ETH_GAS_MINIMUM = 20_000 * 2;
  uint256 internal constant MAX_NAME_BYTES = 15;

  string[] public IMAGES = [
    "ipfs://QmWDi6zXedMwyy4rBgTb2KRJpEL7T4GJm94TFb64dgUP8W",
    "ipfs://QmZidqfqBGS3NXBF72gHBCJurLce52FusvsQwQBmmBmPRw",
    "ipfs://QmPXFdLJpJB8VSPFQF5W7syoij6noxvUU9DWTKKQHRVa5F",
    "ipfs://QmcRoYHMzY54V2ZmCmg8dq195fMETF8nEAVQb3UDqQhknw",
    "ipfs://QmSC4ETHbF1DDuhxaWhqUedsmuyMva3UazpPhrDzuvQgQ3"
  ];

  uint32 public maxIdentityPerDayAtInitialPrice;
  uint32 public priceIncreaseThreshold;
  uint32 public priceDecayBPS;
  uint32 public resetCounterTimestamp;
  uint32 public boughtToday;
  uint256 public currentPrice;

  bytes32 public immutable merkleRoot;
  mapping(address => bool) public claimedPasses;

  mapping(uint256 => Metadata) internal metadataPasses;

  constructor(
    address _owner,
    address _treasury,
    address _nameFilter,
    uint256 _cost,
    bytes32 _merkleRoot
  ) IdentityERC721(_owner, _treasury, _nameFilter, _cost, "Obelisk NFT Pass", "OPASS") {
    resetCounterTimestamp = uint32(block.timestamp + 1 days);
    currentPrice = cost;
    maxIdentityPerDayAtInitialPrice = 25;
    priceIncreaseThreshold = 10;
    priceDecayBPS = 2500;
    merkleRoot = _merkleRoot;
  }

  function claimPass(
    string calldata _name,
    address _receiverWallet,
    bytes32[] calldata merkleProof
  ) external {
    if (bytes(_name).length > MAX_NAME_BYTES) revert NameTooLong();
    if (claimedPasses[msg.sender]) revert AlreadyClaimed();
    if (_receiverWallet == address(0)) _receiverWallet = msg.sender;

    if (!MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encode(msg.sender)))) {
      revert InvalidProof();
    }

    claimedPasses[msg.sender] = true;

    uint256 id = _create(_name, 0);
    metadataPasses[id] = Metadata({
      name: _name,
      walletReceiver: _receiverWallet,
      imageIndex: uint8(
        uint256(keccak256(abi.encode(_name, block.timestamp))) % IMAGES.length
      )
    });

    emit NFTPassCreated(id, _name, _receiverWallet, 0);
  }

  function create(string calldata _name, address _receiverWallet) external payable {
    if (bytes(_name).length > MAX_NAME_BYTES) revert NameTooLong();
    if (cost == 0 && msg.value != 0) revert NoNeedToPay();
    if (_receiverWallet == address(0)) _receiverWallet = msg.sender;

    uint256 costAtDuringTx = _updateCost();

    if (msg.value < costAtDuringTx) revert MsgValueTooLow();

    uint256 id = _create(_name, 0);
    metadataPasses[id] = Metadata({
      name: _name,
      walletReceiver: _receiverWallet,
      imageIndex: uint8(
        uint256(keccak256(abi.encode(_name, block.timestamp))) % IMAGES.length
      )
    });

    emit NFTPassCreated(id, _name, _receiverWallet, costAtDuringTx);

    if (costAtDuringTx == 0) return;
    uint256 remainingValue = msg.value - costAtDuringTx;
    bool success;

    if (remainingValue > tx.gasprice * SEND_ETH_GAS_MINIMUM) {
      (success,) = msg.sender.call{ value: remainingValue }("");
      if (!success) revert TransferFailed();

      remainingValue = 0;
    }

    (success,) = treasury.call{ value: costAtDuringTx + remainingValue }("");
    if (!success) revert TransferFailed();
  }

  function updateReceiverAddress(uint256 _nftId, string calldata _name, address _receiver)
    external
  {
    if (_nftId == 0) {
      _nftId = identityIds[_name];
    }

    if (ownerOf(_nftId) != msg.sender) revert NotIdentityOwner();

    Metadata storage metadata = metadataPasses[_nftId];
    metadata.walletReceiver = _receiver;

    emit NFTPassUpdated(_nftId, metadata.name, _receiver);
  }

  function _updateCost() internal returns (uint256 userCost_) {
    (resetCounterTimestamp, boughtToday, currentPrice, userCost_) = _getCostDetails();
    return userCost_;
  }

  function getCost() external view returns (uint256 userCost_) {
    (,,, userCost_) = _getCostDetails();
    return userCost_;
  }

  function _getCostDetails()
    internal
    view
    returns (
      uint32 resetCounterTimestampReturn_,
      uint32 boughtTodayReturn_,
      uint256 currentCostReturn_,
      uint256 userCost_
    )
  {
    uint32 maxPerDayCached = maxIdentityPerDayAtInitialPrice;
    resetCounterTimestampReturn_ = resetCounterTimestamp;
    boughtTodayReturn_ = boughtToday;
    currentCostReturn_ = currentPrice;
    uint256 cachedCost = cost;

    if (block.timestamp >= resetCounterTimestampReturn_) {
      uint256 totalDayPassed =
        (block.timestamp - resetCounterTimestampReturn_) / 1 days + 1;
      resetCounterTimestampReturn_ += uint32(1 days * totalDayPassed);
      boughtTodayReturn_ = 0;

      for (uint256 i = 0; i < totalDayPassed; ++i) {
        currentCostReturn_ = Math.max(
          cachedCost,
          currentCostReturn_ - Math.mulDiv(currentCostReturn_, priceDecayBPS, MAX_BPS)
        );

        if (currentCostReturn_ <= cachedCost) break;
      }
    }

    bool boughtExceedsMaxPerDay = boughtTodayReturn_ > maxPerDayCached;

    if (
      boughtExceedsMaxPerDay
        && (boughtTodayReturn_ - maxPerDayCached) % priceIncreaseThreshold == 0
    ) {
      currentCostReturn_ += cachedCost / 2;
    }

    userCost_ = !boughtExceedsMaxPerDay ? cachedCost : currentCostReturn_;
    boughtTodayReturn_++;

    return
      (resetCounterTimestampReturn_, boughtTodayReturn_, currentCostReturn_, userCost_);
  }

  function getMetadata(uint256 _nftId, string calldata _name)
    external
    view
    returns (Metadata memory)
  {
    if (_nftId == 0) {
      _nftId = identityIds[_name];
    }

    return metadataPasses[_nftId];
  }

  function updateMaxIdentityPerDayAtInitialPrice(uint32 _maxIdentityPerDayAtInitialPrice)
    external
    onlyOwner
  {
    maxIdentityPerDayAtInitialPrice = _maxIdentityPerDayAtInitialPrice;
    emit MaxIdentityPerDayAtInitialPriceUpdated(_maxIdentityPerDayAtInitialPrice);
  }

  function updatePriceIncreaseThreshold(uint32 _priceIncreaseThreshold)
    external
    onlyOwner
  {
    priceIncreaseThreshold = _priceIncreaseThreshold;
    emit PriceIncreaseThresholdUpdated(_priceIncreaseThreshold);
  }

  function updatePriceDecayBPS(uint32 _priceDecayBPS) external onlyOwner {
    if (_priceDecayBPS > MAX_BPS) revert InvalidBPS();
    priceDecayBPS = _priceDecayBPS;
    emit PriceDecayBPSUpdated(_priceDecayBPS);
  }

  function transferFrom(address, address, uint256) public pure override {
    revert("Non-Transferrable");
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireOwned(tokenId);

    Metadata storage metadata = metadataPasses[tokenId];

    string memory data = string(
      abi.encodePacked(
        '{"name":"NFT Pass: ',
        metadata.name,
        '","description":"Required to use Obelisk","image":"',
        IMAGES[metadata.imageIndex],
        '"}'
      )
    );

    return string(abi.encodePacked("data:application/json;utf8,", data));
  }
}

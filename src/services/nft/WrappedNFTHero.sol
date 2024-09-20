// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC721, IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IWrappedNFTHero } from "src/interfaces/IWrappedNFTHero.sol";
import { TickerNFT } from "./TickerNFT.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract WrappedNFTHero is IWrappedNFTHero, ERC721, IERC721Receiver, TickerNFT {
  uint256 private constant MAX_BPS = 10_000;
  uint256 private constant SECONDS_PER_YEAR = 31_557_600;

  uint256 public constant SLOT_PRICE = 0.1e18;
  uint256 public constant FREE_SLOT_BPS = 2000; // 20 %

  uint256 public constant RATE_PER_YEAR = 0.43e18;
  uint256 public constant MAX_RATE = 3e18;

  IHCT public immutable HCT;
  ERC721 public immutable INPUT_COLLECTION;

  mapping(uint256 => bool) public isMinted;
  mapping(uint256 => uint128) public assignedMultipler;

  uint256 public freeSlots;
  uint32 public collectionStartedUnixTime;
  uint32 public contractStartedUixTime;
  uint32 public contractBlockNumber;
  bool public freeSlotForOdd;
  bool public premium;

  constructor(
    address _HCT,
    address _nftPass,
    address _inputCollection,
    address _obeliskRegistry,
    uint256 _currentSupply,
    uint32 _collectionStartedUnixTime,
    bool _premium
  ) ERC721("WrappedNFTHero", "WNH") TickerNFT(_obeliskRegistry, _nftPass) {
    HCT = IHCT(_HCT);
    INPUT_COLLECTION = ERC721(_inputCollection);

    freeSlots = _currentSupply * FREE_SLOT_BPS / MAX_BPS;
    freeSlotForOdd = uint256(keccak256(abi.encode(tx.origin, _inputCollection))) % 2 == 1;
    collectionStartedUnixTime = _collectionStartedUnixTime;
    premium = _premium;
  }

  function wrap(uint256 _inputCollectionNFTId) external payable override {
    uint256 catchedDepositNFTID = _inputCollectionNFTId;
    bool isIdOdd = catchedDepositNFTID % 2 == 1;
    bool canHaveFreeSlot = freeSlots != 0 && freeSlotForOdd == isIdOdd;

    if (isMinted[catchedDepositNFTID]) revert AlreadyMinted();
    if (canHaveFreeSlot && msg.value != 0) revert FreeSlotAvailable();
    if (!canHaveFreeSlot && msg.value != SLOT_PRICE) revert NoFreeSlots();

    if (!canHaveFreeSlot) {
      obeliskRegistry.onSlotBought{ value: msg.value }();
      emit SlotBought(msg.sender, _inputCollectionNFTId);
    } else {
      freeSlots--;
      emit FreeSlotUsed(freeSlots);
    }

    isMinted[catchedDepositNFTID] = true;
    INPUT_COLLECTION.transferFrom(msg.sender, address(this), catchedDepositNFTID);

    _safeMint(msg.sender, catchedDepositNFTID);

    emit Wrapped(_inputCollectionNFTId);
  }

  function unwrap(uint256 _tokenId) external override {
    if (!isMinted[_tokenId]) revert NotMinted();
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();

    _removeOldTickers(identities[_tokenId], _tokenId, false);

    _burn(_tokenId);
    delete names[_tokenId];
    delete assignedMultipler[_tokenId];

    isMinted[_tokenId] = false;
    INPUT_COLLECTION.safeTransferFrom(address(this), msg.sender, _tokenId);

    emit Unwrapped(_tokenId);
  }

  function _renameRequirements(uint256 _tokenId) internal override {
    if (!isMinted[_tokenId]) revert NotMinted();
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();

    HCT.usesForRenaming(msg.sender);
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    return _ownerOf(_tokenId) == msg.sender;
  }

  function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
    address from = _ownerOf(tokenId);
    uint128 multiplier = assignedMultipler[tokenId];

    if (from != address(0)) {
      HCT.removePower(from, multiplier);
      multiplier = 0;
    }

    if (to != address(0)) {
      multiplier = getWrapperMultiplier();
      HCT.addPower(to, multiplier);
    }

    assignedMultipler[tokenId] = multiplier;

    return super._update(to, tokenId, auth);
  }

  function getWrapperMultiplier() public view returns (uint128) {
    if (premium) return uint128(MAX_RATE);

    uint256 currentYear = (block.timestamp - collectionStartedUnixTime) / SECONDS_PER_YEAR;
    return uint128(Math.min(currentYear * RATE_PER_YEAR, MAX_RATE));
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }
}

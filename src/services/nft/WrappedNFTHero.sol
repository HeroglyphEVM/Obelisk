// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IWrappedNFTHero } from "src/interfaces/IWrappedNFTHero.sol";
import { TickerNFT } from "./TickerNFT.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract WrappedNFTHero is IWrappedNFTHero, ERC721, TickerNFT {
  uint256 private constant MAX_BPS = 10_000;
  uint256 private constant SECONDS_PER_YEAR = 31_557_600;

  uint256 public constant SLOT_PRICE = 0.1 ether;
  uint256 private constant FREE_SLOT_BPS = 2000; // 20%

  uint256 private constant RATE_PER_YEAR = 0.43e18;
  uint256 private constant MAX_RATE = 3e18;

  IHCT public immutable HCT;
  ERC721 public immutable attachedCollection;

  mapping(uint256 => bool) public isMinted;
  mapping(uint256 => uint128) public multiplierUsed;

  uint256 public freeSlots;
  uint32 public collectionStartedUnixTime;
  uint32 public contractStartedUnixTime;
  uint32 public contractBlockNumber;
  bool public freeSlotForOdd;

  constructor(
    address _HCT,
    address _nftPass,
    address _attachedCollection,
    address _heroglyphRegistry,
    uint256 _totalSupply,
    uint32 _collectionStartedUnixTime
  ) ERC721("WrappedNFTHero", "WNH") TickerNFT(_heroglyphRegistry, _nftPass) {
    HCT = IHCT(_HCT);
    attachedCollection = ERC721(_attachedCollection);

    freeSlots = _totalSupply * FREE_SLOT_BPS / MAX_BPS;
    freeSlotForOdd = abi.encode(tx.origin, _attachedCollection).length % 2 == 1;
    collectionStartedUnixTime = _collectionStartedUnixTime;
    contractStartedUnixTime = uint32(block.timestamp);
  }

  function wrap(uint256 _attachedCollectionNFTId) external payable override {
    uint256 catchedDepositNFTID = _attachedCollectionNFTId;
    bool isIdOdd = catchedDepositNFTID % 2 == 1;
    bool canHaveFreeSlot = freeSlots != 0 && freeSlotForOdd == isIdOdd;

    if (isMinted[catchedDepositNFTID]) revert AlreadyMinted();
    if (canHaveFreeSlot && msg.value != 0) revert FreeSlotAvailable();
    if (!canHaveFreeSlot && msg.value != SLOT_PRICE) revert NoFreeSlots();

    if (!canHaveFreeSlot) {
      heroglyphRegistry.onSlotBought{ value: msg.value }();
      emit SlotBought(msg.sender, msg.value);
    } else {
      freeSlots--;
      emit FreeSlotUsed(freeSlots);
    }

    isMinted[catchedDepositNFTID] = true;
    attachedCollection.transferFrom(msg.sender, address(this), catchedDepositNFTID);

    _safeMint(msg.sender, catchedDepositNFTID);

    emit Wrapped(_attachedCollectionNFTId);
  }

  function unwrap(uint256 _tokenId) external override {
    if (!isMinted[_tokenId]) revert NotMinted();
    _removeOldTickers(_tokenId, false);

    HCT.removePower(msg.sender, getWrapperMultiplier());
    attachedCollection.transferFrom(address(this), msg.sender, _tokenId);

    _burn(_tokenId);
    delete names[_tokenId];
    isMinted[_tokenId] = false;

    emit Unwrapped(_tokenId);
  }

  function _renameRequirements(uint256 _tokenId) internal override {
    if (!isMinted[_tokenId]) revert NotMinted();
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();

    HCT.usesForRenaming(msg.sender);
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    return attachedCollection.ownerOf(_tokenId) == msg.sender;
  }

  function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
    address from = _ownerOf(tokenId);
    uint128 multiplier = multiplierUsed[tokenId];
    multiplierUsed[tokenId] = 0;

    if (from != address(0)) {
      HCT.removePower(from, multiplierUsed[tokenId]);
    }

    if (to != address(0)) {
      HCT.addPower(to, multiplier);
      multiplierUsed[tokenId] = multiplier;
    }

    super._update(to, tokenId, auth);
  }

  function getWrapperMultiplier() public view returns (uint128) {
    uint256 currentYear = (block.timestamp - collectionStartedUnixTime) / SECONDS_PER_YEAR;
    return uint128(Math.min(currentYear * RATE_PER_YEAR, MAX_RATE));
  }
}

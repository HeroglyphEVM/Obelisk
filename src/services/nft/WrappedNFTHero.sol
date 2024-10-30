// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { IHCT } from "src/interfaces/IHCT.sol";
import { IWrappedNFTHero } from "src/interfaces/IWrappedNFTHero.sol";
import { ObeliskNFT } from "./ObeliskNFT.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title WrappedNFTHero
 * @notice It allows users to wrap their NFT to get a WrappedNFTHero NFT.
 */
contract WrappedNFTHero is IWrappedNFTHero, ERC721, IERC721Receiver, ObeliskNFT {
  uint256 private constant MAX_BPS = 10_000;
  uint256 private constant SECONDS_PER_YEAR = 31_557_600;

  uint256 public constant SLOT_PRICE = 0.1e18;
  uint256 public constant FREE_SLOT_BPS = 2000; // 20 %

  uint256 public constant RATE_PER_YEAR = 0.43e18;
  uint256 public constant MAX_RATE = 3e18;

  IHCT public immutable HCT;
  ERC721 public immutable INPUT_COLLECTION;

  uint32 public immutable COLLECTION_STARTED_UNIX_TIME;
  bool public immutable FREE_SLOT_FOR_ODD;
  bool public immutable PREMIUM;

  uint256 public freeSlots;

  mapping(uint256 => NFTData) internal nftData;

  constructor(
    address _HCT,
    address _nftPass,
    address _inputCollection,
    address _obeliskRegistry,
    uint256 _currentSupply,
    uint32 _collectionStartedUnixTime,
    bool _premium
  ) ERC721("WrappedNFTHero", "WNH") ObeliskNFT(_obeliskRegistry, _nftPass) {
    HCT = IHCT(_HCT);
    INPUT_COLLECTION = ERC721(_inputCollection);

    freeSlots = _currentSupply * FREE_SLOT_BPS / MAX_BPS;
    FREE_SLOT_FOR_ODD = uint256(keccak256(abi.encode(_inputCollection))) % 2 == 1;
    COLLECTION_STARTED_UNIX_TIME = _collectionStartedUnixTime;
    PREMIUM = _premium;
  }

  function wrap(uint256 _inputCollectionNFTId) external payable override {
    bool isIdOdd = _inputCollectionNFTId % 2 == 1;
    bool canHaveFreeSlot = freeSlots != 0 && FREE_SLOT_FOR_ODD == isIdOdd;

    NFTData storage nftdata = nftData[_inputCollectionNFTId];
    bool didWrapBefore = nftdata.wrappedOnce;

    if (nftdata.isMinted) revert AlreadyMinted();

    if ((canHaveFreeSlot || didWrapBefore) && msg.value != 0) revert FreeSlotAvailable();
    if ((!canHaveFreeSlot && !didWrapBefore) && msg.value != SLOT_PRICE) {
      revert NoFreeSlots();
    }

    nftdata.isMinted = true;
    INPUT_COLLECTION.transferFrom(msg.sender, address(this), _inputCollectionNFTId);

    _safeMint(msg.sender, _inputCollectionNFTId);
    emit Wrapped(_inputCollectionNFTId);

    if (didWrapBefore) return;
    nftdata.wrappedOnce = true;

    if (!canHaveFreeSlot) {
      obeliskRegistry.onSlotBought{ value: msg.value }();
      emit SlotBought(msg.sender, _inputCollectionNFTId);
    } else {
      freeSlots--;
      emit FreeSlotUsed(freeSlots);
    }
  }

  function unwrap(uint256 _tokenId) external override {
    NFTData storage nftdata = nftData[_tokenId];

    if (!nftdata.isMinted) revert NotMinted();
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();

    _removeOldTickers(identityReceivers[_tokenId], _tokenId, false);

    _burn(_tokenId);
    delete names[_tokenId];

    nftdata.assignedMultiplier = 0;
    nftdata.isMinted = false;

    INPUT_COLLECTION.safeTransferFrom(address(this), msg.sender, _tokenId);

    emit Unwrapped(_tokenId);
  }

  function _renameRequirements(uint256 _tokenId) internal override {
    NFTData storage nftdata = nftData[_tokenId];

    if (!nftdata.isMinted) revert NotMinted();
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();

    if (PREMIUM && !nftdata.hasBeenRenamed) {
      nftdata.hasBeenRenamed = true;
      return;
    }

    HCT.usesForRenaming(msg.sender);
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();
    return true;
  }

  function _update(address to, uint256 tokenId, address auth)
    internal
    override
    returns (address)
  {
    NFTData storage nftdata = nftData[tokenId];

    address from = _ownerOf(tokenId);
    uint128 multiplier = nftdata.assignedMultiplier;

    if (to == address(0)) {
      HCT.removePower(from, multiplier);
      multiplier = 0;
    } else if (from == address(0)) {
      multiplier = getWrapperMultiplier();
      HCT.addPower(to, multiplier);
    } else {
      revert CannotTransferUnwrapFirst();
    }

    nftdata.assignedMultiplier = multiplier;
    return super._update(to, tokenId, auth);
  }

  function updateMultiplier(uint256 _tokenId) external {
    NFTData storage nftdata = nftData[_tokenId];
    if (_ownerOf(_tokenId) != msg.sender) revert NotNFTHolder();

    uint128 newMultiplier = getWrapperMultiplier();
    uint128 multiplier = nftdata.assignedMultiplier;

    if (newMultiplier == multiplier) revert SameMultiplier();

    HCT.removePower(msg.sender, multiplier);
    HCT.addPower(msg.sender, newMultiplier);
    nftData[_tokenId].assignedMultiplier = newMultiplier;
  }

  function getWrapperMultiplier() public view returns (uint128) {
    if (PREMIUM) return uint128(MAX_RATE);

    uint256 currentYear =
      (block.timestamp - COLLECTION_STARTED_UNIX_TIME) / SECONDS_PER_YEAR;
    return uint128(Math.min(currentYear * RATE_PER_YEAR, MAX_RATE));
  }

  function getNFTData(uint256 _tokenId) external view returns (NFTData memory) {
    return nftData[_tokenId];
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    override
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }

  //TODO: Customize metadata -- This is a place holder
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireOwned(tokenId);

    string memory name = names[tokenId];

    if (bytes(name).length == 0) name = "Unnamed";

    string memory data = string(
      abi.encodePacked(
        '{"name":"',
        name,
        '","description":"Wrapped Version of an external collection","image":"',
        "ipfs://QmdTq1vZ6cZ6mcJBfkG49FocwqTPFQ8duq6j2tL2rpzEWF",
        '"}'
      )
    );

    return string(abi.encodePacked("data:application/json;utf8,", data));
  }
}

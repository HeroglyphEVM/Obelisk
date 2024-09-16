// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TickerNFT } from "src/services/nft/TickerNFT.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IHashmask is IERC721 {
  function tokenNameByIndex(uint256 _tokenId) external view returns (string memory);
}

contract ObeliskHashmask is TickerNFT, Ownable {
  error NotActivatedByHolder();
  error NotHashmaskHolder();
  error InsufficientActivationPrice();
  error UseUpdateNameForHashmasks();
  error TransferFailed();

  uint256 public constant ACTIVATION_PRICE = 0.1 ether;
  IHashmask public immutable hashmask;
  address public treasury;

  mapping(uint256 => address) public activatedBy;

  constructor(address _hashmask, address _owner, address _obeliskRegistry, address _nftPass, address _treasury)
    TickerNFT(_obeliskRegistry, _nftPass)
    Ownable(_owner)
  {
    hashmask = IHashmask(_hashmask);
    treasury = _treasury;
  }

  function activate(uint256 _hashmaskId) external payable {
    if (msg.value != ACTIVATION_PRICE) revert InsufficientActivationPrice();
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();

    activatedBy[_hashmaskId] = msg.sender;

    (bool success,) = treasury.call{ value: msg.value }("");
    if (!success) revert TransferFailed();
  }

  function updateName(uint256 _hashmaskId) external {
    if (activatedBy[_hashmaskId] != msg.sender) revert NotActivatedByHolder();
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();

    string memory name = hashmask.tokenNameByIndex(_hashmaskId);
    names[_hashmaskId] = name;

    _removeOldTickers(_hashmaskId, true);
    _addNewTickers(_hashmaskId, name);
  }

  function _renameRequirements(uint256) internal pure override {
    revert UseUpdateNameForHashmasks();
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    bool sameName = keccak256(bytes(hashmask.tokenNameByIndex(_tokenId))) == keccak256(bytes(names[_tokenId]));
    return hashmask.ownerOf(_tokenId) == msg.sender && !sameName;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskHashmask } from "src/interfaces/IObeliskHashmask.sol";

import { TickerNFT, ILiteTicker } from "src/services/nft/TickerNFT.sol";

import { IHashmask } from "src/vendor/IHashmask.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { strings } from "src/lib/strings.sol";

contract ObeliskHashmask is IObeliskHashmask, TickerNFT, Ownable {
  using strings for string;
  using strings for strings.slice;

  string public constant TICKER_SPLIT_HASHMASK = " ";
  string public constant TICKER_HASHMASK_START_INCIDE = "O";

  IHashmask public immutable hashmask;
  address public treasury;
  uint256 public activationPrice;

  mapping(uint256 => address) public activatedBy;

  constructor(address _hashmask, address _owner, address _obeliskRegistry, address _nftPass, address _treasury)
    TickerNFT(_obeliskRegistry, _nftPass)
    Ownable(_owner)
  {
    hashmask = IHashmask(_hashmask);
    treasury = _treasury;
    activationPrice = 0.1 ether;
  }

  function activate(uint256 _hashmaskId) external payable {
    if (msg.value != activationPrice) revert InsufficientActivationPrice();
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

    identities[_hashmaskId] = msg.sender;
  }

  function _addNewTickers(uint256 _tokenId, string memory _name) internal override {
    strings.slice memory nameSlice = _name.toSlice();
    strings.slice memory delim = string(" ").toSlice();
    strings.slice[] memory potentialTickers = new strings.slice[](nameSlice.count(delim) + 1);

    address[] storage poolTargets = linkedTickers[_tokenId];

    strings.slice memory potentialTicker;
    address poolTarget;
    for (uint256 i = 0; i < potentialTickers.length; ++i) {
      potentialTicker = nameSlice.split(delim);

      if (!potentialTicker.copy().startsWith(string("O").toSlice())) {
        continue;
      }

      poolTarget = obeliskRegistry.getTickerLogic(potentialTicker.beyond(string("O").toSlice()).toString());
      poolTargets.push(poolTarget);

      ILiteTicker(poolTarget).virtualDeposit(_tokenId, msg.sender);
      emit TickerActivated(_tokenId, poolTarget);
    }

    if (poolTargets.length == 0) revert NoTickersFound();
  }

  function _updateIdentity(uint256 _tokenId, string memory _name) internal override {
    //skip
  }

  function _renameRequirements(uint256) internal pure override {
    revert UseUpdateNameForHashmasks();
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    bool sameName = keccak256(bytes(hashmask.tokenNameByIndex(_tokenId))) == keccak256(bytes(names[_tokenId]));
    return hashmask.ownerOf(_tokenId) == msg.sender && !sameName;
  }

  function setActivationPrice(uint256 _price) external onlyOwner {
    activationPrice = _price;
    emit ActivationPriceSet(_price);
  }
}

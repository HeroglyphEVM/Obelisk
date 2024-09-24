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

  constructor(address _hashmask, address _owner, address _obeliskRegistry, address _nftPass, address _treasury)
    TickerNFT(_obeliskRegistry, _nftPass)
    Ownable(_owner)
  {
    hashmask = IHashmask(_hashmask);
    treasury = _treasury;
    activationPrice = 0.1 ether;
  }

  function link(uint256 _hashmaskId) external payable {
    if (msg.value != activationPrice) revert InsufficientActivationPrice();
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();

    _removeOldTickers(identityReceivers[_hashmaskId], _hashmaskId, true);
    identityReceivers[_hashmaskId] = msg.sender;

    (bool success,) = treasury.call{ value: msg.value }("");
    if (!success) revert TransferFailed();

    //Since it's an override, the from is address(0);
    emit HashmaskLinked(_hashmaskId, address(0), msg.sender);
  }

  function transferLink(uint256 _hashmaskId, bool _triggerNameUpdate) external {
    if (identityReceivers[_hashmaskId] != msg.sender) revert NotLinkedToHolder();

    address newOwner = hashmask.ownerOf(_hashmaskId);

    _removeOldTickers(msg.sender, _hashmaskId, true);
    identityReceivers[_hashmaskId] = newOwner;

    if (_triggerNameUpdate) {
      _updateName(_hashmaskId, msg.sender, newOwner);
    }

    emit HashmaskLinked(_hashmaskId, msg.sender, newOwner);
  }

  function updateName(uint256 _hashmaskId) external {
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();
    if (identityReceivers[_hashmaskId] != msg.sender) revert NotLinkedToHolder();

    _updateName(_hashmaskId, msg.sender, msg.sender);
  }

  function _updateName(uint256 _hashmaskId, address _oldReceiver, address _newReceiver) internal {
    string memory name = hashmask.tokenNameByIndex(_hashmaskId);
    names[_hashmaskId] = name;

    _removeOldTickers(_oldReceiver, _hashmaskId, true);
    _addNewTickers(_newReceiver, _hashmaskId, name);

    emit NameUpdated(_hashmaskId, name);
  }

  function _addNewTickers(address _receiver, uint256 _tokenId, string memory _name) internal override {
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
      if (poolTarget == address(0)) continue;

      poolTargets.push(poolTarget);

      ILiteTicker(poolTarget).virtualDeposit(_tokenId, _receiver);
      emit TickerActivated(_tokenId, poolTarget);
    }

    if (poolTargets.length == 0) revert NoTickersFound();
  }

  function _updateIdentity(uint256, string memory) internal pure override returns (address) {
    revert UseLinkOrTransferLinkInstead();
  }

  function _renameRequirements(uint256) internal pure override {
    revert UseUpdateNameInstead();
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    bool sameName = keccak256(bytes(hashmask.tokenNameByIndex(_tokenId))) == keccak256(bytes(names[_tokenId]));
    address owner = hashmask.ownerOf(_tokenId);
    return owner == msg.sender && owner == identityReceivers[_tokenId] && sameName;
  }

  function setActivationPrice(uint256 _price) external onlyOwner {
    activationPrice = _price;
    emit ActivationPriceSet(_price);
  }

  function setTreasury(address _treasury) external onlyOwner {
    if (_treasury == address(0)) revert ZeroAddress();
    treasury = _treasury;

    emit TreasurySet(_treasury);
  }
}

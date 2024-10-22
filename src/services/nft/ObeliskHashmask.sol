// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskHashmask } from "src/interfaces/IObeliskHashmask.sol";

import { ObeliskNFT, ILiteTicker } from "src/services/nft/ObeliskNFT.sol";

import { IHashmask } from "src/vendor/IHashmask.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { strings } from "src/lib/strings.sol";

/**
 * @title ObeliskHashmask
 * @notice A contract that allows users to link their Hashmasks to their Obelisk identities. It uses the Hashmask's name
 * instead of HCT & Wrapped NFT Hero.
 * @dev Users need to link their Hashmask first, which might contain cost.
 */
contract ObeliskHashmask is IObeliskHashmask, ObeliskNFT, Ownable {
  using strings for string;
  using strings for strings.slice;

  string public constant TICKER_SPLIT_HASHMASK = " ";
  string public constant TICKER_HASHMASK_START_INCIDE = "O";

  IHashmask public immutable hashmask;
  address public treasury;
  uint256 public activationPrice;

  constructor(address _hashmask, address _owner, address _obeliskRegistry, address _nftPass, address _treasury)
    ObeliskNFT(_obeliskRegistry, _nftPass)
    Ownable(_owner)
  {
    hashmask = IHashmask(_hashmask);
    treasury = _treasury;
    activationPrice = 0.1 ether;
  }

  function link(uint256 _hashmaskId) external payable {
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();

    if (msg.value != activationPrice) revert InsufficientActivationPrice();

    address oldReceiver = identityReceivers[_hashmaskId];
    identityReceivers[_hashmaskId] = msg.sender;

    _updateName(_hashmaskId, oldReceiver, msg.sender);

    (bool success,) = treasury.call{ value: msg.value }("");
    if (!success) revert TransferFailed();

    //Since it's an override, the from is address(0);
    emit HashmaskLinked(_hashmaskId, address(0), msg.sender);
  }

  function transferLink(uint256 _hashmaskId) external {
    if (identityReceivers[_hashmaskId] != msg.sender) revert NotLinkedToHolder();

    address newOwner = hashmask.ownerOf(_hashmaskId);
    identityReceivers[_hashmaskId] = newOwner;
    _updateName(_hashmaskId, msg.sender, newOwner);

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
    strings.slice memory delim = TICKER_SPLIT_HASHMASK.toSlice();
    uint256 potentialTickers = nameSlice.count(delim) + 1;

    address[] storage poolTargets = linkedTickers[_tokenId];
    strings.slice memory potentialTicker;
    address poolTarget;

    for (uint256 i = 0; i < potentialTickers; ++i) {
      potentialTicker = nameSlice.split(delim);

      if (!potentialTicker.copy().startsWith(TICKER_HASHMASK_START_INCIDE.toSlice())) {
        continue;
      }

      poolTarget =
        obeliskRegistry.getTickerLogic(potentialTicker.beyond(TICKER_HASHMASK_START_INCIDE.toSlice()).toString());
      if (poolTarget == address(0)) continue;

      poolTargets.push(poolTarget);

      ILiteTicker(poolTarget).virtualDeposit(_tokenId, _receiver);
      emit TickerActivated(_tokenId, poolTarget);
    }
  }

  function _updateIdentity(uint256, string memory) internal pure override returns (address) {
    revert UseLinkOrTransferLinkInstead();
  }

  function _renameRequirements(uint256) internal pure override {
    revert UseUpdateNameInstead();
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    address owner = hashmask.ownerOf(_tokenId);
    if (owner != msg.sender) revert NotHashmaskHolder();

    bool sameName = keccak256(bytes(hashmask.tokenNameByIndex(_tokenId))) == keccak256(bytes(names[_tokenId]));
    return owner == identityReceivers[_tokenId] && sameName;
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

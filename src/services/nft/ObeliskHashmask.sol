// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskHashmask } from "src/interfaces/IObeliskHashmask.sol";

import { ObeliskNFT, ILiteTicker } from "src/services/nft/ObeliskNFT.sol";

import { IHashmask } from "src/vendor/IHashmask.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { strings } from "src/lib/strings.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ObeliskHashmask
 * @notice A contract that allows users to link their Hashmasks to their Obelisk
 * identities. It uses the Hashmask's name
 * instead of HCT & Wrapped NFT Hero.
 * @custom:export abi
 * @dev Users need to link their Hashmask first, which might contain cost.
 * @dev IMPORTANT:
 *
 * Due of the fact we are not holding their NFT, claiming has a different behaviour that
 * might cause the lost of reward for a user if badly interacted with.
 *
 * User WON’T be able to claim if:
 * They are no longer the owner of the hashmask
 * Their hashmask’s name is not the same as the one saved on Obelisk
 *
 * User WILL LOSE their reward if:
 * They transfer their hashmask then a link (or transfer-link) happens
 * They rename their Hashmask then calls updateName
 *
 * RECOMMENDATION
 * User NEEDS to CLAIM before TRANSFERRING or RENAMING their hashmask.
 */
contract ObeliskHashmask is IObeliskHashmask, ObeliskNFT, Ownable {
  using strings for string;
  using strings for strings.slice;

  string public constant TICKER_SPLIT_HASHMASK = " ";
  string public constant TICKER_HASHMASK_START_INCIDE = "O";

  // To make sure nobody can steal an hashmask identity with an nft pass, the prefix goes
  // beyond the bytes limit of an NFT Pass.
  string public constant HASHMASK_IDENTITY_PREFIX = "IDENTITY_HASH_MASK_OBELISK_";

  IHashmask public immutable hashmask;
  address public treasury;
  uint256 public activationPrice;

  mapping(uint256 => address) public linkers;

  constructor(
    address _hashmask,
    address _owner,
    address _obeliskRegistry,
    address _treasury
  ) ObeliskNFT(_obeliskRegistry, address(0)) Ownable(_owner) {
    hashmask = IHashmask(_hashmask);
    treasury = _treasury;
    activationPrice = 0.1 ether;
  }

  /// @inheritdoc IObeliskHashmask
  function link(uint256 _hashmaskId) external payable override {
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();
    if (msg.value != activationPrice) revert InsufficientActivationPrice();

    string memory identityName = nftPassAttached[_hashmaskId];

    if (bytes(identityName).length == 0) {
      identityName =
        string.concat(HASHMASK_IDENTITY_PREFIX, Strings.toString(_hashmaskId));

      nftPassAttached[_hashmaskId] = identityName;
    }

    address oldLinker = linkers[_hashmaskId];

    linkers[_hashmaskId] = msg.sender;

    _updateName(keccak256(abi.encode(identityName)), _hashmaskId, oldLinker, msg.sender);

    (bool success,) = treasury.call{ value: msg.value }("");
    if (!success) revert TransferFailed();

    //Since it's an override, the from is address(0);
    emit HashmaskLinked(_hashmaskId, address(0), msg.sender);
  }

  /// @inheritdoc IObeliskHashmask
  function transferLink(uint256 _hashmaskId) external override {
    if (linkers[_hashmaskId] != msg.sender) revert NotLinkedToHolder();

    address newOwner = hashmask.ownerOf(_hashmaskId);
    linkers[_hashmaskId] = newOwner;

    _updateName(
      keccak256(abi.encode(nftPassAttached[_hashmaskId])),
      _hashmaskId,
      msg.sender,
      newOwner
    );

    emit HashmaskLinked(_hashmaskId, msg.sender, newOwner);
  }

  /// @inheritdoc IObeliskHashmask
  function updateName(uint256 _hashmaskId) external override {
    if (hashmask.ownerOf(_hashmaskId) != msg.sender) revert NotHashmaskHolder();
    if (linkers[_hashmaskId] != msg.sender) revert NotLinkedToHolder();

    _updateName(
      keccak256(abi.encode(nftPassAttached[_hashmaskId])),
      _hashmaskId,
      msg.sender,
      msg.sender
    );
  }

  function _updateName(
    bytes32 _identity,
    uint256 _hashmaskId,
    address _oldReceiver,
    address _newReceiver
  ) internal {
    _removeOldTickers(_identity, _oldReceiver, _hashmaskId, true);

    string memory name = hashmask.tokenNameByIndex(_hashmaskId);
    names[_hashmaskId] = name;

    _addNewTickers(_identity, _newReceiver, _hashmaskId, name);

    emit NameUpdated(_hashmaskId, name);
  }

  function _addNewTickers(
    bytes32 _identity,
    address _receiver,
    uint256 _tokenId,
    string memory _name
  ) internal override {
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

      poolTarget = obeliskRegistry.getTickerLogic(
        potentialTicker.beyond(TICKER_HASHMASK_START_INCIDE.toSlice()).toString()
      );
      if (poolTarget == address(0)) continue;

      poolTargets.push(poolTarget);

      ILiteTicker(poolTarget).virtualDeposit(_identity, _tokenId, _receiver);
      emit TickerActivated(_tokenId, poolTarget);
    }
  }

  function _getIdentityInformation(uint256 _tokenId)
    internal
    view
    override
    returns (bytes32, address)
  {
    return (keccak256(abi.encode(nftPassAttached[_tokenId])), linkers[_tokenId]);
  }

  function _claimRequirements(uint256 _tokenId) internal view override returns (bool) {
    address owner = hashmask.ownerOf(_tokenId);
    if (owner != msg.sender) revert NotHashmaskHolder();

    bool sameName = keccak256(bytes(hashmask.tokenNameByIndex(_tokenId)))
      == keccak256(bytes(names[_tokenId]));
    return owner == linkers[_tokenId] && sameName;
  }

  /**
   * @notice Sets the activation price for linking a Hashmask to an Obelisk.
   * @param _price The new activation price.
   */
  function setActivationPrice(uint256 _price) external onlyOwner {
    activationPrice = _price;
    emit ActivationPriceSet(_price);
  }

  /**
   * @notice Sets the treasury address.
   * @param _treasury The new treasury address.
   */
  function setTreasury(address _treasury) external onlyOwner {
    if (_treasury == address(0)) revert ZeroAddress();
    treasury = _treasury;

    emit TreasurySet(_treasury);
  }
}

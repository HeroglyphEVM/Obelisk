// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskNFT } from "src/interfaces/IObeliskNFT.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";

import { strings } from "src/lib/strings.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ObeliskNFT
 * @notice Base contract for Obelisk NFTs. It contains the staking logic via name.
 */
abstract contract ObeliskNFT is IObeliskNFT, ReentrancyGuard {
  using strings for string;
  using strings for strings.slice;

  string public constant TICKER_START_INDICE = "#";
  string public constant TICKER_SPLIT_STRING = ",";
  string public constant TICKER_START_IDENTITY = "@";
  uint32 public constant MAX_NAME_BYTES_LENGTH = 29;
  IObeliskRegistry public immutable obeliskRegistry;
  INFTPass public immutable NFT_PASS;

  mapping(uint256 => string) public nftPassAttached;
  mapping(uint256 => address[]) internal linkedTickers;
  mapping(uint256 => string) public names;

  constructor(address _obeliskRegistry, address _nftPass) {
    obeliskRegistry = IObeliskRegistry(_obeliskRegistry);
    NFT_PASS = INFTPass(_nftPass);
  }

  function _removeOldTickers(
    bytes32 _identity,
    address _receiver,
    uint256 _tokenId,
    bool _ignoreRewards
  ) internal nonReentrant {
    address[] memory activePools = linkedTickers[_tokenId];
    delete linkedTickers[_tokenId];

    address currentPool;

    for (uint256 i = 0; i < activePools.length; ++i) {
      currentPool = activePools[i];

      ILiteTicker(currentPool).virtualWithdraw(
        _identity, _tokenId, _receiver, _ignoreRewards
      );

      emit TickerDeactivated(_tokenId, currentPool);
    }
  }

  function _addNewTickers(
    bytes32 _identity,
    address _receiver,
    uint256 _tokenId,
    string memory _name
  ) internal virtual nonReentrant {
    strings.slice memory nameSlice = _name.toSlice();
    strings.slice memory needle = TICKER_START_INDICE.toSlice();
    strings.slice memory substring =
      nameSlice.find(needle).beyond(needle).split(string(" ").toSlice());
    strings.slice memory delim = TICKER_SPLIT_STRING.toSlice();

    address[] memory poolTargets = new address[](substring.count(delim) + 1);

    address poolTarget;
    string memory tickerName;
    for (uint256 i = 0; i < poolTargets.length; ++i) {
      tickerName = substring.split(delim).toString();
      if (bytes(tickerName).length == 0) continue;

      poolTarget = obeliskRegistry.getTickerLogic(tickerName);
      if (poolTarget == address(0)) continue;

      poolTargets[i] = poolTarget;

      ILiteTicker(poolTarget).virtualDeposit(_identity, _tokenId, _receiver);
      emit TickerActivated(_tokenId, poolTarget);
    }

    linkedTickers[_tokenId] = poolTargets;
  }

  /// @inheritdoc IObeliskNFT
  function claim(uint256 _tokenId) external nonReentrant {
    address[] memory activePools = linkedTickers[_tokenId];
    assert(_claimRequirements(_tokenId));

    (bytes32 identity, address identityReceiver) = _getIdentityInformation(_tokenId);

    for (uint256 i = 0; i < activePools.length; i++) {
      ILiteTicker(activePools[i]).claim(identity, _tokenId, identityReceiver, false);
      emit TickerClaimed(_tokenId, activePools[i]);
    }
  }

  function _claimRequirements(uint256 _tokenId) internal view virtual returns (bool);

  function _getIdentityInformation(uint256 _tokenId)
    internal
    view
    virtual
    returns (bytes32, address);

  function getLinkedTickers(uint256 _tokenId) external view returns (address[] memory) {
    return linkedTickers[_tokenId];
  }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IShareable } from "./IShareable.sol";
import { ShareableMath } from "./ShareableMath.sol";

abstract contract Shareable is IShareable {
  uint256 public share; // crops per gem    [ray]
  uint256 public stock; // crop balance     [wad]
  uint256 public totalWeight; // [wad]

  //User => Value
  mapping(address => uint256) internal crops; // [wad]
  mapping(address => uint256) internal userShares; // [wad]

  function _crop() internal virtual returns (uint256);

  function _addShare(address _wallet, uint256 _value) internal virtual {
    if (_value > 0) {
      uint256 wad = ShareableMath.wdiv(_value, netAssetsPerShareWAD());
      require(int256(wad) > 0);

      totalWeight += wad;
      userShares[_wallet] += wad;
    }
    crops[_wallet] = ShareableMath.rmulup(userShares[_wallet], share);
    emit ShareUpdated(_wallet, _value);
  }

  function _partialExitShare(address _wallet, uint256 _newShare) internal virtual {
    _deleteShare(_wallet);

    if (_newShare > 0) {
      _addShare(_wallet, _newShare);
    }
  }

  function _exitShare(address _wallet) internal virtual {
    _deleteShare(_wallet);
    emit ShareUpdated(_wallet, 0);
  }

  function _deleteShare(address _wallet) private {
    uint256 value = userShares[_wallet];

    if (value > 0) {
      uint256 wad = ShareableMath.wdivup(value, netAssetsPerShareWAD());

      require(int256(wad) > 0);

      totalWeight -= wad;
      userShares[_wallet] -= wad;
    }

    crops[_wallet] = ShareableMath.rmulup(userShares[_wallet], share);
  }

  function netAssetsPerShareWAD() public view override returns (uint256) {
    return (totalWeight == 0) ? ShareableMath.WAD : ShareableMath.wdiv(totalWeight, totalWeight);
  }

  function getCropsOf(address _target) external view override returns (uint256) {
    return crops[_target];
  }

  function getShareOf(address owner) public view override returns (uint256) {
    return userShares[owner];
  }
}

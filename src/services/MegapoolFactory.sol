// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Megapool } from "src/services/tickers/Megapool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MegapoolFactory
 * @author Heroglyph
 * @notice Factory for creating Megapools
 * @custom:export abi
 */
contract MegapoolFactory is Ownable {
  string public constant PREFIX = "MEGAPOOL_";
  uint256 public hctCreationgCost;

  address public immutable OBELISK_REGISTRY;
  address public immutable APX_ETH;
  address public immutable INTEREST_MANAGER;
  IHCT public immutable HCT;

  uint32 private megapoolCount;
  mapping(uint32 => address) public megapools;

  event MegapoolCreated(
    address indexed pool,
    address indexed deployer,
    string name,
    address[] allowedWrappedCollections
  );
  event HctCreationCostUpdated(uint256 cost);

  constructor(
    address _owner,
    address _obeliskRegistry,
    address _hct,
    address _apxETH,
    address _interestManager
  ) Ownable(_owner) {
    OBELISK_REGISTRY = _obeliskRegistry;
    HCT = IHCT(_hct);
    APX_ETH = _apxETH;
    INTEREST_MANAGER = _interestManager;

    hctCreationgCost = 1000e18;
  }

  function createMegapool(address[] memory _allowedWrappedCollections)
    external
    returns (string memory name_, address pool_)
  {
    address owner = owner();
    name_ = PREFIX;
    megapoolCount++;

    if (megapoolCount < 10) {
      name_ = string.concat(name_, "00");
    } else if (megapoolCount < 100) {
      name_ = string.concat(name_, "0");
    }

    name_ = string.concat(name_, Strings.toString(megapoolCount));

    if (msg.sender != owner) {
      HCT.burn(msg.sender, hctCreationgCost);
    }

    pool_ = address(
      new Megapool(
        owner, OBELISK_REGISTRY, APX_ETH, INTEREST_MANAGER, _allowedWrappedCollections
      )
    );

    IObeliskRegistry(OBELISK_REGISTRY).setTickerLogic(name_, pool_, false);
    megapools[megapoolCount] = pool_;
    emit MegapoolCreated(pool_, msg.sender, name_, _allowedWrappedCollections);

    return (name_, pool_);
  }

  function updateHctCreationCost(uint256 _cost) external onlyOwner {
    hctCreationgCost = _cost;
    emit HctCreationCostUpdated(_cost);
  }
}

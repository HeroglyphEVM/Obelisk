// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Megapool } from "src/services/tickers/Megapool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

/**
 * @title MegapoolFactory
 * @author Heroglyph
 * @notice Factory for creating Megapools
 * @custom:export abi
 */
contract MegapoolFactory is Ownable {
  error NameTooShort();

  string public constant FIRST_MEGAPOOL_NAME = "Senusret";
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

  function createMegapool(
    string calldata _megapoolName,
    address[] memory _allowedWrappedCollections
  ) external returns (address pool_) {
    address owner = owner();

    if (bytes(_megapoolName).length < bytes(FIRST_MEGAPOOL_NAME).length) {
      revert NameTooShort();
    }

    if (msg.sender != owner) {
      HCT.burn(msg.sender, hctCreationgCost);
    }

    pool_ = address(
      new Megapool(
        owner, OBELISK_REGISTRY, APX_ETH, INTEREST_MANAGER, _allowedWrappedCollections
      )
    );

    IObeliskRegistry(OBELISK_REGISTRY).setTickerLogic(_megapoolName, pool_, false);
    megapools[megapoolCount] = pool_;
    megapoolCount++;
    emit MegapoolCreated(pool_, msg.sender, _megapoolName, _allowedWrappedCollections);

    return pool_;
  }

  function updateHctCreationCost(uint256 _cost) external onlyOwner {
    hctCreationgCost = _cost;
    emit HctCreationCostUpdated(_cost);
  }
}

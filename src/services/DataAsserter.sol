// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IDataAsserter } from "src/interfaces/IDataAsserter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { AncillaryData as ClaimData } from "src/vendor/UMA/AncillaryData.sol";
import { OptimisticOracleV3Interface } from
  "src/vendor/UMA/OptimisticOracleV3Interface.sol";

import {
  SafeERC20, IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DataAsserter is Ownable, IDataAsserter {
  using SafeERC20 for IERC20;

  uint64 public constant assertionLiveness = 259_200; // 3 days

  IWETH public immutable defaultCurrency;
  OptimisticOracleV3Interface public immutable oo;
  IObeliskRegistry public immutable obeliskRegistry;
  bytes32 public immutable defaultIdentifier;

  uint256 public assertingPrice;
  address public treasury;

  mapping(bytes32 dataId => CollectionAssertionData) public collectionAssertionsData;
  mapping(bytes32 assertionId => AssertionData) public assertionsData;

  constructor(
    address _owner,
    address _treasury,
    address _defaultCurrency,
    address _optimisticOracleV3,
    address _obeliskRegistry
  ) Ownable(_owner) {
    treasury = _treasury;
    defaultCurrency = IWETH(_defaultCurrency);
    oo = OptimisticOracleV3Interface(_optimisticOracleV3);
    defaultIdentifier = oo.defaultIdentifier();
    obeliskRegistry = IObeliskRegistry(_obeliskRegistry);
    assertingPrice = 0.5 ether;
    defaultCurrency.approve(address(oo), type(uint256).max);
  }

  function assertDataFor(
    address _collection,
    uint32 _deploymentTimestamp,
    uint128 _currentSupply
  ) public returns (bytes32 assertionId) {
    if (obeliskRegistry.getCollection(_collection).allowed) {
      revert CollectionIsAlreadyAllowed();
    }

    CollectionAssertionData memory collectionAssertionData =
      CollectionAssertionData(_collection, _deploymentTimestamp, _currentSupply);
    bytes32 dataId = bytes32(abi.encode(_collection, msg.sender, block.timestamp));

    uint256 bond = oo.getMinimumBond(address(defaultCurrency));
    defaultCurrency.transferFrom(msg.sender, address(this), bond + assertingPrice);

    assertionId = oo.assertTruth(
      abi.encodePacked(
        "Requesting new collection to the Obelisk: 0x",
        ClaimData.toUtf8BytesAddress(_collection),
        " Contract Deployement Timestamp: ",
        ClaimData.toUtf8BytesUint(_deploymentTimestamp),
        " Current Supply at the time of the assertion: ",
        ClaimData.toUtf8BytesUint(_currentSupply),
        " requested by: 0x",
        ClaimData.toUtf8BytesAddress(msg.sender),
        " dataId: 0x",
        ClaimData.toUtf8Bytes(dataId),
        " at timestamp: ",
        ClaimData.toUtf8BytesUint(block.timestamp),
        " in the DataAsserter contract at 0x",
        ClaimData.toUtf8BytesAddress(address(this)),
        " is valid."
      ),
      msg.sender,
      address(this),
      address(0), // No sovereign security.
      assertionLiveness,
      defaultCurrency,
      bond,
      defaultIdentifier,
      bytes32(0) // No domain.
    );

    assertionsData[assertionId] =
      AssertionData(dataId, assertingPrice, msg.sender, false, false, false);
    collectionAssertionsData[dataId] = collectionAssertionData;

    emit DataAsserted(dataId, assertionId, msg.sender, collectionAssertionData);
  }

  // OptimisticOracleV3 resolve callback.
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully)
    external
  {
    if (msg.sender != address(oo)) revert NotOptimisticOracle();

    AssertionData storage assertionData = assertionsData[assertionId];
    CollectionAssertionData memory collectionAssertionData =
      collectionAssertionsData[assertionData.dataId];

    assertionData.hasBeenResolved = true;
    assertionData.hasBeenDisputed = !assertedTruthfully;

    defaultCurrency.transfer(
      assertedTruthfully ? assertionData.asserter : treasury,
      assertionData.securityDeposit
    );

    if (
      assertedTruthfully
        && !obeliskRegistry.getCollection(collectionAssertionData.collection).allowed
    ) {
      try obeliskRegistry.allowNewCollection(
        collectionAssertionData.collection,
        collectionAssertionData.currentSupply,
        collectionAssertionData.deploymentTimestamp,
        false
      ) { } catch {
        assertionData.failedToCallObeliskRegistry = true;
      }
    }

    emit DataAssertionResolved(
      assertionData.dataId,
      assertionId,
      assertedTruthfully,
      collectionAssertionsData[assertionData.dataId]
    );
  }

  function retryCallingObeliskRegistry(bytes32 assertionId) external {
    AssertionData storage assertionData = assertionsData[assertionId];
    CollectionAssertionData memory collectionAssertionData =
      collectionAssertionsData[assertionData.dataId];

    if (!assertionData.hasBeenResolved) revert AssertionNotResolved();
    if (assertionData.hasBeenDisputed) revert DisputedAssertion();

    if (!assertionData.failedToCallObeliskRegistry) revert NothingToRetry();

    obeliskRegistry.allowNewCollection(
      collectionAssertionData.collection,
      collectionAssertionData.currentSupply,
      collectionAssertionData.deploymentTimestamp,
      false
    );

    assertionData.failedToCallObeliskRegistry = false;
  }

  function updateAssertingPrice(uint256 price) external onlyOwner {
    assertingPrice = price;
    emit AssertingPriceUpdated(price);
  }

  function updateTreasury(address _treasury) external onlyOwner {
    treasury = _treasury;
    emit TreasuryUpdated(_treasury);
  }

  function getAssertionCost() external view returns (uint256) {
    return assertingPrice + oo.getMinimumBond(address(defaultCurrency));
  }

  function getData(bytes32 assertionId)
    external
    view
    returns (
      AssertionData memory assertionData_,
      CollectionAssertionData memory collectionAssertionData_
    )
  {
    assertionData_ = assertionsData[assertionId];
    collectionAssertionData_ = collectionAssertionsData[assertionData_.dataId];

    return (assertionData_, collectionAssertionData_);
  }

  // If assertion is disputed, do nothing and wait for resolution.
  // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't
  // revert when it tries to call it.
  function assertionDisputedCallback(bytes32 assertionId) public { }
}

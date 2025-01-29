// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IDataAsserter } from "src/interfaces/IDataAsserter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { AncillaryData as ClaimData } from "src/vendor/UMA/AncillaryData.sol";
import { OptimisticOracleV3Interface } from
  "src/vendor/UMA/OptimisticOracleV3Interface.sol";

/**
 * @title DataAsserter (UMA Powered)
 * @notice Add new Collection into Obelisks
 *
 * @custom:export abi
 */
contract DataAsserter is Ownable, IDataAsserter {
  uint64 public assertionLiveness;

  IWETH public immutable defaultCurrency;
  OptimisticOracleV3Interface public immutable oo;
  IObeliskRegistry public immutable obeliskRegistry;
  bytes32 public immutable defaultIdentifier;

  uint256 public securityDeposit;
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
    securityDeposit = 0.5 ether;
    defaultCurrency.approve(address(oo), type(uint256).max);

    assertionLiveness = 3 days;
  }

  function assertDataFor(
    address _collection,
    uint32 _deploymentTimestamp,
    uint128 _currentSupply
  ) external override returns (bytes32 assertionId) {
    if (obeliskRegistry.getCollection(_collection).allowed) {
      revert CollectionIsAlreadyAllowed();
    }

    CollectionAssertionData memory collectionAssertionData =
      CollectionAssertionData(_collection, _deploymentTimestamp, _currentSupply);
    bytes32 dataId = bytes32(abi.encode(_collection, msg.sender, block.timestamp));

    uint256 bond = oo.getMinimumBond(address(defaultCurrency));
    defaultCurrency.transferFrom(msg.sender, address(this), bond + securityDeposit);

    assertionId = oo.assertTruth(
      abi.encodePacked(
        "NFT contract: 0x",
        ClaimData.toUtf8BytesAddress(_collection),
        " on Ethereum mainnet was deployed at timestamp: ",
        ClaimData.toUtf8BytesUint(_deploymentTimestamp),
        " and has a total supply of: ",
        ClaimData.toUtf8BytesUint(_currentSupply),
        " at the time of assertion."
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
      AssertionData(dataId, securityDeposit, msg.sender, false, false, false);
    collectionAssertionsData[dataId] = collectionAssertionData;

    emit DataAsserted(dataId, assertionId, msg.sender, collectionAssertionData);
  }

  // OptimisticOracleV3 resolve callback.
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully)
    external
    override
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

  function updateSecurityDeposit(uint256 price) external onlyOwner {
    securityDeposit = price;
    emit SecurityDepositUpdated(price);
  }

  function updateTreasury(address _treasury) external onlyOwner {
    treasury = _treasury;
    emit TreasuryUpdated(_treasury);
  }

  function updateAssertionLiveness(uint64 _assertionLiveness) external onlyOwner {
    if (_assertionLiveness < 1 days) revert AssertionLivenessTooShort();

    assertionLiveness = _assertionLiveness;
    emit AssertionLivenessUpdated(_assertionLiveness);
  }

  function getAssertionCost() external view returns (uint256) {
    return securityDeposit + oo.getMinimumBond(address(defaultCurrency));
  }

  function getAssertionData(bytes32 assertionId)
    external
    view
    returns (AssertionData memory)
  {
    return assertionsData[assertionId];
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IDataAsserter {
  struct CollectionAssertionData {
    address collection;
    uint32 deploymentTimestamp;
    uint128 currentSupply;
  }

  struct AssertionData {
    bytes32 dataId;
    uint256 securityDeposit;
    address asserter;
    bool hasBeenResolved;
    bool hasBeenDisputed;
    bool failedToCallObeliskRegistry;
  }

  error CollectionIsAlreadyAllowed();
  error DisputedAssertion();
  error NothingToRetry();
  error AssertionNotResolved();
  error NotOptimisticOracle();

  event DataAsserted(
    bytes32 indexed dataId,
    bytes32 indexed assertionId,
    address indexed asserter,
    CollectionAssertionData collectionAssertionData
  );

  event DataAssertionResolved(
    bytes32 indexed dataId,
    bytes32 indexed assertionId,
    bool assertedTruthfully,
    CollectionAssertionData collectionAssertionData
  );

  event TreasuryUpdated(address indexed treasury);
  event AssertingPriceUpdated(uint256 price);

  function getData(bytes32 assertionId)
    external
    view
    returns (AssertionData memory, CollectionAssertionData memory);
}

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
  error AssertionLivenessTooShort();

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
  event SecurityDepositUpdated(uint256 price);
  event AssertionLivenessUpdated(uint64 assertionLiveness);

  /**
   * @notice Assert data for a collection.
   * @param _collection The collection to assert data for.
   * @param _deploymentTimestamp The deployment timestamp of the collection.
   * @param _currentSupply The current supply of the collection.
   * @return assertionId The assertion ID.
   * @dev This function requires the caller to deposit a security deposit. To punish the
   * user if they are trying to exploit the UMA with bad data.
   */
  function assertDataFor(
    address _collection,
    uint32 _deploymentTimestamp,
    uint128 _currentSupply
  ) external returns (bytes32 assertionId);

  /**
   * @notice Callback function for the OptimisticOracleV3.
   * @param assertionId The assertion ID.
   * @param assertedTruthfully Whether the assertion was asserted truthfully.
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully)
    external;

  /**
   * @notice Retry calling the ObeliskRegistry to get the data.
   * @param assertionId The assertion ID.
   */
  function retryCallingObeliskRegistry(bytes32 assertionId) external;

  /**
   * @notice Get the assertion data and collection assertion data.
   * @param assertionId The assertion ID.
   * @return assertionData The assertion data.
   * @return collectionAssertionData The collection assertion data.
   */
  function getData(bytes32 assertionId)
    external
    view
    returns (AssertionData memory, CollectionAssertionData memory);
}

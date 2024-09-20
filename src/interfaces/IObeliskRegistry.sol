// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IObeliskRegistry {
  error ZeroValue();
  error TooManyEth();
  error GoalReached();
  error AmountExceedsDeposit();
  error TransferFailed();
  error FailedDeployment();
  error TickerAlreadyExists();
  error NotSupporterDepositor();
  error AlreadyRemoved();
  error SupportNotFinished();
  error NothingToClaim();
  error NotWrappedNFT();
  error CollectionNotAllowed();
  error NotAuthorized();
  error OnlyOneValue();
  error AmountTooLow();
  error ZeroAddress();
  error CollectionAlreadyAllowed();

  event WrappedNFTCreated(address indexed collection, address indexed wrappedNFT);
  event TickerLogicSet(string indexed ticker, address pool);
  event NewGenesisTickerCreated(string indexed ticker, address pool);
  event Supported(uint32 indexed supportId, address indexed supporter, uint256 amount);
  event SupportRetrieved(uint32 indexed supportId, address indexed supporter, uint256 amount);
  event CollectionContributed(address indexed collection, address indexed contributor, uint256 amount);
  event CollectionContributionWithdrawn(address indexed collection, address indexed contributor, uint256 amount);
  event Claimed(address indexed collection, address indexed contributor, uint256 amount);
  event SlotBought(address indexed wrappedNFT, uint256 toCollection, uint256 toTreasury);
  event CollectionAllowed(
    address indexed collection, uint256 totalSupply, uint32 collectionStartedUnixTime, bool premium
  );
  event TreasurySet(address indexed treasury);
  event MaxRewardPerCollectionSet(uint256 maxRewardPerCollection);
  event DataAsserterSet(address indexed dataAsserter);

  struct Collection {
    address wrappedVersion;
    uint256 totalSupply;
    uint256 contributionBalance;
    uint32 collectionStartedUnixTime;
    bool allowed;
    bool premium;
  }

  struct Supporter {
    address depositor;
    address token;
    uint128 amount;
    uint32 lockUntil;
    bool removed;
  }

  struct CollectionRewards {
    uint128 totalRewards;
    uint128 claimedRewards;
  }

  struct ContributionInfo {
    uint128 deposit;
    uint128 claimed;
  }

  function isWrappedNFT(address _collection) external view returns (bool);

  /**
   * @notice Contribute to collection
   * @param _collection NFT Collection address
   * @dev Warning: once the collection goal is reached, it cannot be removed
   */
  function addToCollection(address _collection) external payable;

  /**
   * @notice Remove from collection
   * @param _collection Collection address
   * @dev Warning: once the collection goal is reached, it cannot be removed
   */
  function removeFromCollection(address _collection, uint256 _amount) external;

  /**
   * @notice Support the yield pool
   * @param _amount The amount to support with
   * @dev The amount is locked for 30 days
   * @dev if msg.value is 0, the amount is expected to be sent in DAI
   */
  function supportYieldPool(uint256 _amount) external payable;

  /**
   * @notice Retrieve support to yield pool
   * @param _id Support ID
   */
  function retrieveSupportToYieldPool(uint32 _id) external;

  /**
   * @notice When a slot is bought from the wrapped NFT
   */
  function onSlotBought() external payable;

  /**
   * @notice Get ticker logic
   * @param _ticker Ticker
   */
  function getTickerLogic(string memory _ticker) external view returns (address);

  /**
   * @notice Get supporter
   * @param _id Support ID
   */
  function getSupporter(uint32 _id) external view returns (Supporter memory);

  /**
   * @notice Get user contribution
   * @param _user User address
   * @param _collection Collection address
   */
  function getUserContribution(address _user, address _collection) external view returns (ContributionInfo memory);

  /**
   * @notice Get collection rewards
   * @param _collection Collection address
   */
  function getCollectionRewards(address _collection) external view returns (CollectionRewards memory);

  /**
   * @notice Get collection
   * @param _collection Collection address
   */
  function getCollection(address _collection) external view returns (Collection memory);
}

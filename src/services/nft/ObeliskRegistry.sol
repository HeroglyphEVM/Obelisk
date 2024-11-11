// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { WrappedNFTHero } from "./WrappedNFTHero.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { HCT } from "src/services/HCT.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ObeliskRegistry
 * @notice It can creates / allow / modify Tickers, have supporting option to boost yield
 * for 30 days and handle
 * Collection access & unlocking.
 * @custom:export abi
 */
contract ObeliskRegistry is IObeliskRegistry, Ownable, ReentrancyGuard {
  uint256 public constant MINIMUM_SENDING_ETH = 0.005 ether;
  uint256 public constant MINIMUM_ETH_SUPPORT_AMOUNT = 1e18;
  uint256 public constant MINIMUM_DAI_SUPPORT_AMOUNT = 1000e18;
  uint128 public constant REQUIRED_ETH_TO_ENABLE_COLLECTION = 100e18;
  uint32 public constant SUPPORT_LOCK_DURATION = 30 days;
  uint32 public constant COLLECTION_REWARD_PERCENT = 4000;
  uint32 public constant BPS = 10_000;

  mapping(address => Collection) internal supportedCollections;
  mapping(address wrappedCollection => CollectionRewards) internal
    wrappedCollectionRewards;
  mapping(address wrappedNFT => bool isValid) public override isWrappedNFT;

  mapping(string ticker => address logic) private tickersLogic;
  mapping(address user => mapping(address collection => ContributionInfo)) internal
    userSupportedCollections;
  mapping(uint32 => Supporter) private supporters;

  address public immutable HCT_ADDRESS;
  address public immutable NFT_PASS;
  IERC20 public immutable DAI;
  IDripVault public immutable DRIP_VAULT_ETH;
  IDripVault public immutable DRIP_VAULT_DAI;

  address public treasury;
  address public dataAsserter;
  address public megapoolFactory;
  uint32 public supportId;
  uint256 public maxRewardPerCollection;

  string public override wrappedCollectionImageIPFS;

  constructor(
    address _owner,
    address _treasury,
    address _nftPass,
    address _dripVaultETH,
    address _dripVaultDAI,
    address _dai
  ) Ownable(_owner) {
    maxRewardPerCollection = 250e18;

    treasury = _treasury;
    HCT_ADDRESS = address(new HCT(_owner, _treasury));
    DRIP_VAULT_ETH = IDripVault(_dripVaultETH);
    DRIP_VAULT_DAI = IDripVault(_dripVaultDAI);
    NFT_PASS = _nftPass;
    DAI = IERC20(_dai);

    wrappedCollectionImageIPFS = "ipfs://QmVLK98G9xCXKA3r1mAJ2ytJ7XVCfWBy4DfnHkXF2VWJ53";
  }

  /// @inheritdoc IObeliskRegistry
  function addToCollection(address _collection) external payable override nonReentrant {
    Collection storage collection = supportedCollections[_collection];
    uint256 sendingAmount = DRIP_VAULT_ETH.previewDeposit(msg.value);
    uint256 contributionBalance = collection.contributionBalance;
    uint256 surplus;

    if (sendingAmount < MINIMUM_SENDING_ETH) revert AmountTooLow();

    if (contributionBalance >= REQUIRED_ETH_TO_ENABLE_COLLECTION) {
      revert TooManyEth();
    }

    contributionBalance += sendingAmount;

    if (contributionBalance > REQUIRED_ETH_TO_ENABLE_COLLECTION) {
      surplus = contributionBalance - REQUIRED_ETH_TO_ENABLE_COLLECTION;
    }

    if (!collection.allowed) revert CollectionNotAllowed();

    sendingAmount = DRIP_VAULT_ETH.deposit{ value: sendingAmount }(0);
    userSupportedCollections[msg.sender][_collection].deposit += uint128(sendingAmount);

    //Ignore the potential fee from drip_vault.
    collection.contributionBalance =
      Math.min(contributionBalance, REQUIRED_ETH_TO_ENABLE_COLLECTION);

    emit CollectionContributed(_collection, msg.sender, sendingAmount);
    if (contributionBalance < REQUIRED_ETH_TO_ENABLE_COLLECTION) return;

    _createWrappedNFT(
      _collection,
      collection.totalSupply,
      collection.collectionStartedUnixTime,
      collection.premium
    );

    if (surplus != 0) {
      (bool success,) = msg.sender.call{ value: surplus }("");
      if (!success) revert TransferFailed();
    }
  }

  function forceActiveCollection(address _collection) external onlyOwner {
    Collection storage collection = supportedCollections[_collection];
    if (!collection.allowed) revert CollectionNotAllowed();

    uint256 currentBalance = collection.contributionBalance;
    if (currentBalance >= REQUIRED_ETH_TO_ENABLE_COLLECTION) {
      revert TooManyEth();
    }

    uint256 missingEth = REQUIRED_ETH_TO_ENABLE_COLLECTION - currentBalance;

    collection.contributionBalance += missingEth;
    userSupportedCollections[treasury][_collection].deposit += uint128(missingEth);

    _createWrappedNFT(
      _collection,
      collection.totalSupply,
      collection.collectionStartedUnixTime,
      collection.premium
    );
  }

  function _createWrappedNFT(
    address _collection,
    uint256 _totalSupply,
    uint32 _unixTimeCreation,
    bool _premium
  ) internal returns (address addr_) {
    addr_ = address(
      new WrappedNFTHero(
        HCT_ADDRESS,
        NFT_PASS,
        _collection,
        address(this),
        _totalSupply,
        _unixTimeCreation,
        _premium
      )
    );

    isWrappedNFT[addr_] = true;
    supportedCollections[_collection].wrappedVersion = addr_;

    emit WrappedNFTCreated(_collection, addr_);

    return addr_;
  }

  /// @inheritdoc IObeliskRegistry
  function removeFromCollection(address _collection, uint256 _amount)
    external
    override
    nonReentrant
  {
    Collection storage collection = supportedCollections[_collection];
    uint256 depositedAmount = userSupportedCollections[msg.sender][_collection].deposit;
    uint256 currentBalance = collection.contributionBalance;

    if (_amount > depositedAmount) {
      revert AmountExceedsDeposit();
    }
    if (_amount == 0) _amount = depositedAmount;

    if (currentBalance >= REQUIRED_ETH_TO_ENABLE_COLLECTION) {
      revert GoalReached();
    }

    collection.contributionBalance = currentBalance - _amount;
    depositedAmount -= _amount;

    if (depositedAmount != 0 && depositedAmount < MINIMUM_SENDING_ETH) {
      revert ContributionBalanceTooLow();
    }

    userSupportedCollections[msg.sender][_collection].deposit = uint128(depositedAmount);
    DRIP_VAULT_ETH.withdraw(msg.sender, _amount);

    emit CollectionContributionWithdrawn(_collection, msg.sender, _amount);
  }

  /// @inheritdoc IObeliskRegistry
  function supportYieldPool(uint256 _amount) external payable override {
    if (msg.value != 0 && _amount != 0) revert OnlyOneValue();

    address token = msg.value != 0 ? address(0) : address(DAI);
    uint256 sanitizedAmount = msg.value != 0 ? msg.value : _amount;
    uint256 minimumAmount =
      token == address(0) ? MINIMUM_ETH_SUPPORT_AMOUNT : MINIMUM_DAI_SUPPORT_AMOUNT;

    if (sanitizedAmount < minimumAmount) revert AmountTooLow();

    if (token == address(0)) {
      sanitizedAmount = DRIP_VAULT_ETH.deposit{ value: sanitizedAmount }(0);
    } else {
      DAI.transferFrom(msg.sender, address(DRIP_VAULT_DAI), sanitizedAmount);
      sanitizedAmount = DRIP_VAULT_DAI.deposit(sanitizedAmount);
    }

    supportId++;
    supporters[supportId] = Supporter({
      depositor: msg.sender,
      token: token,
      amount: uint128(sanitizedAmount),
      lockUntil: uint32(block.timestamp + SUPPORT_LOCK_DURATION),
      removed: false
    });

    emit Supported(supportId, msg.sender, sanitizedAmount);
  }

  /// @inheritdoc IObeliskRegistry
  function retrieveSupportToYieldPool(uint32 _id) external override nonReentrant {
    Supporter storage supporter = supporters[_id];
    uint256 returningAmount = supporter.amount;

    if (supporter.depositor != msg.sender) revert NotSupporterDepositor();
    if (supporter.lockUntil > block.timestamp) revert SupportNotFinished();
    if (supporter.removed) revert AlreadyRemoved();

    supporter.removed = true;

    if (supporter.token == address(0)) {
      DRIP_VAULT_ETH.withdraw(msg.sender, returningAmount);
    } else {
      DRIP_VAULT_DAI.withdraw(msg.sender, returningAmount);
    }

    emit SupportRetrieved(_id, msg.sender, returningAmount);
  }

  function onSlotBought() external payable {
    if (!isWrappedNFT[msg.sender]) revert NotWrappedNFT();
    if (msg.value == 0) return;

    uint256 collectionTotalReward = wrappedCollectionRewards[msg.sender].totalRewards;
    uint256 toCollection = Math.mulDiv(msg.value, COLLECTION_REWARD_PERCENT, BPS);

    if (collectionTotalReward + toCollection > maxRewardPerCollection) {
      toCollection = maxRewardPerCollection - collectionTotalReward;
    }
    uint256 toTreasury = msg.value - toCollection;

    wrappedCollectionRewards[msg.sender].totalRewards += uint128(toCollection);

    (bool success,) = treasury.call{ value: toTreasury }("");
    if (!success) revert TransferFailed();

    emit SlotBought(msg.sender, toCollection, toTreasury);
  }

  function claim(address _collection) external nonReentrant {
    Collection storage collection = supportedCollections[_collection];
    CollectionRewards storage collectionRewards =
      wrappedCollectionRewards[collection.wrappedVersion];
    ContributionInfo storage userContribution =
      userSupportedCollections[msg.sender][_collection];

    uint256 contributionBalance = collection.contributionBalance;

    if (contributionBalance != REQUIRED_ETH_TO_ENABLE_COLLECTION) revert NothingToClaim();

    uint256 totalUserReward = Math.mulDiv(
      userContribution.deposit, collectionRewards.totalRewards, contributionBalance
    );
    uint128 rewardsToClaim = uint128(totalUserReward - userContribution.claimed);

    if (rewardsToClaim == 0) revert NothingToClaim();

    collectionRewards.claimedRewards += rewardsToClaim;
    userContribution.claimed = uint128(totalUserReward);

    (bool success,) = msg.sender.call{ value: rewardsToClaim }("");
    if (!success) revert TransferFailed();

    emit Claimed(_collection, msg.sender, rewardsToClaim);
  }

  function allowNewCollection(
    address _collection,
    uint256 _totalSupply,
    uint32 _collectionStartedUnixTime,
    bool _premium
  ) external {
    bool isOwner = msg.sender == owner();
    if (!isOwner && msg.sender != dataAsserter) revert NotAuthorized();
    if (supportedCollections[_collection].allowed) revert CollectionAlreadyAllowed();

    supportedCollections[_collection] = Collection({
      wrappedVersion: address(0),
      totalSupply: _totalSupply,
      contributionBalance: 0,
      collectionStartedUnixTime: _collectionStartedUnixTime,
      allowed: true,
      premium: isOwner ? _premium : false
    });

    emit CollectionAllowed(
      _collection, _totalSupply, _collectionStartedUnixTime, _premium
    );
  }

  function toggleIsWrappedNFTFor(
    address _collection,
    address _wrappedVersion,
    bool _allowed
  ) external onlyOwner {
    isWrappedNFT[_wrappedVersion] = _allowed;

    if (_allowed) {
      emit WrappedNFTEnabled(_collection, _wrappedVersion);
    } else {
      emit WrappedNFTDisabled(_collection, _wrappedVersion);
    }
  }

  function setTickerLogic(string memory _ticker, address _pool) external {
    if (msg.sender != owner() && msg.sender != megapoolFactory) revert NoAccess();
    if (tickersLogic[_ticker] != address(0)) revert TickerAlreadyExists();

    tickersLogic[_ticker] = _pool;
    emit TickerLogicSet(_ticker, _pool, _ticker);
  }

  function overrideTickerLogic(string memory _ticker, address _pool) external onlyOwner {
    tickersLogic[_ticker] = _pool;
    emit TickerLogicSet(_ticker, _pool, _ticker);
  }

  function setTreasury(address _treasury) external onlyOwner {
    if (_treasury == address(0)) revert ZeroAddress();
    treasury = _treasury;
    emit TreasurySet(_treasury);
  }

  function setDataAsserter(address _dataAsserter) external onlyOwner {
    dataAsserter = _dataAsserter;
    emit DataAsserterSet(_dataAsserter);
  }

  function setMegapoolFactory(address _megapoolFactory) external onlyOwner {
    megapoolFactory = _megapoolFactory;
    emit MegapoolFactorySet(_megapoolFactory);
  }

  function setMaxRewardPerCollection(uint256 _maxRewardPerCollection) external onlyOwner {
    maxRewardPerCollection = _maxRewardPerCollection;
    emit MaxRewardPerCollectionSet(_maxRewardPerCollection);
  }

  /**
   * @notice Enable emergency withdraw for a wrapped collection
   * @param _wrappedCollection Wrapped collection address
   *
   * @dev This function enables emergency withdrawal for users to retrieve their NFTs
   * in case of external issues.
   *
   * Once activated, this action is irreversible, and the collection will be marked as
   * "offline".
   *
   * This will result in "Ghost weight" in the Tickers, negatively impacting the pool's
   * yield
   * and locking the rewards of these "Ghosts".
   *
   * In such a scenario, a migration is recommended. Although we use a trusted third
   * party,
   * the possibility of this happening is low but not impossible.
   */
  function enableEmergencyWithdrawForCollection(address _wrappedCollection)
    external
    onlyOwner
  {
    WrappedNFTHero(_wrappedCollection).enableEmergencyWithdraw();
  }

  function setWrappedCollectionImageIPFS(string memory _ipfsImage) external onlyOwner {
    wrappedCollectionImageIPFS = _ipfsImage;
  }

  /// @inheritdoc IObeliskRegistry
  function getTickerLogic(string memory _ticker) external view override returns (address) {
    return tickersLogic[_ticker];
  }

  /// @inheritdoc IObeliskRegistry
  function getSupporter(uint32 _id) external view override returns (Supporter memory) {
    return supporters[_id];
  }

  function getUserContribution(address _user, address _collection)
    external
    view
    returns (ContributionInfo memory)
  {
    return userSupportedCollections[_user][_collection];
  }

  function getCollectionRewards(address _collection)
    external
    view
    returns (CollectionRewards memory)
  {
    return wrappedCollectionRewards[supportedCollections[_collection].wrappedVersion];
  }

  function getCollection(address _collection)
    external
    view
    override
    returns (Collection memory)
  {
    return supportedCollections[_collection];
  }

  receive() external payable { }
}

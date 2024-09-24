// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { WrappedNFTHero } from "./WrappedNFTHero.sol";
import { LiteTickerFarmPool } from "../tickers/LiteTickerFarmPool.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract ObeliskRegistry is IObeliskRegistry, Ownable {
  uint256 private constant MINIMUM_SENDING_ETH = 0.005 ether;
  uint256 public constant MIN_SUPPORT_AMOUNT = 1e18;
  uint32 public constant SUPPORT_LOCK_DURATION = 30 days;
  uint256 public constant COLLECTION_REWARD_PERCENT = 4000;
  uint256 public constant BPS = 10_000;
  uint128 public constant REQUIRED_ETH_TO_ENABLE_COLLECTION = 100e18;

  address public immutable HCT;
  address public immutable NFT_PASS;
  IERC20 public immutable DAI;
  IDripVault public immutable DRIP_VAULT_ETH;
  IDripVault public immutable DRIP_VAULT_DAI;

  address public treasury;
  address public dataAsserter;
  uint32 public supportId;
  uint256 public maxRewardPerCollection;

  mapping(address => Collection) public supportedCollections;
  mapping(address wrappedCollection => CollectionRewards) internal wrappedCollectionRewards;
  mapping(address wrappedNFT => bool isValid) public override isWrappedNFT;

  mapping(string ticker => address logic) private tickersLogic;
  mapping(address user => mapping(address collection => ContributionInfo)) internal userSupportedCollections;
  mapping(uint32 => Supporter) private supporters;

  constructor(
    address _owner,
    address _treasury,
    address _hct,
    address _nftPass,
    address _dripVaultETH,
    address _dripVaultDAI,
    address _dai
  ) Ownable(_owner) {
    maxRewardPerCollection = 250e18;

    treasury = _treasury;
    HCT = _hct;
    DRIP_VAULT_ETH = IDripVault(_dripVaultETH);
    DRIP_VAULT_DAI = IDripVault(_dripVaultDAI);
    NFT_PASS = _nftPass;
    DAI = IERC20(_dai);
  }

  /// @inheritdoc IObeliskRegistry
  function addToCollection(address _collection) external payable override {
    if (msg.value < MINIMUM_SENDING_ETH) revert AmountTooLow();

    Collection storage collection = supportedCollections[_collection];
    uint256 newTotalContribution = collection.contributionBalance + msg.value;

    if (!collection.allowed) revert CollectionNotAllowed();

    collection.contributionBalance = newTotalContribution;
    userSupportedCollections[msg.sender][_collection].deposit += uint128(msg.value);
    DRIP_VAULT_ETH.deposit{ value: msg.value }(0);

    if (newTotalContribution > REQUIRED_ETH_TO_ENABLE_COLLECTION) {
      revert TooManyEth();
    }

    emit CollectionContributed(_collection, msg.sender, msg.value);
    if (newTotalContribution != REQUIRED_ETH_TO_ENABLE_COLLECTION) return;

    _createWrappedNFT(_collection, collection.totalSupply, collection.collectionStartedUnixTime, collection.premium);
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
    userSupportedCollections[msg.sender][_collection].deposit += uint128(missingEth);

    _createWrappedNFT(_collection, collection.totalSupply, collection.collectionStartedUnixTime, collection.premium);
  }

  function _createWrappedNFT(address _collection, uint256 _totalSupply, uint32 _unixTimeCreation, bool _premium)
    internal
    returns (address addr_)
  {
    addr_ = _createContract(
      abi.encodePacked(
        type(WrappedNFTHero).creationCode,
        abi.encode(HCT, NFT_PASS, _collection, address(this), _totalSupply, _unixTimeCreation, _premium)
      )
    );

    isWrappedNFT[addr_] = true;
    supportedCollections[_collection].wrappedVersion = addr_;

    emit WrappedNFTCreated(_collection, addr_);

    return addr_;
  }

  /// @inheritdoc IObeliskRegistry
  function removeFromCollection(address _collection, uint256 _amount) external override {
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
    userSupportedCollections[msg.sender][_collection].deposit -= uint128(_amount);
    DRIP_VAULT_ETH.withdraw(msg.sender, _amount);

    (bool success,) = msg.sender.call{ value: _amount }("");
    if (!success) {
      revert TransferFailed();
    }

    emit CollectionContributionWithdrawn(_collection, msg.sender, _amount);
  }

  /// @inheritdoc IObeliskRegistry
  function supportYieldPool(uint256 _amount) external payable override {
    if (msg.value != 0 && _amount != 0) revert OnlyOneValue();

    address token = msg.value != 0 ? address(0) : address(DAI);
    uint256 santizedAmount = msg.value != 0 ? msg.value : _amount;

    if (santizedAmount < MIN_SUPPORT_AMOUNT) revert AmountTooLow();

    supportId++;
    supporters[supportId] = Supporter({
      depositor: msg.sender,
      token: token,
      amount: uint128(santizedAmount),
      lockUntil: uint32(block.timestamp + SUPPORT_LOCK_DURATION),
      removed: false
    });

    if (token == address(0)) {
      DRIP_VAULT_ETH.deposit{ value: msg.value }(0);
    } else {
      DAI.transferFrom(msg.sender, address(DRIP_VAULT_DAI), santizedAmount);
      DRIP_VAULT_DAI.deposit(santizedAmount);
    }

    emit Supported(supportId, msg.sender, santizedAmount);
  }

  /// @inheritdoc IObeliskRegistry
  function retrieveSupportToYieldPool(uint32 _id) external override {
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

  function setTickerLogic(string memory _ticker, address _pool) external onlyOwner {
    tickersLogic[_ticker] = _pool;
    emit TickerLogicSet(_ticker, _pool);
  }

  function addNewGenesisTicker(string memory _name, address _wrappedGenesisReward, address _genesisKey)
    external
    onlyOwner
    returns (address newPool_)
  {
    if (tickersLogic[_name] != address(0)) revert TickerAlreadyExists();

    newPool_ = _createContract(
      abi.encodePacked(
        type(LiteTickerFarmPool).creationCode, abi.encode(msg.sender, address(this), _wrappedGenesisReward, _genesisKey)
      )
    );
    tickersLogic[_name] = newPool_;

    emit NewGenesisTickerCreated(_name, newPool_);
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

  function claim(address _collection) external {
    Collection storage collection = supportedCollections[_collection];
    address wrappedNFT = collection.wrappedVersion;
    uint256 contributionBalance = collection.contributionBalance;

    if (contributionBalance == 0 || !collection.allowed) revert NothingToClaim();

    CollectionRewards storage collectionRewards = wrappedCollectionRewards[wrappedNFT];
    ContributionInfo storage userContribution = userSupportedCollections[msg.sender][_collection];

    uint128 totalCollectionReward = collectionRewards.totalRewards;
    uint256 totalUserReward = Math.mulDiv(userContribution.deposit, totalCollectionReward, contributionBalance);
    uint128 rewardsToClaim = uint128(totalUserReward - userContribution.claimed);
    uint128 totalCollactionClaimedRewards = collectionRewards.claimedRewards;

    if (rewardsToClaim == 0) revert NothingToClaim();

    collectionRewards.claimedRewards = totalCollactionClaimedRewards + rewardsToClaim;
    userContribution.claimed = uint128(totalUserReward);

    (bool success,) = msg.sender.call{ value: rewardsToClaim }("");
    if (!success) revert TransferFailed();

    emit Claimed(_collection, msg.sender, rewardsToClaim);
  }

  function _createContract(bytes memory bytecode) internal returns (address addr_) {
    bytes32 salt = keccak256(abi.encodePacked(address(this), block.number, block.timestamp));

    /// @solidity memory-safe-assembly
    assembly {
      addr_ := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
    }

    if (addr_ == address(0)) revert FailedDeployment();
    return addr_;
  }

  function allowNewCollectionPremium(address _collection, uint256 _totalSupply, uint32 _collectionStartedUnixTime)
    external
    onlyOwner
  {
    _allowNewCollection(_collection, _totalSupply, _collectionStartedUnixTime, true);
  }

  function allowNewCollection(address _collection, uint256 _totalSupply, uint32 _collectionStartedUnixTime) external {
    if (msg.sender != owner() && msg.sender != dataAsserter) revert NotAuthorized();

    _allowNewCollection(_collection, _totalSupply, _collectionStartedUnixTime, false);
  }

  function _allowNewCollection(
    address _collection,
    uint256 _totalSupply,
    uint32 _collectionStartedUnixTime,
    bool _premium
  ) internal {
    if (supportedCollections[_collection].allowed) revert CollectionAlreadyAllowed();

    supportedCollections[_collection] = Collection({
      wrappedVersion: address(0),
      totalSupply: _totalSupply,
      contributionBalance: 0,
      collectionStartedUnixTime: _collectionStartedUnixTime,
      allowed: true,
      premium: _premium
    });

    emit CollectionAllowed(_collection, _totalSupply, _collectionStartedUnixTime, _premium);
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

  function setMaxRewardPerCollection(uint256 _maxRewardPerCollection) external onlyOwner {
    maxRewardPerCollection = _maxRewardPerCollection;
    emit MaxRewardPerCollectionSet(_maxRewardPerCollection);
  }

  /// @inheritdoc IObeliskRegistry
  function getTickerLogic(string memory _ticker) external view override returns (address) {
    return tickersLogic[_ticker];
  }

  /// @inheritdoc IObeliskRegistry
  function getSupporter(uint32 _id) external view override returns (Supporter memory) {
    return supporters[_id];
  }

  function getUserContribution(address _user, address _collection) external view returns (ContributionInfo memory) {
    return userSupportedCollections[_user][_collection];
  }

  function getCollectionRewards(address _collection) external view returns (CollectionRewards memory) {
    return wrappedCollectionRewards[supportedCollections[_collection].wrappedVersion];
  }

  function getCollection(address _collection) external view override returns (Collection memory) {
    return supportedCollections[_collection];
  }

  receive() external payable { }
}

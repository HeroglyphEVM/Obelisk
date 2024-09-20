// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "test/base/BaseTest.t.sol";

import {
  ObeliskRegistry,
  IObeliskRegistry,
  IDripVault,
  WrappedNFTHero,
  Ownable,
  LiteTickerFarmPool
} from "src/services/nft/ObeliskRegistry.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";

import { FailOnReceive } from "test/mock/contract/FailOnReceive.t.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract ObeliskRegistryTest is BaseTest {
  uint256 private constant REQUIRED_ETH_TO_ENABLE_COLLECTION = 100e18;
  uint256 private constant TOTAL_SUPPLY_MOCK_COLLECTION = 10_000;
  uint32 private constant UNIX_MOCK_COLLECTION_STARTED = 99_283;

  address private owner;
  address private treasury;
  address private user;

  address private collectionMock;
  address private hctMock;
  address private dripVaultETHMock;
  address private dripVaultDAIMock;
  address private dataAsserterMock;
  address private mockGenesisWrappedToken;
  address private mockGenesisKey;
  address private nftPassMock;
  MockERC20 private DAI;

  ObeliskRegistryHarness underTest;

  function setUp() external {
    _setupMockVariables();
    _setupMockCalls();

    underTest = new ObeliskRegistryHarness(
      owner, treasury, hctMock, nftPassMock, dripVaultETHMock, dripVaultDAIMock, address(DAI)
    );

    vm.prank(owner);
    underTest.allowNewCollection(collectionMock, TOTAL_SUPPLY_MOCK_COLLECTION, UNIX_MOCK_COLLECTION_STARTED);
  }

  function _setupMockVariables() internal {
    owner = generateAddress("Owner");
    treasury = generateAddress("Treasury");
    user = generateAddress("User", 10_000e18);
    collectionMock = generateAddress("CollectionMock");
    hctMock = generateAddress("HCTMock");
    dripVaultETHMock = generateAddress("DripVaultETHMock");
    dripVaultDAIMock = generateAddress("DripVaultDAIMock");
    dataAsserterMock = generateAddress("DataAsserterMock");
    mockGenesisWrappedToken = generateAddress("MockGenesisToken");
    mockGenesisKey = generateAddress("MockGenesisKey");
    nftPassMock = generateAddress("NFTPassMock");

    DAI = new MockERC20("DAI", "DAI", 18);
    DAI.mint(user, 100_000e18);
  }

  function _setupMockCalls() internal {
    vm.mockCall(dripVaultETHMock, abi.encodeWithSelector(IDripVault.deposit.selector), abi.encode(true));
    vm.mockCall(dripVaultETHMock, abi.encodeWithSelector(IDripVault.withdraw.selector), abi.encode(true));
    vm.mockCall(dripVaultDAIMock, abi.encodeWithSelector(IDripVault.deposit.selector), abi.encode(true));
    vm.mockCall(dripVaultDAIMock, abi.encodeWithSelector(IDripVault.withdraw.selector), abi.encode(true));
  }

  function test_constructor() external {
    underTest = new ObeliskRegistryHarness(
      owner, treasury, hctMock, nftPassMock, dripVaultETHMock, dripVaultDAIMock, address(DAI)
    );

    assertEq(underTest.owner(), owner);
    assertEq(underTest.HCT(), hctMock);
    assertEq(underTest.NFT_PASS(), nftPassMock);
    assertEq(underTest.REQUIRED_ETH_TO_ENABLE_COLLECTION(), REQUIRED_ETH_TO_ENABLE_COLLECTION);
  }

  function test_addToCollection_whenZeroValue_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.ZeroValue.selector);
    underTest.addToCollection(collectionMock);
  }

  function test_addToCollection_whenOverRequiredETH_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.TooManyEth.selector);
    underTest.addToCollection{ value: REQUIRED_ETH_TO_ENABLE_COLLECTION + 1 }(collectionMock);

    underTest.addToCollection{ value: REQUIRED_ETH_TO_ENABLE_COLLECTION }(collectionMock);

    vm.expectRevert(IObeliskRegistry.TooManyEth.selector);
    underTest.addToCollection{ value: 1 }(collectionMock);
  }

  function test_addToCollection_whenGoalNotReached_thenAddsEthAndDepositsIntoDripVault() external prankAs(user) {
    uint256 givingAmount = 1.32e18;

    vm.expectCall(dripVaultETHMock, givingAmount, abi.encodeWithSelector(IDripVault.deposit.selector));

    expectExactEmit();
    emit IObeliskRegistry.CollectionContributed(collectionMock, user, givingAmount);
    underTest.addToCollection{ value: givingAmount }(collectionMock);

    assertEq(underTest.getCollection(collectionMock).contributionBalance, givingAmount);
    assertEq(underTest.getUserContribution(user, collectionMock).deposit, givingAmount);
  }

  function test_addToCollection_whenGoalReached_thenCreatesWrappedNFT() external prankAs(user) {
    uint256 givingAmount = REQUIRED_ETH_TO_ENABLE_COLLECTION;

    expectExactEmit();
    emit IObeliskRegistry.CollectionContributed(collectionMock, user, givingAmount);
    vm.expectEmit(true, false, false, false);
    emit IObeliskRegistry.WrappedNFTCreated(collectionMock, address(0));

    underTest.addToCollection{ value: givingAmount }(collectionMock);
  }

  function test_forceActiveCollection_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.forceActiveCollection(collectionMock);
  }

  function test_forceActiveCollection_whenCollectionNotAllowed_thenReverts() external pranking {
    changePrank(owner);
    vm.expectRevert(IObeliskRegistry.CollectionNotAllowed.selector);
    underTest.forceActiveCollection(generateAddress());
  }

  function test_forceActiveCollection_whenTooManyEth_thenReverts() external pranking {
    changePrank(user);
    underTest.addToCollection{ value: REQUIRED_ETH_TO_ENABLE_COLLECTION }(collectionMock);

    changePrank(owner);
    vm.expectRevert(IObeliskRegistry.TooManyEth.selector);
    underTest.forceActiveCollection(collectionMock);
  }

  function test_forceActiveCollection_whenNoContribution_thenAddsToAllowedCollections() external prankAs(owner) {
    changePrank(owner);
    vm.expectEmit(true, false, false, false);
    emit IObeliskRegistry.WrappedNFTCreated(collectionMock, address(0));
    underTest.forceActiveCollection(collectionMock);

    assertEq(underTest.getCollection(collectionMock).contributionBalance, REQUIRED_ETH_TO_ENABLE_COLLECTION);
  }

  function test_forceActiveCollection_whenSomeContribution_thenAddsToAllowedCollections() external pranking {
    changePrank(user);
    underTest.addToCollection{ value: 25e18 }(collectionMock);

    changePrank(owner);
    vm.expectEmit(true, false, false, false);
    emit IObeliskRegistry.WrappedNFTCreated(collectionMock, address(0));
    underTest.forceActiveCollection(collectionMock);

    assertEq(underTest.getCollection(collectionMock).contributionBalance, REQUIRED_ETH_TO_ENABLE_COLLECTION);
  }

  function test_createWrappedNFT_thenVerifyWrappedNFTConfiguration() external {
    address collection_nonPremium = generateAddress("CollectionNonPremium");
    address collection_premium = generateAddress("CollectionPremium");
    uint32 collectionStartedUnixTime = 999_928;

    WrappedNFTHero wrappedNFT_nonPremium =
      WrappedNFTHero(underTest.exposed_createWrappedNFT(collection_nonPremium, 10_000, collectionStartedUnixTime, false));

    assertTrue(underTest.isWrappedNFT(address(wrappedNFT_nonPremium)));

    assertEq(address(wrappedNFT_nonPremium.HCT()), hctMock);
    assertEq(address(wrappedNFT_nonPremium.INPUT_COLLECTION()), collection_nonPremium);
    assertEq(address(wrappedNFT_nonPremium.obeliskRegistry()), address(underTest));
    assertEq(wrappedNFT_nonPremium.collectionStartedUnixTime(), collectionStartedUnixTime);
    assertFalse(wrappedNFT_nonPremium.premium());

    WrappedNFTHero wrappedNFT_premium =
      WrappedNFTHero(underTest.exposed_createWrappedNFT(collection_premium, 10_000, collectionStartedUnixTime, true));

    assertTrue(underTest.isWrappedNFT(address(wrappedNFT_premium)));

    assertEq(address(wrappedNFT_premium.HCT()), hctMock);
    assertEq(address(wrappedNFT_premium.INPUT_COLLECTION()), collection_premium);
    assertEq(address(wrappedNFT_premium.obeliskRegistry()), address(underTest));
    assertEq(wrappedNFT_premium.collectionStartedUnixTime(), collectionStartedUnixTime);
    assertTrue(wrappedNFT_premium.premium());
  }

  function test_removeFromCollection_whenAmountExceedsDeposit_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.AmountExceedsDeposit.selector);
    underTest.removeFromCollection(collectionMock, 1);
  }

  function test_removeFromCollection_whenGoalReached_thenReverts() external prankAs(user) {
    uint256 givingAmount = REQUIRED_ETH_TO_ENABLE_COLLECTION;
    underTest.addToCollection{ value: givingAmount }(collectionMock);

    vm.expectRevert(IObeliskRegistry.GoalReached.selector);
    underTest.removeFromCollection(collectionMock, 1);
  }

  function test_removeFromCollection_whenTransferFails_thenReverts() external prankAs(user) {
    uint256 givingAmount = 23e18;
    underTest.addToCollection{ value: givingAmount }(collectionMock);

    vm.etch(user, type(FailOnReceive).creationCode);

    vm.expectRevert(IObeliskRegistry.TransferFailed.selector);
    underTest.removeFromCollection(collectionMock, 1);
  }

  function test_removeFromCollection_whenAmountIsZero_thenRemovesAll() external prankAs(user) {
    uint256 initialBalance = user.balance;

    uint256 givingAmount = 32.32e18;
    underTest.addToCollection{ value: givingAmount }(collectionMock);

    vm.expectCall(dripVaultETHMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, givingAmount));

    expectExactEmit();
    emit IObeliskRegistry.CollectionContributionWithdrawn(collectionMock, user, givingAmount);
    underTest.removeFromCollection(collectionMock, 0);

    assertEq(underTest.getCollection(collectionMock).contributionBalance, 0);
    assertEq(underTest.getUserContribution(user, collectionMock).deposit, 0);
    assertEq(user.balance, initialBalance);
  }

  function test_removeFromCollection_whenGoalNotReached_thenRemovesAmount() external prankAs(user) {
    uint256 initialBalance = user.balance;

    uint256 givingAmount = 32.32e18;
    uint256 withdrawn = 13.211e18;
    underTest.addToCollection{ value: givingAmount }(collectionMock);

    vm.expectCall(dripVaultETHMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, withdrawn));

    expectExactEmit();
    emit IObeliskRegistry.CollectionContributionWithdrawn(collectionMock, user, withdrawn);
    underTest.removeFromCollection(collectionMock, withdrawn);

    assertEq(underTest.getCollection(collectionMock).contributionBalance, givingAmount - withdrawn);
    assertEq(underTest.getUserContribution(user, collectionMock).deposit, givingAmount - withdrawn);
    assertEq(user.balance, initialBalance - (givingAmount - withdrawn));
  }

  function test_supportYieldPool_whenZeroValue_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.ZeroValue.selector);
    underTest.supportYieldPool{ value: 0 }(0);
  }

  function test_supportYieldPool_whenBothAmountsAreSet_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.OnlyOneValue.selector);
    underTest.supportYieldPool{ value: 1 }(1);
  }

  function test_supportYieldPool_whenAmountIsTooLow_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.AmountTooLow.selector);
    underTest.supportYieldPool{ value: 0.9e18 }(0);

    vm.expectRevert(IObeliskRegistry.AmountTooLow.selector);
    underTest.supportYieldPool{ value: 0 }(0.9e18);
  }

  function test_supportYieldPool_whenETH_thenUpdatesSupportersAndDepositInDripVault() external prankAs(user) {
    uint256 supportAmount = 13.32e18;

    IObeliskRegistry.Supporter memory expectedSupporter = IObeliskRegistry.Supporter({
      depositor: user,
      token: address(0),
      amount: uint128(supportAmount),
      lockUntil: uint32(block.timestamp + underTest.SUPPORT_LOCK_DURATION()),
      removed: false
    });

    vm.expectCall(dripVaultETHMock, supportAmount, abi.encodeWithSelector(IDripVault.deposit.selector));

    expectExactEmit();
    emit IObeliskRegistry.Supported(1, user, supportAmount);
    underTest.supportYieldPool{ value: supportAmount }(0);

    assertEq(abi.encode(underTest.getSupporter(1)), abi.encode(expectedSupporter));
    assertEq(underTest.supportId(), 1);
  }

  function test_supportYieldPool_whenDAI_thenUpdatesSupportersAndDepositInDripVault() external prankAs(user) {
    uint256 supportAmount = 13.32e18;

    IObeliskRegistry.Supporter memory expectedSupporter = IObeliskRegistry.Supporter({
      depositor: user,
      token: address(DAI),
      amount: uint128(supportAmount),
      lockUntil: uint32(block.timestamp + underTest.SUPPORT_LOCK_DURATION()),
      removed: false
    });

    vm.expectCall(dripVaultDAIMock, abi.encodeWithSelector(IDripVault.deposit.selector, supportAmount));

    expectExactEmit();
    emit IObeliskRegistry.Supported(1, user, supportAmount);
    underTest.supportYieldPool(supportAmount);

    assertEq(abi.encode(underTest.getSupporter(1)), abi.encode(expectedSupporter));
    assertEq(underTest.supportId(), 1);
  }

  function test_retrieveSupportToYieldPool_whenNotSupporter_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.NotSupporterDepositor.selector);
    underTest.retrieveSupportToYieldPool(1);
  }

  function test_retrieveSupportToYieldPool_whenSupportNotFinished_thenReverts() external prankAs(user) {
    underTest.supportYieldPool{ value: 1.1e18 }(0);

    skip(underTest.SUPPORT_LOCK_DURATION() - 1);

    vm.expectRevert(IObeliskRegistry.SupportNotFinished.selector);
    underTest.retrieveSupportToYieldPool(1);
  }

  function test_retrieveSupportToYieldPool_whenAlreadyRemoved_thenReverts() external prankAs(user) {
    underTest.supportYieldPool{ value: 1.1e18 }(0);

    skip(underTest.SUPPORT_LOCK_DURATION());
    underTest.retrieveSupportToYieldPool(1);

    vm.expectRevert(IObeliskRegistry.AlreadyRemoved.selector);
    underTest.retrieveSupportToYieldPool(1);
  }

  function test_retrieveSupportToYieldPool_whenETH_thenWithdrawsFromDripVault() external prankAs(user) {
    uint256 supportAmount = 13.32e18;
    underTest.supportYieldPool{ value: supportAmount }(0);

    skip(underTest.SUPPORT_LOCK_DURATION());

    vm.expectCall(dripVaultETHMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, supportAmount));

    expectExactEmit();
    emit IObeliskRegistry.SupportRetrieved(1, user, supportAmount);
    underTest.retrieveSupportToYieldPool(1);

    assertTrue(underTest.getSupporter(1).removed);
  }

  function test_retrieveSupportToYieldPool_whenDAI_thenWithdrawsFromDripVault() external prankAs(user) {
    uint256 supportAmount = 13.32e18;
    underTest.supportYieldPool(supportAmount);

    skip(underTest.SUPPORT_LOCK_DURATION());

    vm.expectCall(dripVaultDAIMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, supportAmount));

    expectExactEmit();
    emit IObeliskRegistry.SupportRetrieved(1, user, supportAmount);
    underTest.retrieveSupportToYieldPool(1);

    assertTrue(underTest.getSupporter(1).removed);
  }

  function test_setTickerLogic_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setTickerLogic("ticker", generateAddress("TickerPool"));
  }

  function test_setTickerLogic_thenUpdatesTickerPool() external prankAs(owner) {
    address expectedPool = generateAddress("TickerPool");
    string memory ticker = "Super Ticker";

    expectExactEmit();
    emit IObeliskRegistry.TickerLogicSet(ticker, expectedPool);
    underTest.setTickerLogic(ticker, expectedPool);

    assertEq(underTest.getTickerLogic(ticker), expectedPool);
  }

  function test_addNewGenesisTicker_asNonOwner_thenReverts() external prankAs(user) {
    string memory ticker = "Ticker";

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.addNewGenesisTicker(ticker, mockGenesisWrappedToken, mockGenesisKey);
  }

  function test_addNewGenesisTicker_whenTickerExists_thenReverts() external prankAs(owner) {
    string memory ticker = "Ticker";

    underTest.setTickerLogic(ticker, generateAddress("TickerPool"));

    vm.expectRevert(IObeliskRegistry.TickerAlreadyExists.selector);
    underTest.addNewGenesisTicker(ticker, mockGenesisWrappedToken, mockGenesisKey);
  }

  function test_addNewGenesisTicker_thenCreatesNewTickerPool() external prankAs(owner) {
    string memory ticker = "Ticker";

    vm.expectEmit(true, false, false, false);
    emit IObeliskRegistry.NewGenesisTickerCreated(ticker, address(0));
    LiteTickerFarmPool pool =
      LiteTickerFarmPool(underTest.addNewGenesisTicker(ticker, mockGenesisWrappedToken, mockGenesisKey));

    assertEq(underTest.getTickerLogic(ticker), address(pool));

    assertEq(pool.owner(), owner);
    assertEq(address(pool.registry()), address(underTest));
    assertEq(address(pool.genesisKey()), mockGenesisKey);
    assertEq(address(pool.rewardToken()), mockGenesisWrappedToken);
  }

  function test_onSlotBought_whenNotWrappedNFT_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.NotWrappedNFT.selector);
    underTest.onSlotBought();
  }

  function test_onSlotBought_whenFailedTransfer_thenReverts() external pranking {
    uint256 givingAmount = 1.32e18;

    changePrank(owner);
    underTest.forceActiveCollection(collectionMock);

    address wrappedNFT = address(underTest.getCollection(collectionMock).wrappedVersion);
    vm.deal(wrappedNFT, givingAmount);

    changePrank(wrappedNFT);

    vm.etch(treasury, type(FailOnReceive).creationCode);

    vm.expectRevert(IObeliskRegistry.TransferFailed.selector);
    underTest.onSlotBought{ value: givingAmount }();
  }

  function test_onSlotBought_thenSplitBetweenCollectionAndTreasury() external pranking {
    uint256 givingAmount = 1.32e18;
    uint256 expectedCollectionReward = givingAmount * underTest.COLLECTION_REWARD_PERCENT() / 10_000;
    uint256 expectedTreasuryReward = givingAmount - expectedCollectionReward;

    changePrank(owner);
    underTest.forceActiveCollection(collectionMock);

    address wrappedNFT = address(underTest.getCollection(collectionMock).wrappedVersion);
    vm.deal(wrappedNFT, givingAmount);

    changePrank(wrappedNFT);

    expectExactEmit();
    emit IObeliskRegistry.SlotBought(wrappedNFT, expectedCollectionReward, expectedTreasuryReward);
    underTest.onSlotBought{ value: givingAmount }();

    assertEq(underTest.getCollectionRewards(collectionMock).totalRewards, expectedCollectionReward);
    assertEq(treasury.balance, expectedTreasuryReward);
  }

  function test_onSlotBought_whenMaxRewardPerCollection_thenSendsExtraToTreasury() external pranking {
    uint256 maxReward = underTest.maxRewardPerCollection();
    uint256 sending = maxReward * 3;

    uint256 expectedCollectionReward = maxReward;
    uint256 expectedTreasuryReward = sending - maxReward;

    changePrank(owner);
    underTest.forceActiveCollection(collectionMock);

    address wrappedNFT = address(underTest.getCollection(collectionMock).wrappedVersion);
    vm.deal(wrappedNFT, sending);

    changePrank(wrappedNFT);

    expectExactEmit();
    emit IObeliskRegistry.SlotBought(wrappedNFT, expectedCollectionReward, expectedTreasuryReward);
    underTest.onSlotBought{ value: sending }();

    assertEq(underTest.getCollectionRewards(collectionMock).totalRewards, expectedCollectionReward);
    assertEq(treasury.balance, expectedTreasuryReward);
  }

  function test_claim_whenNothingToClaim_thenReverts() external prankAs(user) {
    vm.expectRevert(IObeliskRegistry.NothingToClaim.selector);
    underTest.claim(collectionMock);
  }

  function test_claim_thenSendsRewards() external pranking {
    uint256 givingAmount = 1.32e18;
    uint256 expectedCollectionReward = givingAmount * underTest.COLLECTION_REWARD_PERCENT() / 10_000;

    changePrank(owner);
    underTest.forceActiveCollection(collectionMock);
    address wrappedNFT = address(underTest.getCollection(collectionMock).wrappedVersion);

    changePrank(wrappedNFT);
    vm.deal(wrappedNFT, givingAmount);
    underTest.onSlotBought{ value: givingAmount }();

    changePrank(owner);
    expectExactEmit();
    emit IObeliskRegistry.Claimed(collectionMock, owner, expectedCollectionReward);
    underTest.claim(collectionMock);

    assertEq(owner.balance, expectedCollectionReward);
  }

  function test_fizz_claim(uint128[10] memory _amounts, uint128 _slotBought) external {
    address[10] memory fizzUsers;
    _slotBought = uint128(bound(_slotBought, 0.1e18, underTest.maxRewardPerCollection()));
    uint128 requiredEth = underTest.REQUIRED_ETH_TO_ENABLE_COLLECTION();

    address currentUser;
    uint128 sanitizedAmount;
    uint128 totalAmount;
    uint256 expectedReward;

    for (uint256 i = 0; i < _amounts.length; ++i) {
      if (i == _amounts.length - 1) {
        sanitizedAmount = requiredEth - totalAmount;
      } else {
        sanitizedAmount = uint128(bound(_amounts[i], 0.01e18, 10e18));
      }

      totalAmount += sanitizedAmount;
      _amounts[i] = sanitizedAmount;

      currentUser = generateAddress(string.concat("User-", Strings.toString(i)), sanitizedAmount);
      fizzUsers[i] = currentUser;

      changePrank(currentUser);
      vm.deal(currentUser, sanitizedAmount);
      underTest.addToCollection{ value: sanitizedAmount }(collectionMock);
    }

    address wrappedNFT = address(underTest.getCollection(collectionMock).wrappedVersion);
    uint256 totalRewardToContributor = _slotBought * underTest.COLLECTION_REWARD_PERCENT() / 10_000;

    changePrank(wrappedNFT);
    vm.deal(wrappedNFT, _slotBought);
    underTest.onSlotBought{ value: _slotBought }();

    for (uint256 i = 0; i < fizzUsers.length; ++i) {
      currentUser = fizzUsers[i];
      sanitizedAmount = _amounts[i];

      changePrank(currentUser);
      expectedReward = Math.mulDiv(sanitizedAmount, totalRewardToContributor, totalAmount);

      expectExactEmit();
      emit IObeliskRegistry.Claimed(collectionMock, currentUser, expectedReward);
      underTest.claim(collectionMock);

      assertEq(currentUser.balance, expectedReward);
    }
  }

  function test_createContract_whenFailedDeployment_thenReverts() external {
    vm.expectRevert(IObeliskRegistry.FailedDeployment.selector);
    underTest.exposed_createContract(type(ObeliskRegistry).creationCode);
  }

  function test_allowNewCollectionPremium_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.allowNewCollectionPremium(collectionMock, TOTAL_SUPPLY_MOCK_COLLECTION, UNIX_MOCK_COLLECTION_STARTED);
  }

  function test_allowNewCollectionPremium_whenCollectionAlreadyExists_thenReverts() external pranking {
    address collection = generateAddress("Collection");

    changePrank(owner);
    underTest.allowNewCollectionPremium(collection, TOTAL_SUPPLY_MOCK_COLLECTION, UNIX_MOCK_COLLECTION_STARTED);

    vm.expectRevert(IObeliskRegistry.CollectionAlreadyAllowed.selector);
    underTest.allowNewCollectionPremium(collection, TOTAL_SUPPLY_MOCK_COLLECTION, UNIX_MOCK_COLLECTION_STARTED);
  }

  function test_allowNewCollectionPremium_thenUpdatesCollection() external pranking {
    address collection = generateAddress("Collection");
    uint256 totalSupply = 123.3e18;
    uint32 startedAt = 1_714_329_600;

    IObeliskRegistry.Collection memory expectedCollection = IObeliskRegistry.Collection({
      wrappedVersion: address(0),
      totalSupply: totalSupply,
      contributionBalance: 0,
      collectionStartedUnixTime: startedAt,
      allowed: true,
      premium: true
    });

    changePrank(owner);
    expectExactEmit();
    emit IObeliskRegistry.CollectionAllowed(collection, totalSupply, startedAt, true);
    underTest.allowNewCollectionPremium(collection, totalSupply, startedAt);

    assertEq(abi.encode(underTest.getCollection(collection)), abi.encode(expectedCollection));
  }

  function test_allowNewCollection_whenNotAuthorized_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskRegistry.NotAuthorized.selector));
    underTest.allowNewCollection(collectionMock, TOTAL_SUPPLY_MOCK_COLLECTION, UNIX_MOCK_COLLECTION_STARTED);
  }

  function test_allowNewCollection_thenUpdatesCollection() external pranking {
    changePrank(owner);
    underTest.setDataAsserter(dataAsserterMock);

    address[2] memory authorizedUsers;
    authorizedUsers[0] = owner;
    authorizedUsers[1] = dataAsserterMock;

    for (uint256 i = 0; i < authorizedUsers.length; ++i) {
      changePrank(authorizedUsers[i]);

      address collection = generateAddress("Collection");
      uint256 totalSupply = 123.3e18;
      uint32 startedAt = 1_714_329_600;

      IObeliskRegistry.Collection memory expectedCollection = IObeliskRegistry.Collection({
        wrappedVersion: address(0),
        totalSupply: totalSupply,
        contributionBalance: 0,
        collectionStartedUnixTime: startedAt,
        allowed: true,
        premium: false
      });

      changePrank(owner);
      expectExactEmit();
      emit IObeliskRegistry.CollectionAllowed(collection, totalSupply, startedAt, false);
      underTest.allowNewCollection(collection, totalSupply, startedAt);

      assertEq(abi.encode(underTest.getCollection(collection)), abi.encode(expectedCollection));
    }
  }

  function test_setTreasury_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setTreasury(generateAddress("Treasury"));
  }

  function test_setTreasury_thenUpdatesTreasury() external prankAs(owner) {
    address newTreasury = generateAddress("Treasury");

    expectExactEmit();
    emit IObeliskRegistry.TreasurySet(newTreasury);
    underTest.setTreasury(newTreasury);

    assertEq(underTest.treasury(), newTreasury);
  }

  function test_setMaxRewardPerCollection_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setMaxRewardPerCollection(1e18);
  }

  function test_setMaxRewardPerCollection_thenUpdatesMaxRewardPerCollection() external prankAs(owner) {
    uint256 newMaxReward = 1e18;

    expectExactEmit();
    emit IObeliskRegistry.MaxRewardPerCollectionSet(newMaxReward);
    underTest.setMaxRewardPerCollection(newMaxReward);

    assertEq(underTest.maxRewardPerCollection(), newMaxReward);
  }

  function test_setDataAsserter_asNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setDataAsserter(address(0));
  }

  function test_setDataAsserter_thenUpdatesDataAsserter() external prankAs(owner) {
    address newDataAsserter = generateAddress("DataAsserter");

    expectExactEmit();
    emit IObeliskRegistry.DataAsserterSet(newDataAsserter);
    underTest.setDataAsserter(newDataAsserter);

    assertEq(underTest.dataAsserter(), newDataAsserter);
  }
}

contract ObeliskRegistryHarness is ObeliskRegistry {
  constructor(
    address _owner,
    address _treasury,
    address _hct,
    address _nftPass,
    address _dripVaultETH,
    address _dripVaultDAI,
    address _dai
  ) ObeliskRegistry(_owner, _treasury, _hct, _nftPass, _dripVaultETH, _dripVaultDAI, _dai) { }

  function exposed_createWrappedNFT(address _collection, uint256 _totalSupply, uint32 _blockOfCreation, bool _premium)
    external
    returns (address addr_)
  {
    addr_ = _createWrappedNFT(_collection, _totalSupply, _blockOfCreation, _premium);
  }

  function exposed_createContract(bytes memory bytecode) external returns (address addr_) {
    addr_ = _createContract(bytecode);
  }
}

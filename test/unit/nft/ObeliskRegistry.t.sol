// // SPDX-License-Identifier: Unlicense
// pragma solidity >=0.8.0;

// import "test/base/BaseTest.t.sol";

// import {
//   ObeliskRegistry,
//   IObeliskRegistry,
//   IDripVault,
//   WrappedNFTHero,
//   Ownable,
//   LiteTickerFarmPool
// } from "src/services/nft/ObeliskRegistry.sol";

// import { FailOnReceive } from "test/mock/contract/FailOnReceive.t.sol";

// contract ObeliskRegistryTest is BaseTest {
//   uint256 private constant REQUIRED_ETH_TO_ENABLE_COLLECTION = 100e18;

//   address private owner;
//   address private treasury;
//   address private user;

//   address private collectionMock;
//   address private hctMock;
//   address private dripVaultMock;
//   address private dataAsserterMock;
//   address private mockGenesisWrappedToken;
//   address private mockGenesisKey;
//   address private nftPassMock;

//   ObeliskRegistryHarness underTest;

//   function setUp() external {
//     _setupMockVariables();
//     _setupMockCalls();

//     underTest = new ObeliskRegistryHarness(owner, treasury, hctMock, nftPassMock, dripVaultMock, dataAsserterMock);
//   }

//   function _setupMockVariables() internal {
//     owner = generateAddress("Owner");
//     treasury = generateAddress("Treasury");
//     user = generateAddress("User", 10_000e18);
//     collectionMock = generateAddress("CollectionMock");
//     hctMock = generateAddress("HCTMock");
//     dripVaultMock = generateAddress("DripVaultMock");
//     dataAsserterMock = generateAddress("DataAsserterMock");
//     mockGenesisWrappedToken = generateAddress("MockGenesisToken");
//     mockGenesisKey = generateAddress("MockGenesisKey");
//     nftPassMock = generateAddress("NFTPassMock");
//   }

//   function _setupMockCalls() internal {
//     vm.mockCall(dripVaultMock, abi.encodeWithSelector(IDripVault.deposit.selector), abi.encode(true));
//     vm.mockCall(dripVaultMock, abi.encodeWithSelector(IDripVault.withdraw.selector), abi.encode(true));
//   }

//   function test_constructor() external {
//     underTest = new ObeliskRegistryHarness(owner, treasury, hctMock, nftPassMock, dripVaultMock, dataAsserterMock);

//     assertEq(underTest.owner(), owner);
//     assertEq(underTest.hct(), hctMock);
//     assertEq(underTest.nftPass(), nftPassMock);
//     assertEq(underTest.requiredEthToEnableCollection(), REQUIRED_ETH_TO_ENABLE_COLLECTION);
//   }

//   function test_addToCollection_whenZeroValue_thenReverts() external prankAs(user) {
//     vm.expectRevert(IObeliskRegistry.ZeroValue.selector);
//     underTest.addToCollection(collectionMock);
//   }

//   function test_addToCollection_whenOverRequiredETH_thenReverts() external prankAs(user) {
//     vm.expectRevert(IObeliskRegistry.TooManyEth.selector);
//     underTest.addToCollection{ value: REQUIRED_ETH_TO_ENABLE_COLLECTION + 1 }(collectionMock);

//     underTest.addToCollection{ value: REQUIRED_ETH_TO_ENABLE_COLLECTION }(collectionMock);

//     vm.expectRevert(IObeliskRegistry.TooManyEth.selector);
//     underTest.addToCollection{ value: 1 }(collectionMock);
//   }

//   function test_addToCollection_whenGoalNotReached_thenAddsEthAndDepositsIntoDripVault() external prankAs(user) {
//     uint256 givingAmount = 1.32e18;

//     vm.expectCall(dripVaultMock, givingAmount, abi.encodeWithSelector(IDripVault.deposit.selector));

//     expectExactEmit();
//     emit IObeliskRegistry.CollectionContributed(collectionMock, user, givingAmount);
//     underTest.addToCollection{ value: givingAmount }(collectionMock);

//     assertEq(underTest.getCollection(collectionMock).contributionBalance, givingAmount);
//     assertEq(underTest.getUserContribution(user, collectionMock).deposit, givingAmount);
//   }

//   function test_addToCollection_whenGoalReached_thenCreatesWrappedNFT() external prankAs(user) {
//     uint256 givingAmount = REQUIRED_ETH_TO_ENABLE_COLLECTION;

//     expectExactEmit();
//     emit IObeliskRegistry.CollectionContributed(collectionMock, user, givingAmount);
//     vm.expectEmit(true, false, false, false);
//     emit IObeliskRegistry.WrappedNFTCreated(collectionMock, address(0));

//     underTest.addToCollection{ value: givingAmount }(collectionMock);
//   }

//   function test_createWrappedNFT_thenVerifyWrappedNFTConfiguration() external {
//     uint32 collectionStartedUnixTime = 999_928;

//     WrappedNFTHero wrappedNFT =
//       WrappedNFTHero(underTest.exposed_createWrappedNFT(collectionMock, 10_000, collectionStartedUnixTime));

//     assertTrue(underTest.isWrappedNFT(address(wrappedNFT)));

//     assertEq(address(wrappedNFT.HCT()), hctMock);
//     assertEq(address(wrappedNFT.attachedCollection()), collectionMock);
//     assertEq(address(wrappedNFT.obeliskRegistry()), address(underTest));
//     assertEq(wrappedNFT.collectionStartedUnixTime(), collectionStartedUnixTime);
//     assertEq(wrappedNFT.contractStartedUnixTime(), uint32(block.timestamp));
//   }

//   function test_removeFromCollection_whenAmountExceedsDeposit_thenReverts() external prankAs(user) {
//     vm.expectRevert(IObeliskRegistry.AmountExceedsDeposit.selector);
//     underTest.removeFromCollection(collectionMock, 1);
//   }

//   function test_removeFromCollection_whenGoalReached_thenReverts() external prankAs(user) {
//     uint256 givingAmount = REQUIRED_ETH_TO_ENABLE_COLLECTION;
//     underTest.addToCollection{ value: givingAmount }(collectionMock);

//     vm.expectRevert(IObeliskRegistry.GoalReached.selector);
//     underTest.removeFromCollection(collectionMock, 1);
//   }

//   function test_removeFromCollection_whenTransferFails_thenReverts() external prankAs(user) {
//     uint256 givingAmount = 23e18;
//     underTest.addToCollection{ value: givingAmount }(collectionMock);

//     vm.etch(user, type(FailOnReceive).creationCode);

//     vm.expectRevert(IObeliskRegistry.TransferFailed.selector);
//     underTest.removeFromCollection(collectionMock, 1);
//   }

//   function test_removeFromCollection_whenAmountIsZero_thenRemovesAll() external prankAs(user) {
//     uint256 initialBalance = user.balance;

//     uint256 givingAmount = 32.32e18;
//     underTest.addToCollection{ value: givingAmount }(collectionMock);

//     vm.expectCall(dripVaultMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, givingAmount));

//     expectExactEmit();
//     emit IObeliskRegistry.CollectionContributionWithdrawn(collectionMock, user, givingAmount);
//     underTest.removeFromCollection(collectionMock, 0);

//     assertEq(underTest.getCollection(collectionMock).contributionBalance, 0);
//     assertEq(underTest.getUserContribution(user, collectionMock).deposit, 0);
//     assertEq(user.balance, initialBalance);
//   }

//   function test_removeFromCollection_whenGoalNotReached_thenRemovesAmount() external prankAs(user) {
//     uint256 initialBalance = user.balance;

//     uint256 givingAmount = 32.32e18;
//     uint256 withdrawn = 13.211e18;
//     underTest.addToCollection{ value: givingAmount }(collectionMock);

//     vm.expectCall(dripVaultMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, withdrawn));

//     expectExactEmit();
//     emit IObeliskRegistry.CollectionContributionWithdrawn(collectionMock, user, withdrawn);
//     underTest.removeFromCollection(collectionMock, withdrawn);

//     assertEq(underTest.getCollection(collectionMock).contributionBalance, givingAmount - withdrawn);
//     assertEq(underTest.getUserContribution(user, collectionMock).deposit, givingAmount - withdrawn);
//     assertEq(user.balance, initialBalance - (givingAmount - withdrawn));
//   }

//   function test_supportYieldPool_whenZeroValue_thenReverts() external prankAs(user) {
//     vm.expectRevert(IObeliskRegistry.ZeroValue.selector);
//     underTest.supportYieldPool{ value: 0 }();
//   }

//   function test_supportYieldPool_thenUpdatesSupportersAndDepositInDripVault() external prankAs(user) {
//     uint256 supportAmount = 13.32e18;

//     IObeliskRegistry.Supporter memory expectedSupporter = IObeliskRegistry.Supporter({
//       depositor: user,
//       amount: uint128(supportAmount),
//       lockUntil: uint32(block.timestamp + underTest.SUPPORT_LOCK_DURATION()),
//       removed: false
//     });

//     vm.expectCall(dripVaultMock, supportAmount, abi.encodeWithSelector(IDripVault.deposit.selector));

//     expectExactEmit();
//     emit IObeliskRegistry.Supported(1, user, supportAmount);
//     underTest.supportYieldPool{ value: supportAmount }();

//     assertEq(abi.encode(underTest.getSupporter(1)), abi.encode(expectedSupporter));
//     assertEq(underTest.supportId(), 1);
//   }

//   function test_retrieveSupportToYieldPool_whenNotSupporter_thenReverts() external prankAs(user) {
//     vm.expectRevert(IObeliskRegistry.NotSupporterDepositor.selector);
//     underTest.retrieveSupportToYieldPool(1);
//   }

//   function test_retrieveSupportToYieldPool_whenSupportNotFinished_thenReverts() external prankAs(user) {
//     underTest.supportYieldPool{ value: 1 }();

//     skip(underTest.SUPPORT_LOCK_DURATION() - 1);

//     vm.expectRevert(IObeliskRegistry.SupportNotFinished.selector);
//     underTest.retrieveSupportToYieldPool(1);
//   }

//   function test_retrieveSupportToYieldPool_whenAlreadyRemoved_thenReverts() external prankAs(user) {
//     underTest.supportYieldPool{ value: 1 }();

//     skip(underTest.SUPPORT_LOCK_DURATION());
//     underTest.retrieveSupportToYieldPool(1);

//     vm.expectRevert(IObeliskRegistry.AlreadyRemoved.selector);
//     underTest.retrieveSupportToYieldPool(1);
//   }

//   function test_retrieveSupportToYieldPool_thenWithdrawsFromDripVault() external prankAs(user) {
//     uint256 supportAmount = 13.32e18;
//     underTest.supportYieldPool{ value: supportAmount }();

//     skip(underTest.SUPPORT_LOCK_DURATION());

//     vm.expectCall(dripVaultMock, abi.encodeWithSelector(IDripVault.withdraw.selector, user, supportAmount));

//     expectExactEmit();
//     emit IObeliskRegistry.SupportRetrieved(1, user, supportAmount);
//     underTest.retrieveSupportToYieldPool(1);

//     assertTrue(underTest.getSupporter(1).removed);
//   }

//   function test_setTickerLogic_asNonOwner_thenReverts() external prankAs(user) {
//     vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
//     underTest.setTickerLogic("ticker", generateAddress("TickerPool"));
//   }

//   function test_setTickerLogic_thenUpdatesTickerPool() external prankAs(owner) {
//     address expectedPool = generateAddress("TickerPool");
//     string memory ticker = "Super Ticker";

//     expectExactEmit();
//     emit IObeliskRegistry.TickerLogicSet(ticker, expectedPool);
//     underTest.setTickerLogic(ticker, expectedPool);

//     assertEq(underTest.getTickerLogic(ticker), expectedPool);
//   }

//   function test_addNewGenesisTicker_asNonOwner_thenReverts() external prankAs(user) {
//     string memory ticker = "Ticker";

//     vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
//     underTest.addNewGenesisTicker(ticker, mockGenesisWrappedToken, mockGenesisKey);
//   }

//   function test_addNewGenesisTicker_whenTickerExists_thenReverts() external prankAs(owner) {
//     string memory ticker = "Ticker";

//     underTest.setTickerLogic(ticker, generateAddress("TickerPool"));

//     vm.expectRevert(IObeliskRegistry.TickerAlreadyExists.selector);
//     underTest.addNewGenesisTicker(ticker, mockGenesisWrappedToken, mockGenesisKey);
//   }

//   function test_addNewGenesisTicker_thenCreatesNewTickerPool() external prankAs(owner) {
//     string memory ticker = "Ticker";

//     vm.expectEmit(true, false, false, false);
//     emit IObeliskRegistry.NewGenesisTickerCreated(ticker, address(0));
//     LiteTickerFarmPool pool =
//       LiteTickerFarmPool(underTest.addNewGenesisTicker(ticker, mockGenesisWrappedToken, mockGenesisKey));

//     assertEq(underTest.getTickerLogic(ticker), address(pool));

//     assertEq(pool.owner(), owner);
//     assertEq(address(pool.registry()), address(underTest));
//     assertEq(address(pool.genesisKey()), mockGenesisKey);
//     assertEq(address(pool.rewardToken()), mockGenesisWrappedToken);
//   }

//   function test_createContract_whenFailedDeployment_thenReverts() external {
//     vm.expectRevert(IObeliskRegistry.FailedDeployment.selector);
//     underTest.exposed_createContract(type(ObeliskRegistry).creationCode);
//   }

//   function test_allowNewCollection_asNonOwner_thenReverts() external prankAs(user) {
//     vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
//     underTest.allowNewCollection(collectionMock);
//   }

//   function test_allowNewCollection_whenTooManyEth_thenReverts() external pranking {
//     changePrank(user);
//     underTest.addToCollection{ value: REQUIRED_ETH_TO_ENABLE_COLLECTION }(collectionMock);

//     changePrank(owner);
//     vm.expectRevert(IObeliskRegistry.TooManyEth.selector);
//     underTest.allowNewCollection(collectionMock);
//   }

//   function test_allowNewCollection_whenNoContribution_thenAddsToAllowedCollections() external prankAs(owner) {
//     changePrank(owner);
//     vm.expectEmit(true, false, false, false);
//     emit IObeliskRegistry.WrappedNFTCreated(collectionMock, address(0));
//     underTest.allowNewCollection(collectionMock);

//     assertEq(underTest.getCollection(collectionMock).contributionBalance, REQUIRED_ETH_TO_ENABLE_COLLECTION);
//   }

//   function test_allowNewCollection_whenSomeContribution_thenAddsToAllowedCollections() external pranking {
//     changePrank(user);
//     underTest.addToCollection{ value: 25e18 }(collectionMock);

//     changePrank(owner);
//     vm.expectEmit(true, false, false, false);
//     emit IObeliskRegistry.WrappedNFTCreated(collectionMock, address(0));
//     underTest.allowNewCollection(collectionMock);

//     assertEq(underTest.getCollection(collectionMock).contributionBalance, REQUIRED_ETH_TO_ENABLE_COLLECTION);
//   }
// }

// contract ObeliskRegistryHarness is ObeliskRegistry {
//   constructor(
//     address _owner,
//     address _treasury,
//     address _hct,
//     address _nftPass,
//     address _dripVault,
//     address _dataAsserter
//   ) ObeliskRegistry(_owner, _treasury, _hct, _nftPass, _dripVault, _dataAsserter) { }

//   function exposed_createWrappedNFT(address _collection, uint256 _totalSupply, uint32 _blockOfCreation)
//     external
//     returns (address addr_)
//   {
//     addr_ = _createWrappedNFT(_collection, _totalSupply, _blockOfCreation);
//   }

//   function exposed_createContract(bytes memory bytecode) external returns (address addr_) {
//     addr_ = _createContract(bytecode);
//   }
// }

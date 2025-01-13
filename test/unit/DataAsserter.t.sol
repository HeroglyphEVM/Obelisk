// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "test/base/BaseTest.t.sol";
import { DataAsserter, IDataAsserter } from "src/services/DataAsserter.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { OptimisticOracleV3Interface } from
  "src/vendor/UMA/OptimisticOracleV3Interface.sol";
import { AncillaryData as ClaimData } from "src/vendor/UMA/AncillaryData.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract DataAsserterTest is BaseTest {
  address private constant DEFAULT_IDENTIFIER = address(0x0282);
  uint256 private constant BOND = 0.01 ether;
  uint256 private SECURITY_DEPOSIT;

  DataAsserterHarness private underTest;

  address private owner;
  address private user;
  address private treasuryMock;
  MockERC20 private defaultCurrencyMock;
  address private optimisticOracleV3Mock;
  address private obeliskRegistryMock;

  function setUp() public {
    _generateMocks();
    _setupDefaultCalls();

    underTest = new DataAsserterHarness(
      owner,
      treasuryMock,
      address(defaultCurrencyMock),
      optimisticOracleV3Mock,
      obeliskRegistryMock
    );

    SECURITY_DEPOSIT = underTest.securityDeposit();
  }

  function _generateMocks() internal {
    owner = generateAddress("owner");
    user = generateAddress("user");
    treasuryMock = generateAddress("treasuryMock");
    defaultCurrencyMock = new MockERC20("defaultCurrencyMock", "DC", 18);
    optimisticOracleV3Mock = generateAddress("optimisticOracleV3Mock");
    obeliskRegistryMock = generateAddress("obeliskRegistryMock");

    defaultCurrencyMock.mint(user, 1000 ether);
  }

  function _setupDefaultCalls() internal {
    vm.mockCall(
      optimisticOracleV3Mock,
      abi.encodeWithSelector(OptimisticOracleV3Interface.defaultIdentifier.selector),
      abi.encode(DEFAULT_IDENTIFIER)
    );

    vm.mockCall(
      optimisticOracleV3Mock,
      abi.encodeWithSelector(OptimisticOracleV3Interface.getMinimumBond.selector),
      abi.encode(BOND)
    );
  }

  function test_constructor() public {
    underTest = new DataAsserterHarness(
      owner,
      treasuryMock,
      address(defaultCurrencyMock),
      optimisticOracleV3Mock,
      obeliskRegistryMock
    );

    assertEq(underTest.owner(), owner);
    assertEq(underTest.treasury(), treasuryMock);
    assertEq(address(underTest.defaultCurrency()), address(defaultCurrencyMock));
    assertEq(address(underTest.oo()), optimisticOracleV3Mock);
    assertEq(address(underTest.obeliskRegistry()), obeliskRegistryMock);

    assertEq(
      defaultCurrencyMock.allowance(address(underTest), address(optimisticOracleV3Mock)),
      type(uint256).max
    );

    assertEq(underTest.securityDeposit(), SECURITY_DEPOSIT);
  }

  function test_assertDataFor_whenCollectionIsAlreadyAllowed_thenReverts() external {
    address collection = generateAddress("collection");
    mockCall_getCollection(collection, true);

    vm.expectRevert(IDataAsserter.CollectionIsAlreadyAllowed.selector);
    underTest.assertDataFor(collection, 1, 1);
  }

  function test_assertDataFor_thenCreateAssertion() external prankAs(user) {
    address collection = generateAddress("collection");
    uint32 deploymentTimestamp = 9_387_272;
    uint128 currentSupply = 7533;
    bytes32 assertionId = bytes32("92u1093u21");
    uint64 assertionLiveness = underTest.assertionLiveness();

    uint256 securityDeposit = underTest.securityDeposit();
    uint256 balanceBefore = defaultCurrencyMock.balanceOf(address(underTest));

    bytes32 dataId = bytes32(abi.encode(collection, user, block.timestamp));

    bytes memory assertionData = abi.encodePacked(
      "NFT contract: 0x",
      ClaimData.toUtf8BytesAddress(collection),
      " on Ethereum mainnet was deployed at timestamp: ",
      ClaimData.toUtf8BytesUint(deploymentTimestamp),
      " and has a total supply of: ",
      ClaimData.toUtf8BytesUint(currentSupply),
      " at the time of assertion."
    );

    mockCall_getCollection(collection, false);

    vm.mockCall(
      optimisticOracleV3Mock,
      abi.encodeWithSelector(
        OptimisticOracleV3Interface.assertTruth.selector,
        assertionData,
        user,
        address(underTest),
        address(0),
        assertionLiveness,
        address(defaultCurrencyMock),
        BOND,
        DEFAULT_IDENTIFIER,
        bytes32(0)
      ),
      abi.encode(assertionId)
    );

    vm.expectCall(
      optimisticOracleV3Mock,
      abi.encodeWithSelector(OptimisticOracleV3Interface.assertTruth.selector)
    );

    expectExactEmit();
    emit IDataAsserter.DataAsserted(
      dataId,
      assertionId,
      user,
      IDataAsserter.CollectionAssertionData(
        collection, deploymentTimestamp, currentSupply
      )
    );
    underTest.assertDataFor(collection, deploymentTimestamp, currentSupply);

    assertEq(
      defaultCurrencyMock.balanceOf(address(underTest)),
      balanceBefore + underTest.getAssertionCost()
    );

    (
      IDataAsserter.AssertionData memory response,
      IDataAsserter.CollectionAssertionData memory collectionResponse
    ) = underTest.getData(assertionId);

    assertEq(response.dataId, dataId);
    assertEq(response.securityDeposit, securityDeposit);
    assertEq(response.asserter, user);
    assertEq(response.hasBeenResolved, false);
    assertEq(response.hasBeenDisputed, false);
    assertEq(response.failedToCallObeliskRegistry, false);

    assertEq(collectionResponse.collection, collection);
    assertEq(collectionResponse.deploymentTimestamp, deploymentTimestamp);
    assertEq(collectionResponse.currentSupply, currentSupply);
  }

  function test_assertionResolvedCallback_whenNotOptimisticOracle_thenReverts() external {
    vm.expectRevert(IDataAsserter.NotOptimisticOracle.selector);
    underTest.assertionResolvedCallback(bytes32(0), false);
  }

  function test_assertionResolvedCallback_givenAssertionIsNotTrusthfully_thenTransferToTreasury(
  ) external prankAs(optimisticOracleV3Mock) {
    address collection = generateAddress("collection");
    uint32 deploymentTimestamp = 9_387_272;
    uint128 currentSupply = 7533;

    bytes32 assertionId = underTest.exposed_generateDataAssertion(
      user, collection, deploymentTimestamp, currentSupply
    );

    defaultCurrencyMock.mint(address(underTest), SECURITY_DEPOSIT);
    underTest.assertionResolvedCallback(assertionId, false);

    assertEq(defaultCurrencyMock.balanceOf(treasuryMock), SECURITY_DEPOSIT);
    assertTrue(underTest.getAssertionData(assertionId).hasBeenResolved);
    assertTrue(underTest.getAssertionData(assertionId).hasBeenDisputed);
    assertFalse(underTest.getAssertionData(assertionId).failedToCallObeliskRegistry);
  }

  function test_assertionResolvedCallback_givenAssertionIsTrusthfully_whenFailedToCallObeliskRegistry_thenSavesAssertion(
  ) external prankAs(optimisticOracleV3Mock) {
    address collection = generateAddress("collection");
    uint32 deploymentTimestamp = 9_387_272;
    uint128 currentSupply = 7533;

    bytes32 assertionId = underTest.exposed_generateDataAssertion(
      user, collection, deploymentTimestamp, currentSupply
    );

    defaultCurrencyMock.mint(address(underTest), SECURITY_DEPOSIT);

    uint256 balanceBefore = defaultCurrencyMock.balanceOf(user);

    mockCall_allowNewCollection(true);
    mockCall_getCollection(collection, false);
    underTest.assertionResolvedCallback(assertionId, true);

    assertEq(defaultCurrencyMock.balanceOf(treasuryMock), 0);
    assertEq(defaultCurrencyMock.balanceOf(user), balanceBefore + SECURITY_DEPOSIT);
    assertTrue(underTest.getAssertionData(assertionId).hasBeenResolved);
    assertFalse(underTest.getAssertionData(assertionId).hasBeenDisputed);
    assertTrue(underTest.getAssertionData(assertionId).failedToCallObeliskRegistry);
  }

  function test_assertionResolvedCallback_givenAssertionIsTrusthfully_whenSuccessfullyCallsObeliskRegistry_thenSavesAssertion(
  ) external prankAs(optimisticOracleV3Mock) {
    address collection = generateAddress("collection");
    uint32 deploymentTimestamp = 9_387_272;
    uint128 currentSupply = 7533;

    bytes32 assertionId = underTest.exposed_generateDataAssertion(
      user, collection, deploymentTimestamp, currentSupply
    );

    defaultCurrencyMock.mint(address(underTest), SECURITY_DEPOSIT);

    uint256 balanceBefore = defaultCurrencyMock.balanceOf(user);

    mockCall_allowNewCollection(false);
    mockCall_getCollection(collection, false);
    underTest.assertionResolvedCallback(assertionId, true);

    assertEq(defaultCurrencyMock.balanceOf(treasuryMock), 0);
    assertEq(defaultCurrencyMock.balanceOf(user), balanceBefore + SECURITY_DEPOSIT);
    assertTrue(underTest.getAssertionData(assertionId).hasBeenResolved);
    assertFalse(underTest.getAssertionData(assertionId).hasBeenDisputed);
    assertFalse(underTest.getAssertionData(assertionId).failedToCallObeliskRegistry);
  }

  function test_retryCallingObeliskRegistry_whenAssertionIsNotResolved_thenReverts()
    external
  {
    vm.expectRevert(IDataAsserter.AssertionNotResolved.selector);
    underTest.retryCallingObeliskRegistry(bytes32(0));
  }

  function test_retryCallingObeliskRegistry_whenAssertionIsDisputed_thenReverts()
    external
    prankAs(optimisticOracleV3Mock)
  {
    address collection = generateAddress("collection");
    bytes32 assertionId =
      underTest.exposed_generateDataAssertion(user, collection, 9_387_272, 7533);

    defaultCurrencyMock.mint(address(underTest), SECURITY_DEPOSIT);
    underTest.assertionResolvedCallback(assertionId, false);

    vm.expectRevert(IDataAsserter.DisputedAssertion.selector);
    underTest.retryCallingObeliskRegistry(assertionId);
  }

  function test_retryCallingObeliskRegistry_whenNothingToRetry_thenReverts()
    external
    prankAs(optimisticOracleV3Mock)
  {
    address collection = generateAddress("collection");
    bytes32 assertionId =
      underTest.exposed_generateDataAssertion(user, collection, 9_387_272, 7533);

    defaultCurrencyMock.mint(address(underTest), SECURITY_DEPOSIT);
    mockCall_getCollection(collection, false);
    mockCall_allowNewCollection(false);
    underTest.assertionResolvedCallback(assertionId, true);

    vm.expectRevert(IDataAsserter.NothingToRetry.selector);
    underTest.retryCallingObeliskRegistry(assertionId);
  }

  function test_retryCallingObeliskRegistry_whenRetry_thenCallsObeliskRegistry()
    external
    prankAs(optimisticOracleV3Mock)
  {
    address collection = generateAddress("collection");
    bytes32 assertionId =
      underTest.exposed_generateDataAssertion(user, collection, 9_387_272, 7533);

    defaultCurrencyMock.mint(address(underTest), SECURITY_DEPOSIT);
    mockCall_getCollection(collection, false);
    mockCall_allowNewCollection(true);
    underTest.assertionResolvedCallback(assertionId, true);

    mockCall_allowNewCollection(false);
    underTest.retryCallingObeliskRegistry(assertionId);

    assertFalse(underTest.getAssertionData(assertionId).failedToCallObeliskRegistry);
  }

  function test_updateSecurityDeposit_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updateSecurityDeposit(1 ether);
  }

  function test_updateSecurityDeposit_whenOwner_thenUpdatesSecurityDeposit()
    external
    prankAs(owner)
  {
    uint256 newSecurityDeposit = 1 ether;

    expectExactEmit();
    emit IDataAsserter.SecurityDepositUpdated(newSecurityDeposit);
    underTest.updateSecurityDeposit(newSecurityDeposit);

    assertEq(underTest.securityDeposit(), newSecurityDeposit);
  }

  function test_updateTreasury_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updateTreasury(treasuryMock);
  }

  function test_updateTreasury_whenOwner_thenUpdatesTreasury() external prankAs(owner) {
    expectExactEmit();
    emit IDataAsserter.TreasuryUpdated(treasuryMock);

    underTest.updateTreasury(treasuryMock);
    assertEq(underTest.treasury(), treasuryMock);
  }

  function test_updateAssertionLiveness_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updateAssertionLiveness(1 days);
  }

  function test_updateAssertionLiveness_whenAssertionLivenessIsTooShort_thenReverts()
    external
    prankAs(owner)
  {
    vm.expectRevert(IDataAsserter.AssertionLivenessTooShort.selector);
    underTest.updateAssertionLiveness(1 days - 1);
  }

  function test_updateAssertionLiveness_whenAssertionLivenessIsTooShort_thenUpdatesAssertionLiveness(
  ) external prankAs(owner) {
    uint64 newAssertionLiveness = 1 days;

    expectExactEmit();
    emit IDataAsserter.AssertionLivenessUpdated(newAssertionLiveness);
    underTest.updateAssertionLiveness(newAssertionLiveness);

    assertEq(underTest.assertionLiveness(), newAssertionLiveness);
  }

  function mockCall_getCollection(address _collection, bool _allowed) internal {
    vm.mockCall(
      obeliskRegistryMock,
      abi.encodeWithSelector(IObeliskRegistry.getCollection.selector, _collection),
      abi.encode(
        IObeliskRegistry.Collection({
          totalSupply: 0,
          contributionBalance: 0,
          wrappedVersion: address(0),
          collectionStartedUnixTime: 0,
          allowed: _allowed,
          premium: false
        })
      )
    );
  }

  function mockCall_allowNewCollection(bool _reverts) internal {
    if (_reverts) {
      vm.mockCallRevert(
        obeliskRegistryMock,
        abi.encodeWithSelector(IObeliskRegistry.allowNewCollection.selector),
        "revert"
      );
    } else {
      vm.mockCall(
        obeliskRegistryMock,
        abi.encodeWithSelector(IObeliskRegistry.allowNewCollection.selector),
        abi.encode(true)
      );
    }
  }
}

contract DataAsserterHarness is DataAsserter {
  uint256 private index;

  constructor(
    address _owner,
    address _treasury,
    address _defaultCurrency,
    address _oo,
    address _obeliskRegistry
  ) DataAsserter(_owner, _treasury, _defaultCurrency, _oo, _obeliskRegistry) { }

  function exposed_generateDataAssertion(
    address _user,
    address _collection,
    uint32 _deploymentTimestamp,
    uint128 _currentSupply
  ) external returns (bytes32 assertionId) {
    assertionId = bytes32(abi.encodePacked(index++));

    bytes32 dataId = bytes32(abi.encode(_collection, _user, block.timestamp));

    CollectionAssertionData memory collectionAssertionData =
      CollectionAssertionData(_collection, _deploymentTimestamp, _currentSupply);

    assertionsData[assertionId] =
      AssertionData(dataId, securityDeposit, _user, false, false, false);
    collectionAssertionsData[dataId] = collectionAssertionData;

    return assertionId;
  }
}

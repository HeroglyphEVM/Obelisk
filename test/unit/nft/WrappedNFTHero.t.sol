// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "test/base/BaseTest.t.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";

import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
import { WrappedNFTHero, IWrappedNFTHero } from "src/services/nft/WrappedNFTHero.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";
import { IObeliskNFT } from "src/interfaces/IObeliskNFT.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract WrappedNFTHeroTest is BaseTest {
  uint128 private constant ACTIVE_SUPPLY = 10_000e18;
  uint256 private UNLOCK_SLOT_BPS = 2500;
  uint256 private BPS = 10_000;
  uint32 private TEST_UNIX_TIME = 1_726_850_955;
  uint32 private YEAR_IN_SECONDS = 31_557_600;
  uint256 private SLOT_PRICE = 0.1e18;

  string private constant IDENTITY_NAME = "M";
  string private constant START_NAME = "@M #";
  bytes32 private constant IDENTITY = keccak256(abi.encode(IDENTITY_NAME));

  INFTPass.Metadata private mockNftPassMetadata = INFTPass.Metadata({
    name: IDENTITY_NAME,
    walletReceiver: generateAddress("Identity Receiver"),
    imageIndex: 1
  });

  INFTPass.Metadata private EMPTY_NFT_METADATA;

  address private mockHCT;
  address private mockNFTPass;
  MockERC721 private mockInputCollection;
  address private mockObeliskRegistry;
  address private user;

  string[] private TICKERS = ["#Pool", "HenZ", "MyWorld"];
  address[] private POOL_TARGETS = [
    generateAddress("PoolTarget1"),
    generateAddress("PoolTarget2"),
    generateAddress("PoolTarget3")
  ];

  WrappedNFTHeroHarness private underTest;

  function setUp() external {
    vm.warp(TEST_UNIX_TIME);

    _prepareMocks();
    _mockCalls();

    mockInputCollection.mint(user, 1);
    mockInputCollection.mint(user, 2);

    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      false,
      22
    );
  }

  function _prepareMocks() internal {
    mockHCT = generateAddress("mockHCT");
    mockInputCollection = new MockERC721();
    mockObeliskRegistry = generateAddress("mockObeliskRegistry");
    user = generateAddress("User", 10e18);
  }

  function _mockCalls() internal {
    for (uint256 i = 0; i < POOL_TARGETS.length; i++) {
      vm.mockCall(
        POOL_TARGETS[i],
        abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector),
        abi.encode(true)
      );
      vm.mockCall(
        POOL_TARGETS[i],
        abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector),
        abi.encode(true)
      );
      vm.mockCall(
        mockObeliskRegistry,
        abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[i]),
        abi.encode(POOL_TARGETS[i])
      );
    }

    vm.mockCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector), abi.encode(true));
    vm.mockCall(
      mockHCT, abi.encodeWithSelector(IHCT.usesForRenaming.selector), abi.encode(true)
    );

    vm.mockCall(
      mockNFTPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.mockCall(
      mockNFTPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector),
      abi.encode(EMPTY_NFT_METADATA)
    );

    vm.mockCall(
      mockNFTPass, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1)
    );
  }

  function test_constructor_thenSetsValues() external {
    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      false,
      22
    );

    assertEq(address(underTest.HCT()), mockHCT);
    assertEq(address(underTest.NFT_PASS()), mockNFTPass);
    assertEq(address(underTest.INPUT_COLLECTION()), address(mockInputCollection));
    assertEq(address(underTest.obeliskRegistry()), mockObeliskRegistry);
    assertEq(underTest.freeSlots(), ACTIVE_SUPPLY * UNLOCK_SLOT_BPS / BPS);
    assertEq(
      underTest.FREE_SLOT_FOR_ODD(),
      uint256(keccak256(abi.encode(tx.origin, address(mockInputCollection)))) % 2 == 1
    );
    assertEq(
      underTest.COLLECTION_STARTED_UNIX_TIME(), uint32(block.timestamp) - YEAR_IN_SECONDS
    );
    assertFalse(underTest.PREMIUM());
    assertEq(underTest.ID(), 22);

    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      true,
      22
    );

    assertTrue(underTest.PREMIUM());
  }

  function test_wrap_whenAlreadyMinted_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.AlreadyMinted.selector));
    underTest.wrap(tokenId);
  }

  function test_wrap_givenETH_whenFreeSlotAvailable_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.FreeSlotAvailable.selector));
    underTest.wrap{ value: 1 }(tokenId);
  }

  function test_wrap_givenNoEth_whenNoFreeSlotAvailable_thenReverts()
    external
    prankAs(user)
  {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 2 : 1;

    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NoFreeSlots.selector));
    underTest.wrap(tokenId);
  }

  function test_wrap_whenNotNFTPassHolder_thenReverts() external prankAs(user) {
    vm.mockCall(
      mockNFTPass, abi.encodeWithSelector(IERC721.balanceOf.selector, user), abi.encode(0)
    );

    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotNFTPassHolder.selector));
    underTest.wrap(1);
  }

  function test_wrap_whenEmergencyWithdrawEnabled_thenReverts() external pranking {
    changePrank(mockObeliskRegistry);
    underTest.enableEmergencyWithdraw();

    changePrank(user);
    vm.expectRevert(
      abi.encodeWithSelector(IWrappedNFTHero.EmergencyModeIsActive.selector)
    );
    underTest.wrap(1);
  }

  function test_wrap_whenBuyingSlot_thenCallsObeliskRegistryAndWraps()
    external
    prankAs(user)
  {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 2 : 1;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    vm.expectCall(
      mockObeliskRegistry,
      SLOT_PRICE,
      abi.encodeWithSelector(IObeliskRegistry.onSlotBought.selector)
    );
    vm.expectCall(
      mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, user, expectingMultiplier)
    );

    expectExactEmit();
    emit IWrappedNFTHero.Wrapped(tokenId);
    expectExactEmit();
    emit IWrappedNFTHero.SlotBought(user, tokenId);
    underTest.wrap{ value: SLOT_PRICE }(tokenId);

    assertEq(underTest.ownerOf(tokenId), user);
    assertEq(mockInputCollection.ownerOf(tokenId), address(underTest));
    assertEq(underTest.getNFTData(tokenId).assignedMultiplier, expectingMultiplier);
  }

  function test_wrap_whenFreeSlotAvailable_thenWraps() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    uint256 freeSlotsBefore = underTest.freeSlots();
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    vm.expectCall(
      mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, user, expectingMultiplier)
    );

    expectExactEmit();
    emit IWrappedNFTHero.Wrapped(tokenId);
    expectExactEmit();
    emit IWrappedNFTHero.FreeSlotUsed(freeSlotsBefore - 1);

    underTest.wrap(tokenId);

    assertEq(underTest.ownerOf(tokenId), user);
    assertEq(mockInputCollection.ownerOf(tokenId), address(underTest));
    assertEq(underTest.getNFTData(tokenId).assignedMultiplier, expectingMultiplier);
    assertEq(underTest.freeSlots(), freeSlotsBefore - 1);
  }

  function test_rename_whenNameIsTooLong_thenReverts() external {
    string memory tooLongName = string(new bytes(30));

    vm.expectRevert(IWrappedNFTHero.InvalidNameLength.selector);
    underTest.rename(0, tooLongName);

    vm.expectRevert(IWrappedNFTHero.InvalidNameLength.selector);
    underTest.rename(0, "");
  }

  function test_rename_whenRenameRequirementsReverts_thenReverts() external {
    vm.expectRevert(IWrappedNFTHero.NotMinted.selector);
    underTest.rename(0, "Hello");
  }

  function test_rename_whenNoIdentityFound_thenReverts() external prankAs(user) {
    uint256 tokenId = 1;
    underTest.wrap(tokenId);

    vm.expectRevert(IWrappedNFTHero.InvalidWalletReceiver.selector);
    underTest.rename(tokenId, "Hello");

    changePrank(generateAddress("NotHolder"));
    vm.expectRevert(IWrappedNFTHero.NotNFTHolder.selector);
    underTest.rename(tokenId, "Hello");
  }

  function test_rename_whenNoTickers_thenRenames() external prankAs(user) {
    string memory newName = string.concat("NewName @", IDENTITY_NAME);
    uint256 tokenId = 23;

    mockInputCollection.mint(user, tokenId);
    underTest.wrap(tokenId);

    expectExactEmit();
    emit IObeliskNFT.NameUpdated(tokenId, newName);
    underTest.rename(tokenId, newName);

    assertEq(underTest.names(tokenId), newName);
    assertEq(abi.encode(underTest.nftPassAttached(tokenId)), abi.encode(IDENTITY_NAME));
  }

  function test_rename_givenTickers_thenAddsNewTickers() external prankAs(user) {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    mockInputCollection.mint(user, tokenId);
    underTest.wrap(tokenId);

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[0])
    );
    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualDeposit.selector,
        IDENTITY,
        tokenId,
        mockNftPassMetadata.walletReceiver
      )
    );

    underTest.rename(tokenId, newName);

    assertEq(underTest.names(tokenId), newName);
    assertEq(abi.encode(underTest.nftPassAttached(tokenId)), abi.encode(IDENTITY_NAME));
    assertEq(underTest.getLinkedTickers(tokenId)[0], POOL_TARGETS[0]);
    assertEq(underTest.getLinkedTickers(tokenId).length, 1);
  }

  function test_rename_whenHasTickers_thenRemovesOldTickers() external prankAs(user) {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    mockInputCollection.mint(user, tokenId);
    underTest.wrap(tokenId);

    underTest.rename(tokenId, newName);
    newName = string.concat(START_NAME, TICKERS[1]);

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualWithdraw.selector,
        IDENTITY,
        tokenId,
        mockNftPassMetadata.walletReceiver,
        false
      )
    );

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[1])
    );
    vm.expectCall(
      POOL_TARGETS[1],
      abi.encodeWithSelector(
        ILiteTicker.virtualDeposit.selector,
        IDENTITY,
        tokenId,
        mockNftPassMetadata.walletReceiver
      )
    );

    underTest.rename(tokenId, newName);
  }

  function test_rename_whenChangeIdentityReceiver_thenRemoveFromOldAndUpdatesToNew()
    external
    prankAs(user)
  {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    mockInputCollection.mint(user, tokenId);
    underTest.wrap(tokenId);
    underTest.rename(tokenId, newName);

    newName = string.concat(START_NAME, TICKERS[1]);

    address newReceiver = generateAddress("New Identity Receiver");
    mockNftPassMetadata.walletReceiver = newReceiver;

    vm.mockCall(
      mockNFTPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualWithdraw.selector, IDENTITY, tokenId, newReceiver, false
      )
    );

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[1])
    );
    vm.expectCall(
      POOL_TARGETS[1],
      abi.encodeWithSelector(
        ILiteTicker.virtualDeposit.selector, IDENTITY, tokenId, newReceiver
      )
    );

    underTest.rename(tokenId, newName);
    assertEq(abi.encode(underTest.nftPassAttached(tokenId)), abi.encode(IDENTITY_NAME));
  }

  function test_updateIdentity_whenNoIdentityFound_thenReverts() external {
    mockNftPassMetadata.walletReceiver = address(0);

    vm.mockCall(
      mockNFTPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.expectRevert(IWrappedNFTHero.InvalidWalletReceiver.selector);
    underTest.exposed_updateIdentity(0, "Hello");
  }

  function test_updateIdentity_thenUpdatesIdentity() external prankAs(user) {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    mockInputCollection.mint(user, tokenId);
    underTest.wrap(tokenId);

    underTest.rename(tokenId, newName);

    mockNftPassMetadata.walletReceiver = generateAddress("New Identity Receiver");

    vm.mockCall(
      mockNFTPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    underTest.exposed_updateIdentity(tokenId, newName);

    assertEq(abi.encode(underTest.nftPassAttached(tokenId)), abi.encode(IDENTITY_NAME));
  }

  function test_unwrap_whenNotMinted_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotMinted.selector));
    underTest.unwrap(1);
  }

  function test_unwrap_whenNotNFTHolder_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    changePrank(generateAddress("NotHolder"));
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotNFTHolder.selector));
    underTest.unwrap(tokenId);
  }

  function test_unwrap_thenUnwraps() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    expectExactEmit();
    emit IWrappedNFTHero.Unwrapped(tokenId);
    underTest.unwrap(tokenId);

    vm.expectRevert();
    underTest.ownerOf(tokenId);

    assertEq(mockInputCollection.ownerOf(tokenId), user);
    assertEq(bytes(underTest.names(tokenId)).length, 0);
    assertEq(underTest.getNFTData(tokenId).assignedMultiplier, 0);
    assertEq(underTest.getNFTData(tokenId).isMinted, false);
  }

  function test_unwrap_whenHasTikcers_thenRemoveTickersAndUnwraps()
    external
    prankAs(user)
  {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);
    underTest.rename(tokenId, newName);

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualWithdraw.selector,
        IDENTITY,
        tokenId,
        mockNftPassMetadata.walletReceiver,
        false
      )
    );

    underTest.unwrap(tokenId);

    assertEq(underTest.getLinkedTickers(tokenId).length, 0);
  }

  function test_unwrap_whenEmergencyWithdrawEnabled_thenIgnoresTickersAndUnwraps()
    external
    pranking
  {
    changePrank(user);
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);
    underTest.rename(tokenId, newName);

    changePrank(mockObeliskRegistry);
    underTest.enableEmergencyWithdraw();
    changePrank(user);

    vm.mockCallRevert(
      POOL_TARGETS[0],
      abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector),
      "Should not be called"
    );

    underTest.unwrap(tokenId);
    assertEq(mockInputCollection.ownerOf(tokenId), user);
  }

  function test_renameRequirements_whenNotMinted_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotMinted.selector));
    underTest.exposed_renameRequirements(1);
  }

  function test_renameRequirements_whenNotNFTHolder_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    changePrank(generateAddress("NotHolder"));
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotNFTHolder.selector));
    underTest.exposed_renameRequirements(1);
  }

  function test_renameRequirements_whenCorrect_thenRenames() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.usesForRenaming.selector, user));
    underTest.exposed_renameRequirements(1);
  }

  function test_renameRequirements_whenFirstRenameAndPremium_thenDoesNotHTC()
    external
    prankAs(user)
  {
    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      true,
      1
    );

    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    vm.mockCallRevert(
      mockHCT,
      abi.encodeWithSelector(IHCT.usesForRenaming.selector, user),
      "Should not be called"
    );
    underTest.exposed_renameRequirements(1);

    vm.clearMockedCalls();
    _mockCalls();

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.usesForRenaming.selector, user));
    underTest.exposed_renameRequirements(1);
  }

  function test_claimRequirements_whenNotHolder_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    underTest.wrap(tokenId);

    changePrank(generateAddress("NotHolder"));

    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotNFTHolder.selector));
    underTest.exposed_claimRequirements(1);
  }

  function test_claimRequirements_whenHolder_thenReturnsTrue() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    underTest.wrap(tokenId);

    assertTrue(underTest.exposed_claimRequirements(1));
  }

  function test_updateMultiplier_whenNotNFTHolder_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    underTest.wrap(tokenId);

    changePrank(generateAddress("NotHolder"));
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotNFTHolder.selector));
    underTest.updateMultiplier(tokenId);
  }

  function test_updateMultiplier_whenSameMultiplier_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    underTest.wrap(tokenId);

    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.SameMultiplier.selector));
    underTest.updateMultiplier(tokenId);
  }

  function test_updateMultiplier_whenIncreased_thenAddsPower() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    underTest.wrap(tokenId);

    uint256 multiplier = underTest.getWrapperMultiplier();

    skip(YEAR_IN_SECONDS + 1);

    uint256 newMultiplier = underTest.getWrapperMultiplier();

    vm.expectCall(
      mockHCT,
      abi.encodeWithSelector(IHCT.addPower.selector, user, newMultiplier - multiplier)
    );
    underTest.updateMultiplier(tokenId);
  }

  function test_enableEmergencyWithdraw_whenNotObeliskRegistry_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotObeliskRegistry.selector));
    underTest.enableEmergencyWithdraw();
  }

  function test_enableEmergencyWithdraw_thenEnables()
    external
    prankAs(mockObeliskRegistry)
  {
    expectExactEmit();
    emit IWrappedNFTHero.EmergencyWithdrawEnabled();
    underTest.enableEmergencyWithdraw();

    assertTrue(underTest.emergencyWithdrawEnabled());
  }

  function test_mint_thenAddPower() external {
    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    vm.expectCall(
      mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, user, expectingMultiplier)
    );
    underTest.exposed_mint(user, tokenId);
  }

  function test_burn_thenRemovePower() external {
    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    underTest.exposed_mint(user, tokenId);

    vm.expectCall(
      mockHCT,
      abi.encodeWithSelector(IHCT.removePower.selector, user, expectingMultiplier)
    );
    underTest.exposed_burn(tokenId);

    assertEq(underTest.getNFTData(tokenId).assignedMultiplier, 0);
  }

  function test_burn_whenMultiplierChanged_thenRemovesCorrectPower() external {
    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    underTest.exposed_mint(user, tokenId);

    skip(YEAR_IN_SECONDS);

    vm.expectCall(
      mockHCT,
      abi.encodeWithSelector(IHCT.removePower.selector, user, expectingMultiplier)
    );
    underTest.exposed_burn(tokenId);

    assertGt(underTest.getWrapperMultiplier(), expectingMultiplier);
  }

  function test_transfer_whenCannotTransferUnwrapFirst_thenReverts()
    external
    prankAs(user)
  {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    vm.expectRevert(
      abi.encodeWithSelector(IWrappedNFTHero.CannotTransferUnwrapFirst.selector)
    );
    underTest.transferFrom(user, generateAddress("To"), tokenId);
  }

  function test_onERC721Received_whenCalled_thenReturnsSelector() external view {
    bytes4 expectedSelector = underTest.onERC721Received.selector;
    assertEq(
      underTest.onERC721Received(address(0), address(0), 0, bytes("")), expectedSelector
    );
  }
}

contract WrappedNFTHeroHarness is WrappedNFTHero {
  constructor(
    address _HCT,
    address _nftPass,
    address _inputCollection,
    address _obeliskRegistry,
    uint256 _currentSupply,
    uint32 _collectionStartedUnixTime,
    bool _premium,
    uint256 _id
  )
    WrappedNFTHero(
      _HCT,
      _nftPass,
      _inputCollection,
      _obeliskRegistry,
      _currentSupply,
      _collectionStartedUnixTime,
      _premium,
      _id
    )
  { }

  function exposed_renameRequirements(uint256 _tokenId) external {
    _renameRequirements(_tokenId);
  }

  function exposed_claimRequirements(uint256 _tokenId) external view returns (bool) {
    return _claimRequirements(_tokenId);
  }

  function exposed_mint(address _to, uint256 _tokenId) external {
    _mint(_to, _tokenId);
  }

  function exposed_updateIdentity(uint256 _tokenId, string memory _name) external {
    _updateIdentity(_tokenId, _name);
  }

  function exposed_burn(uint256 _tokenId) external {
    _burn(_tokenId);
  }
}

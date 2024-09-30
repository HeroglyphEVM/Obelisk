// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "test/base/BaseTest.t.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { IHCT } from "src/interfaces/IHCT.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";

import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
import { WrappedNFTHero, IWrappedNFTHero } from "src/services/nft/WrappedNFTHero.sol";

contract WrappedNFTHeroTest is BaseTest {
  uint128 private constant ACTIVE_SUPPLY = 10_000e18;
  uint256 private UNLOCK_SLOT_BPS = 2000;
  uint256 private BPS = 10_000;
  uint32 private TEST_UNIX_TIME = 1_726_850_955;
  uint32 private YEAR_IN_SECONDS = 31_557_600;
  uint256 private SLOT_PRICE = 0.1e18;

  address private mockHCT;
  address private mockNFTPass;
  MockERC721 private mockInputCollection;
  address private mockObeliskRegistry;
  address private user;

  string[] private tickers = ["#Pool", "HenZ", "MyWorld"];
  address[] private poolTargets =
    [generateAddress("PoolTarget1"), generateAddress("PoolTarget2"), generateAddress("PoolTarget3")];

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
      false
    );
  }

  function _prepareMocks() internal {
    mockHCT = generateAddress("mockHCT");
    mockInputCollection = new MockERC721();
    mockObeliskRegistry = generateAddress("mockObeliskRegistry");
    user = generateAddress("User", 10e18);
  }

  function _mockCalls() internal {
    for (uint256 i = 0; i < poolTargets.length; i++) {
      vm.mockCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector), abi.encode(true));
      vm.mockCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector), abi.encode(true));
      vm.mockCall(
        mockObeliskRegistry,
        abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, tickers[i]),
        abi.encode(poolTargets[i])
      );
    }

    vm.mockCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector), abi.encode(true));
    vm.mockCall(mockHCT, abi.encodeWithSelector(IHCT.usesForRenaming.selector), abi.encode(true));
  }

  function test_constructor_thenSetsValues() external {
    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      false
    );

    assertEq(address(underTest.HCT()), mockHCT);
    assertEq(address(underTest.NFT_PASS()), mockNFTPass);
    assertEq(address(underTest.INPUT_COLLECTION()), address(mockInputCollection));
    assertEq(address(underTest.obeliskRegistry()), mockObeliskRegistry);
    assertEq(underTest.freeSlots(), ACTIVE_SUPPLY * UNLOCK_SLOT_BPS / BPS);
    assertEq(
      underTest.FREE_SLOT_FOR_ODD(), uint256(keccak256(abi.encode(tx.origin, address(mockInputCollection)))) % 2 == 1
    );
    assertEq(underTest.COLLECTION_STARTED_UNIX_TIME(), uint32(block.timestamp) - YEAR_IN_SECONDS);
    assertFalse(underTest.PREMIUM());

    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      true
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

  function test_givenNoEth_whenNoFreeSlotAvailable_thenReverts() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 2 : 1;

    vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NoFreeSlots.selector));
    underTest.wrap(tokenId);
  }

  function test_wrap_whenBuyingSlot_thenCallsObeliskRegistryAndWraps() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 2 : 1;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    vm.expectCall(mockObeliskRegistry, SLOT_PRICE, abi.encodeWithSelector(IObeliskRegistry.onSlotBought.selector));
    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, user, expectingMultiplier));

    expectExactEmit();
    emit IWrappedNFTHero.SlotBought(user, tokenId);
    expectExactEmit();
    emit IWrappedNFTHero.Wrapped(tokenId);
    underTest.wrap{ value: SLOT_PRICE }(tokenId);

    assertEq(underTest.ownerOf(tokenId), user);
    assertEq(mockInputCollection.ownerOf(tokenId), address(underTest));
    assertEq(underTest.assignedMultipler(tokenId), expectingMultiplier);
  }

  function test_wrap_whenFreeSlotAvailable_thenWraps() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    uint256 freeSlotsBefore = underTest.freeSlots();
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, user, expectingMultiplier));

    expectExactEmit();
    emit IWrappedNFTHero.FreeSlotUsed(freeSlotsBefore - 1);
    expectExactEmit();
    emit IWrappedNFTHero.Wrapped(tokenId);

    underTest.wrap(tokenId);

    assertEq(underTest.ownerOf(tokenId), user);
    assertEq(mockInputCollection.ownerOf(tokenId), address(underTest));
    assertEq(underTest.assignedMultipler(tokenId), expectingMultiplier);
    assertEq(underTest.freeSlots(), freeSlotsBefore - 1);
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
    assertEq(underTest.assignedMultipler(tokenId), 0);
    assertEq(underTest.isMinted(tokenId), false);
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

  function test_renameRequirements_whenFirstRenameAndPremium_thenDoesNotHTC() external prankAs(user) {
    underTest = new WrappedNFTHeroHarness(
      mockHCT,
      mockNFTPass,
      address(mockInputCollection),
      mockObeliskRegistry,
      ACTIVE_SUPPLY,
      uint32(block.timestamp) - YEAR_IN_SECONDS,
      true
    );

    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;

    underTest.wrap(tokenId);

    vm.mockCallRevert(mockHCT, abi.encodeWithSelector(IHCT.usesForRenaming.selector, user), "Should not be called");
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
    assertFalse(underTest.exposed_claimRequirements(1));
  }

  function test_claimRequirements_whenHolder_thenReturnsTrue() external prankAs(user) {
    uint256 tokenId = underTest.FREE_SLOT_FOR_ODD() ? 1 : 2;
    underTest.wrap(tokenId);

    assertTrue(underTest.exposed_claimRequirements(1));
  }

  function test_mint_thenAddPower() external {
    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, user, expectingMultiplier));
    underTest.exposed_mint(user, tokenId);
  }

  function test_burn_thenRemovePower() external {
    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    underTest.exposed_mint(user, tokenId);

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.removePower.selector, user, expectingMultiplier));
    underTest.exposed_burn(tokenId);

    assertEq(underTest.assignedMultipler(tokenId), 0);
  }

  function test_burn_whenMultiplierChanged_thenRemovesCorrectPower() external {
    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    underTest.exposed_mint(user, tokenId);

    skip(YEAR_IN_SECONDS);

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.removePower.selector, user, expectingMultiplier));
    underTest.exposed_burn(tokenId);

    assertGt(underTest.getWrapperMultiplier(), expectingMultiplier);
  }

  function test_transfer_thenRemoveFromPowerAndAddToPower() external {
    address from = generateAddress("From");
    address to = generateAddress("To");

    uint256 tokenId = 33;
    uint256 expectingMultiplier = 1 * underTest.RATE_PER_YEAR();

    underTest.exposed_mint(from, tokenId);

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.removePower.selector, from, expectingMultiplier));
    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, to, expectingMultiplier));

    vm.prank(from);
    underTest.transferFrom(from, to, tokenId);

    assertEq(underTest.assignedMultipler(tokenId), expectingMultiplier);
    assertEq(underTest.ownerOf(tokenId), to);
  }

  function test_transfer_whenMultiplierChanged_thenRemovesCorrectPowerAndAddsNewPower() external {
    uint256 tokenId = 33;
    uint256 expectingRemovingMultiplier = 1 * underTest.RATE_PER_YEAR();
    uint256 expectingAddingMultiplier = 2 * underTest.RATE_PER_YEAR();

    address from = generateAddress("From");
    address to = generateAddress("To");

    underTest.exposed_mint(from, tokenId);
    skip(YEAR_IN_SECONDS);

    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.removePower.selector, from, expectingRemovingMultiplier));
    vm.expectCall(mockHCT, abi.encodeWithSelector(IHCT.addPower.selector, to, expectingAddingMultiplier));

    vm.prank(from);
    underTest.transferFrom(from, to, tokenId);

    assertEq(underTest.assignedMultipler(tokenId), expectingAddingMultiplier);
    assertEq(underTest.ownerOf(tokenId), to);
  }

  function test_onERC721Received_whenCalled_thenReturnsSelector() external view {
    bytes4 expectedSelector = underTest.onERC721Received.selector;
    assertEq(underTest.onERC721Received(address(0), address(0), 0, bytes("")), expectedSelector);
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
    bool _premium
  )
    WrappedNFTHero(
      _HCT,
      _nftPass,
      _inputCollection,
      _obeliskRegistry,
      _currentSupply,
      _collectionStartedUnixTime,
      _premium
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

  function exposed_burn(uint256 _tokenId) external {
    _burn(_tokenId);
  }
}

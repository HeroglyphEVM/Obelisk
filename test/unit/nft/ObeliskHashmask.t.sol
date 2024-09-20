// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "test/base/BaseTest.t.sol";

import { ObeliskHashmask, IObeliskHashmask } from "src/services/nft/ObeliskHashmask.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { IHashmask, IERC721 } from "src/vendor/IHashmask.sol";
import { FailOnReceive } from "test/mock/contract/FailOnReceive.t.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { ITickerNFT } from "src/interfaces/ITickerNFT.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ObeliskHashmaskTest is BaseTest {
  string[] private TICKERS = ["Hello", "megaPool", "Bobby"];
  address[] private POOL_TARGETS = [generateAddress("Pool A"), generateAddress("Pool B"), generateAddress("Pool C")];
  uint256 private HASH_MASK_ID = 33;

  address private owner;
  address private user;
  address private hashmaskUser;
  address private treasury;
  address private mockObeliskRegistry;
  address private mockHashmask;

  uint256 private activationPrice;

  ObeliskHashmaskHarness private underTest;

  function setUp() external {
    _setupMockVariables();
    _setupMockCalls();

    underTest = new ObeliskHashmaskHarness(mockHashmask, owner, mockObeliskRegistry, address(0), treasury);
    activationPrice = underTest.activationPrice();
  }

  function _setupMockVariables() internal {
    owner = generateAddress("OWNER");
    treasury = generateAddress("TREASURY");
    user = generateAddress("USER", 100e18);
    hashmaskUser = generateAddress("HASHMASK_USER", 100e18);
    mockObeliskRegistry = generateAddress("MOCK_OBELISK_REGISTRY");
    mockHashmask = generateAddress("MOCK_HASHMASK");
  }

  function _setupMockCalls() internal {
    for (uint256 i = 0; i < TICKERS.length; i++) {
      vm.mockCall(
        mockObeliskRegistry,
        abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[i]),
        abi.encode(POOL_TARGETS[i])
      );

      vm.mockCall(POOL_TARGETS[i], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector), abi.encode(true));
      vm.mockCall(POOL_TARGETS[i], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector), abi.encode(true));
    }

    vm.mockCall(
      mockObeliskRegistry, abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector), abi.encode(address(0))
    );

    vm.mockCall(mockHashmask, abi.encodeWithSelector(IERC721.ownerOf.selector, HASH_MASK_ID), abi.encode(hashmaskUser));
    _mockHashmaskName("");
  }

  function test_construction_thenSetups() external {
    underTest = new ObeliskHashmaskHarness(mockHashmask, owner, mockObeliskRegistry, address(0), treasury);

    assertEq(address(underTest.hashmask()), mockHashmask);
    assertEq(underTest.treasury(), treasury);
    assertEq(underTest.activationPrice(), 0.1 ether);
    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.obeliskRegistry()), mockObeliskRegistry);
    assertEq(address(underTest.NFT_PASS()), address(0));
  }

  function test_link_whenMsgValueIsNotActivationPrice_thenReverts() external prankAs(hashmaskUser) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.InsufficientActivationPrice.selector));
    underTest.link{ value: activationPrice - 1 }(HASH_MASK_ID);

    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.InsufficientActivationPrice.selector));
    underTest.link{ value: activationPrice + 1 }(HASH_MASK_ID);
  }

  function test_link_whenNotHashmaskHolder_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NotHashmaskHolder.selector));
    underTest.link{ value: activationPrice }(HASH_MASK_ID);
  }

  function test_link_whenEthTransferFails_thenReverts() external prankAs(hashmaskUser) {
    vm.etch(treasury, type(FailOnReceive).creationCode);

    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.TransferFailed.selector));
    underTest.link{ value: activationPrice }(HASH_MASK_ID);
  }

  function test_link_thenLinksIdentityToHolder() external prankAs(hashmaskUser) {
    expectExactEmit();
    emit IObeliskHashmask.HashmaskLinked(HASH_MASK_ID, address(0), hashmaskUser);
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    assertEq(treasury.balance, activationPrice);
    assertEq(underTest.getIdentity(HASH_MASK_ID), hashmaskUser);
  }

  function test_link_whenOldLinker_thenRemovesOldTickersWithoutRewards() external pranking {
    changePrank(hashmaskUser);
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    vm.mockCall(mockHashmask, abi.encodeWithSelector(IERC721.ownerOf.selector, HASH_MASK_ID), abi.encode(user));

    changePrank(user);
    underTest.exposed_injectTicker(HASH_MASK_ID, POOL_TARGETS[0]);

    vm.expectCall(
      POOL_TARGETS[0], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector, HASH_MASK_ID, hashmaskUser, true)
    );
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    assertEq(underTest.getIdentity(HASH_MASK_ID), user);
  }

  function test_transferLink_whenNotLinkedToHolder_thenReverts() external prankAs(hashmaskUser) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NotLinkedToHolder.selector));
    underTest.transferLink(HASH_MASK_ID, false);
  }

  function test_transferLink_thenTransfersLinkToNewHolder() external prankAs(hashmaskUser) {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    vm.mockCall(mockHashmask, abi.encodeWithSelector(IERC721.ownerOf.selector, HASH_MASK_ID), abi.encode(user));

    expectExactEmit();
    emit IObeliskHashmask.HashmaskLinked(HASH_MASK_ID, hashmaskUser, user);
    underTest.transferLink(HASH_MASK_ID, false);

    assertEq(underTest.getIdentity(HASH_MASK_ID), user);
  }

  function test_transferLink_givenNoUpdateTrigger_whenLinkedTickers_thenRemovesOldTickersWithoutRewards()
    external
    prankAs(hashmaskUser)
  {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);
    underTest.exposed_injectTicker(HASH_MASK_ID, POOL_TARGETS[1]);

    vm.mockCall(mockHashmask, abi.encodeWithSelector(IERC721.ownerOf.selector, HASH_MASK_ID), abi.encode(user));

    vm.expectCall(
      POOL_TARGETS[1], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector, HASH_MASK_ID, hashmaskUser, true)
    );

    underTest.transferLink(HASH_MASK_ID, false);
  }

  function test_transferLink_givenNameUpdateTrigger_whenLinkedTickers_thenUpdatesName() external prankAs(hashmaskUser) {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    vm.mockCall(mockHashmask, abi.encodeWithSelector(IERC721.ownerOf.selector, HASH_MASK_ID), abi.encode(user));

    _mockHashmaskName(string.concat("O", TICKERS[0]));

    expectExactEmit();
    emit IObeliskHashmask.HashmaskLinked(HASH_MASK_ID, hashmaskUser, user);
    underTest.transferLink(HASH_MASK_ID, true);
  }

  function test_updateName_whenNotHashmaskHolder_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NotHashmaskHolder.selector));
    underTest.updateName(HASH_MASK_ID);
  }

  function test_updateName_whenNotLinker_thenReverts() external prankAs(hashmaskUser) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NotLinkedToHolder.selector));
    underTest.updateName(HASH_MASK_ID);
  }

  function test_updateName_whenNoTickers_thenReverts() external prankAs(hashmaskUser) {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    _mockHashmaskName(string.concat("Hello World ", TICKERS[2]));

    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NoTickersFound.selector));
    underTest.updateName(HASH_MASK_ID);
  }

  function test_updateName_thenDepositsTickersAndUpdatesName() external prankAs(hashmaskUser) {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    string memory name = string.concat("O", TICKERS[2]);

    _mockHashmaskName(name);

    vm.expectCall(
      POOL_TARGETS[2], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, HASH_MASK_ID, hashmaskUser)
    );

    expectExactEmit();
    emit IObeliskHashmask.NameUpdated(HASH_MASK_ID, name);

    underTest.updateName(HASH_MASK_ID);
  }

  function test_updateName_whenHasLinkedTickers_thenRemovesAndUpdatesTickers() external prankAs(hashmaskUser) {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    underTest.exposed_injectTicker(HASH_MASK_ID, POOL_TARGETS[0]);
    _mockHashmaskName(string.concat("O", TICKERS[1]));

    vm.expectCall(
      POOL_TARGETS[0], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector, HASH_MASK_ID, hashmaskUser, true)
    );

    vm.expectCall(
      POOL_TARGETS[1], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, HASH_MASK_ID, hashmaskUser)
    );

    underTest.updateName(HASH_MASK_ID);
  }

  function test_addNewTickers_whenEmptyString_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NoTickersFound.selector));
    underTest.exposed_addNewTickers(hashmaskUser, HASH_MASK_ID, "");
  }

  function test_addNewTickers_whenNoTickers_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.NoTickersFound.selector));
    underTest.exposed_addNewTickers(hashmaskUser, HASH_MASK_ID, "Hello Orange");
  }

  function test_addNewTickers_whenContainsTickers_thenReverts() external {
    string memory name = string.concat("Orange O", TICKERS[0]);
    name = string.concat(name, " O");
    name = string.concat(name, TICKERS[2]);
    name = string.concat(name, " O");
    name = string.concat(name, TICKERS[1]);
    name = string.concat(name, " BoBy");

    address[] memory expectedTickers = new address[](3);
    expectedTickers[0] = POOL_TARGETS[0];
    expectedTickers[1] = POOL_TARGETS[2];
    expectedTickers[2] = POOL_TARGETS[1];

    vm.expectCall(
      POOL_TARGETS[0], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, HASH_MASK_ID, hashmaskUser)
    );

    vm.expectCall(
      POOL_TARGETS[2], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, HASH_MASK_ID, hashmaskUser)
    );

    vm.expectCall(
      POOL_TARGETS[1], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, HASH_MASK_ID, hashmaskUser)
    );

    expectExactEmit();
    emit ITickerNFT.TickerActivated(HASH_MASK_ID, POOL_TARGETS[0]);
    expectExactEmit();
    emit ITickerNFT.TickerActivated(HASH_MASK_ID, POOL_TARGETS[2]);
    expectExactEmit();
    emit ITickerNFT.TickerActivated(HASH_MASK_ID, POOL_TARGETS[1]);

    underTest.exposed_addNewTickers(hashmaskUser, HASH_MASK_ID, name);

    assertEq(abi.encode(underTest.getLinkedTickers(HASH_MASK_ID)), abi.encode(expectedTickers));
  }

  function test_claimRequirements_thenReturnsValidRequirements() external prankAs(hashmaskUser) {
    underTest.link{ value: activationPrice }(HASH_MASK_ID);
    _mockHashmaskName(string.concat("O", TICKERS[0]));

    underTest.updateName(HASH_MASK_ID);

    //Not same name
    _mockHashmaskName(string.concat("O", TICKERS[1]));
    assertFalse(underTest.exposed_claimRequirements(HASH_MASK_ID));

    //Not same Owner
    _mockHashmaskName(string.concat("O", TICKERS[0]));

    vm.mockCall(mockHashmask, abi.encodeWithSelector(IERC721.ownerOf.selector, HASH_MASK_ID), abi.encode(user));
    assertFalse(underTest.exposed_claimRequirements(HASH_MASK_ID));

    //Not same identity
    changePrank(user);
    assertFalse(underTest.exposed_claimRequirements(HASH_MASK_ID));

    underTest.link{ value: activationPrice }(HASH_MASK_ID);

    assertTrue(underTest.exposed_claimRequirements(HASH_MASK_ID));
  }

  function test_setActivationPrice_whenNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setActivationPrice(0.2 ether);
  }

  function test_setActivationPrice_asOwner_thenUpdatesPrice() external prankAs(owner) {
    expectExactEmit();
    emit IObeliskHashmask.ActivationPriceSet(0.2 ether);

    underTest.setActivationPrice(0.2 ether);
    assertEq(underTest.activationPrice(), 0.2 ether);
  }

  function test_setTreasury_asNotOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setTreasury(treasury);
  }

  function test_setTreasury_asZeroAddress_thenReverts() external prankAs(owner) {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.ZeroAddress.selector));
    underTest.setTreasury(address(0));
  }

  function test_setTreasury_asOwner_thenUpdatesTreasury() external prankAs(owner) {
    expectExactEmit();
    emit IObeliskHashmask.TreasurySet(treasury);
    underTest.setTreasury(treasury);

    assertEq(underTest.treasury(), treasury);
  }

  function test_rename_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.UseUpdateNameInstead.selector));
    underTest.rename(HASH_MASK_ID, "Hello");
  }

  function test_updateIdentityReceiver_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IObeliskHashmask.UseLinkOrTransferLinkInstead.selector));
    underTest.updateIdentityReceiver(HASH_MASK_ID);
  }

  function _mockHashmaskName(string memory _name) internal {
    vm.mockCall(
      mockHashmask, abi.encodeWithSelector(IHashmask.tokenNameByIndex.selector, HASH_MASK_ID), abi.encode(_name)
    );
  }
}

contract ObeliskHashmaskHarness is ObeliskHashmask {
  constructor(address _hashmask, address _owner, address _obeliskRegistry, address _nftPass, address _treasury)
    ObeliskHashmask(_hashmask, _owner, _obeliskRegistry, _nftPass, _treasury)
  { }

  function exposed_injectTicker(uint256 _id, address _ticker) external {
    linkedTickers[_id].push(_ticker);
  }

  function exposed_addNewTickers(address _receiver, uint256 _tokenId, string memory _name) external {
    _addNewTickers(_receiver, _tokenId, _name);
  }

  function exposed_claimRequirements(uint256 _tokenId) external view returns (bool) {
    return _claimRequirements(_tokenId);
  }
}

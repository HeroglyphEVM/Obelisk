// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../../base/BaseTest.t.sol";
import { NFTPass, INFTPass } from "src/services/nft/NFTPass.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { INameFilter } from "src/vendor/heroglyph/INameFilter.sol";
import { IIdentityERC721 } from "src/vendor/heroglyph/IIdentityERC721.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract NFTPassTest is BaseTest {
  uint256 public constant MAX_BPS = 10_000;
  uint256 private COST = 0.1e18;

  address private owner;
  address private treasury;
  address private mockNameFilter;
  address private user;
  address private oldIdentity;

  NFTPassHarness private underTest;

  bytes32 private MERKLE_ROOT =
    bytes32(hex"0b1dac9cedfcfd7cfe059834cbc7bac5fe17b62583d07f1d6b12232e11e80084");
  address private PROOF_USER = 0xf94a9145600140A27f3E3122AD4d1f0FA4320664;
  bytes32[] private PROOF = [
    bytes32(hex"aee0596b7414d00c1199f50e5a8c1e592713ee3db57f30b0be6d48d17a16be55"),
    hex"87705553de17763c7c946b944568d00767977ea60bd6eeaf8240729890a0c899",
    hex"71c2b5f904a0fff51644bc53f44b5060e1ff1e37c846fc57416c984ebf2263f3",
    hex"dd92259d01d48318916d0a7d02a2653a0dcd21f3edd44c6ca4c071ea7a80e70d",
    hex"dac5855b5b0cd44dd57f54be3906ab6ef69fabe17310e07e0b278905442acb42",
    hex"2ed384ec21181feaf5da117e7ffca60bea86cb83b93b3a78fa22e12538f7d7ea",
    hex"550d391446ca85aaa6550eaddf9e49df4d29919dad5619372a5ee6da9cb51399",
    hex"f5b7b1aac70ff4062e0a34b232b98a811903210688c8e3e55ed5b61aa1ac10b3",
    hex"88b868a542d524a173e4c703578aaebd0ca4ee38725e7f260a22f3d4f894c1d2",
    hex"f5d91a9590209f7d7841cca74dee1f1b169da4adb3652f54b105eaaf1971023b",
    hex"f52f709b9bcecbd67b39b299d6b46eee06a019e3314672651fc2a1f742ee446d",
    hex"570b872fa96e710e16f7fd68df4127168b10bc69c57aa0a2a3be681c217ab428",
    hex"bcf4ef158948faaf536d9097449a0d2a36097d499f2d834aa7757563ba151ac8",
    hex"1f18ace9983416ee25c783bcace482569695f63042bcf89e2125567c56bcbbf9"
  ];

  function setUp() public pranking {
    _generateAddresses();
    vm.deal(user, 1000e18);

    changePrank(owner);

    underTest = new NFTPassHarness(owner, treasury, mockNameFilter, COST, MERKLE_ROOT);

    vm.mockCall(
      mockNameFilter,
      abi.encodeWithSelector(INameFilter.isNameValidWithIndexError.selector),
      abi.encode(true, 0)
    );
    vm.mockCall(
      mockNameFilter,
      abi.encodeWithSelector(INameFilter.isNameValid.selector),
      abi.encode(true)
    );

    vm.mockCall(
      oldIdentity,
      abi.encodeWithSelector(IIdentityERC721.getIdentityNFTId.selector),
      abi.encode(0)
    );

    skip(1 weeks);
  }

  function _generateAddresses() internal {
    owner = generateAddress("Owner");
    treasury = generateAddress("Treasury");
    mockNameFilter = generateAddress("Name Filter");
    oldIdentity = generateAddress("Old Identity");
    user = generateAddress("User");
  }

  function test_constructor_thenContractWellConfigured() external {
    underTest = new NFTPassHarness(owner, treasury, mockNameFilter, COST, MERKLE_ROOT);

    assertEq(underTest.owner(), owner);
    assertEq(address(underTest.nameFilter()), mockNameFilter);
    assertEq(underTest.treasury(), treasury);
    assertEq(underTest.cost(), COST);
    assertEq(underTest.merkleRoot(), MERKLE_ROOT);
  }

  function test_claimPass_whenClaimingEnded_thenReverts() external pranking {
    skip(31 days);

    changePrank(PROOF_USER);
    vm.expectRevert(INFTPass.ClaimingEnded.selector);
    underTest.claimPass("!", PROOF_USER, PROOF);
  }

  function test_claimPass_whenNameTooLong_thenReverts() external pranking {
    changePrank(PROOF_USER);
    bytes memory tooLongName = new bytes(underTest.MAX_NAME_BYTES() + 1);

    vm.expectRevert(INFTPass.NameTooLong.selector);
    underTest.claimPass(string(tooLongName), PROOF_USER, PROOF);
  }

  function test_claimPass_whenAlreadyClaimed_thenReverts() external pranking {
    changePrank(PROOF_USER);
    underTest.claimPass("L", PROOF_USER, PROOF);

    vm.expectRevert(INFTPass.AlreadyClaimed.selector);
    underTest.claimPass("!", PROOF_USER, PROOF);
  }

  function test_claimPass_whenInvalidProof_thenReverts() external pranking {
    changePrank(generateAddress());
    vm.expectRevert(INFTPass.InvalidProof.selector);
    underTest.claimPass("!", PROOF_USER, PROOF);
  }

  function test_claimPass_thenCreatesAndAssigns() external pranking {
    changePrank(PROOF_USER);
    expectExactEmit();
    emit INFTPass.NFTPassCreated(1, "!", PROOF_USER, 0);
    underTest.claimPass("!", PROOF_USER, PROOF);

    assertEq(underTest.getMetadata(0, "!").walletReceiver, PROOF_USER);
  }

  function test_create_givenMsgValue_whenCostIsZero_thenReverts() external pranking {
    changePrank(owner);
    underTest.updateCost(0);

    string memory name = "!";
    address receiver = generateAddress();

    changePrank(user);
    vm.expectRevert(INFTPass.NoNeedToPay.selector);
    underTest.create{ value: COST }(name, receiver);
  }

  function test_create_whenValueIsLowerThanCost_thenReverts() external prankAs(user) {
    vm.expectRevert(INFTPass.MsgValueTooLow.selector);
    underTest.create{ value: COST - 1 }("!", address(0));
  }

  function test_create_whenSendingTooMuchEth_thenReturnsExtra() external prankAs(user) {
    uint256 sending = 10e18;
    uint256 balanceBefore = address(user).balance;

    changePrank(user);
    underTest.create{ value: sending }("!", address(0));

    assertEq(balanceBefore - address(user).balance, COST);
    assertEq(address(treasury).balance, COST);
  }

  function test_create_givenWalletReceiver_thenCreatesAndAssignWalletReceiver()
    external
    pranking
  {
    string memory name = "!";
    address receiver = generateAddress();

    changePrank(user);
    underTest.create{ value: COST }(name, receiver);

    assertEq(underTest.getMetadata(0, name).walletReceiver, receiver);
    assertEq(underTest.getMetadata(1, "").walletReceiver, receiver);
    assertEq(underTest.ownerOf(1), user);
  }

  function test_create_thenCreateValidatorIdentityAndMint() external pranking {
    string memory name = "!";
    string memory name_2 = "!!";
    address user_B = generateAddress("B", 100e18);

    changePrank(user_B);

    expectExactEmit();
    emit INFTPass.NFTPassCreated(1, name, user_B, COST);
    underTest.create{ value: COST }(name, address(0));

    changePrank(user);

    expectExactEmit();
    emit INFTPass.NFTPassCreated(2, name_2, user, COST);
    underTest.create{ value: COST }(name_2, address(0));

    assertEq(underTest.getMetadata(0, name).walletReceiver, user_B);
    assertEq(underTest.getMetadata(1, "").walletReceiver, user_B);
    assertEq(underTest.ownerOf(1), user_B);

    assertEq(underTest.getMetadata(0, name_2).walletReceiver, user);
    assertEq(underTest.getMetadata(2, "").walletReceiver, user);
    assertEq(underTest.ownerOf(2), user);
  }

  function test_updateReceiverAddress_asNoneIdentifier_thenReverts() external pranking {
    changePrank(user);
    underTest.create{ value: COST }("A", address(0));

    changePrank(generateAddress());

    vm.expectRevert(IIdentityERC721.NotIdentityOwner.selector);
    underTest.updateReceiverAddress(0, "A", address(0x0122));
    vm.expectRevert(IIdentityERC721.NotIdentityOwner.selector);
    underTest.updateReceiverAddress(1, "", address(0x0122));
  }

  function test_updateReceiverAddress_thenUpdatesTokenReceiver() external pranking {
    address tokenReceiverA = generateAddress();
    address tokenReceiverB = generateAddress();

    changePrank(user);
    underTest.create{ value: COST }("A", address(0));

    expectExactEmit();
    emit INFTPass.NFTPassUpdated(1, "A", tokenReceiverA);
    underTest.updateReceiverAddress(0, "A", tokenReceiverA);

    assertEq(underTest.getMetadata(1, "").walletReceiver, tokenReceiverA);

    expectExactEmit();
    emit INFTPass.NFTPassUpdated(1, "A", tokenReceiverB);
    underTest.updateReceiverAddress(1, "", tokenReceiverB);

    assertEq(underTest.getMetadata(1, "").walletReceiver, tokenReceiverB);
  }

  function test_transferFrom_thenReverts() external prankAs(user) {
    underTest.create{ value: COST }("A", address(0));

    vm.expectRevert("Non-Transferrable");
    underTest.transferFrom(user, generateAddress(), 1);

    vm.expectRevert("Non-Transferrable");
    underTest.safeTransferFrom(user, generateAddress(), 1);
  }

  //UpdateCost adds 1 to the boughtToday tracker
  function test_updateCost_simpleVerification() external {
    underTest.exposed_resetCounterTimestamp(block.timestamp + 1 days);
    uint256 expectedCost = COST;
    uint32 maxPerDay = underTest.maxIdentityPerDayAtInitialPrice();
    uint32 priceIncreaseThreshold = underTest.priceIncreaseThreshold();

    underTest.exposed_addBoughtToday(maxPerDay);
    console.log("Next: (MaxPerDay) | Current:", underTest.boughtToday());
    assertEq(underTest.exposed_updateCost(), expectedCost);

    underTest.exposed_addBoughtToday(priceIncreaseThreshold - 2);
    console.log("Next: (MaxPerDay + threshold - 1) | Current:", underTest.boughtToday());
    assertEq(underTest.exposed_updateCost(), expectedCost);

    expectedCost += COST / 2;
    console.log("Next: (MaxPerDay + threshold) | Current:", underTest.boughtToday());
    assertEq(underTest.exposed_updateCost(), expectedCost);

    underTest.exposed_addBoughtToday(priceIncreaseThreshold - 2);
    console.log(
      "Next: (MaxPerDay + threshold * 2 - 1) | Current:", underTest.boughtToday()
    );
    assertEq(underTest.exposed_updateCost(), expectedCost);

    expectedCost += COST / 2;
    console.log("Next: (MaxPerDay + threshold * 2) | Current:", underTest.boughtToday());
    assertEq(underTest.exposed_updateCost(), expectedCost);

    skip(1 days);
    uint256 actualPrice =
      Math.max(COST, expectedCost - (expectedCost * underTest.priceDecayBPS() / MAX_BPS));

    expectedCost = COST;
    assertEq(underTest.getCost(), expectedCost);
    assertEq(underTest.exposed_updateCost(), expectedCost);

    underTest.exposed_addBoughtToday(maxPerDay - 1);

    console.log("Next: (MaxPerDay) | Current:", underTest.boughtToday());
    assertEq(underTest.exposed_updateCost(), expectedCost);

    expectedCost = actualPrice;
    assertEq(underTest.exposed_updateCost(), actualPrice);

    expectedCost += COST / 2;
    underTest.exposed_addBoughtToday(priceIncreaseThreshold - 2);
    console.log("Next: (MaxPerDay + threshold) | Current:", underTest.boughtToday());
    assertEq(underTest.exposed_updateCost(), expectedCost);
  }

  function test_getCost_thenReturnsValue() external prankAs(user) {
    uint256 expectedCost = COST;
    uint32 maxIdentityPerDay = underTest.maxIdentityPerDayAtInitialPrice();
    uint32 priceIncreaseThreshold = underTest.priceIncreaseThreshold();
    uint32 id = 0;

    for (uint32 i = 0; i < maxIdentityPerDay + priceIncreaseThreshold; ++i) {
      id++;

      assertEq(underTest.getCost(), expectedCost);
      underTest.create{ value: expectedCost }(Strings.toString(id), address(0));
    }

    expectedCost += COST / 2;
    assertEq(underTest.getCost(), expectedCost);

    for (uint32 i = 0; i < priceIncreaseThreshold; ++i) {
      id++;

      assertEq(underTest.getCost(), expectedCost);

      expectExactEmit();
      emit INFTPass.NFTPassCreated(id, Strings.toString(id), user, expectedCost);
      underTest.create{ value: expectedCost }(Strings.toString(id), address(0));
    }

    assertEq(underTest.getCost(), expectedCost + COST / 2);

    skip(1 days);

    for (uint32 i = 0; i <= maxIdentityPerDay; ++i) {
      id++;

      assertEq(underTest.getCost(), COST);
      underTest.create{ value: expectedCost }(Strings.toString(id), address(0));
    }

    expectedCost = Math.max(
      COST, expectedCost - Math.mulDiv(expectedCost, underTest.priceDecayBPS(), MAX_BPS)
    );
    assertEq(underTest.getCost(), expectedCost);

    id++;
    expectExactEmit();
    emit INFTPass.NFTPassCreated(id, Strings.toString(id), user, expectedCost);
    underTest.create{ value: expectedCost }(Strings.toString(id), address(0));

    expectedCost = COST;

    skip(10 days);
    for (uint32 i = 0; i <= maxIdentityPerDay + (priceIncreaseThreshold * 10); ++i) {
      id++;
      underTest.create{ value: 2e18 }(Strings.toString(id), address(0));
    }

    expectedCost += (COST / 2) * 10;
    assertEq(underTest.currentPrice(), expectedCost);

    skip(60 days);
    for (uint32 i = 0; i <= maxIdentityPerDay; ++i) {
      id++;
      underTest.create{ value: 2e18 }(Strings.toString(id), address(0));
    }

    id++;
    underTest.create{ value: expectedCost }(Strings.toString(id), address(0));

    assertEq(underTest.currentPrice(), COST);
  }

  function test_updateMaxIdentityPerDayAtInitialPrice_asNonOwner_thenReverts()
    external
    prankAs(user)
  {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updateMaxIdentityPerDayAtInitialPrice(30);
  }

  function test_updateMaxIdentityPerDayAtInitialPrice_thenUpdates()
    external
    prankAs(owner)
  {
    uint32 newMaxIdentityPerDay = 30;

    expectExactEmit();
    emit INFTPass.MaxIdentityPerDayAtInitialPriceUpdated(newMaxIdentityPerDay);
    underTest.updateMaxIdentityPerDayAtInitialPrice(newMaxIdentityPerDay);

    assertEq(underTest.maxIdentityPerDayAtInitialPrice(), newMaxIdentityPerDay);
  }

  function test_updatePriceIncreaseThreshold_asNonOwner_thenReverts()
    external
    prankAs(user)
  {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updatePriceIncreaseThreshold(30);
  }

  function test_updatePriceIncreaseThreshold_thenUpdates() external prankAs(owner) {
    uint32 newPriceIncreaseThreshold = 30;

    expectExactEmit();
    emit INFTPass.PriceIncreaseThresholdUpdated(newPriceIncreaseThreshold);
    underTest.updatePriceIncreaseThreshold(newPriceIncreaseThreshold);

    assertEq(underTest.priceIncreaseThreshold(), newPriceIncreaseThreshold);
  }

  function test_updatePriceDecayBPS_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updatePriceDecayBPS(30);
  }

  function test_updatePriceDecayBPS_givenInvalidBPS_thenReverts() external prankAs(owner) {
    vm.expectRevert(INFTPass.InvalidBPS.selector);
    underTest.updatePriceDecayBPS(10_001);
  }

  function test_updatePriceDecayBPS_thenUpdates() external prankAs(owner) {
    uint32 newPriceDecayBPS = 30;

    expectExactEmit();
    emit INFTPass.PriceDecayBPSUpdated(newPriceDecayBPS);
    underTest.updatePriceDecayBPS(newPriceDecayBPS);

    assertEq(underTest.priceDecayBPS(), newPriceDecayBPS);
  }
}

contract NFTPassHarness is NFTPass {
  constructor(
    address _owner,
    address _treasury,
    address _nameFilter,
    uint256 _cost,
    bytes32 _proofRoot
  ) NFTPass(_owner, _treasury, _nameFilter, _cost, _proofRoot) { }

  function exposed_addBoughtToday(uint32 _amount) external {
    boughtToday += _amount;
  }

  function exposed_updateCost() external returns (uint256) {
    return _updateCost();
  }

  function exposed_resetCounterTimestamp(uint256 _resetTime) external {
    resetCounterTimestamp = uint32(_resetTime);
  }
}

contract FailOnEth {
  receive() external payable {
    revert("No!");
  }
}

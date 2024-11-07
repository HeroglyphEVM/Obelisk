// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "test/base/BaseTest.t.sol";

import { HCT, IHCT } from "src/services/HCT.sol";
import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { strings } from "src/lib/strings.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract HCTTest is BaseTest {
  using strings for string;
  using strings for strings.slice;

  uint128 private constant MULTIPLIER_BY_NFT_MOCK_A = 3e18;
  uint128 private constant MULTIPLIER_BY_NFT_MOCK_B = 0.8e18;

  address private obeliskRegistryMock;
  address private wrappedNFTMock_A;
  address private wrappedNFTMock_B;
  address private owner;
  address private user;
  address private treasury;
  HCTHarness public underTest;

  function setUp() public {
    _setupMocks();
    _setupMockCalls();

    vm.prank(obeliskRegistryMock);
    underTest = new HCTHarness(owner, treasury);
  }

  function _setupMocks() internal {
    obeliskRegistryMock = generateAddress("ObeliskRegistry");
    wrappedNFTMock_A = generateAddress("WrappedNFT_A");
    wrappedNFTMock_B = generateAddress("WrappedNFT_B");
    user = generateAddress("User");
    owner = generateAddress("Owner");
    treasury = generateAddress("Treasury");
  }

  function _setupMockCalls() internal {
    vm.mockCall(
      obeliskRegistryMock,
      abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector),
      abi.encode(false)
    );
    vm.mockCall(
      obeliskRegistryMock,
      abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector, wrappedNFTMock_A),
      abi.encode(true)
    );
    vm.mockCall(
      obeliskRegistryMock,
      abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector, wrappedNFTMock_B),
      abi.encode(true)
    );
  }

  function test_constructor_thenPreMints() external prankAs(obeliskRegistryMock) {
    underTest = new HCTHarness(owner, treasury);

    assertEq(underTest.balanceOf(treasury), underTest.PRE_MINT_AMOUNT());
    assertEq(address(underTest.obeliskRegistry()), obeliskRegistryMock);
  }

  function test_addPower_asNonWrappedNFTSystem_thenReverts() external {
    vm.expectRevert(IHCT.NotWrappedNFT.selector);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
  }

  function test_addPower_thenAddsPower() external pranking {
    IHCT.UserInfo memory expectedUserInfo = IHCT.UserInfo({
      multiplier: MULTIPLIER_BY_NFT_MOCK_A + MULTIPLIER_BY_NFT_MOCK_B,
      userRates: 0
    });

    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_B, true);

    assertEq(underTest.balanceOf(user), 0);
    assertEq(abi.encode(underTest.getUserInfo(user)), abi.encode(expectedUserInfo));
  }

  function test_addPower_whenPendingClaiming_thenClaims()
    external
    prankAs(wrappedNFTMock_A)
  {
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
    skip(30 days);

    uint256 userRatesBefore = underTest.getUserInfo(user).userRates;
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);

    assertEq(underTest.getUserInfo(user).multiplier, MULTIPLIER_BY_NFT_MOCK_A * 2);
    assertGt(underTest.getUserInfo(user).userRates, userRatesBefore);
    assertEq(underTest.getUserPendingRewards(user), 0);
    assertGt(underTest.balanceOf(user), 0);
  }

  function test_removePower_asNonWrappedNFTSystem_thenReverts() external {
    vm.expectRevert(IHCT.NotWrappedNFT.selector);
    underTest.removePower(user, MULTIPLIER_BY_NFT_MOCK_A);
  }

  function test_removePower_thenRemovesPower() external prankAs(wrappedNFTMock_A) {
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
    underTest.removePower(user, MULTIPLIER_BY_NFT_MOCK_A);

    IHCT.UserInfo memory expectedUserInfo = IHCT.UserInfo({ multiplier: 0, userRates: 0 });

    assertEq(underTest.balanceOf(user), 0);
    assertEq(abi.encode(underTest.getUserInfo(user)), abi.encode(expectedUserInfo));
  }

  function test_removePower_whenPendingClaiming_thenClaims()
    external
    prankAs(wrappedNFTMock_A)
  {
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
    skip(30 days);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);

    uint256 userRatesBefore = underTest.getUserInfo(user).userRates;
    underTest.removePower(user, MULTIPLIER_BY_NFT_MOCK_A);

    assertEq(underTest.getUserInfo(user).multiplier, MULTIPLIER_BY_NFT_MOCK_A);
    assertLt(underTest.getUserInfo(user).userRates, userRatesBefore);
    assertEq(underTest.getUserPendingRewards(user), 0);
  }

  function test_userForRenaming_asNonWrappedNFTSystem_thenReverts() external {
    vm.expectRevert(IHCT.NotWrappedNFT.selector);
    underTest.usesForRenaming(user);
  }

  function test_usesForRenaming_thenBurnsNFTAndMints() external prankAs(wrappedNFTMock_A) {
    underTest.exposed_mint(user, 10_000e18);
    uint256 balance = underTest.balanceOf(user);
    uint128 cost = underTest.NAME_COST();

    expectExactEmit();
    emit IHCT.BurnedForRenaming(wrappedNFTMock_A, user, cost);
    underTest.usesForRenaming(user);

    assertEq(underTest.balanceOf(user), balance - cost);
  }

  function test_usesForRenaming_whenPendingClaiming_thenClaims()
    external
    prankAs(wrappedNFTMock_A)
  {
    underTest.exposed_mint(user, 10_000e18);
    uint256 balance = underTest.balanceOf(user);
    uint128 cost = underTest.NAME_COST();

    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
    skip(30 days);

    uint256 userRatesBefore = underTest.getUserInfo(user).userRates;
    underTest.usesForRenaming(user);

    assertGt(underTest.balanceOf(user), balance - cost);
    assertEq(underTest.getUserInfo(user).multiplier, MULTIPLIER_BY_NFT_MOCK_A);
    assertGt(underTest.getUserInfo(user).userRates, userRatesBefore);
  }

  function test_claim_whenNothingToClaim_thenReverts() external {
    vm.expectRevert(IHCT.NothingToClaim.selector);
    underTest.claim();
  }

  function test_claim_thenClaims() external pranking {
    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, 2e18, true);

    uint256 expectingAfterADay = uint256(1) * 1e18 / 1 days;

    skip(3 days);
    assertEq(underTest.getUserPendingRewards(user), expectingAfterADay * 3 days);

    changePrank(user);
    underTest.claim();

    assertEq(underTest.getUserPendingRewards(user), 0);
    assertEq(underTest.balanceOf(user), expectingAfterADay * 3 days);
  }

  function test_balanceOf_thenReturnsBalance() external prankAs(wrappedNFTMock_A) {
    uint256 preMint = 10_000e18;
    underTest.exposed_mint(user, preMint);

    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A, true);
    assertEq(underTest.balanceOf(user), preMint);
    skip(30 days);

    assertGt(underTest.balanceOf(user), preMint);
  }

  function test_getPendingToBeClaimed_thenReturnsPending() external pranking {
    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, 2e18, true);

    uint256 expectingAfterADay = uint256(1) * 1e18 / 1 days;

    skip(1 days);
    assertEq(underTest.getUserPendingRewards(user), expectingAfterADay * 1 days);
    skip(2 days);
    assertEq(underTest.getUserPendingRewards(user), expectingAfterADay * 3 days);
  }

  function test_getSystemPendingRewards_whenInflation_thenReturnsInflation()
    external
    pranking
  {
    underTest.exposed_mint(
      treasury, underTest.inflationThreshold() - underTest.PRE_MINT_AMOUNT()
    );

    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, 2e18, true);

    uint256 expectingAfterADayInflation = uint256(1) * underTest.inflationRate();
    uint256 expectingAfterADayNoInflation = uint256(1) * underTest.baseRate();

    skip(1 days);
    assertEqTolerance(underTest.getSystemPendingRewards(), expectingAfterADayInflation, 1);

    underTest.exposed_burn(treasury, 1e18);
    assertEqTolerance(
      underTest.getSystemPendingRewards(), expectingAfterADayNoInflation, 1
    );
  }

  function test_setInflationRate_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.setInflationRate(100);
  }

  function test_setInflationRate_thenSetsInflationRate() external prankAs(owner) {
    expectExactEmit();
    emit IHCT.InflationRateSet(100);

    underTest.setInflationRate(100);

    assertEq(underTest.inflationRate(), 100);
  }

  function test_setBaseRate_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.setBaseRate(100);
  }

  function test_setBaseRate_thenSetsBaseRate() external prankAs(owner) {
    expectExactEmit();
    emit IHCT.BaseRateSet(2e18);

    underTest.setBaseRate(2e18);

    assertEq(underTest.baseRate(), 2e18);
  }

  function test_setInflationThreshold_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.setInflationThreshold(100);
  }

  function test_setInflationThreshold_thenSetsInflationThreshold()
    external
    prankAs(owner)
  {
    expectExactEmit();
    emit IHCT.InflationThresholdSet(250_000e18);

    underTest.setInflationThreshold(250_000e18);

    assertEq(underTest.inflationThreshold(), 250_000e18);
  }
}

contract HCTHarness is HCT {
  constructor(address _owner, address _treasury) HCT(_owner, _treasury) { }

  function exposed_mint(address _user, uint256 _amount) external {
    _mint(_user, _amount);
  }

  function exposed_burn(address _user, uint256 _amount) external {
    _burn(_user, _amount);
  }

  function exposed_setMultiplier(address _user, uint128 _multiplier) external {
    usersInfo[_user].multiplier = _multiplier;
  }

  function exposed_setLastUnixTimeClaim(uint256 _lastUnixTimeClaim) external {
    lastUnixTimeRewards = uint32(_lastUnixTimeClaim);
  }
}

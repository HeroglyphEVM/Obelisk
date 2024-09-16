// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "test/base/BaseTest.t.sol";

import { HCT, IHCT } from "src/services/HCT.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";

contract HCTTest is BaseTest {
  uint128 private constant POWER_BY_NFT = 1e18;
  uint128 private constant MULTIPLIER_BY_NFT_MOCK_A = 3e18;
  uint128 private constant MULTIPLIER_BY_NFT_MOCK_B = 0.8e18;

  address private obeliskRegistryMock;
  address private wrappedNFTMock_A;
  address private wrappedNFTMock_B;
  address private user;
  HCTHarness public underTest;

  function setUp() public {
    _setupMocks();
    _setupMockCalls();
    underTest = new HCTHarness();
    underTest.initHCT(obeliskRegistryMock);
  }

  function _setupMocks() internal {
    obeliskRegistryMock = generateAddress("ObeliskRegistry");
    wrappedNFTMock_A = generateAddress("WrappedNFT_A");
    wrappedNFTMock_B = generateAddress("WrappedNFT_B");
    user = generateAddress("User");
  }

  function _setupMockCalls() internal {
    vm.mockCall(obeliskRegistryMock, abi.encodeWithSelector(IObeliskRegistry.isWrappedNFT.selector), abi.encode(false));
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

  function test_initHCT_whenAlreadyInitialized_thenReverts() external {
    underTest = new HCTHarness();
    underTest.initHCT(obeliskRegistryMock);

    vm.expectRevert(IHCT.AlreadyInitialized.selector);
    underTest.initHCT(obeliskRegistryMock);
  }

  function test_initHCT_thenSetsObeliskRegistry() external {
    underTest = new HCTHarness();
    underTest.initHCT(obeliskRegistryMock);

    assertEq(address(underTest.obeliskRegistry()), obeliskRegistryMock);
  }

  function test_addPower_asNonWrappedNFTSystem_thenReverts() external {
    vm.expectRevert(IHCT.NotWrappedNFT.selector);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A);
  }

  function test_addPower_thenAddsPower() external pranking {
    IHCT.UserInfo memory expectedUserInfo = IHCT.UserInfo({
      power: POWER_BY_NFT * 2,
      multiplier: (MULTIPLIER_BY_NFT_MOCK_A + MULTIPLIER_BY_NFT_MOCK_B) * 1e18 / (POWER_BY_NFT * 2),
      totalMultiplier: MULTIPLIER_BY_NFT_MOCK_A + MULTIPLIER_BY_NFT_MOCK_B,
      lastUnixTimeClaim: uint32(block.timestamp)
    });

    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A);
    changePrank(wrappedNFTMock_A);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_B);

    assertEq(underTest.balanceOf(user), 0);
    assertEq(abi.encode(underTest.getUserInfo(user)), abi.encode(expectedUserInfo));
  }

  function test_addPower_whenPendingClaiming_thenClaims() external prankAs(wrappedNFTMock_A) {
    IHCT.UserInfo memory expectedUserInfo = IHCT.UserInfo({
      power: POWER_BY_NFT * 2,
      multiplier: MULTIPLIER_BY_NFT_MOCK_A,
      totalMultiplier: MULTIPLIER_BY_NFT_MOCK_A * 2,
      lastUnixTimeClaim: uint32(block.timestamp + 30 days)
    });

    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A);
    skip(30 days);
    underTest.addPower(user, MULTIPLIER_BY_NFT_MOCK_A);

    assertEq(abi.encode(underTest.getUserInfo(user)), abi.encode(expectedUserInfo));
    assertEq(underTest.getPendingToBeClaimed(user), 0);
    assertGt(underTest.balanceOf(user), 0);
  }
}

contract HCTHarness is HCT { }

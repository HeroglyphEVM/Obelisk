// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../base/BaseTest.t.sol";

import { ApxETHVault, IApxETH } from "src/services/liquidity/ApxETHVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract DineroE2E is BaseTest {
  address private constant axpETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
  address private constant pxAdmin = 0xA52Fd396891E7A74b641a2Cb1A6999Fcf56B077e;
  address private constant pirexETH = 0xD664b74274DfEB538d9baC494F3a4760828B02b0;

  address private owner;
  address private mockGovernance;
  address private obeliskRegistry;
  address private rateReceiver;
  address private mockUser;

  ApxETHVault public vault;

  function setUp() external {
    vm.createSelectFork(vm.envString("RPC_MAINNET"));

    owner = generateAddress("OWNER");
    obeliskRegistry = generateAddress("OBELISK_REGISTRY", 100_000e18);
    rateReceiver = generateAddress("RATE_RECEIVER");
    mockUser = generateAddress("MOCK_USER");
    mockGovernance = generateAddress("MOCK_GOVERNANCE");

    vault = new ApxETHVault(owner, obeliskRegistry, axpETH, rateReceiver);

    vm.prank(pxAdmin);
    AccessControl(pirexETH).grantRole(keccak256("GOVERNANCE_ROLE"), mockGovernance);
  }

  function test_onDeposit_thenUpdatesBalance() external pranking {
    uint256 deposit = 250.3e18;
    uint256 prevDeposit = vault.previewDeposit(deposit);

    changePrank(obeliskRegistry);
    uint256 returnedValue = vault.deposit{ value: deposit }(0);

    skip(30 days);

    uint256 expectedApxEth = IApxETH(axpETH).convertToShares(deposit);
    vault.withdraw(mockUser, deposit);

    vault.claim();

    assertEq(IERC20(axpETH).balanceOf(mockUser), expectedApxEth);
    assertEq(prevDeposit, deposit);
    assertEq(returnedValue, prevDeposit);
    assertGt(IERC20(axpETH).balanceOf(rateReceiver), 0);
  }

  function test_onDeposit_withFee_thenUpdatesBalance() external pranking {
    changePrank(mockGovernance);
    (bool success,) =
      pirexETH.call(abi.encodeWithSignature("setFee(uint8,uint32)", 0, 1000));

    require(success, "Failed to set fee");

    uint256 deposit = 250.3e18;
    uint256 expectedDeposit = deposit - (deposit * 1000) / 1_000_000;
    uint256 prevDeposit = vault.previewDeposit(deposit);
    uint256 expectedApxEth = IApxETH(axpETH).convertToShares(expectedDeposit);

    changePrank(obeliskRegistry);
    uint256 returnedValue = vault.deposit{ value: deposit }(0);
    vault.withdraw(mockUser, expectedDeposit);

    assertEq(IERC20(axpETH).balanceOf(mockUser), expectedApxEth);
    assertEq(prevDeposit, expectedDeposit);
    assertEq(returnedValue, prevDeposit);
  }
}

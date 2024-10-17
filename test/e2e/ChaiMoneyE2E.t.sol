// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "../base/BaseTest.t.sol";

import { ChaiMoneyVault } from "src/services/liquidity/ChainMoney.sol";
import { IPot } from "src/vendor/chai/IPot.sol";
import { IChaiMoney } from "src/vendor/chai/IChaiMoney.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ChainMoneyE2E is BaseTest {
  address private owner;
  address private obeliskRegistry;
  address private dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  IChaiMoney private chaiMoney = IChaiMoney(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
  IPot private pot;
  address private rateReceiver;
  address private userWithCHAI = 0x6979039759EA5f6AD1d86261ad3f33d4Cec83e8A;
  address private userWithDAI = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;
  address private mockUser;

  ChaiMoneyVault public vault;

  uint256 constant RAY = 10 ** 27;

  function setUp() external {
    vm.createSelectFork(vm.envString("RPC_MAINNET"));

    owner = generateAddress("OWNER");
    obeliskRegistry = generateAddress("OBELISK_REGISTRY");
    rateReceiver = generateAddress("RATE_RECEIVER");
    mockUser = generateAddress("MOCK_USER");

    vault = new ChaiMoneyVault(owner, obeliskRegistry, address(chaiMoney), dai, rateReceiver);

    vm.prank(obeliskRegistry);
    IERC20(dai).approve(address(vault), type(uint256).max);

    pot = IPot(chaiMoney.pot());
  }

  function test_onDeposit_thenUpdatesBalance() external pranking {
    uint256 initialBalance = 250_304e18;
    uint256 deposit = 250.3e18;

    changePrank(userWithDAI);
    IERC20(dai).transfer(mockUser, initialBalance);

    changePrank(mockUser);
    IERC20(dai).transfer(address(obeliskRegistry), deposit);

    changePrank(obeliskRegistry);
    vault.deposit(deposit);
    skip(30 days);
    vault.withdraw(mockUser, deposit);

    assertEq(IERC20(dai).balanceOf(mockUser), initialBalance);

    vault.claim();
    assertGt(IERC20(dai).balanceOf(rateReceiver), 0);
  }

  function _convertToChai(uint256 _amount) internal returns (uint256) {
    uint256 chi = (block.timestamp > pot.rho()) ? pot.drip() : pot.chi();
    return ((_amount * RAY) + (chi - 1)) / chi;
  }
}

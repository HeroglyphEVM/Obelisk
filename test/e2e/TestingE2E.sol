// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/base/BaseTest.t.sol";

import { WrappedNFTHero } from "src/services/nft/WrappedNFTHero.sol";
import { HCT } from "src/services/HCT.sol";

contract TestingE2E is BaseTest {
  function setUp() external {
    vm.createSelectFork(vm.envString("RPC_SEPOLIA"));
  }

  function test_obeliskRegistry_flow_addToCollection() external pranking {
    changePrank(0x476476A595b45Ab21a51f69fDe50bc0eD64116A0);

    console.log(
      HCT(0x6D4039a3FECDf1ef2b4b4948cbAf8200637d8bfC).getTotalRewardsGenerated()
    );
    WrappedNFTHero(0x908b3AA10801995835bf6A105C920E12cf31Cb4a).wrap(3);
  }
}
//68611111111110672
//190972222222221000

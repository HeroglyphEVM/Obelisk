// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { BaseTest } from "test/base/BaseTest.t.sol";
import { ApxETHVault } from "src/services/liquidity/ApxETHVault.sol";
import { ChaiMoneyVault } from "src/services/liquidity/ChaiMoney.sol";
import { ObeliskRegistry } from "src/services/nft/ObeliskRegistry.sol";
import { HCT } from "src/services/HCT.sol";
import { NFTPass } from "src/services/nft/NFTPass.sol";
import { ObeliskHashmask } from "src/services/nft/ObeliskHashmask.sol";
import { StreamingPool } from "src/services/StreamingPool.sol";
import { InterestManager } from "src/services/InterestManager.sol";
import { Megapool } from "src/services/tickers/Megapool.sol";
import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IApxETH } from "src/vendor/dinero/IApxETH.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract ProtocolE2E is BaseTest {
  address private owner;
  address private treasury;
  address[] private users;

  ApxETHVault private apxVault;
  ChaiMoneyVault private daiVault;
  ObeliskRegistry private obeliskRegistry;
  ObeliskHashmask private obeliskHashmask;
  InterestManager private interestManager;
  StreamingPool private streamingPool;
  HCT private hct;
  NFTPass private nftPass;
  Megapool private megapool01;

  address private apxETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
  address private chaiMoney = 0x06AF07097C9Eeb7fD685c692751D5C66dB49c215;
  address private dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address private nameFilter = 0xee2b6483b966C7497dd8d4bb183763cdf6fC73aC;
  address private hashmask = 0xC2C747E0F7004F9E8817Db2ca4997657a7746928;
  address private swapRouter = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
  address private weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address private chainlinkDaiETH = 0x773616E4d11A78F511299002da57A0a94577F1f4;
  uint256 private nftPassCost = 0.05 ether;

  MockERC721 private mockERC721;

  function setUp() external {
    vm.createSelectFork(vm.envString("RPC_MAINNET"));

    owner = generateAddress("Owner");
    treasury = generateAddress("Treasury");
    mockERC721 = new MockERC721();

    vm.startPrank(owner);

    for (uint256 i = 0; i < 10; i++) {
      users.push(generateAddress(string.concat("User ", Strings.toString(i)), 25e18));
      mockERC721.mint(users[i], i + 1);
    }

    nftPass = new NFTPass(owner, treasury, nameFilter, nftPassCost, bytes32(0));
    apxVault = new ApxETHVault(owner, address(0), apxETH, address(0));
    daiVault = new ChaiMoneyVault(owner, address(0), chaiMoney, dai, address(0));
    obeliskRegistry = new ObeliskRegistry(
      owner, treasury, address(nftPass), address(apxVault), address(daiVault), dai
    );

    hct = HCT(obeliskRegistry.HCT_ADDRESS());
    obeliskHashmask =
      new ObeliskHashmask(hashmask, owner, address(obeliskRegistry), treasury);

    interestManager = new InterestManager(
      owner,
      address(0),
      address(apxVault),
      address(daiVault),
      swapRouter,
      chainlinkDaiETH,
      weth
    );

    streamingPool = new StreamingPool(owner, address(interestManager), apxETH);
    megapool01 =
      new Megapool(owner, address(obeliskRegistry), apxETH, address(interestManager));

    interestManager.setStreamingPool(address(streamingPool));
    daiVault.setObeliskRegistry(address(obeliskRegistry));
    daiVault.setInterestRateReceiver(address(interestManager));

    apxVault.setObeliskRegistry(address(obeliskRegistry));
    apxVault.setInterestRateReceiver(address(interestManager));

    obeliskRegistry.toggleIsWrappedNFTFor(hashmask, address(obeliskHashmask), true);

    vm.stopPrank();
  }

  function test_obeliskRegistry_flow_addToCollection() external pranking {
    _createCollection();

    changePrank(users[9]);
    obeliskRegistry.addToCollection{ value: 20e18 }(address(mockERC721));
  }

  function test_obeliskRegistry_flow_removeFromCollection() external pranking {
    _createCollection();

    changePrank(users[0]);
    uint256 removingAmount = 15e18;
    uint256 expectingBalanceApx = IApxETH(apxETH).convertToShares(removingAmount);

    obeliskRegistry.removeFromCollection(address(mockERC721), removingAmount);

    assertEq(IERC20(apxETH).balanceOf(address(users[0])), expectingBalanceApx);
    assertEq(
      obeliskRegistry.getUserContribution(address(users[0]), address(mockERC721)).deposit,
      5e18
    );

    for (uint256 i = 0; i < 4; i++) {
      changePrank(users[i]);
      obeliskRegistry.removeFromCollection(address(mockERC721), 0);

      assertEq(
        obeliskRegistry.getUserContribution(address(users[i]), address(mockERC721))
          .deposit,
        0
      );
    }

    assertEq(obeliskRegistry.getCollection(address(mockERC721)).contributionBalance, 0);
  }

  function test_flow_supportYield() external { }

  function test_flow_wrappedNFT() external { }

  function _createCollection() internal {
    changePrank(owner);
    obeliskRegistry.allowNewCollection(
      address(mockERC721), 10, uint32(block.timestamp - 365 days), false
    );

    for (uint256 i = 0; i < 4; i++) {
      changePrank(users[i]);
      obeliskRegistry.addToCollection{ value: 20e18 }(address(mockERC721));
    }
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/base/BaseTest.t.sol";
import { ApxETHVault } from "src/services/liquidity/ApxETHVault.sol";
import { ChaiMoneyVault } from "src/services/liquidity/ChaiMoneyVault.sol";
import { ObeliskRegistry } from "src/services/nft/ObeliskRegistry.sol";
import { HCT } from "src/services/HCT.sol";
import { NFTPass } from "src/services/nft/NFTPass.sol";
import { ObeliskHashmask } from "src/services/nft/ObeliskHashmask.sol";
import { StreamingPool } from "src/services/StreamingPool.sol";
import { InterestManager } from "src/services/InterestManager.sol";
import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IApxETH } from "src/vendor/dinero/IApxETH.sol";
import { WrappedNFTHero } from "src/services/nft/WrappedNFTHero.sol";
import { NameFilter } from "src/vendor/heroglyph/NameFilter.sol";
import { MegapoolFactory } from "src/services/MegapoolFactory.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract ProtocolE2E is BaseTest {
  address private owner;
  address private treasury;
  address private gaugeController;
  address[] private users;

  ApxETHVault private apxVault;
  ChaiMoneyVault private daiVault;
  ObeliskRegistry private obeliskRegistry;
  ObeliskHashmask private obeliskHashmask;
  InterestManager private interestManager;
  StreamingPool private streamingPool;
  HCT private hct;
  NFTPass private nftPass;
  MegapoolFactory private megapoolFactory;

  address private apxETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
  address private chaiMoney = 0x06AF07097C9Eeb7fD685c692751D5C66dB49c215;
  address private dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address private hashmask = 0xC2C747E0F7004F9E8817Db2ca4997657a7746928;
  address private swapRouter = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
  address private weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address private chainlinkDaiETH = 0x773616E4d11A78F511299002da57A0a94577F1f4;
  uint256 private nftPassCost = 0.05 ether;
  address private nameFilter;

  MockERC721 private mockERC721;

  function setUp() external {
    vm.createSelectFork(vm.envString("RPC_MAINNET"));

    nameFilter = address(new NameFilter());

    owner = generateAddress("Owner");
    treasury = generateAddress("Treasury");
    gaugeController = generateAddress("Gauge Controller");
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
      gaugeController,
      address(apxVault),
      address(daiVault),
      swapRouter,
      chainlinkDaiETH,
      weth
    );

    streamingPool = new StreamingPool(owner, address(interestManager), apxETH);
    megapoolFactory = new MegapoolFactory(
      owner, address(obeliskRegistry), address(hct), apxETH, address(interestManager)
    );

    vm.label(address(nftPass), "NFT Pass");
    vm.label(address(apxVault), "ApxETH Vault");
    vm.label(address(daiVault), "Chai Money Vault");
    vm.label(address(obeliskRegistry), "Obelisk Registry");
    vm.label(address(hct), "HCT");
    vm.label(address(obeliskHashmask), "Obelisk Hashmask");
    vm.label(address(interestManager), "Interest Manager");
    vm.label(address(streamingPool), "Streaming Pool");
    vm.label(address(megapoolFactory), "Megapool Factory");

    interestManager.setStreamingPool(address(streamingPool));
    daiVault.setObeliskRegistry(address(obeliskRegistry));
    daiVault.setInterestRateReceiver(address(interestManager));

    apxVault.setObeliskRegistry(address(obeliskRegistry));
    apxVault.setInterestRateReceiver(address(interestManager));

    obeliskRegistry.toggleIsWrappedNFTFor(hashmask, address(obeliskHashmask), true);
    obeliskRegistry.setMegapoolFactory(address(megapoolFactory));

    megapoolFactory.createMegapool(new address[](0));

    vm.stopPrank();

    assertEq(obeliskRegistry.getTickerLogic("MEGAPOOL_001"), megapoolFactory.megapools(1));
  }

  function test_obeliskRegistry_flow_addToCollection() external pranking {
    _createCollection();

    changePrank(users[9]);
    obeliskRegistry.addToCollection{ value: 20e18 }(address(mockERC721));

    assertTrue(
      obeliskRegistry.getCollection(address(mockERC721)).wrappedVersion != address(0)
    );

    skip(30 days);

    apxVault.claim();
    assertGt(IApxETH(apxETH).balanceOf(address(interestManager)), 0);
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

      skip(1 days);

      assertEq(
        obeliskRegistry.getUserContribution(address(users[i]), address(mockERC721))
          .deposit,
        0
      );
    }

    apxVault.claim();

    assertEq(obeliskRegistry.getCollection(address(mockERC721)).contributionBalance, 0);
    assertGt(IApxETH(apxETH).balanceOf(address(interestManager)), 0);
  }

  function test_flow_supportYield() external pranking {
    _createCollection();
    uint256 support = 9.93e18;

    changePrank(users[8]);
    obeliskRegistry.supportYieldPool{ value: support }(0);

    assertEq(obeliskRegistry.getSupporter(1).amount, support);

    skip(30 days);

    uint256 expectingBalanceApx = IApxETH(apxETH).convertToShares(support);
    obeliskRegistry.retrieveSupportToYieldPool(1);

    assertTrue(obeliskRegistry.getSupporter(1).removed);
    assertEq(IERC20(apxETH).balanceOf(address(users[8])), expectingBalanceApx);
  }

  function test_flow_wrappedNFT() external {
    _createCollection();

    changePrank(users[9]);
    obeliskRegistry.addToCollection{ value: 20e18 }(address(mockERC721));

    WrappedNFTHero wrapped =
      WrappedNFTHero(obeliskRegistry.getCollection(address(mockERC721)).wrappedVersion);

    changePrank(users[0]);
    wrapped.wrap(1);

    wrapped.unwrap(1);
    assertEq(mockERC721.ownerOf(1), users[0]);
  }

  function test_flow_wrappedNFT_tickersFarming() external pranking {
    _createCollection();

    changePrank(users[9]);
    obeliskRegistry.addToCollection{ value: 20e18 }(address(mockERC721));

    WrappedNFTHero wrapped =
      WrappedNFTHero(obeliskRegistry.getCollection(address(mockERC721)).wrappedVersion);

    changePrank(users[0]);
    vm.deal(users[0], 1e18);
    nftPass.create{ value: 1e18 }("me", users[0]);
    wrapped.wrap(1);

    skip(250 days);

    hct.claim();
    wrapped.rename(1, "@me #MEGAPOOL_001");

    changePrank(gaugeController);
    address[] memory megapools = new address[](1);
    megapools[0] = megapoolFactory.megapools(1);
    uint128[] memory weights = new uint128[](1);
    weights[0] = 10_000;

    interestManager.applyGauges(megapools, weights);
    skip(30 days);

    changePrank(users[0]);
    wrapped.claim(1);

    assertGt(IERC20(apxETH).balanceOf(address(users[0])), 0);
  }

  function _createCollection() internal {
    changePrank(owner);
    obeliskRegistry.allowNewCollection(
      address(mockERC721), 10, uint32(block.timestamp - 400 days), false
    );

    for (uint256 i = 0; i < 4; i++) {
      changePrank(users[i]);
      obeliskRegistry.addToCollection{ value: 20e18 }(address(mockERC721));
    }
  }
}

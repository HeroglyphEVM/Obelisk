// // SPDX-License-Identifier: Unlicense
// pragma solidity >=0.8.0;

// import "test/base/BaseTest.t.sol";

// import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
// import { IHCT } from "src/interfaces/IHCT.sol";
// import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";

// import { MockERC721 } from "test/mock/contract/MockERC721.t.sol";
// import { WrappedNFTHero, IWrappedNFTHero } from "src/services/staking/nft/WrappedNFTHero.sol";

// contract WrappedNFTHeroTest is BaseTest {
//   uint128 private constant TOTAL_SUPPLY = 10_000e18;

//   address private hctMock;
//   MockERC721 private nftCollectionMock;
//   address private obeliskRegistryMock;
//   address private user;

//   string[] private tickers = ["#Pool", "HenZ", "MyWorld"];
//   address[] private poolTargets =
//     [generateAddress("PoolTarget1"), generateAddress("PoolTarget2"), generateAddress("PoolTarget3")];

//   WrappedNFTHero underTest;

//   function setUp() external {
//     _prepareMocks();
//     _mockCalls();

//     nftCollectionMock.mint(user, 1);

//     underTest = new WrappedNFTHero(
//       hctMock, address(nftCollectionMock), obeliskRegistryMock, TOTAL_SUPPLY, uint32(block.timestamp)
//     );
//   }

//   function _prepareMocks() internal {
//     hctMock = generateAddress("HCTMock");
//     nftCollectionMock = new MockERC721();
//     obeliskRegistryMock = generateAddress("obeliskRegistryMock");
//     user = generateAddress("User");
//   }

//   function _mockCalls() internal {
//     for (uint256 i = 0; i < poolTargets.length; i++) {
//       vm.mockCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector), abi.encode(true));
//       vm.mockCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector), abi.encode(true));
//       vm.mockCall(
//         obeliskRegistryMock,
//         abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, tickers[i]),
//         abi.encode(poolTargets[i])
//       );
//     }

//     vm.mockCall(hctMock, abi.encodeWithSelector(IHCT.addPower.selector), abi.encode(true));
//     vm.mockCall(hctMock, abi.encodeWithSelector(IHCT.usesForRenaming.selector), abi.encode(true));
//   }

//   function test_constructor_thenSetsValues() external {
//     underTest = new WrappedNFTHero(hctMock, address(nftCollectionMock), obeliskRegistryMock, 10_000, 999_928);

//     assertEq(address(underTest.HCT()), hctMock);
//     assertEq(address(underTest.attachedCollection()), address(nftCollectionMock));
//     assertEq(address(underTest.obeliskRegistry()), obeliskRegistryMock);
//   }

//   function test_wrap_whenAlreadyMinted_thenReverts() external prankAs(user) {
//     underTest.wrap(1);
//     vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.AlreadyMinted.selector));
//     underTest.wrap(1);
//   }

//   function test_wrap_thenWraps() external prankAs(user) {
//     uint256 tokenId = 929;
//     nftCollectionMock.mint(user, tokenId);

//     vm.expectCall(hctMock, abi.encodeWithSelector(IHCT.addPower.selector, tokenId));

//     expectExactEmit();
//     emit IWrappedNFTHero.Wrapped(tokenId);
//     underTest.wrap(tokenId);

//     assertEq(underTest.ownerOf(tokenId), user);
//     assertEq(nftCollectionMock.ownerOf(tokenId), address(underTest));
//   }

//   function test_unwrap_whenTokenIsNotMinted_thenReverts() external {
//     vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotMinted.selector));
//     underTest.unwrap(1);
//   }

//   function test_unwrap_thenUnwraps() external prankAs(user) {
//     uint256 tokenId = 929;
//     nftCollectionMock.mint(user, tokenId);
//     underTest.wrap(tokenId);

//     vm.expectCall(hctMock, abi.encodeWithSelector(IHCT.removePower.selector, tokenId));

//     expectExactEmit();
//     emit IWrappedNFTHero.Unwrapped(tokenId);
//     underTest.unwrap(tokenId);

//     assertEq(nftCollectionMock.ownerOf(tokenId), user);

//     vm.expectRevert();
//     underTest.ownerOf(tokenId);
//   }

//   function test_rename_whenTokenIsNotMinted_thenReverts() external {
//     vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.NotMinted.selector));
//     underTest.rename(1, "1");
//   }

//   function test_rename_whenInvalidNameLength_thenReverts() external prankAs(user) {
//     underTest.wrap(1);

//     bytes memory emptyName = new bytes(0);
//     bytes memory tooLongName = new bytes(33);

//     vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.InvalidNameLength.selector));
//     underTest.rename(1, string(emptyName));
//     vm.expectRevert(abi.encodeWithSelector(IWrappedNFTHero.InvalidNameLength.selector));
//     underTest.rename(1, string(tooLongName));
//   }

//   function test_rename_thenDeactiveOldTickersAndUpdatesTickers() external prankAs(user) {
//     underTest.wrap(1);
//     for (uint256 i = 0; i < poolTargets.length; i++) {
//       vm.expectCall(
//         obeliskRegistryMock, abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, tickers[i])
//       );
//       vm.expectCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, 1, user));
//     }

//     underTest.rename(1, "MyNFT ##Pool,HenZ,MyWorld");
//     assertEq(abi.encode(underTest.getActiveTickerPools(1)), abi.encode(poolTargets));

//     for (uint256 i = 0; i < poolTargets.length; i++) {
//       vm.expectCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector, 1, user));

//       if (i > 0) {
//         vm.expectCall(
//           obeliskRegistryMock, abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, tickers[i])
//         );
//         vm.expectCall(poolTargets[i], abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, 1, user));
//       }
//     }

//     underTest.rename(1, "MyNFT Test #HenZ,MyWorld");
//     poolTargets[0] = poolTargets[1];
//     poolTargets[1] = poolTargets[2];
//     poolTargets.pop();

//     assertEq(abi.encode(underTest.getActiveTickerPools(1)), abi.encode(poolTargets));
//   }
// }

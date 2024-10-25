// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "test/base/BaseTest.t.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { ObeliskNFT, IObeliskNFT } from "src/services/nft/ObeliskNFT.sol";
import { INFTPass } from "src/interfaces/INFTPass.sol";

contract ObeliskNFTTest is BaseTest {
  string[] private TICKERS = ["Hello", "megaPool", "Bobby"];
  address[] private POOL_TARGETS =
    [generateAddress("Pool A"), generateAddress("Pool B"), generateAddress("Pool C")];
  string private constant IDENTITY_NAME = "M";
  string private constant START_NAME = "@M #";

  address private mockNftPass;
  address private mockObeliskRegistry;

  INFTPass.Metadata private EMPTY_NFT_METADATA;
  INFTPass.Metadata private mockNftPassMetadata = INFTPass.Metadata({
    name: IDENTITY_NAME,
    walletReceiver: generateAddress("Identity Receiver")
  });

  ObeliskNFTHarness private underTest;

  function setUp() public {
    _createVariables();
    _createMockCalls();

    underTest = new ObeliskNFTHarness(mockObeliskRegistry, mockNftPass);
  }

  function _createVariables() internal {
    mockObeliskRegistry = generateAddress("ObeliskRegistry");
    mockNftPass = generateAddress("NftPass");
  }

  function _createMockCalls() internal {
    for (uint256 i = 0; i < TICKERS.length; i++) {
      vm.mockCall(
        mockObeliskRegistry,
        abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[i]),
        abi.encode(POOL_TARGETS[i])
      );

      vm.mockCall(
        POOL_TARGETS[i],
        abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector),
        abi.encode(true)
      );
      vm.mockCall(
        POOL_TARGETS[i],
        abi.encodeWithSelector(ILiteTicker.virtualWithdraw.selector),
        abi.encode(true)
      );
    }

    vm.mockCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector),
      abi.encode(address(0))
    );

    vm.mockCall(
      mockNftPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.mockCall(
      mockNftPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector),
      abi.encode(EMPTY_NFT_METADATA)
    );
  }

  function test_construction_thenSetups() external {
    underTest = new ObeliskNFTHarness(mockObeliskRegistry, mockNftPass);

    assertEq(address(underTest.obeliskRegistry()), mockObeliskRegistry);
    assertEq(address(underTest.NFT_PASS()), mockNftPass);
  }

  function test_rename_whenNameIsTooLong_thenReverts() external {
    string memory tooLongName = string(new bytes(30));

    vm.expectRevert(IObeliskNFT.InvalidNameLength.selector);
    underTest.rename(0, tooLongName);

    vm.expectRevert(IObeliskNFT.InvalidNameLength.selector);
    underTest.rename(0, "");
  }

  function test_rename_whenRenameRequirementsReverts_thenReverts() external {
    underTest.exposed_setTriggerRevert(true);

    vm.expectRevert(ObeliskNFTHarness.RequirementsReverted.selector);
    underTest.rename(0, "Hello");
  }

  function test_rename_whenNoIdentityFound_thenReverts() external {
    vm.expectRevert(IObeliskNFT.InvalidWalletReceiver.selector);
    underTest.rename(0, "Hello");
  }

  function test_rename_whenNoTickers_thenRenames() external {
    string memory newName = string.concat("NewName @", IDENTITY_NAME);
    uint256 tokenId = 23;

    expectExactEmit();
    emit IObeliskNFT.NameChanged(tokenId, newName);
    underTest.rename(tokenId, newName);

    assertEq(underTest.names(tokenId), newName);
    assertEq(underTest.getIdentityReceiver(tokenId), mockNftPassMetadata.walletReceiver);
  }

  function test_rename_givenTickers_thenAddsNewTickers() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[0])
    );
    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualDeposit.selector, tokenId, mockNftPassMetadata.walletReceiver
      )
    );

    underTest.rename(tokenId, newName);

    assertEq(underTest.names(tokenId), newName);
    assertEq(underTest.getIdentityReceiver(tokenId), mockNftPassMetadata.walletReceiver);
    assertEq(underTest.getLinkedTickers(tokenId)[0], POOL_TARGETS[0]);
    assertEq(underTest.getLinkedTickers(tokenId).length, 1);
  }

  function test_rename_whenHasTickers_thenRemovesOldTickers() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    underTest.rename(tokenId, newName);
    newName = string.concat(START_NAME, TICKERS[1]);

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualWithdraw.selector,
        tokenId,
        mockNftPassMetadata.walletReceiver,
        false
      )
    );

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[1])
    );
    vm.expectCall(
      POOL_TARGETS[1],
      abi.encodeWithSelector(
        ILiteTicker.virtualDeposit.selector, tokenId, mockNftPassMetadata.walletReceiver
      )
    );

    underTest.rename(tokenId, newName);
  }

  function test_rename_whenChangeIdentityReceiver_thenRemoveFromOldAndUpdatesToNew()
    external
  {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    underTest.rename(tokenId, newName);
    newName = string.concat(START_NAME, TICKERS[1]);

    address oldReceiver = mockNftPassMetadata.walletReceiver;
    address newReceiver = generateAddress("New Identity Receiver");
    mockNftPassMetadata.walletReceiver = newReceiver;

    vm.mockCall(
      mockNftPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualWithdraw.selector, tokenId, oldReceiver, false
      )
    );

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[1])
    );
    vm.expectCall(
      POOL_TARGETS[1],
      abi.encodeWithSelector(ILiteTicker.virtualDeposit.selector, tokenId, newReceiver)
    );

    underTest.rename(tokenId, newName);
    assertEq(underTest.getIdentityReceiver(tokenId), newReceiver);
  }

  function test_updateIdentityReceiver_whenNoIdentityFound_thenReverts() external {
    mockNftPassMetadata.walletReceiver = address(0);

    vm.mockCall(
      mockNftPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.expectRevert(IObeliskNFT.InvalidWalletReceiver.selector);
    underTest.updateIdentityReceiver(0);
  }

  function test_updateIdentityReceiver_whenNoTickers_thenUpdatesIdentity() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    underTest.rename(tokenId, newName);

    mockNftPassMetadata.walletReceiver = generateAddress("New Identity Receiver");

    vm.mockCall(
      mockNftPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    underTest.updateIdentityReceiver(tokenId);

    assertEq(underTest.getIdentityReceiver(tokenId), mockNftPassMetadata.walletReceiver);
  }

  function test_updateIdentityReceiver_whenHasTickers_thenRemovesOldAndAddsNew() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    underTest.rename(tokenId, newName);

    address oldReceiver = mockNftPassMetadata.walletReceiver;
    mockNftPassMetadata.walletReceiver = generateAddress("New Identity Receiver");

    vm.mockCall(
      mockNftPass,
      abi.encodeWithSelector(INFTPass.getMetadata.selector, 0, IDENTITY_NAME),
      abi.encode(mockNftPassMetadata)
    );

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualWithdraw.selector, tokenId, oldReceiver, false
      )
    );

    vm.expectCall(
      mockObeliskRegistry,
      abi.encodeWithSelector(IObeliskRegistry.getTickerLogic.selector, TICKERS[0])
    );
    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.virtualDeposit.selector, tokenId, mockNftPassMetadata.walletReceiver
      )
    );

    underTest.updateIdentityReceiver(tokenId);

    assertEq(underTest.getIdentityReceiver(tokenId), mockNftPassMetadata.walletReceiver);
  }

  function test_claim_whenCanClaim_thenCallsTickersWithRewards() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    underTest.rename(tokenId, newName);
    underTest.exposed_setCanClaim(true);

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.claim.selector, tokenId, mockNftPassMetadata.walletReceiver, false
      )
    );

    underTest.claim(tokenId);
  }

  function test_claim_whenCannotClaim_thenCallsTickersWithoutRewards() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    underTest.rename(tokenId, newName);
    underTest.exposed_setCanClaim(false);

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.claim.selector, tokenId, mockNftPassMetadata.walletReceiver, true
      )
    );

    underTest.claim(tokenId);
  }
}

contract ObeliskNFTHarness is ObeliskNFT {
  bool public canClaim;
  bool public triggerRevert;

  error RequirementsReverted();

  constructor(address _obeliskRegistry, address _nftPass)
    ObeliskNFT(_obeliskRegistry, _nftPass)
  { }

  function exposed_setTriggerRevert(bool _triggerRevert) external {
    triggerRevert = _triggerRevert;
  }

  function _renameRequirements(uint256) internal view override {
    if (triggerRevert) revert RequirementsReverted();
  }

  function exposed_setCanClaim(bool _canClaim) external {
    canClaim = _canClaim;
  }

  function _claimRequirements(uint256) internal view override returns (bool) {
    return canClaim;
  }
}

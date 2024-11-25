// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "test/base/BaseTest.t.sol";

import { IObeliskRegistry } from "src/interfaces/IObeliskRegistry.sol";
import { ILiteTicker } from "src/interfaces/ILiteTicker.sol";
import { ObeliskNFT } from "src/services/nft/ObeliskNFT.sol";
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
    walletReceiver: generateAddress("Identity Receiver"),
    imageIndex: 1
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

  function test_claim_whenCanClaim_thenCallsTickersWithRewards() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    bytes32 identity = keccak256(abi.encode(mockNftPassMetadata.walletReceiver));
    address receiver = mockNftPassMetadata.walletReceiver;

    underTest.mockIdentityInformation(identity, receiver);
    underTest.exposed_addNewTickers(identity, receiver, tokenId, newName);

    underTest.exposed_setCanClaim(true);

    vm.expectCall(
      POOL_TARGETS[0],
      abi.encodeWithSelector(
        ILiteTicker.claim.selector,
        identity,
        tokenId,
        mockNftPassMetadata.walletReceiver,
        false
      )
    );

    underTest.claim(tokenId);
  }

  function test_claim_whenCannotClaim_thenReverts() external {
    string memory newName = string.concat(START_NAME, TICKERS[0]);
    uint256 tokenId = 23;

    bytes32 identity = keccak256(abi.encode(mockNftPassMetadata.walletReceiver));
    address receiver = mockNftPassMetadata.walletReceiver;

    underTest.mockIdentityInformation(identity, receiver);
    underTest.exposed_addNewTickers(identity, receiver, tokenId, newName);

    underTest.exposed_setCanClaim(false);

    vm.expectRevert();
    underTest.claim(tokenId);
  }
}

contract ObeliskNFTHarness is ObeliskNFT {
  bool public canClaim;
  bool public triggerRevert;

  bytes32 public mockedIdentity;
  address public mockedReceiver;

  error RequirementsReverted();

  constructor(address _obeliskRegistry, address _nftPass)
    ObeliskNFT(_obeliskRegistry, _nftPass)
  { }

  function exposed_setCanClaim(bool _canClaim) external {
    canClaim = _canClaim;
  }

  function exposed_addNewTickers(
    bytes32 _identity,
    address _receiver,
    uint256 _tokenId,
    string memory _name
  ) external {
    _addNewTickers(_identity, _receiver, _tokenId, _name);
  }

  function _claimRequirements(uint256) internal view override returns (bool) {
    return canClaim;
  }

  function mockIdentityInformation(bytes32 _identity, address _receiver) external {
    mockedIdentity = _identity;
    mockedReceiver = _receiver;
  }

  function _getIdentityInformation(uint256 _tokenId)
    internal
    view
    override
    returns (bytes32, address)
  {
    return (mockedIdentity, mockedReceiver);
  }
}

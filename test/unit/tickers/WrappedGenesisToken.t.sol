// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "test/base/BaseTest.t.sol";
import { WrappedGenesisToken } from "src/services/tickers/WrappedGenesisToken.sol";

import { ILayerZeroEndpointV2 } from
  "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {
  MessagingReceipt,
  MessagingParams,
  MessagingFee,
  Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IGenesisTokenPool } from "src/interfaces/IGenesisTokenPool.sol";

contract WrappedGenesisTokenTest is BaseTest {
  uint32 private constant MAINNET_LZ_ENDPOINT_ID = 30_101;
  uint32 private constant ORIGIN_LZ_ENDPOITN = 48_271;
  bytes32 private constant PEER = bytes32("PEER");
  uint256 private constant LZ_FEE = 2_399_482;
  Origin private origin = Origin({ srcEid: 1, sender: bytes32("PEER"), nonce: 0 });

  address private owner;
  address private user;
  address private lzEndpoint;
  address private pool;
  MockERC20 private genesisToken;

  bytes private defaultLzOption;
  WrappedGnosisTokenHarness private underTest;

  function setUp() external {
    _setupVariables();

    vm.mockCall(
      lzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true)
    );
    vm.mockCall(
      lzEndpoint,
      abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
      abi.encode(MessagingFee(LZ_FEE, 0))
    );

    MessagingReceipt memory emptyMsg;
    vm.mockCall(
      lzEndpoint,
      abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector),
      abi.encode(emptyMsg)
    );

    genesisToken.mint(user, 100e18);
    underTest = new WrappedGnosisTokenHarness(
      owner, ORIGIN_LZ_ENDPOITN, lzEndpoint, address(genesisToken)
    );

    vm.startPrank(owner);
    underTest.attachPool(pool);
    underTest.setPeer(MAINNET_LZ_ENDPOINT_ID, PEER);
    underTest.setPeer(ORIGIN_LZ_ENDPOITN, PEER);
    vm.stopPrank();

    vm.mockCall(
      pool,
      abi.encodeWithSelector(IGenesisTokenPool.notifyRewardAmount.selector),
      abi.encode(true)
    );

    defaultLzOption = underTest.defaultLzOption();
  }

  function _setupVariables() internal {
    owner = generateAddress("owner");
    user = generateAddress("user", 9999e18);
    lzEndpoint = generateAddress("lzEndpoint");
    genesisToken = new MockERC20("GenesisToken", "GT", 18);
    pool = generateAddress("pool");
  }

  function test_constructor_thenContractIsInitialized() external {
    underTest = new WrappedGnosisTokenHarness(
      owner, ORIGIN_LZ_ENDPOITN, lzEndpoint, address(genesisToken)
    );

    assertEq(underTest.owner(), owner);
    assertEq(underTest.genesisToken(), address(genesisToken));
    assertEq(underTest.originLzEndpoint(), ORIGIN_LZ_ENDPOITN);
  }

  function test_addRewardOnMainnet_whenOnMainnet_thenReverts() external {
    vm.chainId(1);

    vm.expectRevert(
      abi.encodeWithSelector(WrappedGenesisToken.CannotWrapOnMainnet.selector)
    );
    underTest.addRewardOnMainnet{ value: 1 ether }(100e18);
  }

  function test_addRewardOnMainnet_whenPayingTooMuchFeeOrTooLittle_thenReverts()
    external
    prankAs(user)
  {
    vm.expectRevert();
    underTest.addRewardOnMainnet{ value: LZ_FEE + 1 }(100e18);

    vm.expectRevert();
    underTest.addRewardOnMainnet{ value: LZ_FEE - 1 }(100e18);
  }

  function test_addRewardOnMainnet_thenCallsLayerZero() external prankAs(user) {
    uint256 amount = 37.2e18;

    _expectLZSend(
      LZ_FEE,
      MAINNET_LZ_ENDPOINT_ID,
      abi.encode(address(0), amount, false),
      defaultLzOption,
      user
    );

    underTest.addRewardOnMainnet{ value: LZ_FEE }(amount);
  }

  function test_unwrap_thenUnwraps() external prankAs(user) {
    uint256 amount = 37.2e18;

    underTest.exposed_mint(user, amount);

    _expectLZSend(
      LZ_FEE, ORIGIN_LZ_ENDPOITN, abi.encode(user, amount, true), defaultLzOption, user
    );

    underTest.unwrap{ value: LZ_FEE }(user, amount);

    assertEq(underTest.balanceOf(user), 0);
  }

  function test_lzReceive_whenUnwrap_thenSendsUnwrappedVersion() external {
    uint256 amount = 37.2e18;
    address to = generateAddress("to");

    genesisToken.mint(address(underTest), amount);

    underTest.exposed_lzReceive(origin, abi.encode(to, amount, true), defaultLzOption);

    assertEq(genesisToken.balanceOf(to), amount);
  }

  function test_lzReceive_whenToIsZero_thenMintsToPool() external {
    uint256 amount = 37.2e18;

    vm.expectCall(
      pool, abi.encodeWithSelector(IGenesisTokenPool.notifyRewardAmount.selector, amount)
    );
    underTest.exposed_lzReceive(
      origin, abi.encode(address(0), amount, false), defaultLzOption
    );

    assertEq(underTest.balanceOf(pool), amount);
  }

  function test_lzReceive_whenToIsZeroAndPoolZero_thenMintsToOwner() external {
    uint256 amount = 37.2e18;

    vm.prank(owner);
    underTest.attachPool(address(0));

    uint256 balanceBefore = underTest.balanceOf(owner);

    underTest.exposed_lzReceive(
      origin, abi.encode(address(0), amount, false), defaultLzOption
    );

    assertEq(underTest.balanceOf(owner) - balanceBefore, amount);
  }

  function test_lzReceive_whenToIsUser_thenMintsToUser() external {
    uint256 amount = 37.2e18;

    vm.mockCallRevert(
      pool,
      abi.encodeWithSelector(IGenesisTokenPool.notifyRewardAmount.selector),
      abi.encode("Shouldn't be called")
    );
    underTest.exposed_lzReceive(origin, abi.encode(user, amount, false), defaultLzOption);

    assertEq(underTest.balanceOf(user), amount);
  }

  function test_retrieveToken_whenCalledByNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.retrieveToken(address(genesisToken));
  }

  function test_retrieveToken_whenCalledByOwner_thenTransfersBalance()
    external
    prankAs(owner)
  {
    uint256 amount = 37.2e18;
    MockERC20 token = new MockERC20("Token", "TKN", 18);
    token.mint(address(underTest), amount);
    underTest.retrieveToken(address(token));

    assertEq(token.balanceOf(owner), amount);
  }

  function test_updateLayerZeroGasLimit_whenCalledByNonOwner_thenReverts()
    external
    prankAs(user)
  {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.updateLayerZeroGasLimit(100);
  }

  function test_updateLayerZeroGasLimit_whenCalledByOwner_thenUpdates()
    external
    prankAs(owner)
  {
    underTest.updateLayerZeroGasLimit(100);
    assertEq(underTest.lzGasLimit(), 100);
  }

  function test_attachPool_whenCalledByNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(
      abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
    );
    underTest.attachPool(pool);
  }

  function test_attachPool_whenCalledByOwner_thenUpdates() external prankAs(owner) {
    address newPool = generateAddress("newPool");
    underTest.attachPool(newPool);
    assertEq(address(underTest.pool()), newPool);
  }

  function _expectLZSend(
    uint256 _fee,
    uint32 _toEndpoint,
    bytes memory _payload,
    bytes memory _option,
    address _refund
  ) private {
    vm.expectCall(
      lzEndpoint,
      _fee,
      abi.encodeWithSelector(
        ILayerZeroEndpointV2.send.selector,
        MessagingParams(_toEndpoint, PEER, _payload, _option, false),
        _refund
      )
    );
  }
}

contract WrappedGnosisTokenHarness is WrappedGenesisToken {
  constructor(
    address _owner,
    uint32 _originLzEndpoint,
    address _lzEndpoint,
    address _genesisToken
  ) WrappedGenesisToken(_owner, _originLzEndpoint, _lzEndpoint, _genesisToken) { }

  function exposed_mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function exposed_lzReceive(
    Origin calldata _origin,
    bytes calldata _message,
    bytes calldata _extraData
  ) external {
    _lzReceive(_origin, bytes32("guid"), _message, address(0), _extraData);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "test/base/BaseTest.t.sol";
import { WrappedGnosisToken } from "src/services/tickers/WrappedGnosisToken.sol";

import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {
  MessagingReceipt,
  MessagingParams,
  MessagingFee,
  Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IGenesisTokenPool } from "src/interfaces/IGenesisTokenPool.sol";

contract WrappedGnosisTokenTest is BaseTest {
  uint32 private constant MAINNET_LZ_ENDPOINT_ID = 30_101;
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

    vm.mockCall(lzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));
    vm.mockCall(
      lzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector), abi.encode(MessagingFee(LZ_FEE, 0))
    );

    MessagingReceipt memory emptyMsg;
    vm.mockCall(lzEndpoint, abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector), abi.encode(emptyMsg));

    genesisToken.mint(user, 100e18);
    underTest = new WrappedGnosisTokenHarness(owner, lzEndpoint, address(genesisToken));

    vm.startPrank(owner);
    underTest.attachPool(pool);
    underTest.setPeer(MAINNET_LZ_ENDPOINT_ID, PEER);
    vm.stopPrank();

    vm.mockCall(pool, abi.encodeWithSelector(IGenesisTokenPool.notifyRewardAmount.selector), abi.encode(true));

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
    underTest = new WrappedGnosisTokenHarness(owner, lzEndpoint, address(genesisToken));

    assertEq(underTest.owner(), owner);
    assertEq(underTest.genesisToken(), address(genesisToken));
  }

  function test_addRewardOnMainnet_whenOnMainnet_thenReverts() external {
    vm.chainId(1);

    vm.expectRevert(abi.encodeWithSelector(WrappedGnosisToken.CannotWrapOnMainnet.selector));
    underTest.addRewardOnMainnet{ value: 1 ether }(100e18);
  }

  function test_addRewardOnMainnet_whenPayingTooMuchFeeOrTooLittle_thenReverts() external prankAs(user) {
    vm.expectRevert();
    underTest.addRewardOnMainnet{ value: LZ_FEE + 1 }(100e18);

    vm.expectRevert();
    underTest.addRewardOnMainnet{ value: LZ_FEE - 1 }(100e18);
  }

  function test_addRewardOnMainnet_thenCallsLayerZero() external prankAs(user) {
    uint256 amount = 37.2e18;

    _expectLZSend(LZ_FEE, MAINNET_LZ_ENDPOINT_ID, abi.encode(address(0), amount), defaultLzOption, user);
    underTest.addRewardOnMainnet{ value: LZ_FEE }(amount);
  }

  function test_unwrap_onMainnet_thenReverts() external {
    vm.chainId(1);
    vm.expectRevert(abi.encodeWithSelector(WrappedGnosisToken.CannotUnwrapOnMainnet.selector));
    underTest.unwrap(100e18);
  }

  function test_unwrap_thenUnwraps() external prankAs(user) {
    uint256 amount = 37.2e18;

    uint256 amountBefore = genesisToken.balanceOf(user);

    underTest.exposed_mint(user, amount);
    genesisToken.mint(address(underTest), amount);

    underTest.unwrap(amount);
    assertEq(genesisToken.balanceOf(user) - amountBefore, amount);
    assertEq(underTest.balanceOf(user), 0);
  }

  function test_lzReceive_whenToIsZero_thenMintsToPool() external {
    uint256 amount = 37.2e18;

    vm.expectCall(pool, abi.encodeWithSelector(IGenesisTokenPool.notifyRewardAmount.selector, amount));
    underTest.exposed_lzReceive(origin, abi.encode(address(0), amount), defaultLzOption);

    assertEq(underTest.balanceOf(pool), amount);
  }

  function test_lzReceive_whenToIsUser_thenMintsToUser() external {
    uint256 amount = 37.2e18;

    vm.mockCallRevert(
      pool, abi.encodeWithSelector(IGenesisTokenPool.notifyRewardAmount.selector), abi.encode("Shouldn't be called")
    );
    underTest.exposed_lzReceive(origin, abi.encode(user, amount), defaultLzOption);

    assertEq(underTest.balanceOf(user), amount);
  }

  function test_retrieveToken_whenCalledByNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.retrieveToken(address(genesisToken));
  }

  function test_retrieveToken_whenCalledByOwner_thenTransfersBalance() external prankAs(owner) {
    uint256 amount = 37.2e18;
    MockERC20 token = new MockERC20("Token", "TKN", 18);
    token.mint(address(underTest), amount);
    underTest.retrieveToken(address(token));

    assertEq(token.balanceOf(owner), amount);
  }

  function test_updateLayerZeroGasLimit_whenCalledByNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.updateLayerZeroGasLimit(100);
  }

  function test_updateLayerZeroGasLimit_whenCalledByOwner_thenUpdates() external prankAs(owner) {
    underTest.updateLayerZeroGasLimit(100);
    assertEq(underTest.lzGasLimit(), 100);
  }

  function test_attachPool_whenCalledByNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.attachPool(pool);
  }

  function test_attachPool_whenCalledByOwner_thenUpdates() external prankAs(owner) {
    address newPool = generateAddress("newPool");
    underTest.attachPool(newPool);
    assertEq(address(underTest.pool()), newPool);
  }

  function _expectLZSend(uint256 _fee, uint32 _toEndpoint, bytes memory _payload, bytes memory _option, address _refund)
    private
  {
    vm.expectCall(
      lzEndpoint,
      _fee,
      abi.encodeWithSelector(
        ILayerZeroEndpointV2.send.selector, MessagingParams(_toEndpoint, PEER, _payload, _option, false), _refund
      )
    );
  }
}

contract WrappedGnosisTokenHarness is WrappedGnosisToken {
  constructor(address _owner, address _lzEndpoint, address _genesisToken)
    WrappedGnosisToken(_owner, _lzEndpoint, _genesisToken)
  { }

  function exposed_mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function exposed_lzReceive(Origin calldata _origin, bytes calldata _message, bytes calldata _extraData) external {
    _lzReceive(_origin, bytes32("guid"), _message, address(0), _extraData);
  }
}

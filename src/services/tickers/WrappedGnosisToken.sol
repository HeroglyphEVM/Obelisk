// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title WrappedGnosisToken
 * @notice We wrapped our GenesisTokens so we don't have to cross-chain with uint64 limitations from LZ template.
 */
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import { IGenesisTokenPool } from "src/interfaces/IGenesisTokenPool.sol";

contract WrappedGnosisToken is ERC20, OApp {
  using OptionsBuilder for bytes;

  uint32 public constant MAINNET_LZ_ENDPOINT_ID = 30_101;
  address public immutable genesisToken;

  uint32 public lzGasLimit;
  bytes public defaultLzOption;

  IGenesisTokenPool public pool;

  event OFTSent(bytes32 indexed guid, uint32 indexed dstEid, address indexed to, uint256 amountOrId);
  event OFTReceived(bytes32 indexed guid, uint32 indexed srcEid, address indexed to, uint256 amountOrId);
  event NewPoolAttached(address pool);

  error CannotWrapOnMainnet();
  error CannotUnwrapOnMainnet();
  error GasLimitCannotBeZero();
  error SlippageExceeded(uint256 amountOrIdReceiving, uint256 minAmountOut);

  constructor(address _owner, address _lzEndpoint, address _genesisToken)
    ERC20("WrappedGenesisToken", "WGT")
    OApp(_lzEndpoint, _owner)
    Ownable(_owner)
  {
    genesisToken = _genesisToken;
    _updateLayerZeroGasLimit(200_000);
  }

  function attachPool(address _pool) external onlyOwner {
    pool = IGenesisTokenPool(_pool);
    emit NewPoolAttached(_pool);
  }

  function send(uint32 _dstEid, address _to, uint256 _amountIn, uint256 _minAmountOut)
    external
    payable
    returns (MessagingReceipt memory msgReceipt)
  {
    bytes memory option = defaultLzOption;
    uint256 amountReceiving = _debit(_amountIn, _minAmountOut);

    if (amountReceiving < _minAmountOut) {
      revert SlippageExceeded(amountReceiving, _minAmountOut);
    }

    bytes memory payload = _generateMessage(_to, amountReceiving);
    MessagingFee memory fee = _estimateFee(_dstEid, payload, option);

    msgReceipt = _lzSend(_dstEid, payload, option, fee, payable(msg.sender));

    emit OFTSent(msgReceipt.guid, _dstEid, msg.sender, amountReceiving);

    return msgReceipt;
  }

  /**
   * @notice addRewardOnMainnet the GenesisToken into this contract. Then mints the wrapped version on mainnet
   * @param _amount The amount of GenesisToken to wrap.
   */
  function addRewardOnMainnet(uint256 _amount) external payable {
    if (block.chainid == 1) revert CannotWrapOnMainnet();

    ERC20(genesisToken).transferFrom(msg.sender, address(this), _amount);

    bytes memory cachedLzOption = defaultLzOption;
    bytes memory payload = _generateMessage(address(0), _amount);
    MessagingFee memory fee = _estimateFee(MAINNET_LZ_ENDPOINT_ID, payload, cachedLzOption);

    MessagingReceipt memory msgReceipt =
      _lzSend(MAINNET_LZ_ENDPOINT_ID, payload, cachedLzOption, fee, payable(msg.sender));

    emit OFTSent(msgReceipt.guid, MAINNET_LZ_ENDPOINT_ID, msg.sender, _amount);
  }

  function estimateFee(uint32 _dstEid, address _to, uint256 _tokenId) external view returns (uint256) {
    return _estimateFee(_dstEid, _generateMessage(_to, _tokenId), defaultLzOption).nativeFee;
  }

  function _estimateFee(uint32 _dstEid, bytes memory _message, bytes memory _options)
    internal
    view
    returns (MessagingFee memory fee_)
  {
    return _quote(_dstEid, _message, _options, false);
  }

  function _generateMessage(address _to, uint256 _amount) internal pure returns (bytes memory) {
    return abi.encode(_to, _amount);
  }

  function unwrap(uint256 _amount) external {
    if (block.chainid == 1) revert CannotUnwrapOnMainnet();

    _burn(msg.sender, _amount);
    ERC20(genesisToken).transfer(msg.sender, _amount);
  }

  function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address, /*_executor*/
    bytes calldata /*_extraData*/
  ) internal virtual override {
    (address to, uint256 amount) = abi.decode(_message, (address, uint256));

    uint256 amountReceivedLD = _credit(to == address(0) ? address(pool) : to, amount, false);
    emit OFTReceived(_guid, _origin.srcEid, to, amountReceivedLD);
  }

  function _credit(address _to, uint256 _value, bool) internal returns (uint256) {
    IGenesisTokenPool cachedPool = pool;

    if (_to == address(0)) {
      _to = owner();
    } else if (_to == address(cachedPool)) {
      cachedPool.notifyRewardAmount(_value);
    }

    _mint(_to, _value);
    return _value;
  }

  function _debit(uint256 _amountIn, uint256) internal returns (uint256 amountReceiving_) {
    _burn(msg.sender, _amountIn);
    return _amountIn;
  }

  function retrieveToken(address _token) external onlyOwner {
    ERC20(_token).transfer(msg.sender, ERC20(_token).balanceOf(address(this)));
  }

  /**
   * @notice updateLayerZeroGasLimit Set a new gas limit for LZ
   * @param _lzGasLimit gas limit of a LZ Message execution
   */
  function updateLayerZeroGasLimit(uint32 _lzGasLimit) external virtual onlyOwner {
    _updateLayerZeroGasLimit(_lzGasLimit);
  }

  function _updateLayerZeroGasLimit(uint32 _lzGasLimit) internal virtual {
    if (_lzGasLimit == 0) revert GasLimitCannotBeZero();

    lzGasLimit = _lzGasLimit;
    defaultLzOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_lzGasLimit, 0);
  }
}

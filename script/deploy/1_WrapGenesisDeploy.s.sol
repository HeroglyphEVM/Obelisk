// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { WrappedGenesisToken } from "src/services/tickers/WrappedGenesisToken.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

contract WrapGenesisDeploy is BaseScript {
  struct ExecutorConfig {
    uint32 maxMessageSize;
    address executor;
  }

  struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length
    // directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to
      // override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to
      // override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed
      // overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed
      // overlap with requiredDVNs
  }

  uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
  uint32 internal constant CONFIG_TYPE_ULN = 2;

  struct Config {
    address owner;
    address treasury;
    address apxETH;
    address chaiMoney;
    address dai;
    address gaugeController;
    address hashmask;
    address swapRouter;
    address weth;
    address chainlinkDaiETH;
    uint256 nftPassCost;
    bytes32 merkleRoot;
  }

  struct WrapConfig {
    uint256 chainId;
    address lzEndpoint;
    uint32 lzEID;
    address[] genesisTokens;
    string[] genesisNames;
  }

  string private constant CONFIG_NAME = "ProtocolConfig";
  string private constant WRAP_CONFIG_NAME = "WrapConfig";

  WrapConfig[] private wrapConfig;
  address private deployerWallet;

  uint88 private PREFIX_ID = 9970;

  function run() external override {
    _loadContracts(true);
    deployerWallet = _getDeployerAddress();

    uint32 ETHEREUM_ID = 30_101;

    wrapConfig = abi.decode(vm.parseJson(_getConfig(WRAP_CONFIG_NAME)), (WrapConfig[]));

    address wrap;
    bool isAlreadyExisting;
    WrapConfig memory currentWrapConfig;
    uint88 idIndex = 0;
    string memory name;
    string memory symbol;
    address realGenesisToken;
    for (uint88 i = 0; i < wrapConfig.length; ++i) {
      currentWrapConfig = wrapConfig[i];

      for (uint256 x = 0; x < currentWrapConfig.genesisTokens.length; ++x) {
        idIndex++;

        if (block.chainid != 1 && block.chainid != currentWrapConfig.chainId) continue;

        realGenesisToken = currentWrapConfig.genesisTokens[x];
        name = string.concat("Wrapped ", currentWrapConfig.genesisNames[x]);
        symbol = string.concat("W", currentWrapConfig.genesisNames[x]);

        (wrap, isAlreadyExisting) = _tryDeployContractDeterministic(
          name,
          _generateSeed(PREFIX_ID + idIndex),
          abi.encodePacked(type(WrappedGenesisToken).creationCode),
          abi.encode(
            deployerWallet,
            name,
            symbol,
            currentWrapConfig.lzEID,
            currentWrapConfig.lzEndpoint,
            realGenesisToken
          )
        );

        if (!isAlreadyExisting) {
          vm.broadcast(_getDeployerPrivateKey());
          WrappedGenesisToken(wrap).setPeer(
            block.chainid != 1 ? ETHEREUM_ID : currentWrapConfig.lzEID,
            bytes32(abi.encode(wrap))
          );
        }

        sendToPool(ETHEREUM_ID, wrap, realGenesisToken);
      }
    }
  }

  function sendToPool(uint32 ETHEREUM_ID, address wrap, address realGenesisToken)
    internal
  {
    uint256 balance = WrappedGenesisToken(realGenesisToken).balanceOf(deployerWallet);
    uint256 sending = balance / 2;
    uint256 fee = WrappedGenesisToken(wrap).estimateFee(ETHEREUM_ID, wrap, sending);

    if (WrappedGenesisToken(realGenesisToken).allowance(deployerWallet, wrap) == 0) {
      vm.broadcast(_getDeployerPrivateKey());
      WrappedGenesisToken(realGenesisToken).approve(wrap, sending);
    }

    console.log(WrappedGenesisToken(realGenesisToken).name(), balance - sending);

    vm.broadcast(_getDeployerPrivateKey());
    WrappedGenesisToken(wrap).addRewardOnMainnet{ value: fee }(sending);
  }
}

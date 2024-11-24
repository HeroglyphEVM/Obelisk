// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { WrappedGenesisToken } from "src/services/tickers/WrappedGenesisToken.sol";

contract WrapGenesisDeploy is BaseScript {
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
    _loadContracts(false);
    deployerWallet = _getDeployerAddress();

    uint32 ETHEREUM_ID = 30_101;

    wrapConfig = abi.decode(vm.parseJson(_getConfig(WRAP_CONFIG_NAME)), (WrapConfig[]));

    address wrap;
    bool isAlreadyExisting;
    WrapConfig memory currentWrapConfig;
    uint88 idIndex = 0;
    string memory name;
    string memory symbol;
    for (uint88 i = 0; i < wrapConfig.length; ++i) {
      currentWrapConfig = wrapConfig[i];

      for (uint256 x = 0; x < currentWrapConfig.genesisTokens.length; ++x) {
        idIndex++;

        if (block.chainid != 1 && block.chainid != currentWrapConfig.chainId) continue;
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
            currentWrapConfig.genesisTokens[x]
          )
        );

        if (!isAlreadyExisting) {
          vm.broadcast(_getDeployerPrivateKey());
          WrappedGenesisToken(wrap).setPeer(
            block.chainid != 1 ? ETHEREUM_ID : currentWrapConfig.lzEID,
            bytes32(abi.encode(wrap))
          );
        }

        uint256 sending = WrappedGenesisToken(currentWrapConfig.genesisTokens[x])
          .balanceOf(deployerWallet) / 2;

        require(sending > 0, "No tokens to send");

        vm.broadcast(_getDeployerPrivateKey());
        WrappedGenesisToken(currentWrapConfig.genesisTokens[x]).approve(
          address(wrap), sending
        );

        vm.broadcast(_getDeployerPrivateKey());
        WrappedGenesisToken(wrap).addRewardOnMainnet(sending);
      }
    }
  }
}

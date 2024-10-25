// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { ApxETHVault } from "src/services/liquidity/ApxETHVault.sol";
import { ChaiMoneyVault } from "src/services/liquidity/ChaiMoney.sol";
import { ObeliskRegistry } from "src/services/nft/ObeliskRegistry.sol";
import { HCT } from "src/services/HCT.sol";
import { NFTPass } from "src/services/nft/NFTPass.sol";
import { ObeliskHashmask } from "src/services/nft/ObeliskHashmask.sol";
import { StreamingPool } from "src/services/StreamingPool.sol";
import { InterestManager } from "src/services/InterestManager.sol";
import { Megapool } from "src/services/tickers/Megapool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolDeploy is BaseScript {
  struct Config {
    address owner;
    address treasury;
    address apxETH;
    address chaiMoney;
    address dai;
    address nameFilter;
    address hashmask;
    address swapRouter;
    address weth;
    address chainlinkDaiETH;
    uint256 nftPassCost;
  }

  string private constant CONFIG_NAME = "ProtocolConfig";

  Config private config;
  address private deployerWallet;

  address private interestManager;
  address private apxVault;
  address private daiVault;
  address private obeliskRegistry;
  address private streamingPool;
  address private obeliskHashmask;
  bool private obeliskHashmaskExists;

  function run() external override {
    _loadContracts(false);

    deployerWallet = _getDeployerAddress();
    bool apxVaultExists;
    bool daiVaultExists;
    bool streamingExists;

    string memory file = _getConfig(CONFIG_NAME);
    config = abi.decode(vm.parseJson(file, string.concat(".", _getNetwork())), (Config));

    (address nftPass,) = _tryDeployContract(
      "NFT Pass",
      0,
      type(NFTPass).creationCode,
      abi.encode(config.owner, config.treasury, config.nameFilter, config.nftPassCost)
    );
    (apxVault, apxVaultExists) = _tryDeployContract(
      "Apx ETH Vault",
      0,
      type(ApxETHVault).creationCode,
      abi.encode(deployerWallet, address(0), config.apxETH, address(0))
    );

    (daiVault, daiVaultExists) = _tryDeployContract(
      "Dai Vault",
      0,
      type(ChaiMoneyVault).creationCode,
      abi.encode(deployerWallet, address(0), config.chaiMoney, config.dai, address(0))
    );

    (obeliskRegistry,) = _tryDeployContract(
      "Obelisk Registry",
      0,
      type(ObeliskRegistry).creationCode,
      abi.encode(deployerWallet, config.treasury, nftPass, apxVault, daiVault, config.dai)
    );

    if (contracts["HCT"] == address(0)) {
      _saveDeployment("HCT", ObeliskRegistry(payable(obeliskRegistry)).HCT_ADDRESS());
    }

    (obeliskHashmask, obeliskHashmaskExists) = _tryDeployContract(
      "Obelisk Hashmask",
      0,
      type(ObeliskHashmask).creationCode,
      abi.encode(config.hashmask, config.owner, obeliskRegistry, config.treasury)
    );

    (interestManager,) = _tryDeployContract(
      "Interest Manager",
      0,
      type(InterestManager).creationCode,
      abi.encode(
        deployerWallet,
        address(0),
        apxVault,
        daiVault,
        config.swapRouter,
        config.chainlinkDaiETH,
        config.weth
      )
    );

    (streamingPool, streamingExists) = _tryDeployContract(
      "Streaming Pool",
      0,
      type(StreamingPool).creationCode,
      abi.encode(config.owner, config.treasury, config.dai, interestManager)
    );

    _tryDeployContract(
      "Megapool_01",
      0,
      type(Megapool).creationCode,
      abi.encode(config.owner, obeliskRegistry, config.apxETH, interestManager)
    );

    if (!streamingExists) {
      vm.broadcast(_getDeployerPrivateKey());
      InterestManager(payable(interestManager)).setStreamingPool(streamingPool);
    }

    if (!daiVaultExists) {
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(daiVault).setObeliskRegistry(obeliskRegistry);
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(daiVault).setInterestRateReceiver(interestManager);
    }

    if (!apxVaultExists) {
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(apxVault).setObeliskRegistry(obeliskRegistry);
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(apxVault).setInterestRateReceiver(interestManager);
    }

    if (!obeliskHashmaskExists) {
      vm.broadcast(_getDeployerPrivateKey());
      ObeliskRegistry(payable(obeliskRegistry)).toggleIsWrappedNFTFor(
        config.hashmask, obeliskHashmask, true
      );
    }

    _transferOwnership(config.owner);
  }

  function _transferOwnership(address _owner) internal {
    if (Ownable(interestManager).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(interestManager).transferOwnership(_owner);
    }

    if (Ownable(daiVault).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(daiVault).transferOwnership(_owner);
    }

    if (Ownable(apxVault).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(apxVault).transferOwnership(_owner);
    }

    if (Ownable(obeliskRegistry).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(obeliskRegistry).transferOwnership(_owner);
    }
  }
}

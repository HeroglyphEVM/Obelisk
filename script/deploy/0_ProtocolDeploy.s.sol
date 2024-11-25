// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { ApxETHVault } from "src/services/liquidity/ApxETHVault.sol";
import { ChaiMoneyVault } from "src/services/liquidity/ChaiMoneyVault.sol";
import { ObeliskRegistry } from "src/services/nft/ObeliskRegistry.sol";
import { HCT } from "src/services/HCT.sol";
import { NFTPass } from "src/services/nft/NFTPass.sol";
import { ObeliskHashmask } from "src/services/nft/ObeliskHashmask.sol";
import { StreamingPool } from "src/services/StreamingPool.sol";
import { InterestManager } from "src/services/InterestManager.sol";
import { MegapoolFactory } from "src/services/MegapoolFactory.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { NameFilter } from "src/vendor/heroglyph/NameFilter.sol";
import { TestnetERC20 } from "src/mocks/TestnetERC20.sol";
import { MockDripVault } from "src/mocks/MockDripVault.sol";
import { MockHashmask } from "src/mocks/MockHashmask.sol";
import { TestnetERC721 } from "src/mocks/TestnetERC721.sol";
import { Permission } from "atoumic/access/Permission.sol";
import { GenesisTokenPool } from "src/services/tickers/GenesisTokenPool.sol";
import { WrappedGenesisToken } from "src/services/tickers/WrappedGenesisToken.sol";

contract ProtocolDeploy is BaseScript {
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

  string private constant CONFIG_NAME = "ProtocolConfig";

  Config private config;
  address private deployerWallet;

  address private interestManager;
  address private apxVault;
  address private daiVault;
  address private obeliskRegistry;
  address private streamingPool;
  address private obeliskHashmask;
  address private megapoolFactory;
  bool private obeliskHashmaskExists;

  function run() external override {
    _loadContracts(false);

    deployerWallet = _getDeployerAddress();
    bool apxVaultExists;
    bool daiVaultExists;
    bool streamingExists;
    bool obeliskRegistryExists;
    bool megapoolFactoryExists;
    address testnetERC721;
    address pending721;

    string memory file = _getConfig(CONFIG_NAME);
    config = abi.decode(vm.parseJson(file, string.concat(".", _getNetwork())), (Config));

    if (_isTestnet()) {
      (config.dai,) = _tryDeployContract(
        "Mock Dai", 0, type(TestnetERC20).creationCode, abi.encode("Mock Dai", "MDAI")
      );

      (config.hashmask,) =
        _tryDeployContract("MockHashmask", 0, type(MockHashmask).creationCode, "");

      (config.apxETH,) = _tryDeployContract(
        "Mock Apx ETH",
        0,
        type(TestnetERC20).creationCode,
        abi.encode("Mock Apx ETH", "MAPXETH")
      );

      (testnetERC721,) = _tryDeployContract(
        "Testnet ERC721",
        0,
        type(TestnetERC721).creationCode,
        abi.encode("Testnet ERC721", "T721")
      );

      (pending721,) = _tryDeployContract(
        "Pending ERC721",
        0,
        type(TestnetERC721).creationCode,
        abi.encode("Pending ERC721", "TP721")
      );
    }

    (address nameFilter,) =
      _tryDeployContract("NameFilter", 0, type(NameFilter).creationCode, "");

    (address nftPass,) = _tryDeployContract(
      "NFT Pass",
      0,
      type(NFTPass).creationCode,
      abi.encode(
        config.owner, config.treasury, nameFilter, config.nftPassCost, config.merkleRoot
      )
    );

    (apxVault, apxVaultExists) = _tryDeployContract(
      "Apx ETH Vault",
      0,
      _isTestnet() ? type(MockDripVault).creationCode : type(ApxETHVault).creationCode,
      _isTestnet()
        ? abi.encode(deployerWallet, address(0), address(0), config.apxETH, config.treasury)
        : abi.encode(deployerWallet, address(0), config.apxETH, config.treasury)
    );

    (daiVault, daiVaultExists) = _tryDeployContract(
      "Dai Vault",
      0,
      _isTestnet() ? type(MockDripVault).creationCode : type(ChaiMoneyVault).creationCode,
      _isTestnet()
        ? abi.encode(deployerWallet, address(0), config.dai, config.dai, config.treasury)
        : abi.encode(
          deployerWallet, address(0), config.chaiMoney, config.dai, config.treasury
        )
    );

    (obeliskRegistry, obeliskRegistryExists) = _tryDeployContract(
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
        config.gaugeController,
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
      abi.encode(config.owner, interestManager, config.apxETH)
    );

    (megapoolFactory, megapoolFactoryExists) = _tryDeployContract(
      "Megapool Factory",
      0,
      type(MegapoolFactory).creationCode,
      abi.encode(
        deployerWallet, obeliskRegistry, contracts["HCT"], config.apxETH, interestManager
      )
    );

    if (!obeliskRegistryExists) {
      vm.broadcast(_getDeployerPrivateKey());
      ObeliskRegistry(payable(obeliskRegistry)).setMegapoolFactory(megapoolFactory);

      if (_isTestnet()) {
        vm.startBroadcast(_getDeployerPrivateKey());
        ObeliskRegistry(payable(obeliskRegistry)).allowNewCollection(
          testnetERC721, 10_000, uint32(block.timestamp - 375 days), false
        );

        ObeliskRegistry(payable(obeliskRegistry)).forceActiveCollection(testnetERC721);

        ObeliskRegistry(payable(obeliskRegistry)).allowNewCollection(
          pending721, 10_000, uint32(block.timestamp - 250 days), true
        );

        vm.stopBroadcast();
      }
    }

    if (!megapoolFactoryExists) {
      vm.broadcast(_getDeployerPrivateKey());
      MegapoolFactory(payable(megapoolFactory)).createMegapool(new address[](0));
    }

    if (!streamingExists) {
      vm.broadcast(_getDeployerPrivateKey());
      InterestManager(payable(interestManager)).setStreamingPool(streamingPool);
    }

    if (!apxVaultExists) {
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(apxVault).setObeliskRegistry(obeliskRegistry);
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(apxVault).setInterestRateReceiver(interestManager);
    }

    if (!daiVaultExists) {
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(daiVault).setObeliskRegistry(obeliskRegistry);
      vm.broadcast(_getDeployerPrivateKey());
      ChaiMoneyVault(daiVault).setInterestRateReceiver(interestManager);
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

    if (Ownable(apxVault).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(apxVault).transferOwnership(_owner);
    }

    if (Ownable(daiVault).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(daiVault).transferOwnership(_owner);
    }

    if (Permission(obeliskRegistry).permissionAdmin() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Permission(obeliskRegistry).transferPermissionAdmin(_owner);
    }

    if (Ownable(streamingPool).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(streamingPool).transferOwnership(_owner);
    }

    if (Ownable(obeliskHashmask).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(obeliskHashmask).transferOwnership(_owner);
    }

    if (Ownable(megapoolFactory).owner() == deployerWallet) {
      vm.broadcast(_getDeployerPrivateKey());
      Ownable(megapoolFactory).transferOwnership(_owner);
    }
  }
}

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

    for (uint256 i; i < 15; i++) {
      (address molandakPool,) = _tryDeployContract(
        "Wrapped MOLANDAK POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0xFe55a10603c2eD1C848532a4f381925Dd8BC8eaD,
          0xe0a6B8751a91Ffe43406BFC7d97c4736aB86f483
        )
      );

      (address arbinautsPool,) = _tryDeployContract(
        "Wrapped ARBINAUTS POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0xB0f936Ef8200C325Fce19068dbaf04C2F4AdA235,
          0x384f025f8B1993584857A305C3b2fE181087ae78
        )
      );

      (address oogabooogaPool,) = _tryDeployContract(
        "Wrapped OOGABOOGA POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x930C037c1e11051bAC6b88147863400cE3dDD11b,
          0xB4db8A6B356eea6B0B182878849094f63028533c
        )
      );

      (address lueygiPool,) = _tryDeployContract(
        "Wrapped LUEYGI POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x67BCeCA030e7a16217cA1B805e1cBADC7C77249d,
          0x00155a64C651873FFed663C62FfB0001C6D608F1
        )
      );

      (address porigonPool,) = _tryDeployContract(
        "Wrapped PORIGON POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x6DA7767De554e68bDe771d8e9831443A5Eb2013A,
          0xF6cc130F301C80b8aeBF6651e5376cE9CfE8Da0a
        )
      );

      (address overPoweredPool,) = _tryDeployContract(
        "Wrapped OVERPOWERED POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0xdF3aef4E8724813c33242B79Bb3F9b53Bf0D12B1,
          0x6262f6a2291D61139f319ac81fACbDA506A9e049
        )
      );

      (address sixtyNinePool,) = _tryDeployContract(
        "Wrapped 69 POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x255f6fb25B3E07509c11ff15F3A0F295be031Abc,
          0xA48017630cB10182d70bbc37d38914610a0bAd61
        )
      );

      (address onePunchPool,) = _tryDeployContract(
        "Wrapped ONEPUNCH POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x4Df2ccC51cDC58275e3201e5e14A8D3bc013fFF0,
          0x571645Df4004217bB625107DD0aaC0c092336727
        )
      );

      (address sanicsuperSpeedPool,) = _tryDeployContract(
        "Wrapped SANICSUPERSPEED POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0xb26B429F451688Cda4c5AB6215177dee39D47aFf,
          0x4D7d8e2F51738DD1d59E99d3ab699B5B771269DF
        )
      );

      (address kabosuPool,) = _tryDeployContract(
        "Wrapped KABOSU POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x72B67D1BF561614B7A99d84b15524c55a7714E8e,
          0x2bd73234Eb66A45a757787443Ddc24e48C6265E4
        )
      );

      (address garfeldoPool,) = _tryDeployContract(
        "Wrapped GARFELDO POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x8A32FE46E2974A5331eCD13437DC2Ac32EA8d754,
          0x266392EAF7AE4358bd74b3215BcA1860D64EbCb6
        )
      );

      (address scribesPool,) = _tryDeployContract(
        "Wrapped SCRIBES POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x3c7EFf8fb329c5e2814AD2eDc87F563fa5fDCb4c,
          0xEF4bD738C869Fa6ffbc9CE2A38cBBD4f30E32c4b
        )
      );

      (address frxBullasPool,) = _tryDeployContract(
        "Wrapped FRXBULLAS POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x956294599365D2a405dAEed7354b0eABa0b8C908,
          0x988287f489027811A115CDFc8eB8e4260990aB2B
        )
      );

      (address gnobbyPool,) = _tryDeployContract(
        "Wrapped GNOBBY POOL",
        0,
        abi.encodePacked(type(GenesisTokenPool).creationCode),
        abi.encode(
          config.owner,
          obeliskRegistry,
          0x531966EeA5d10c2Ca8736226F83776e76D3d0150,
          0x38Ad57C848d4822bACf8997fb7E3EfaE839df04d
        )
      );

      link(molandakPool, "MNDK");
      link(arbinautsPool, "ARBI");
      link(oogabooogaPool, "OOGA");
      link(lueygiPool, "LUEY");
      link(porigonPool, "PORI");
      link(overPoweredPool, "OPOW");
      link(sixtyNinePool, "SIX9");
      link(onePunchPool, "ONEP");
      link(sanicsuperSpeedPool, "SANIC");
      link(kabosuPool, "KBSU");
      link(garfeldoPool, "LASG");
      link(scribesPool, "SCRB");
      link(frxBullasPool, "FXBL");
      link(gnobbyPool, "GNOB");

      vm.broadcast(_getDeployerPrivateKey());
      ObeliskRegistry(payable(obeliskRegistry)).setTreasury(config.treasury);
    }

    // _transferOwnership(config.owner);
  }

  function link(address _pool, string memory tickerName) internal {
    address wrapped = address(GenesisTokenPool(_pool).REWARD_TOKEN());
    vm.broadcast(_getDeployerPrivateKey());
    WrappedGenesisToken(wrapped).attachPool(_pool);

    vm.broadcast(_getDeployerPrivateKey());
    ObeliskRegistry(payable(obeliskRegistry)).setTickerLogic(tickerName, wrapped, false);

    vm.broadcast(_getDeployerPrivateKey());
    WrappedGenesisToken(wrapped).setDelegate(config.owner);
    vm.broadcast(_getDeployerPrivateKey());
    WrappedGenesisToken(wrapped).transferOwnership(config.owner);
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

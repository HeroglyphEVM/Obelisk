// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";
import { DataAsserter } from "src/services/DataAsserter.sol";

contract UMADeploy is BaseScript {
  struct Config {
    address owner;
    address treasury;
    address defaultCurrency;
    address optimisticOracleV3;
    address obeliskRegistry;
  }

  string private constant CONFIG_NAME = "UMAConfig";

  Config private config;
  address private deployerWallet;

  function run() external override {
    _loadContracts(false);

    string memory file = _getConfig(CONFIG_NAME);
    config = abi.decode(vm.parseJson(file, string.concat(".", _getNetwork())), (Config));

    _tryDeployContract(
      "DataAsserter",
      0,
      type(DataAsserter).creationCode,
      abi.encode(
        config.owner,
        config.treasury,
        config.defaultCurrency,
        config.optimisticOracleV3,
        config.obeliskRegistry
      )
    );
  }
}

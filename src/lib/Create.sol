// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

library Create {
  error FailedDeployment();

  function createContract(bytes memory bytecode) internal returns (address addr_) {
    bytes32 salt =
      keccak256(abi.encodePacked(address(this), block.number, block.timestamp));

    /// @solidity memory-safe-assembly
    assembly {
      addr_ := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
    }

    if (addr_ == address(0)) revert FailedDeployment();
    return addr_;
  }
}

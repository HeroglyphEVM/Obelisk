// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { AncillaryData as ClaimData } from "src/vendor/UMA/AncillaryData.sol";
import { OptimisticOracleV3Interface } from
  "src/vendor/UMA/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// This contract allows assertions on any form of data to be made using the UMA Optimistic
// Oracle V3 and stores the
// proposed value so that it may be retrieved on chain. The dataId is intended to be an
// arbitrary value that uniquely
// identifies a specific piece of information in the consuming contract and is
// replaceable. Similarly, any data
// structure can be used to replace the asserted data.
contract DataAsserter is Ownable {
  using SafeERC20 for IERC20;

  IWETH public immutable defaultCurrency;
  OptimisticOracleV3Interface public immutable oo;
  uint64 public constant assertionLiveness = 7200;
  bytes32 public immutable defaultIdentifier;
  uint256 public assertingPrice;
  mapping(address => uint256) public collectionAssertingTries;
  mapping(address => bool) public collectionAssertingSuccess;

  struct DataAssertion {
    bytes32 dataId; // The dataId that was asserted.
    bytes32 data; // This could be an arbitrary data type.
    address asserter; // The address that made the assertion.
    bool resolved; // Whether the assertion has been resolved.
  }

  mapping(bytes32 => DataAssertion) public assertionsData;

  event DataAsserted(
    bytes32 indexed dataId,
    bytes32 data,
    address indexed asserter,
    bytes32 indexed assertionId
  );

  event DataAssertionResolved(
    bytes32 indexed dataId,
    bytes32 data,
    address indexed asserter,
    bytes32 indexed assertionId
  );

  struct CollectionAssertionData {
    address collection;
    uint32 deploymentTimestamp;
    uint128 currentSupply;
  }

  address public treasury;

  constructor(
    address _owner,
    address _treasury,
    address _defaultCurrency,
    address _optimisticOracleV3
  ) Ownable(_owner) {
    treasury = _treasury;
    defaultCurrency = IWETH(_defaultCurrency);
    oo = OptimisticOracleV3Interface(_optimisticOracleV3);
    defaultIdentifier = oo.defaultIdentifier();
  }

  // For a given assertionId, returns a boolean indicating whether the data is accessible
  // and the data itself.
  function getData(bytes32 assertionId) public view returns (bool, bytes32) {
    if (!assertionsData[assertionId].resolved) return (false, 0);
    return (true, assertionsData[assertionId].data);
  }

  // Asserts data for a specific dataId on behalf of an asserter address.
  // Data can be asserted many times with the same combination of arguments, resulting in
  // unique assertionIds. This is
  // because the block.timestamp is included in the claim. The consumer contract must
  // store the returned assertionId
  // identifiers to able to get the information using getData.
  function assertDataFor(
    address _collection,
    uint32 _deploymentTimestamp,
    uint128 _currentSupply,
    address asserter
  ) public returns (bytes32 assertionId) {
    uint256 tryNumber = collectionAssertingTries[_collection];
    bytes32 dataId = bytes32(abi.encode(_collection, tryNumber));
    bytes32 data = bytes32(
      abi.encode(
        CollectionAssertionData({
          deploymentTimestamp: _deploymentTimestamp,
          currentSupply: _currentSupply
        })
      )
    );

    asserter = asserter == address(0) ? msg.sender : asserter;
    uint256 bond = oo.getMinimumBond(address(defaultCurrency));
    defaultCurrency.transferFrom(msg.sender, address(this), bond + assertingPrice);
    defaultCurrency.approve(address(oo), bond);

    // The claim we want to assert is the first argument of assertTruth. It must contain
    // all of the relevant
    // details so that anyone may verify the claim without having to read any further
    // information on chain. As a
    // result, the claim must include both the data id and data, as well as a set of
    // instructions that allow anyone
    // to verify the information in publicly available sources.
    // See the UMIP corresponding to the defaultIdentifier used in the OptimisticOracleV3
    // "ASSERT_TRUTH" for more
    // information on how to construct the claim.
    assertionId = oo.assertTruth(
      abi.encodePacked(
        "Data asserted: 0x",
        ClaimData.toUtf8Bytes(data),
        " for dataId: 0x",
        ClaimData.toUtf8Bytes(dataId),
        " and asserter: 0x",
        ClaimData.toUtf8BytesAddress(asserter),
        " at timestamp: ",
        ClaimData.toUtf8BytesUint(block.timestamp),
        " in the DataAsserter contract at 0x",
        ClaimData.toUtf8BytesAddress(address(this)),
        " is valid."
      ),
      asserter,
      address(this),
      address(0), // No sovereign security.
      assertionLiveness,
      defaultCurrency,
      bond,
      defaultIdentifier,
      bytes32(0) // No domain.
    );
    assertionsData[assertionId] = DataAssertion(dataId, data, asserter, false);
    emit DataAsserted(dataId, data, asserter, assertionId);
  }

  // OptimisticOracleV3 resolve callback.
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public {
    require(msg.sender == address(oo));
    DataAssertion storage dataAssertion = assertionsData[assertionId];
    address collection = address(uint160(uint256(dataAssertion.dataId)));

    if (!assertedTruthfully) {
      collectionAssertingTries[collection]++;
      delete assertionsData[assertionId];
      defaultCurrency.transfer(treasury, assertingPrice);
      return;
    }

    dataAssertion.resolved = true;
    defaultCurrency.transfer(dataAssertion.asserter, assertingPrice);

    emit DataAssertionResolved(
      dataAssertion.dataId, dataAssertion.data, dataAssertion.asserter, assertionId
    );
  }

  // If assertion is disputed, do nothing and wait for resolution.
  // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't
  // revert when it tries to call it.
  function assertionDisputedCallback(bytes32 assertionId) public { }

  function updateAssertingPrice(uint256 price) public onlyOwner {
    assertingPrice = price;
  }
}

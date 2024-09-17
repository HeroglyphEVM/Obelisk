// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IObeliskHashmask {
  error NotLinkedToHolder();
  error NotHashmaskHolder();
  error InsufficientActivationPrice();
  error UseUpdateNameInstead();
  error UseLinkOrTransferLinkInstead();
  error NoTickersFound();
  error TransferFailed();
  error ZeroAddress();

  event ActivationPriceSet(uint256 price);
  event HashmaskLinked(uint256 indexed hashmaskId, address indexed from, address indexed to);
  event NameUpdated(uint256 indexed hashmaskId, string name);
  event TreasurySet(address treasury);
  /**
   * @notice Links a hashmask to the user's account.
   * @param _hashmaskId The ID of the hashmask to link.
   */

  function link(uint256 _hashmaskId) external payable;

  /**
   * @notice Transfers the link of a hashmask to another user without requiring an additional linking fee if the
   * transfer is to another wallet owned by the same user.
   * @param _hashmaskId The ID of the hashmask to transfer.
   * @param _triggerNameUpdate Whether to trigger a name update.
   * @dev The hashmask.ownerOf() will be set as linker.
   */
  function transferLink(uint256 _hashmaskId, bool _triggerNameUpdate) external;

  /**
   * @notice Updates their virtual name to copy the name of the hashmask.
   * @param _hashmaskId The ID of the hashmask to update.
   */
  function updateName(uint256 _hashmaskId) external;
}

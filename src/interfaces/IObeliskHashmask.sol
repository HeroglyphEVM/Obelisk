// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IObeliskHashmask {
  error NotActivatedByHolder();
  error NotHashmaskHolder();
  error InsufficientActivationPrice();
  error UseUpdateNameForHashmasks();
  error NoTickersFound();
  error TransferFailed();

  event ActivationPriceSet(uint256 price);
}

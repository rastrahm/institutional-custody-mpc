// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Standard signature validation method for contracts (ERC-1271).
interface IERC1271 {
    /// @notice Validates that `_signature` is a valid signature for `_hash`.
    /// @param _hash Hash of the data signed.
    /// @param _signature Signature byte array associated with `_hash`.
    /// @return magicValue `0x1626ba7e` if valid; otherwise `0xffffffff` (or other non-magic).
    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4 magicValue);
}

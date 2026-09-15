// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice EIP-712 typehashes and struct hashing for custody vault transactions.
library EIP712Custody {
    /// @dev keccak256("CustodyTransaction(address to,uint256 value,bytes data,uint256 nonce)")
    bytes32 internal constant TRANSACTION_TYPEHASH =
        keccak256("CustodyTransaction(address to,uint256 value,bytes data,uint256 nonce)");

    /// @notice Hashes a custody transaction struct per EIP-712.
    /// @param to Destination of the call.
    /// @param value ETH value to send.
    /// @param data Calldata to forward.
    /// @param nonce_ Vault nonce included in the typed data.
    /// @return structHash EIP-712 struct hash (not yet domain-separated).
    function hashTransaction(address to, uint256 value, bytes memory data, uint256 nonce_)
        internal
        pure
        returns (bytes32 structHash)
    {
        structHash = keccak256(abi.encode(TRANSACTION_TYPEHASH, to, value, keccak256(data), nonce_));
    }
}

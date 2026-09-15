// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Institutional multisig custody vault (M-of-N over EIP-712 transaction hashes).
interface ICustodyVault {
    /// @notice Returns the current owner/signer set.
    function getOwners() external view returns (address[] memory);

    /// @notice Returns the M threshold required for full quorum execution.
    function getThreshold() external view returns (uint256);

    /// @notice Returns the current execution nonce included in EIP-712 hashes.
    function nonce() external view returns (uint256);

    /// @notice EIP-712 domain separator for this vault instance.
    function domainSeparator() external view returns (bytes32);

    /// @notice Computes the EIP-712 struct hash for a pending transaction at `nonce_`.
    /// @param to Destination of the call.
    /// @param value ETH value to send.
    /// @param data Calldata to forward.
    /// @param nonce_ Nonce used in the typed data.
    function getTransactionHash(address to, uint256 value, bytes memory data, uint256 nonce_)
        external
        view
        returns (bytes32);

    /// @notice Executes a call authorized by an M-of-N sorted signature payload.
    /// @param to Destination of the call.
    /// @param value ETH value to send.
    /// @param data Calldata to forward.
    /// @param signatures Concatenated ECDSA signatures, sorted by recovered signer address.
    /// @return success True if the external call succeeded.
    function execTransaction(address to, uint256 value, bytes memory data, bytes memory signatures)
        external
        returns (bool success);

    /// @notice Executes a low-value call under the daily spending limit with a single owner signature.
    /// @param to Destination of the call.
    /// @param value ETH value to send.
    /// @param data Calldata to forward.
    /// @param signature Single owner ECDSA signature over the EIP-712 hash.
    /// @return success True if the external call succeeded.
    function execTransactionUnderLimit(address to, uint256 value, bytes memory data, bytes memory signature)
        external
        returns (bool success);

    /// @notice Returns whether `account` is a registered owner/signer.
    function isOwner(address account) external view returns (bool);
}

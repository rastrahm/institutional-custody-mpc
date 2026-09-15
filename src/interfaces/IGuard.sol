// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Pluggable pre/post execution checks for the custody vault.
interface IGuard {
    /// @notice Called before the vault executes an external call.
    /// @dev Implementations should revert (or the vault maps failure to `GuardRejected`) to block execution.
    /// @param to Destination of the call.
    /// @param value ETH value forwarded.
    /// @param data Calldata forwarded.
    /// @param operation Call type discriminator (0 = Call, 1 = DelegateCall) reserved for future use.
    /// @param msgSender Address that submitted the execution transaction.
    function checkTransaction(address to, uint256 value, bytes memory data, uint8 operation, address msgSender) external;

    /// @notice Called after the vault attempts an external call.
    /// @param txHash EIP-712 transaction hash that was executed.
    /// @param success Whether the external call succeeded.
    function checkAfterExecution(bytes32 txHash, bool success) external;
}

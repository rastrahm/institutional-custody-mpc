// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Delayed execution surface for sensitive custody changes (signers / threshold).
interface IRecoveryTimelock {
    /// @notice Minimum delay before a scheduled operation can be executed.
    function delay() external view returns (uint256);

    /// @notice Schedules an operation to become executable at `eta`.
    /// @param operationId Unique identifier of the operation.
    /// @param data Encoded call payload associated with the operation.
    /// @param eta Earliest timestamp at which execution is allowed.
    function schedule(bytes32 operationId, bytes calldata data, uint256 eta) external;

    /// @notice Executes a previously scheduled operation if the delay has elapsed.
    /// @param operationId Unique identifier of the operation.
    /// @param data Encoded call payload that must match the scheduled data.
    function execute(bytes32 operationId, bytes calldata data) external;

    /// @notice Cancels a scheduled operation.
    /// @param operationId Unique identifier of the operation.
    function cancel(bytes32 operationId) external;
}

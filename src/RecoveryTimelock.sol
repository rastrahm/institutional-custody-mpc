// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "./errors/CustodyErrors.sol";
import {IRecoveryTimelock} from "./interfaces/IRecoveryTimelock.sol";
import {CustodyVault} from "./CustodyVault.sol";

/// @notice Delayed execution module for custody key / threshold changes.
/// @dev `schedule` / `cancel` are vault-only (multisig self-call to this contract).
///      `execute` is permissionless after `eta` and before `eta + GRACE_PERIOD`.
contract RecoveryTimelock is IRecoveryTimelock {
    /// @notice Maximum window after `eta` during which an operation remains executable.
    uint256 public constant GRACE_PERIOD = 14 days;

    /// @notice Custody vault controlled by this timelock.
    CustodyVault public immutable vault;

    /// @inheritdoc IRecoveryTimelock
    uint256 public immutable delay;

    /// @dev operationId => earliest execution timestamp (`0` = not scheduled).
    mapping(bytes32 => uint256) private _eta;
    /// @dev operationId => keccak256(data) committed at schedule time.
    mapping(bytes32 => bytes32) private _dataHash;

    /// @notice Emitted when an operation is scheduled.
    event OperationScheduled(bytes32 indexed operationId, bytes data, uint256 eta);

    /// @notice Emitted when a scheduled operation is executed.
    event OperationExecuted(bytes32 indexed operationId);

    /// @notice Emitted when a scheduled operation is cancelled.
    event OperationCancelled(bytes32 indexed operationId);

    /// @param vault_ Target custody vault.
    /// @param delay_ Minimum seconds between `block.timestamp` at schedule and `eta`.
    constructor(address vault_, uint256 delay_) {
        if (vault_ == address(0)) {
            revert CustodyErrors.ZeroAddress();
        }
        if (delay_ == 0) {
            revert CustodyErrors.ZeroValue();
        }
        vault = CustodyVault(payable(vault_));
        delay = delay_;
    }

    /// @notice Returns the scheduled `eta` for `operationId` (`0` if none).
    function getEta(bytes32 operationId) external view returns (uint256) {
        return _eta[operationId];
    }

    /// @inheritdoc IRecoveryTimelock
    function schedule(bytes32 operationId, bytes calldata data, uint256 eta) external {
        if (msg.sender != address(vault)) {
            revert CustodyErrors.Unauthorized();
        }
        if (data.length == 0) {
            revert CustodyErrors.ZeroValue();
        }
        if (_eta[operationId] != 0) {
            revert CustodyErrors.OperationAlreadyScheduled();
        }
        if (eta < block.timestamp + delay) {
            revert CustodyErrors.TimelockNotReady();
        }

        _eta[operationId] = eta;
        _dataHash[operationId] = keccak256(data);
        emit OperationScheduled(operationId, data, eta);
    }

    /// @inheritdoc IRecoveryTimelock
    function execute(bytes32 operationId, bytes calldata data) external {
        uint256 eta = _eta[operationId];
        if (eta == 0) {
            revert CustodyErrors.OperationNotScheduled();
        }
        if (block.timestamp < eta) {
            revert CustodyErrors.TimelockNotReady();
        }
        if (block.timestamp > eta + GRACE_PERIOD) {
            revert CustodyErrors.TimelockExpired();
        }
        if (keccak256(data) != _dataHash[operationId]) {
            revert CustodyErrors.Unauthorized();
        }

        delete _eta[operationId];
        delete _dataHash[operationId];

        (bool ok,) = address(vault).call(data);
        if (!ok) {
            revert CustodyErrors.ExecutionFailed();
        }

        emit OperationExecuted(operationId);
    }

    /// @inheritdoc IRecoveryTimelock
    function cancel(bytes32 operationId) external {
        if (msg.sender != address(vault)) {
            revert CustodyErrors.Unauthorized();
        }
        if (_eta[operationId] == 0) {
            revert CustodyErrors.OperationNotScheduled();
        }

        delete _eta[operationId];
        delete _dataHash[operationId];
        emit OperationCancelled(operationId);
    }
}

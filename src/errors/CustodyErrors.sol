// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Custom errors del módulo Institutional Custody / Multisig / MPC verification.
library CustodyErrors {
    error InvalidThresholdSignature();
    error UnsortedSignatures();
    error DuplicateSignature();
    error NotASigner();
    error InvalidSignatureLength();
    error ThresholdTooHigh();
    error ThresholdTooLow();
    error SignerAlreadyExists();
    error SignerDoesNotExist();
    error DailyLimitExceeded();
    error ExecutionFailed();
    error GuardRejected();
    error TimelockNotReady();
    error TimelockExpired();
    error OperationNotScheduled();
    error OperationAlreadyScheduled();
    error ZeroAddress();
    error ZeroValue();
    error InvalidNonce();
    error Unauthorized();
}

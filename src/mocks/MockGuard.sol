// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGuard} from "../interfaces/IGuard.sol";

/// @notice Configurable guard for custody vault tests (lab).
contract MockGuard is IGuard {
    bool public rejectPre;
    bool public rejectPost;
    uint256 public preCalls;
    uint256 public postCalls;

    address public lastTo;
    uint256 public lastValue;
    address public lastMsgSender;
    bytes32 public lastTxHash;
    bool public lastSuccess;

    error MockGuardPreRejected();
    error MockGuardPostRejected();

    /// @notice Toggles whether `checkTransaction` should revert.
    function setRejectPre(bool reject) external {
        rejectPre = reject;
    }

    /// @notice Toggles whether `checkAfterExecution` should revert.
    function setRejectPost(bool reject) external {
        rejectPost = reject;
    }

    /// @inheritdoc IGuard
    function checkTransaction(address to, uint256 value, bytes memory, uint8, address msgSender) external {
        unchecked {
            ++preCalls;
        }
        lastTo = to;
        lastValue = value;
        lastMsgSender = msgSender;
        if (rejectPre) {
            revert MockGuardPreRejected();
        }
    }

    /// @inheritdoc IGuard
    function checkAfterExecution(bytes32 txHash, bool success) external {
        unchecked {
            ++postCalls;
        }
        lastTxHash = txHash;
        lastSuccess = success;
        if (rejectPost) {
            revert MockGuardPostRejected();
        }
    }
}

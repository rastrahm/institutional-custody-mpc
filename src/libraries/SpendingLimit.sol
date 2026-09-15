// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../errors/CustodyErrors.sol";

/// @notice Rolling daily spending window tracked by timestamp.
library SpendingLimit {
    /// @dev Length of each spending window (1 day).
    uint256 internal constant WINDOW = 1 days;

    /// @notice On-chain spending cap state.
    struct Data {
        uint256 dailyLimit;
        uint256 spentInWindow;
        uint256 windowStart;
    }

    /// @notice Remaining allowance in the current window (after implicit reset).
    function remaining(Data storage self) internal view returns (uint256) {
        if (_needsReset(self)) {
            return self.dailyLimit;
        }
        if (self.spentInWindow >= self.dailyLimit) {
            return 0;
        }
        return self.dailyLimit - self.spentInWindow;
    }

    /// @notice Effective spent amount in the active window (0 if the window has elapsed).
    function spentToday(Data storage self) internal view returns (uint256) {
        if (_needsReset(self)) {
            return 0;
        }
        return self.spentInWindow;
    }

    /// @notice Reverts if `amount` does not fit in the remaining allowance.
    function checkCanSpend(Data storage self, uint256 amount) internal view {
        if (amount > remaining(self)) {
            revert CustodyErrors.DailyLimitExceeded();
        }
    }

    /// @notice Resets the window if elapsed, then accumulates `amount`.
    /// @dev Caller must have already verified `amount` fits via `checkCanSpend`.
    function recordSpend(Data storage self, uint256 amount) internal {
        if (_needsReset(self)) {
            self.windowStart = block.timestamp;
            self.spentInWindow = 0;
        }
        self.spentInWindow += amount;
    }

    function _needsReset(Data storage self) private view returns (bool) {
        if (self.windowStart == 0) {
            return true;
        }
        return block.timestamp >= self.windowStart + WINDOW;
    }
}

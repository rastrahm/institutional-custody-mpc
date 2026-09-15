// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../../src/errors/CustodyErrors.sol";
import {CustodyVault} from "../../src/CustodyVault.sol";
import {SpendingLimit} from "../../src/libraries/SpendingLimit.sol";
import {CustodyTestBase} from "../helpers/CustodyTestBase.sol";

/// @notice Fuzz daily volume across timestamp boundaries — no bypass inside an active window.
contract SpendingWindowFuzzTest is CustodyTestBase {
    /// @dev Multiple under-limit spends + warps; spent never exceeds dailyLimit in an active window.
    function testFuzz_UnderLimit_NeverExceedsCapInWindow(uint256 seed, uint8 actions) public {
        actions = uint8(bound(actions, 1, 12));
        uint256 limit = vault.dailyLimit();

        for (uint256 i; i < actions; ++i) {
            uint256 roll = uint256(keccak256(abi.encode(seed, i)));
            bool warpAcross = (roll % 5 == 0);
            if (warpAcross) {
                vm.warp(block.timestamp + SpendingLimit.WINDOW + (roll % 1000));
            } else if (roll % 3 == 0) {
                // Stay inside window (no reset).
                uint256 start = vault.windowStart();
                if (start != 0) {
                    uint256 maxTs = start + SpendingLimit.WINDOW - 1;
                    if (block.timestamp < maxTs) {
                        vm.warp(block.timestamp + 1);
                    }
                }
            }

            uint256 remaining = vault.remainingDailyLimit();
            uint256 value = (roll % (limit + 1)); // 0..limit inclusive before clamp to remaining+

            address payable recipient = payable(address(uint160(1000 + i)));
            bytes memory data = "";
            bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
            bytes memory sig = _signDigest(OWNER1_PK, digest);

            if (value > remaining) {
                vm.expectRevert(CustodyErrors.DailyLimitExceeded.selector);
                vault.execTransactionUnderLimit(recipient, value, data, sig);
                assertLe(vault.spentInWindow(), limit);
            } else {
                bool ok = vault.execTransactionUnderLimit(recipient, value, data, sig);
                assertTrue(ok);
                assertLe(vault.spentInWindow(), limit);
                assertEq(vault.spentInWindow() + vault.remainingDailyLimit(), limit);
            }
        }
    }

    /// @dev After crossing the window boundary, allowance fully restores regardless of prior spent.
    function testFuzz_WindowBoundary_ResetsAllowance(uint256 spentBefore, uint256 warpExtra) public {
        spentBefore = bound(spentBefore, 1, vault.dailyLimit());
        warpExtra = bound(warpExtra, 0, 30 days);

        _send(spentBefore);
        assertEq(vault.spentInWindow(), spentBefore);

        vm.warp(block.timestamp + SpendingLimit.WINDOW + warpExtra);

        assertEq(vault.spentInWindow(), 0);
        assertEq(vault.remainingDailyLimit(), vault.dailyLimit());
    }

    function _send(uint256 value) internal {
        address payable recipient = payable(makeAddr("fuzz-recv"));
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER2_PK, digest);
        assertTrue(vault.execTransactionUnderLimit(recipient, value, data, sig));
    }
}

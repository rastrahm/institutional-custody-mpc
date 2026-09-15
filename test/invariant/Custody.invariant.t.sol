// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {CustodyVault} from "../../src/CustodyVault.sol";
import {SpendingLimit} from "../../src/libraries/SpendingLimit.sol";
import {CustodyHandler} from "./CustodyHandler.sol";

/// @notice Invariants: threshold ≤ owners, spent ≤ dailyLimit, nonce monotonic.
contract CustodyInvariantTest is StdInvariant, Test {
    uint256 internal constant OWNER1_PK = 0xA11CE;
    uint256 internal constant OWNER2_PK = 0xB0B;
    uint256 internal constant OWNER3_PK = 0xC0FFEE;

    CustodyVault internal vault;
    CustodyHandler internal handler;

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = vm.addr(OWNER1_PK);
        owners[1] = vm.addr(OWNER2_PK);
        owners[2] = vm.addr(OWNER3_PK);
        // sort
        for (uint256 i; i < 3; ++i) {
            for (uint256 j = i + 1; j < 3; ++j) {
                if (uint160(owners[j]) < uint160(owners[i])) {
                    (owners[i], owners[j]) = (owners[j], owners[i]);
                }
            }
        }

        vault = new CustodyVault(owners, 2, 1 ether, address(0));
        vm.deal(address(vault), 100 ether);

        // Use the two lowest addresses' keys for quorum packing in the handler.
        uint256 pkLow = _pkFor(owners[0]);
        uint256 pkMid = _pkFor(owners[1]);
        handler = new CustodyHandler(vault, pkLow, pkMid);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = CustodyHandler.underLimitSend.selector;
        selectors[1] = CustodyHandler.quorumSend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Threshold never exceeds owner count.
    function invariant_ThresholdBoundedByOwners() public view {
        assertLe(vault.getThreshold(), vault.getOwners().length);
        assertGe(vault.getThreshold(), 1);
    }

    /// @notice Spent in the active window never exceeds the configured daily limit.
    function invariant_SpentWithinDailyLimit() public view {
        assertLe(vault.spentInWindow(), vault.dailyLimit());
        assertEq(vault.spentInWindow() + vault.remainingDailyLimit(), vault.dailyLimit());
    }

    /// @notice Nonce is monotonic non-decreasing vs handler ghost.
    function invariant_NonceMonotonic() public view {
        assertGe(vault.nonce(), handler.ghostNonce());
        // After each successful handler action ghostNonce is synced to vault.nonce.
        assertEq(vault.nonce(), handler.ghostNonce());
    }

    /// @notice Window constant is the expected 1 day.
    function invariant_WindowConstant() public pure {
        assertEq(SpendingLimit.WINDOW, 1 days);
    }

    function _pkFor(address account) internal view returns (uint256) {
        if (account == vm.addr(OWNER1_PK)) {
            return OWNER1_PK;
        }
        if (account == vm.addr(OWNER2_PK)) {
            return OWNER2_PK;
        }
        if (account == vm.addr(OWNER3_PK)) {
            return OWNER3_PK;
        }
        revert("unknown");
    }
}

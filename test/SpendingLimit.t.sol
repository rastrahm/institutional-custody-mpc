// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../src/errors/CustodyErrors.sol";
import {SpendingLimit} from "../src/libraries/SpendingLimit.sol";
import {CustodyTestBase} from "./helpers/CustodyTestBase.sol";

/// @notice Daily spending limit: single-owner under-limit path and window reset.
contract SpendingLimitTest is CustodyTestBase {
    function test_UnderLimit_SingleOwner_TransfersEth() public {
        address payable recipient = payable(makeAddr("ops"));
        uint256 value = 0.4 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);

        bool ok = vault.execTransactionUnderLimit(recipient, value, data, sig);

        assertTrue(ok);
        assertEq(recipient.balance, value);
        assertEq(vault.spentInWindow(), value);
        assertEq(vault.remainingDailyLimit(), DEFAULT_DAILY_LIMIT - value);
        assertEq(vault.nonce(), 1);
    }

    function test_UnderLimit_ZeroValueCall_DoesNotConsumeAllowance() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER2_PK, digest);

        vault.execTransactionUnderLimit(address(target), 0, data, sig);

        assertEq(target.counter(), 1);
        assertEq(vault.spentInWindow(), 0);
        assertEq(vault.remainingDailyLimit(), DEFAULT_DAILY_LIMIT);
    }

    function test_UnderLimit_AccumulatesUntilCap() public {
        _underLimitSend(0.6 ether);
        _underLimitSend(0.4 ether);

        assertEq(vault.spentInWindow(), 1 ether);
        assertEq(vault.remainingDailyLimit(), 0);

        address payable recipient = payable(makeAddr("over"));
        bytes memory data = "";
        uint256 value = 1 wei;
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);

        vm.expectRevert(CustodyErrors.DailyLimitExceeded.selector);
        vault.execTransactionUnderLimit(recipient, value, data, sig);
    }

    function test_UnderLimit_ExactRemaining_Succeeds() public {
        _underLimitSend(0.75 ether);

        address payable recipient = payable(makeAddr("tail"));
        uint256 value = 0.25 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER3_PK, digest);

        assertTrue(vault.execTransactionUnderLimit(recipient, value, data, sig));
        assertEq(vault.remainingDailyLimit(), 0);
    }

    function test_UnderLimit_WindowReset_AfterWarp() public {
        _underLimitSend(1 ether);
        assertEq(vault.remainingDailyLimit(), 0);

        vm.warp(block.timestamp + SpendingLimit.WINDOW);

        assertEq(vault.spentInWindow(), 0);
        assertEq(vault.remainingDailyLimit(), DEFAULT_DAILY_LIMIT);

        _underLimitSend(0.5 ether);
        assertEq(vault.spentInWindow(), 0.5 ether);
    }

    function test_UnderLimit_WithinWindow_WarpDoesNotReset() public {
        uint256 start = block.timestamp;
        _underLimitSend(0.5 ether);

        vm.warp(start + SpendingLimit.WINDOW - 1);

        assertEq(vault.spentInWindow(), 0.5 ether);
        assertEq(vault.remainingDailyLimit(), 0.5 ether);

        address payable recipient = payable(makeAddr("still-capped"));
        bytes memory data = "";
        uint256 value = 0.6 ether;
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);

        vm.expectRevert(CustodyErrors.DailyLimitExceeded.selector);
        vault.execTransactionUnderLimit(recipient, value, data, sig);
    }

    function test_FullQuorum_BypassesDailyLimit() public {
        _underLimitSend(1 ether);
        assertEq(vault.remainingDailyLimit(), 0);

        address payable recipient = payable(makeAddr("governance"));
        uint256 value = 2 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        assertTrue(vault.execTransaction(recipient, value, data, signatures));
        assertEq(recipient.balance, 2 ether);
        // Daily window untouched by quorum path.
        assertEq(vault.spentInWindow(), 1 ether);
    }

    function test_UnderLimit_NonSigner_Reverts() public {
        address payable recipient = payable(makeAddr("x"));
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, 0.1 ether, data, vault.nonce());
        bytes memory sig = _signDigest(STRANGER_PK, digest);

        vm.expectRevert(CustodyErrors.NotASigner.selector);
        vault.execTransactionUnderLimit(recipient, 0.1 ether, data, sig);
    }

    function test_UnderLimit_BadSignatureLength_Reverts() public {
        vm.expectRevert(CustodyErrors.InvalidSignatureLength.selector);
        vault.execTransactionUnderLimit(address(target), 0, "", hex"01");
    }

    function test_UnderLimit_TargetFail_StillConsumesSpendAndNonce() public {
        // Fund call with value against a reverting target that accepts ETH then reverts via boom-like...
        // boom() is pure and ignores value; send value to boom.
        bytes memory data = abi.encodeCall(target.boom, ());
        uint256 value = 0.2 ether;
        bytes32 digest = vault.getTransactionHash(address(target), value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);

        bool ok = vault.execTransactionUnderLimit(address(target), value, data, sig);

        assertFalse(ok);
        assertEq(vault.nonce(), 1);
        assertEq(vault.spentInWindow(), value);
    }

    function _underLimitSend(uint256 value) internal {
        address payable recipient =
            payable(address(uint160(uint256(keccak256(abi.encode("recv", value, vault.nonce()))))));
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);
        assertTrue(vault.execTransactionUnderLimit(recipient, value, data, sig));
    }
}

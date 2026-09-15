// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../src/errors/CustodyErrors.sol";
import {MockGuard} from "../src/mocks/MockGuard.sol";
import {CustodyTestBase} from "./helpers/CustodyTestBase.sol";

/// @notice Pluggable guard pre/post hooks on quorum and under-limit execution.
contract GuardTest is CustodyTestBase {
    MockGuard internal mockGuard;

    function setUp() public override {
        super.setUp();
        mockGuard = new MockGuard();
        _setGuardViaMultisig(address(mockGuard));
    }

    function test_SetGuard_OnlySelf_RevertsForEOA() public {
        vm.expectRevert(CustodyErrors.Unauthorized.selector);
        vault.setGuard(address(mockGuard));
    }

    function test_SetGuard_ViaMultisig_Succeeds() public view {
        assertEq(vault.guard(), address(mockGuard));
    }

    function test_ClearGuard_ViaMultisig() public {
        _setGuardViaMultisig(address(0));
        assertEq(vault.guard(), address(0));

        uint256 preBefore = mockGuard.preCalls();
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertTrue(vault.execTransaction(address(target), 0, data, signatures));
        assertEq(mockGuard.preCalls(), preBefore);
    }

    function test_ExecTransaction_CallsGuardPreAndPost() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        assertTrue(vault.execTransaction(address(target), 0, data, signatures));

        assertEq(mockGuard.preCalls(), 1);
        assertEq(mockGuard.postCalls(), 1);
        assertEq(mockGuard.lastTo(), address(target));
        assertEq(mockGuard.lastTxHash(), digest);
        assertTrue(mockGuard.lastSuccess());
        assertEq(target.counter(), 1);
    }

    function test_ExecTransaction_PreReject_RevertsWithoutConsumingNonce() public {
        mockGuard.setRejectPre(true);

        uint256 nonceBefore = vault.nonce();
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, nonceBefore);
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        vm.expectRevert(CustodyErrors.GuardRejected.selector);
        vault.execTransaction(address(target), 0, data, signatures);

        assertEq(vault.nonce(), nonceBefore);
        assertEq(target.counter(), 0);
    }

    function test_ExecTransaction_PostReject_RevertsAndRollsBackNonce() public {
        mockGuard.setRejectPost(true);

        uint256 nonceBefore = vault.nonce();
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, nonceBefore);
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        vm.expectRevert(CustodyErrors.GuardRejected.selector);
        vault.execTransaction(address(target), 0, data, signatures);

        // Full tx revert rolls back effects (nonce + target state).
        assertEq(vault.nonce(), nonceBefore);
        assertEq(target.counter(), 0);
    }

    function test_UnderLimit_PreReject_RevertsWithoutConsumingSpend() public {
        mockGuard.setRejectPre(true);

        uint256 nonceBefore = vault.nonce();
        address payable recipient = payable(makeAddr("blocked"));
        uint256 value = 0.1 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, nonceBefore);
        bytes memory sig = _signDigest(OWNER1_PK, digest);

        vm.expectRevert(CustodyErrors.GuardRejected.selector);
        vault.execTransactionUnderLimit(recipient, value, data, sig);

        assertEq(vault.nonce(), nonceBefore);
        assertEq(vault.spentInWindow(), 0);
        assertEq(recipient.balance, 0);
    }

    function test_UnderLimit_WithGuard_Succeeds() public {
        address payable recipient = payable(makeAddr("ops"));
        uint256 value = 0.1 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);

        assertTrue(vault.execTransactionUnderLimit(recipient, value, data, sig));
        assertEq(mockGuard.preCalls(), 1);
        assertEq(mockGuard.postCalls(), 1);
        assertEq(recipient.balance, value);
    }

    function test_NoGuard_ExecStillWorks() public {
        // Fresh vault without guard from parent setUp path — clear first.
        _setGuardViaMultisig(address(0));

        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertTrue(vault.execTransaction(address(target), 0, data, signatures));
        assertEq(target.counter(), 1);
    }

    function _setGuardViaMultisig(address guard_) internal {
        bytes memory data = abi.encodeCall(vault.setGuard, (guard_));
        bytes32 digest = vault.getTransactionHash(address(vault), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertTrue(vault.execTransaction(address(vault), 0, data, signatures));
    }
}

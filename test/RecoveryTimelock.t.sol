// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../src/errors/CustodyErrors.sol";
import {CustodyVault} from "../src/CustodyVault.sol";
import {RecoveryTimelock} from "../src/RecoveryTimelock.sol";
import {CustodyTestBase} from "./helpers/CustodyTestBase.sol";

/// @notice Recovery timelock: schedule → delay → execute / cancel for custody mutations.
contract RecoveryTimelockTest is CustodyTestBase {
    uint256 internal constant DELAY = 1 days;

    RecoveryTimelock internal timelock;
    address internal newOwner;
    uint256 internal constant NEW_OWNER_PK = 0xD00D;

    function setUp() public override {
        super.setUp();
        newOwner = vm.addr(NEW_OWNER_PK);
        timelock = new RecoveryTimelock(address(vault), DELAY);
        _bindTimelock();
    }

    function test_Schedule_OnlyVault_RevertsForEOA() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes32 opId = keccak256("op");
        uint256 eta = block.timestamp + DELAY;

        vm.expectRevert(CustodyErrors.Unauthorized.selector);
        timelock.schedule(opId, data, eta);
    }

    function test_ChangeThreshold_AfterDelay() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes32 opId = keccak256(abi.encode(data, "change-threshold"));
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);

        vm.expectRevert(CustodyErrors.TimelockNotReady.selector);
        timelock.execute(opId, data);

        vm.warp(eta);
        timelock.execute(opId, data);

        assertEq(vault.getThreshold(), 1);
        assertEq(timelock.getEta(opId), 0);
    }

    function test_AddOwner_AfterDelay() public {
        bytes memory data = abi.encodeCall(vault.addOwnerWithThreshold, (newOwner, 2));
        bytes32 opId = keccak256(abi.encode(data, "add"));
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        vm.warp(eta);
        timelock.execute(opId, data);

        assertTrue(vault.isOwner(newOwner));
        assertEq(vault.getOwners().length, 4);
        assertEq(vault.getThreshold(), 2);
    }

    function test_RemoveOwner_AfterDelay() public {
        address[] memory owners = vault.getOwners();
        address toRemove = owners[2];
        bytes memory data = abi.encodeCall(vault.removeOwnerWithThreshold, (toRemove, 2));
        bytes32 opId = keccak256(abi.encode(data, "remove"));
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        vm.warp(eta);
        timelock.execute(opId, data);

        assertFalse(vault.isOwner(toRemove));
        assertEq(vault.getOwners().length, 2);
        assertEq(vault.getThreshold(), 2);
    }

    function test_Execute_WrongData_Reverts() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes memory wrong = abi.encodeCall(vault.changeThreshold, (3));
        bytes32 opId = keccak256("wrong-data");
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        vm.warp(eta);

        vm.expectRevert(CustodyErrors.Unauthorized.selector);
        timelock.execute(opId, wrong);
    }

    function test_Execute_Expired_Reverts() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes32 opId = keccak256("expired");
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        vm.warp(eta + timelock.GRACE_PERIOD() + 1);

        vm.expectRevert(CustodyErrors.TimelockExpired.selector);
        timelock.execute(opId, data);
    }

    function test_Cancel_PreventsExecute() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes32 opId = keccak256("cancel-me");
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        _cancelViaMultisig(opId);

        vm.warp(eta);
        vm.expectRevert(CustodyErrors.OperationNotScheduled.selector);
        timelock.execute(opId, data);
        assertEq(vault.getThreshold(), 2);
    }

    function test_Schedule_EtaTooSoon_Reverts() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes32 opId = keccak256("too-soon");
        uint256 eta = block.timestamp + DELAY - 1;

        bytes memory callData = abi.encodeCall(timelock.schedule, (opId, data, eta));
        bytes32 digest = vault.getTransactionHash(address(timelock), 0, callData, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        // Outer exec succeeds but inner schedule reverts → ExecutionFailure path returns false
        bool ok = vault.execTransaction(address(timelock), 0, callData, signatures);
        assertFalse(ok);
        assertEq(timelock.getEta(opId), 0);
    }

    function test_Schedule_Duplicate_Reverts() public {
        bytes memory data = abi.encodeCall(vault.changeThreshold, (1));
        bytes32 opId = keccak256("dup");
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);

        bytes memory callData = abi.encodeCall(timelock.schedule, (opId, data, eta + DELAY));
        bytes32 digest = vault.getTransactionHash(address(timelock), 0, callData, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertFalse(vault.execTransaction(address(timelock), 0, callData, signatures));
    }

    function test_DirectVaultMutation_RevertsUnauthorized() public {
        vm.expectRevert(CustodyErrors.Unauthorized.selector);
        vault.changeThreshold(1);

        vm.expectRevert(CustodyErrors.Unauthorized.selector);
        vault.addOwnerWithThreshold(newOwner, 2);
    }

    function test_InvalidThreshold_OnExecute_BubblesExecutionFailed() public {
        // newThreshold 0 is invalid
        bytes memory data = abi.encodeCall(vault.changeThreshold, (0));
        bytes32 opId = keccak256("bad-threshold");
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        vm.warp(eta);

        vm.expectRevert(CustodyErrors.ExecutionFailed.selector);
        timelock.execute(opId, data);
    }

    function test_AddOwner_InvalidThresholdTooHigh_RevertsOnExecute() public {
        // 5 > owners.length after add (4)
        bytes memory data = abi.encodeCall(vault.addOwnerWithThreshold, (newOwner, 5));
        bytes32 opId = keccak256("too-high");
        uint256 eta = block.timestamp + DELAY;

        _scheduleViaMultisig(opId, data, eta);
        vm.warp(eta);

        vm.expectRevert(CustodyErrors.ExecutionFailed.selector);
        timelock.execute(opId, data);
        assertFalse(vault.isOwner(newOwner));
    }

    function _bindTimelock() internal {
        bytes memory data = abi.encodeCall(vault.setRecoveryTimelock, (address(timelock)));
        bytes32 digest = vault.getTransactionHash(address(vault), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertTrue(vault.execTransaction(address(vault), 0, data, signatures));
        assertEq(vault.recoveryTimelock(), address(timelock));
    }

    function _scheduleViaMultisig(bytes32 opId, bytes memory data, uint256 eta) internal {
        bytes memory callData = abi.encodeCall(timelock.schedule, (opId, data, eta));
        bytes32 digest = vault.getTransactionHash(address(timelock), 0, callData, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertTrue(vault.execTransaction(address(timelock), 0, callData, signatures));
        assertEq(timelock.getEta(opId), eta);
    }

    function _cancelViaMultisig(bytes32 opId) internal {
        bytes memory callData = abi.encodeCall(timelock.cancel, (opId));
        bytes32 digest = vault.getTransactionHash(address(timelock), 0, callData, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        assertTrue(vault.execTransaction(address(timelock), 0, callData, signatures));
        assertEq(timelock.getEta(opId), 0);
    }
}

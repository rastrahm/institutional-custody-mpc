// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../src/errors/CustodyErrors.sol";
import {CustodyVault} from "../src/CustodyVault.sol";
import {CustodyTestBase} from "./helpers/CustodyTestBase.sol";

/// @notice Threshold M-of-N execution: exact quorum, excess signatures, ETH transfer, failures.
contract ThresholdExecutionTest is CustodyTestBase {
    function test_ExecTransaction_ExactThreshold_Succeeds() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        bool ok = vault.execTransaction(address(target), 0, data, signatures);

        assertTrue(ok);
        assertEq(target.counter(), 1);
        assertEq(target.lastCaller(), address(vault));
        assertEq(vault.nonce(), 1);
    }

    function test_ExecTransaction_ExcessSignatures_Succeeds() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _threeOwnerPks());

        bool ok = vault.execTransaction(address(target), 0, data, signatures);

        assertTrue(ok);
        assertEq(target.counter(), 1);
        assertEq(vault.nonce(), 1);
    }

    function test_ExecTransaction_TransfersEth() public {
        address payable recipient = payable(makeAddr("recipient"));
        bytes memory data = "";
        uint256 value = 1 ether;
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        vault.execTransaction(recipient, value, data, signatures);

        assertEq(recipient.balance, 1 ether);
        assertEq(address(vault).balance, 9 ether);
        assertEq(vault.nonce(), 1);
    }

    function test_ExecTransaction_InsufficientSignatures_Reverts() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());

        uint256[] memory one = new uint256[](1);
        one[0] = OWNER1_PK;
        bytes memory signatures = _packSortedSignatures(digest, one);

        vm.expectRevert(CustodyErrors.InvalidThresholdSignature.selector);
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function test_ExecTransaction_TargetRevert_ReturnsFalse_AndConsumesNonce() public {
        bytes memory data = abi.encodeCall(target.boom, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        vm.expectEmit(true, true, false, true);
        emit CustodyVault.ExecutionFailure(digest, address(target), 0);

        bool ok = vault.execTransaction(address(target), 0, data, signatures);

        assertFalse(ok);
        assertEq(vault.nonce(), 1);
    }

    function test_ExecTransaction_ZeroTo_Reverts() public {
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(address(0), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        vm.expectRevert(CustodyErrors.ZeroAddress.selector);
        vault.execTransaction(address(0), 0, data, signatures);
    }

    function test_Constructor_ThresholdTooHigh_Reverts() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        vm.expectRevert(CustodyErrors.ThresholdTooHigh.selector);
        new CustodyVault(owners, 3, DEFAULT_DAILY_LIMIT);
    }

    function test_Constructor_ThresholdZero_Reverts() public {
        address[] memory owners = new address[](1);
        owners[0] = owner1;
        vm.expectRevert(CustodyErrors.ThresholdTooLow.selector);
        new CustodyVault(owners, 0, DEFAULT_DAILY_LIMIT);
    }

    function test_Constructor_DuplicateOwner_Reverts() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner1;
        vm.expectRevert(CustodyErrors.SignerAlreadyExists.selector);
        new CustodyVault(owners, 1, DEFAULT_DAILY_LIMIT);
    }
}

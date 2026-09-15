// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyTestBase} from "../helpers/CustodyTestBase.sol";

/**
 * @title CustodyVaultGasTest
 * @notice Baseline gas hot paths (`forge snapshot --match-contract CustodyVaultGasTest`).
 */
contract CustodyVaultGasTest is CustodyTestBase {
    function testGas_execTransaction_ExactThreshold() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function testGas_execTransaction_ExcessSignatures() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _threeOwnerPks());
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function testGas_execTransactionUnderLimit() public {
        address payable recipient = payable(makeAddr("gas-ops"));
        uint256 value = 0.1 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory sig = _signDigest(OWNER1_PK, digest);
        vault.execTransactionUnderLimit(recipient, value, data, sig);
    }

    function testGas_isValidSignature() public view {
        bytes32 hash = keccak256("gas-erc1271");
        bytes memory signatures = _packSortedSignatures(hash, _twoOwnerPks());
        vault.isValidSignature(hash, signatures);
    }

    function testGas_execTransaction_EthTransfer() public {
        address payable recipient = payable(makeAddr("gas-eth"));
        uint256 value = 1 ether;
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(recipient, value, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());
        vault.execTransaction(recipient, value, data, signatures);
    }
}

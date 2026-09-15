// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CustodyErrors} from "../src/errors/CustodyErrors.sol";
import {CustodyTestBase} from "./helpers/CustodyTestBase.sol";

/// @notice Signature sorting, duplicate rejection and non-signer rejection.
contract SignatureSortingTest is CustodyTestBase {
    function test_UnsortedSignatures_Reverts() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());

        address[] memory ordered = _sortedOwners3();
        // Higher address first → unsorted ascending requirement fails.
        uint256 highPk = _pkFor(ordered[2]);
        uint256 lowPk = _pkFor(ordered[0]);

        bytes memory signatures = bytes.concat(_signDigest(highPk, digest), _signDigest(lowPk, digest));

        vm.expectRevert(CustodyErrors.UnsortedSignatures.selector);
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function test_DuplicateSignature_Reverts() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());

        bytes memory sig = _signDigest(OWNER1_PK, digest);
        bytes memory signatures = bytes.concat(sig, sig);

        vm.expectRevert(CustodyErrors.DuplicateSignature.selector);
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function test_NonSigner_Reverts() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());

        address[] memory ordered = _sortedOwners3();
        uint256 ownerPk = _pkFor(ordered[0]);

        // Stranger address relative order: pack sorted so stranger may be first or second.
        uint256[] memory pks = new uint256[](2);
        if (uint160(stranger) < uint160(ordered[0])) {
            pks[0] = STRANGER_PK;
            pks[1] = ownerPk;
        } else {
            pks[0] = ownerPk;
            pks[1] = STRANGER_PK;
        }

        bytes memory signatures = _packSortedSignatures(digest, pks);

        vm.expectRevert(CustodyErrors.NotASigner.selector);
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function test_InvalidSignatureLength_Reverts() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes memory signatures = hex"01";

        vm.expectRevert(CustodyErrors.InvalidSignatureLength.selector);
        vault.execTransaction(address(target), 0, data, signatures);
    }

    function test_EmptySignatures_Reverts() public {
        bytes memory data = abi.encodeCall(target.ping, ());

        vm.expectRevert(CustodyErrors.InvalidSignatureLength.selector);
        vault.execTransaction(address(target), 0, data, "");
    }

    function test_ReplaySameSignatures_FailsAfterNonceBump() public {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        vault.execTransaction(address(target), 0, data, signatures);

        // Old signatures authorize the previous nonce digest only.
        vm.expectRevert();
        vault.execTransaction(address(target), 0, data, signatures);

        assertEq(target.counter(), 1);
        assertEq(vault.nonce(), 1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1271} from "../src/interfaces/IERC1271.sol";
import {CustodyTestBase} from "./helpers/CustodyTestBase.sol";

/// @notice ERC-1271 integration: threshold-signed hashes validate against the vault contract.
contract ERC1271Test is CustodyTestBase {
    bytes4 internal constant MAGIC = 0x1626ba7e;
    bytes4 internal constant INVALID = 0xffffffff;

    function test_IsValidSignature_ExactThreshold_ReturnsMagic() public view {
        bytes32 hash = keccak256("custody-offchain-message");
        bytes memory signatures = _packSortedSignatures(hash, _twoOwnerPks());

        bytes4 magic = vault.isValidSignature(hash, signatures);
        assertEq(magic, MAGIC);
        assertEq(magic, IERC1271.isValidSignature.selector);
    }

    function test_IsValidSignature_ExcessSignatures_ReturnsMagic() public view {
        bytes32 hash = keccak256("excess-signers-ok");
        bytes memory signatures = _packSortedSignatures(hash, _threeOwnerPks());

        assertEq(vault.isValidSignature(hash, signatures), MAGIC);
    }

    function test_IsValidSignature_TypedTransactionHash_ReturnsMagic() public view {
        bytes memory data = abi.encodeCall(target.ping, ());
        bytes32 digest = vault.getTransactionHash(address(target), 0, data, vault.nonce());
        bytes memory signatures = _packSortedSignatures(digest, _twoOwnerPks());

        assertEq(vault.isValidSignature(digest, signatures), MAGIC);
    }

    function test_IsValidSignature_InsufficientSignatures_ReturnsInvalid() public view {
        bytes32 hash = keccak256("need-two");
        uint256[] memory one = new uint256[](1);
        one[0] = OWNER1_PK;
        bytes memory signatures = _packSortedSignatures(hash, one);

        assertEq(vault.isValidSignature(hash, signatures), INVALID);
    }

    function test_IsValidSignature_Unsorted_ReturnsInvalid() public view {
        bytes32 hash = keccak256("unsorted");
        address[] memory ordered = _sortedOwners3();
        bytes memory signatures =
            bytes.concat(_signDigest(_pkFor(ordered[2]), hash), _signDigest(_pkFor(ordered[0]), hash));

        assertEq(vault.isValidSignature(hash, signatures), INVALID);
    }

    function test_IsValidSignature_Duplicate_ReturnsInvalid() public view {
        bytes32 hash = keccak256("dup");
        bytes memory sig = _signDigest(OWNER1_PK, hash);

        assertEq(vault.isValidSignature(hash, bytes.concat(sig, sig)), INVALID);
    }

    function test_IsValidSignature_NonSigner_ReturnsInvalid() public view {
        bytes32 hash = keccak256("stranger");
        address[] memory ordered = _sortedOwners3();
        uint256[] memory pks = new uint256[](2);
        if (uint160(stranger) < uint160(ordered[0])) {
            pks[0] = STRANGER_PK;
            pks[1] = _pkFor(ordered[0]);
        } else {
            pks[0] = _pkFor(ordered[0]);
            pks[1] = STRANGER_PK;
        }

        assertEq(vault.isValidSignature(hash, _packSortedSignatures(hash, pks)), INVALID);
    }

    function test_IsValidSignature_Empty_ReturnsInvalid() public view {
        assertEq(vault.isValidSignature(keccak256("empty"), ""), INVALID);
    }

    function test_IsValidSignature_WrongHash_ReturnsInvalid() public view {
        bytes32 signedHash = keccak256("signed");
        bytes32 otherHash = keccak256("other");
        bytes memory signatures = _packSortedSignatures(signedHash, _twoOwnerPks());

        assertEq(vault.isValidSignature(otherHash, signatures), INVALID);
    }
}

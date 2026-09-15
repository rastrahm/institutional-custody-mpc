// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {CustodyErrors} from "../errors/CustodyErrors.sol";

/// @notice M-of-N ECDSA threshold validation with strict ascending signer order.
library ThresholdSignature {
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /// @notice Validates that `signatures` contains at least `threshold` unique owner signatures, sorted ascending.
    /// @dev All provided signatures are checked (excess over threshold is allowed if still valid/sorted).
    /// @param hash Digest that was signed (EIP-712 typed hash or arbitrary ERC-1271 hash).
    /// @param signatures Concatenated 65-byte ECDSA signatures.
    /// @param threshold Minimum number of valid owner signatures required.
    /// @param owners Owner bitmap (`true` if address is a signer).
    function validateThreshold(
        bytes32 hash,
        bytes memory signatures,
        uint256 threshold,
        mapping(address => bool) storage owners
    ) internal view {
        (bool ok, bytes4 errorSelector) = _check(hash, signatures, threshold, owners);
        if (ok) {
            return;
        }
        _revertSelector(errorSelector);
    }

    /// @notice Soft-check variant for ERC-1271 (never reverts).
    /// @return valid True when the packed signatures satisfy the same rules as `validateThreshold`.
    function isValidThreshold(
        bytes32 hash,
        bytes memory signatures,
        uint256 threshold,
        mapping(address => bool) storage owners
    ) internal view returns (bool valid) {
        (valid,) = _check(hash, signatures, threshold, owners);
    }

    function _check(bytes32 hash, bytes memory signatures, uint256 threshold, mapping(address => bool) storage owners)
        private
        view
        returns (bool valid, bytes4 errorSelector)
    {
        uint256 length = signatures.length;
        if (length == 0 || length % SIGNATURE_LENGTH != 0) {
            return (false, CustodyErrors.InvalidSignatureLength.selector);
        }

        uint256 count = length / SIGNATURE_LENGTH;
        if (count < threshold) {
            return (false, CustodyErrors.InvalidThresholdSignature.selector);
        }

        address previous;
        for (uint256 i; i < count; ++i) {
            bytes memory signature = _signatureAt(signatures, i);
            (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
            if (err != ECDSA.RecoverError.NoError || signer == address(0)) {
                return (false, CustodyErrors.InvalidThresholdSignature.selector);
            }

            if (uint160(signer) <= uint160(previous)) {
                if (signer == previous) {
                    return (false, CustodyErrors.DuplicateSignature.selector);
                }
                return (false, CustodyErrors.UnsortedSignatures.selector);
            }
            if (!owners[signer]) {
                return (false, CustodyErrors.NotASigner.selector);
            }

            previous = signer;
        }

        return (true, bytes4(0));
    }

    function _revertSelector(bytes4 errorSelector) private pure {
        if (errorSelector == CustodyErrors.InvalidSignatureLength.selector) {
            revert CustodyErrors.InvalidSignatureLength();
        }
        if (errorSelector == CustodyErrors.InvalidThresholdSignature.selector) {
            revert CustodyErrors.InvalidThresholdSignature();
        }
        if (errorSelector == CustodyErrors.DuplicateSignature.selector) {
            revert CustodyErrors.DuplicateSignature();
        }
        if (errorSelector == CustodyErrors.UnsortedSignatures.selector) {
            revert CustodyErrors.UnsortedSignatures();
        }
        if (errorSelector == CustodyErrors.NotASigner.selector) {
            revert CustodyErrors.NotASigner();
        }
        revert CustodyErrors.InvalidThresholdSignature();
    }

    /// @notice Extracts the 65-byte signature at `index` from a packed signature blob.
    function _signatureAt(bytes memory signatures, uint256 index) private pure returns (bytes memory signature) {
        signature = new bytes(SIGNATURE_LENGTH);
        uint256 offset = index * SIGNATURE_LENGTH;
        for (uint256 j; j < SIGNATURE_LENGTH; ++j) {
            signature[j] = signatures[offset + j];
        }
    }
}

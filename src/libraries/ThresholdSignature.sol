// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {CustodyErrors} from "../errors/CustodyErrors.sol";

/// @notice M-of-N ECDSA threshold validation with strict ascending signer order.
library ThresholdSignature {
    using ECDSA for bytes32;

    uint256 internal constant SIGNATURE_LENGTH = 65;

    /// @notice Validates that `signatures` contains at least `threshold` unique owner signatures, sorted ascending.
    /// @dev All provided signatures are checked (excess over threshold is allowed if still valid/sorted).
    /// @param hash EIP-712 digest that was signed.
    /// @param signatures Concatenated 65-byte ECDSA signatures.
    /// @param threshold Minimum number of valid owner signatures required.
    /// @param owners Owner bitmap (`true` if address is a signer).
    function validateThreshold(
        bytes32 hash,
        bytes memory signatures,
        uint256 threshold,
        mapping(address => bool) storage owners
    ) internal view {
        uint256 length = signatures.length;
        if (length == 0 || length % SIGNATURE_LENGTH != 0) {
            revert CustodyErrors.InvalidSignatureLength();
        }

        uint256 count = length / SIGNATURE_LENGTH;
        if (count < threshold) {
            revert CustodyErrors.InvalidThresholdSignature();
        }

        address previous;
        for (uint256 i; i < count; ++i) {
            bytes memory signature = _signatureAt(signatures, i);
            address signer = hash.recover(signature);

            if (uint160(signer) <= uint160(previous)) {
                if (signer == previous) {
                    revert CustodyErrors.DuplicateSignature();
                }
                revert CustodyErrors.UnsortedSignatures();
            }
            if (!owners[signer]) {
                revert CustodyErrors.NotASigner();
            }

            previous = signer;
        }
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

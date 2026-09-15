// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {CustodyVault} from "../../src/CustodyVault.sol";

/// @notice Handler for custody invariant fuzzing (under-limit + quorum ETH sends).
contract CustodyHandler is Test {
    CustodyVault public immutable vault;

    uint256 public ghostNonce;
    uint256 internal immutable owner1Pk;
    uint256 internal immutable owner2Pk;

    address[] internal recipients;

    constructor(CustodyVault vault_, uint256 owner1Pk_, uint256 owner2Pk_) {
        vault = vault_;
        owner1Pk = owner1Pk_;
        owner2Pk = owner2Pk_;
        ghostNonce = vault_.nonce();

        recipients = new address[](3);
        recipients[0] = address(0xBEEF);
        recipients[1] = address(0xCAFE);
        recipients[2] = address(0xDEAD);
    }

    /// @notice Single-owner under-limit ETH transfer (clamped to remaining allowance).
    function underLimitSend(uint256 recipientSeed, uint256 valueSeed) external {
        uint256 remaining = vault.remainingDailyLimit();
        uint256 bal = address(vault).balance;
        if (remaining == 0 || bal == 0) {
            return;
        }

        address payable to = payable(recipients[recipientSeed % recipients.length]);
        uint256 maxValue = remaining < bal ? remaining : bal;
        uint256 value = _bound(valueSeed, 0, maxValue);

        uint256 nonce_ = vault.nonce();
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(to, value, data, nonce_);
        bytes memory sig = _sign(owner1Pk, digest);

        vault.execTransactionUnderLimit(to, value, data, sig);
        ghostNonce = vault.nonce();
    }

    /// @notice Full quorum ETH transfer (bypasses daily limit).
    function quorumSend(uint256 recipientSeed, uint256 valueSeed) external {
        uint256 bal = address(vault).balance;
        if (bal == 0) {
            return;
        }

        address payable to = payable(recipients[recipientSeed % recipients.length]);
        uint256 value = _bound(valueSeed, 0, bal);

        uint256 nonce_ = vault.nonce();
        bytes memory data = "";
        bytes32 digest = vault.getTransactionHash(to, value, data, nonce_);
        bytes memory signatures = _packTwoSorted(digest, owner1Pk, owner2Pk);

        vault.execTransaction(to, value, data, signatures);
        ghostNonce = vault.nonce();
    }

    function _sign(uint256 pk, bytes32 digest) private returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _packTwoSorted(bytes32 digest, uint256 pkA, uint256 pkB) private returns (bytes memory packed) {
        address a = vm.addr(pkA);
        address b = vm.addr(pkB);
        bytes memory sigA = _sign(pkA, digest);
        bytes memory sigB = _sign(pkB, digest);
        if (uint160(a) < uint160(b)) {
            packed = bytes.concat(sigA, sigB);
        } else {
            packed = bytes.concat(sigB, sigA);
        }
    }
}

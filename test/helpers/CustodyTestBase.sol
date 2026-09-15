// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {CustodyVault} from "../../src/CustodyVault.sol";
import {MockTarget} from "../../src/mocks/MockTarget.sol";

/// @notice Shared owners, vault wiring and EIP-712 signature helpers for custody tests.
abstract contract CustodyTestBase is Test {
    uint256 internal constant OWNER1_PK = 0xA11CE;
    uint256 internal constant OWNER2_PK = 0xB0B;
    uint256 internal constant OWNER3_PK = 0xC0FFEE;
    uint256 internal constant STRANGER_PK = 0xDEAD;

    address internal owner1;
    address internal owner2;
    address internal owner3;
    address internal stranger;

    CustodyVault internal vault;
    MockTarget internal target;

    uint256 internal constant DEFAULT_DAILY_LIMIT = 1 ether;

    function setUp() public virtual {
        owner1 = vm.addr(OWNER1_PK);
        owner2 = vm.addr(OWNER2_PK);
        owner3 = vm.addr(OWNER3_PK);
        stranger = vm.addr(STRANGER_PK);

        // Ensure ascending address order for deterministic packing helpers when needed.
        address[] memory owners = _sortedOwners3();
        vault = new CustodyVault(owners, 2, DEFAULT_DAILY_LIMIT, address(0));
        target = new MockTarget();
        vm.deal(address(vault), 10 ether);
    }

    function _sortedOwners3() internal view returns (address[] memory owners) {
        owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        // Sort ascending (small N bubble).
        for (uint256 i; i < 3; ++i) {
            for (uint256 j = i + 1; j < 3; ++j) {
                if (uint160(owners[j]) < uint160(owners[i])) {
                    (owners[i], owners[j]) = (owners[j], owners[i]);
                }
            }
        }
    }

    function _pkFor(address account) internal view returns (uint256) {
        if (account == owner1) {
            return OWNER1_PK;
        }
        if (account == owner2) {
            return OWNER2_PK;
        }
        if (account == owner3) {
            return OWNER3_PK;
        }
        if (account == stranger) {
            return STRANGER_PK;
        }
        revert("unknown account");
    }

    function _signDigest(uint256 pk, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    /// @notice Signs `digest` with `pks` and concatenates signatures sorted by recovered address.
    function _packSortedSignatures(bytes32 digest, uint256[] memory pks) internal pure returns (bytes memory packed) {
        uint256 n = pks.length;
        address[] memory signers = new address[](n);
        bytes[] memory sigs = new bytes[](n);

        for (uint256 i; i < n; ++i) {
            sigs[i] = _signDigest(pks[i], digest);
            signers[i] = vm.addr(pks[i]);
        }

        // Sort by signer address ascending; keep sigs aligned.
        for (uint256 i; i < n; ++i) {
            for (uint256 j = i + 1; j < n; ++j) {
                if (uint160(signers[j]) < uint160(signers[i])) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (sigs[i], sigs[j]) = (sigs[j], sigs[i]);
                }
            }
        }

        for (uint256 i; i < n; ++i) {
            packed = bytes.concat(packed, sigs[i]);
        }
    }

    function _twoOwnerPks() internal view returns (uint256[] memory pks) {
        address[] memory owners = _sortedOwners3();
        pks = new uint256[](2);
        pks[0] = _pkFor(owners[0]);
        pks[1] = _pkFor(owners[1]);
    }

    function _threeOwnerPks() internal view returns (uint256[] memory pks) {
        address[] memory owners = _sortedOwners3();
        pks = new uint256[](3);
        pks[0] = _pkFor(owners[0]);
        pks[1] = _pkFor(owners[1]);
        pks[2] = _pkFor(owners[2]);
    }
}

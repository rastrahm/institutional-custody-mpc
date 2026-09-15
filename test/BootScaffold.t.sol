// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {CustodyErrors} from "../src/errors/CustodyErrors.sol";
import {ICustodyVault} from "../src/interfaces/ICustodyVault.sol";
import {IERC1271} from "../src/interfaces/IERC1271.sol";
import {IGuard} from "../src/interfaces/IGuard.sol";
import {IRecoveryTimelock} from "../src/interfaces/IRecoveryTimelock.sol";

/// @notice Smoke test Fase BOOT: artefactos base importables y selector de error obligatorio.
contract BootScaffoldTest is Test {
    bytes4 internal constant ERC1271_MAGIC = 0x1626ba7e;

    function test_InvalidThresholdSignatureSelectorIsNonZero() public pure {
        bytes4 selector = CustodyErrors.InvalidThresholdSignature.selector;
        assertTrue(selector != bytes4(0));
    }

    function test_Erc1271MagicValueConstant() public pure {
        assertEq(ERC1271_MAGIC, bytes4(0x1626ba7e));
    }

    function test_InterfaceIdsAreDistinct() public pure {
        bytes4 vaultId = type(ICustodyVault).interfaceId;
        bytes4 erc1271Id = type(IERC1271).interfaceId;
        bytes4 guardId = type(IGuard).interfaceId;
        bytes4 timelockId = type(IRecoveryTimelock).interfaceId;

        assertTrue(vaultId != erc1271Id);
        assertTrue(vaultId != guardId);
        assertTrue(vaultId != timelockId);
        assertTrue(erc1271Id != guardId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {CustodyVault} from "../src/CustodyVault.sol";
import {RecoveryTimelock} from "../src/RecoveryTimelock.sol";

/// @notice Deploy CustodyVault + RecoveryTimelock and bind them (Fase LOCK).
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = pk != 0 ? vm.addr(pk) : msg.sender;

        uint256 threshold = vm.envOr("THRESHOLD", uint256(2));
        uint256 dailyLimit = vm.envOr("DAILY_LIMIT", uint256(1 ether));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(1 days));

        address ownerA = vm.envOr("OWNER_1", deployer);
        address ownerB = vm.envOr("OWNER_2", address(0));
        address ownerC = vm.envOr("OWNER_3", address(0));

        address[] memory owners = _buildOwners(ownerA, ownerB, ownerC);
        if (threshold > owners.length) {
            threshold = owners.length;
        }
        if (threshold == 0) {
            threshold = 1;
        }

        if (pk != 0) {
            vm.startBroadcast(pk);
        } else {
            vm.startBroadcast();
        }

        CustodyVault vault = new CustodyVault(owners, threshold, dailyLimit, address(0));
        RecoveryTimelock timelock = new RecoveryTimelock(address(vault), timelockDelay);

        vm.stopBroadcast();

        console2.log("Deployer", deployer);
        console2.log("CustodyVault", address(vault));
        console2.log("RecoveryTimelock", address(timelock));
        console2.log("THRESHOLD", threshold);
        console2.log("OwnerCount", owners.length);
        console2.log("DAILY_LIMIT", dailyLimit);
        console2.log("TIMELOCK_DELAY", timelockDelay);
        console2.log("NOTE: bind via multisig setRecoveryTimelock(timelock)");
    }

    function _buildOwners(address a, address b, address c) internal pure returns (address[] memory owners) {
        uint256 n = 1;
        if (b != address(0)) {
            ++n;
        }
        if (c != address(0)) {
            ++n;
        }
        owners = new address[](n);
        owners[0] = a;
        uint256 i = 1;
        if (b != address(0)) {
            owners[i] = b;
            ++i;
        }
        if (c != address(0)) {
            owners[i] = c;
        }
    }
}

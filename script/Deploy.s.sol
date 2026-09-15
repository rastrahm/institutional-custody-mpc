// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Stub de deploy (Fase BOOT). Se cablea el stack completo en fases posteriores.
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = pk != 0 ? vm.addr(pk) : msg.sender;

        uint256 threshold = vm.envOr("THRESHOLD", uint256(2));
        uint256 dailyLimit = vm.envOr("DAILY_LIMIT", uint256(1 ether));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(1 days));

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast();

        // CustodyVault + RecoveryTimelock se despliegan a partir de Fase THRESH / LOCK.
        vm.stopBroadcast();

        console2.log("Deployer", deployer);
        console2.log("THRESHOLD (planned)", threshold);
        console2.log("DAILY_LIMIT (planned)", dailyLimit);
        console2.log("TIMELOCK_DELAY (planned)", timelockDelay);
        console2.log("BOOT stub - no contracts deployed yet");
    }
}

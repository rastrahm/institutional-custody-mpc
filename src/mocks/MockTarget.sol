// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

error Boom();

/// @notice Minimal target used in custody execution tests.
contract MockTarget {
    uint256 public counter;
    address public lastCaller;

    event Pinged(address caller, uint256 newCounter);

    /// @notice Increments an internal counter; used as calldata target.
    function ping() external {
        unchecked {
            ++counter;
        }
        lastCaller = msg.sender;
        emit Pinged(msg.sender, counter);
    }

    /// @notice Always reverts; used to assert ExecutionFailed path.
    function boom() external pure {
        revert Boom();
    }

    receive() external payable {}
}

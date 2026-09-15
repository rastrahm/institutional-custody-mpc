// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {CustodyErrors} from "./errors/CustodyErrors.sol";
import {ICustodyVault} from "./interfaces/ICustodyVault.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {IGuard} from "./interfaces/IGuard.sol";
import {EIP712Custody} from "./libraries/EIP712Custody.sol";
import {SpendingLimit} from "./libraries/SpendingLimit.sol";
import {ThresholdSignature} from "./libraries/ThresholdSignature.sol";

/// @notice Institutional M-of-N custody vault with EIP-712, ERC-1271, daily limits and pluggable guards.
/// @dev Under-limit path: any single owner signature; only `value` (ETH) counts toward the daily cap.
///      Full quorum `execTransaction` bypasses the daily cap (governance override).
///      `setGuard` is only callable by the vault itself (via multisig `execTransaction`).
contract CustodyVault is ICustodyVault, IERC1271, EIP712, ReentrancyGuardTransient {
    using SpendingLimit for SpendingLimit.Data;

    /// @dev ERC-1271 magic value (`bytes4(keccak256("isValidSignature(bytes32,bytes)"))`).
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;
    /// @dev ERC-1271 invalid marker returned instead of reverting (dApp compatibility).
    bytes4 internal constant ERC1271_INVALID = 0xffffffff;
    /// @dev Call operation discriminator passed to guards (DelegateCall reserved).
    uint8 internal constant OPERATION_CALL = 0;

    /// @notice Emitted after a successful external call authorized by threshold signatures.
    event ExecutionSuccess(bytes32 indexed txHash, address indexed to, uint256 value);

    /// @notice Emitted when the external call reverts (vault still consumes the nonce).
    event ExecutionFailure(bytes32 indexed txHash, address indexed to, uint256 value);

    /// @notice Emitted when spend is recorded against the daily window.
    event DailySpendRecorded(uint256 amount, uint256 spentInWindow, uint256 windowStart);

    /// @notice Emitted when the active guard module changes.
    event GuardChanged(address indexed previousGuard, address indexed newGuard);

    /// @notice Emitted when the recovery timelock is bound (once).
    event RecoveryTimelockSet(address indexed timelock);

    /// @notice Emitted when an owner is added via the recovery timelock.
    event OwnerAdded(address indexed owner, uint256 newThreshold);

    /// @notice Emitted when an owner is removed via the recovery timelock.
    event OwnerRemoved(address indexed owner, uint256 newThreshold);

    /// @notice Emitted when the threshold is changed via the recovery timelock.
    event ThresholdChanged(uint256 newThreshold);

    mapping(address => bool) private _isOwner;
    address[] private _owners;

    uint256 private _threshold;
    uint256 private _nonce;
    SpendingLimit.Data private _spending;
    address private _guard;
    address private _recoveryTimelock;

    /// @notice Deploys a vault with an initial owner set, threshold and daily ETH spending limit.
    /// @param owners_ Initial signers (unique, non-zero).
    /// @param threshold_ Required M for quorum (`1 <= M <= N`).
    /// @param dailyLimit_ Max ETH (`value`) spendable via `execTransactionUnderLimit` per window.
    /// @param recoveryTimelock_ Optional pre-bound timelock (`address(0)` to set later via self-call).
    constructor(address[] memory owners_, uint256 threshold_, uint256 dailyLimit_, address recoveryTimelock_)
        EIP712("CustodyVault", "1")
    {
        uint256 length = owners_.length;
        if (length == 0) {
            revert CustodyErrors.ZeroAddress();
        }
        if (threshold_ == 0) {
            revert CustodyErrors.ThresholdTooLow();
        }
        if (threshold_ > length) {
            revert CustodyErrors.ThresholdTooHigh();
        }

        for (uint256 i; i < length; ++i) {
            address owner = owners_[i];
            if (owner == address(0)) {
                revert CustodyErrors.ZeroAddress();
            }
            if (_isOwner[owner]) {
                revert CustodyErrors.SignerAlreadyExists();
            }
            _isOwner[owner] = true;
            _owners.push(owner);
        }

        _threshold = threshold_;
        _spending.dailyLimit = dailyLimit_;
        _recoveryTimelock = recoveryTimelock_;
    }

    /// @notice Accepts ETH deposits for custody.
    receive() external payable {}

    /// @inheritdoc ICustodyVault
    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    /// @inheritdoc ICustodyVault
    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    /// @inheritdoc ICustodyVault
    function nonce() external view returns (uint256) {
        return _nonce;
    }

    /// @inheritdoc ICustodyVault
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc ICustodyVault
    function isOwner(address account) external view returns (bool) {
        return _isOwner[account];
    }

    /// @notice Configured daily ETH spending limit for the under-limit path.
    function dailyLimit() external view returns (uint256) {
        return _spending.dailyLimit;
    }

    /// @notice ETH already spent in the active window (0 if the window has elapsed).
    function spentInWindow() external view returns (uint256) {
        return _spending.spentToday();
    }

    /// @notice Start timestamp of the active spending window (`0` before first under-limit spend).
    function windowStart() external view returns (uint256) {
        return _spending.windowStart;
    }

    /// @notice Remaining ETH that can still be spent via `execTransactionUnderLimit` in this window.
    function remainingDailyLimit() external view returns (uint256) {
        return _spending.remaining();
    }

    /// @notice Current guard module (`address(0)` if none).
    function guard() external view returns (address) {
        return _guard;
    }

    /// @notice Bound recovery timelock (`address(0)` if not set).
    function recoveryTimelock() external view returns (address) {
        return _recoveryTimelock;
    }

    /// @notice Sets or clears the execution guard. Only callable by this vault (multisig self-call).
    /// @param guard_ New guard address, or zero to disable.
    function setGuard(address guard_) external {
        if (msg.sender != address(this)) {
            revert CustodyErrors.Unauthorized();
        }
        address previous = _guard;
        _guard = guard_;
        emit GuardChanged(previous, guard_);
    }

    /// @notice Binds the recovery timelock once. Only callable by this vault (multisig self-call).
    /// @param timelock_ Timelock contract address.
    function setRecoveryTimelock(address timelock_) external {
        if (msg.sender != address(this)) {
            revert CustodyErrors.Unauthorized();
        }
        if (timelock_ == address(0)) {
            revert CustodyErrors.ZeroAddress();
        }
        if (_recoveryTimelock != address(0)) {
            revert CustodyErrors.Unauthorized();
        }
        _recoveryTimelock = timelock_;
        emit RecoveryTimelockSet(timelock_);
    }

    /// @notice Adds an owner and sets the new threshold. Only callable by the recovery timelock.
    /// @param owner Owner to add.
    /// @param newThreshold Threshold after the addition (`1 <= newThreshold <= owners.length`).
    function addOwnerWithThreshold(address owner, uint256 newThreshold) external {
        _onlyRecoveryTimelock();
        if (owner == address(0)) {
            revert CustodyErrors.ZeroAddress();
        }
        if (_isOwner[owner]) {
            revert CustodyErrors.SignerAlreadyExists();
        }
        _isOwner[owner] = true;
        _owners.push(owner);
        _setThreshold(newThreshold);
        emit OwnerAdded(owner, newThreshold);
    }

    /// @notice Removes an owner and sets the new threshold. Only callable by the recovery timelock.
    /// @param owner Owner to remove.
    /// @param newThreshold Threshold after the removal.
    function removeOwnerWithThreshold(address owner, uint256 newThreshold) external {
        _onlyRecoveryTimelock();
        if (!_isOwner[owner]) {
            revert CustodyErrors.SignerDoesNotExist();
        }
        _isOwner[owner] = false;

        uint256 length = _owners.length;
        for (uint256 i; i < length; ++i) {
            if (_owners[i] == owner) {
                _owners[i] = _owners[length - 1];
                _owners.pop();
                break;
            }
        }

        _setThreshold(newThreshold);
        emit OwnerRemoved(owner, newThreshold);
    }

    /// @notice Updates the signature threshold. Only callable by the recovery timelock.
    /// @param newThreshold New M (`1 <= newThreshold <= owners.length`).
    function changeThreshold(uint256 newThreshold) external {
        _onlyRecoveryTimelock();
        _setThreshold(newThreshold);
        emit ThresholdChanged(newThreshold);
    }

    /// @inheritdoc ICustodyVault
    /// @dev Returns the EIP-712 digest that owners must sign (same value used by `vm.sign` / eth_signTypedDataV4).
    function getTransactionHash(address to, uint256 value, bytes memory data, uint256 nonce_)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(EIP712Custody.hashTransaction(to, value, data, nonce_));
    }

    /// @inheritdoc ICustodyVault
    /// @dev Full quorum bypasses the daily spending cap.
    function execTransaction(address to, uint256 value, bytes memory data, bytes memory signatures)
        external
        nonReentrant
        returns (bool success)
    {
        if (to == address(0)) {
            revert CustodyErrors.ZeroAddress();
        }

        uint256 currentNonce = _nonce;
        bytes32 txHash = getTransactionHash(to, value, data, currentNonce);

        ThresholdSignature.validateThreshold(txHash, signatures, _threshold, _isOwner);

        address guard_ = _guard;
        _guardCheckTransaction(guard_, to, value, data);

        // Effects
        unchecked {
            _nonce = currentNonce + 1;
        }

        // Interactions
        (success,) = to.call{value: value}(data);
        if (success) {
            emit ExecutionSuccess(txHash, to, value);
        } else {
            emit ExecutionFailure(txHash, to, value);
        }

        _guardCheckAfterExecution(guard_, txHash, success);
    }

    /// @inheritdoc ICustodyVault
    /// @dev Single owner ECDSA signature. Only `value` counts toward the rolling 1-day window.
    ///      Exceeding the remaining allowance reverts with `DailyLimitExceeded` (use full quorum instead).
    function execTransactionUnderLimit(address to, uint256 value, bytes memory data, bytes memory signature)
        external
        nonReentrant
        returns (bool success)
    {
        if (to == address(0)) {
            revert CustodyErrors.ZeroAddress();
        }
        if (signature.length != ThresholdSignature.SIGNATURE_LENGTH) {
            revert CustodyErrors.InvalidSignatureLength();
        }

        uint256 currentNonce = _nonce;
        bytes32 txHash = getTransactionHash(to, value, data, currentNonce);

        address signer = ECDSA.recover(txHash, signature);
        if (!_isOwner[signer]) {
            revert CustodyErrors.NotASigner();
        }

        _spending.checkCanSpend(value);

        address guard_ = _guard;
        _guardCheckTransaction(guard_, to, value, data);

        // Effects
        unchecked {
            _nonce = currentNonce + 1;
        }
        _spending.recordSpend(value);
        emit DailySpendRecorded(value, _spending.spentInWindow, _spending.windowStart);

        // Interactions
        (success,) = to.call{value: value}(data);
        if (success) {
            emit ExecutionSuccess(txHash, to, value);
        } else {
            emit ExecutionFailure(txHash, to, value);
        }

        _guardCheckAfterExecution(guard_, txHash, success);
    }

    /// @inheritdoc IERC1271
    /// @dev Reuses the same M-of-N sorted-owner rules as `execTransaction`. Invalid payloads return
    ///      `0xffffffff` (no revert) so external dApps can branch on the magic value.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        if (ThresholdSignature.isValidThreshold(hash, signature, _threshold, _isOwner)) {
            return ERC1271_MAGICVALUE;
        }
        return ERC1271_INVALID;
    }

    function _guardCheckTransaction(address guard_, address to, uint256 value, bytes memory data) private {
        if (guard_ == address(0)) {
            return;
        }
        try IGuard(guard_).checkTransaction(to, value, data, OPERATION_CALL, msg.sender) {}
        catch {
            revert CustodyErrors.GuardRejected();
        }
    }

    function _guardCheckAfterExecution(address guard_, bytes32 txHash, bool success) private {
        if (guard_ == address(0)) {
            return;
        }
        try IGuard(guard_).checkAfterExecution(txHash, success) {}
        catch {
            revert CustodyErrors.GuardRejected();
        }
    }

    function _onlyRecoveryTimelock() private view {
        if (msg.sender != _recoveryTimelock || _recoveryTimelock == address(0)) {
            revert CustodyErrors.Unauthorized();
        }
    }

    function _setThreshold(uint256 newThreshold) private {
        if (newThreshold == 0) {
            revert CustodyErrors.ThresholdTooLow();
        }
        if (newThreshold > _owners.length) {
            revert CustodyErrors.ThresholdTooHigh();
        }
        _threshold = newThreshold;
    }
}

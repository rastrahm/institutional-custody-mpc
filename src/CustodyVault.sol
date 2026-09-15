// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {CustodyErrors} from "./errors/CustodyErrors.sol";
import {ICustodyVault} from "./interfaces/ICustodyVault.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {EIP712Custody} from "./libraries/EIP712Custody.sol";
import {ThresholdSignature} from "./libraries/ThresholdSignature.sol";

/// @notice Institutional M-of-N custody vault with EIP-712 transaction authorization and ERC-1271.
/// @dev Phase THRESH+ERC1271: full quorum execution and off-chain message validation.
contract CustodyVault is ICustodyVault, IERC1271, EIP712, ReentrancyGuardTransient {
    /// @dev ERC-1271 magic value (`bytes4(keccak256("isValidSignature(bytes32,bytes)"))`).
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;
    /// @dev ERC-1271 invalid marker returned instead of reverting (dApp compatibility).
    bytes4 internal constant ERC1271_INVALID = 0xffffffff;
    /// @notice Emitted after a successful external call authorized by threshold signatures.
    event ExecutionSuccess(bytes32 indexed txHash, address indexed to, uint256 value);

    /// @notice Emitted when the external call reverts (vault still consumes the nonce).
    event ExecutionFailure(bytes32 indexed txHash, address indexed to, uint256 value);

    mapping(address => bool) private _isOwner;
    address[] private _owners;

    uint256 private _threshold;
    uint256 private _nonce;

    /// @notice Deploys a vault with an initial owner set and threshold.
    /// @param owners_ Initial signers (unique, non-zero).
    /// @param threshold_ Required M for quorum (`1 <= M <= N`).
    constructor(address[] memory owners_, uint256 threshold_) EIP712("CustodyVault", "1") {
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

    /// @inheritdoc ICustodyVault
    /// @dev Implemented in Fase SPEND; reverts until then.
    function execTransactionUnderLimit(address to, uint256 value, bytes memory data, bytes memory signature)
        external
        pure
        returns (bool)
    {
        to;
        value;
        data;
        signature;
        revert CustodyErrors.Unauthorized();
    }
}

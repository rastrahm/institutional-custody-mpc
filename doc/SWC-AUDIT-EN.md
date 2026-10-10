# SWC Audit — Institutional Custody, Multisig & MPC Integration

Verification of the institutional custody vault (module 20) against the [SWC Registry](https://swcregistry.io/) (EIP-1470). Style aligned with [`19-rwa-tokenization/doc/SWC-AUDIT-EN.md`](../../19-rwa-tokenization/doc/SWC-AUDIT-EN.md) and [`18-liquid-staking-protocol/doc/SWC-AUDIT-EN.md`](../../18-liquid-staking-protocol/doc/SWC-AUDIT-EN.md).

> **Note:** The SWC Registry has not been actively maintained since ~2020. Complement it with [SCSVS](https://github.com/ComposableSecurity/SCSVS) and [EEA EthTrust](https://entethalliance.org/specs/ethtrust/).

**Audited contracts (prod / core):**  
`src/CustodyVault.sol`,  
`src/RecoveryTimelock.sol`,  
`src/libraries/ThresholdSignature.sol`,  
`src/libraries/EIP712Custody.sol`,  
`src/libraries/SpendingLimit.sol`,  
`src/errors/CustodyErrors.sol`,  
`src/interfaces/ICustodyVault.sol`,  
`src/interfaces/IERC1271.sol`,  
`src/interfaces/IGuard.sol`,  
`src/interfaces/IRecoveryTimelock.sol`

**Trusted dependencies:** forge-std, OpenZeppelin Contracts v5.2 (`ECDSA`, `EIP712`, `ReentrancyGuardTransient`)

**Mocks (out of prod):** `MockTarget`, `MockGuard`  
**Date:** 2026-09-15 (SOLV phase / v1 close)  
**Test references:** `test/ThresholdExecution.t.sol`, `test/SignatureSorting.t.sol`, `test/ERC1271.t.sol`, `test/SpendingLimit.t.sol`, `test/Guard.t.sol`, `test/RecoveryTimelock.t.sol`, `test/fuzz/SpendingWindow.t.sol`, `test/invariant/Custody.invariant.t.sol`, `test/gas/CustodyVault.gas.t.sol`  
**Index:** [`README-EN.md`](./README-EN.md) · Module README: [`../README-EN.md`](../README-EN.md)

---

## Executive summary

| Status | Count |
|--------|-------|
| ✅ Mitigated / Not applicable | 31 |
| ⚠️ Informational (custody design / ops trust) | 5 |
| ❌ Vulnerable | 0 |

**Conclusion:** No exploitable SWC vulnerabilities within the v1 scope. The vault requires **M-of-N** over **EIP-712** hashes with **sorted** signatures (anti-duplicate), exposes **ERC-1271**, enforces a **daily limit** on the under-limit path, supports pre/post **guards** and a **timelock** for custody key changes. ETH via **`.call{value}`** with CEI + `ReentrancyGuardTransient`. Fixed pragma **`0.8.24`**.

**Verified suite / module 20 principles:**

| Principle | Status |
|-----------|--------|
| Custom errors (no `require` strings) | ✅ `CustodyErrors` |
| Fixed pragma `0.8.24` | ✅ |
| CEI + reentrancy protection on execution | ✅ `ReentrancyGuardTransient` |
| M-of-N threshold + sorting | ✅ `InvalidThresholdSignature` / unsorted / dup |
| ERC-1271 `isValidSignature` | ✅ magic / `0xffffffff` |
| Daily spending window + fuzz | ✅ `DailyLimitExceeded` |
| Pluggable guards | ✅ `GuardRejected` |
| Recovery timelock | ✅ `TimelockNotReady` / `TimelockExpired` |
| ETH `.call` (no transfer/send) | ✅ |
| Fuzz ≥ 1000 + invariants | ✅ `foundry.toml` |

---

## Full SWC-100 — SWC-136 matrix

| ID | Title | Applies | Status | Evidence in the custody vault |
|----|-------|---------|--------|-------------------------------|
| SWC-100 | Function Default Visibility | Yes | ✅ | Explicit visibility in `src/` |
| SWC-101 | Integer Overflow and Underflow | Yes | ✅ | Solidity `0.8.24`; `spentInWindow += amount` checked; threshold bounds |
| SWC-102 | Outdated Compiler Version | Yes | ✅ | `pragma solidity 0.8.24` + `foundry.toml` |
| SWC-103 | Floating Pragma | Yes | ✅ | Exact pragma (no `^`) in every `.sol` |
| SWC-104 | Unchecked Call Return Value | Yes | ✅ | `(success,) = to.call{value}(data)` captured; failure → event / `ExecutionFailed` in timelock |
| SWC-105 | Unprotected Ether Withdrawal | Yes | ✅ | ETH out only via `execTransaction` / under-limit with valid signatures |
| SWC-106 | Unprotected SELFDESTRUCT | No | N/A | No `selfdestruct` |
| SWC-107 | Reentrancy | Yes | ✅ | `nonReentrant` + CEI (nonce/spend before the call); guard post after the call |
| SWC-108 | State Variable Default Visibility | Yes | ✅ | Explicit `private` / `immutable` / `public` |
| SWC-109 | Uninitialized Storage Pointer | No | N/A | No legacy storage pointers |
| SWC-110 | Assert Violation | No | N/A | No production `assert` |
| SWC-111 | Deprecated Solidity Functions | Yes | ✅ | No `suicide` / `throw` / `tx.origin` / ETH `transfer`/`send` |
| SWC-112 | Delegatecall to Untrusted Callee | No | N/A | No `delegatecall` (DelegateCall operation reserved, not exposed) |
| SWC-113 | DoS with Failed Call | Partial | ✅ | A failed call does not revert the outer tx in the vault (returns `false`, nonce consumed); the timelock does revert `ExecutionFailed` |
| SWC-114 | Transaction Order Dependence | Yes | ⚠️ | Relayers compete to publish signatures; the nonce fixes the order — see risks |
| SWC-115 | Authorization through tx.origin | No | N/A | Auth via ECDSA owners / self-call / timelock; no `tx.origin` |
| SWC-116 | Block values as a proxy for time | Yes | ⚠️ | Daily window + timelock `eta` use `block.timestamp` — see risks |
| SWC-117 | Signature Malleability | Yes | ✅ | OZ `ECDSA` rejects high `s` / invalid `v` |
| SWC-118 | Incorrect Constructor Name | No | N/A | 0.8+ `constructor` |
| SWC-119 | Shadowing State Variables | Yes | ✅ | No material shadowing |
| SWC-120 | Weak Sources of Randomness | No | N/A | No on-chain RNG |
| SWC-121 | Missing Protection against Signature Replay | Yes | ✅ | Nonce in EIP-712; anti-dup sorting; replay tests |
| SWC-122 | Lack of Proper Signature Verification | Yes | ✅ | ECDSA recover + `isOwner` + threshold; ERC-1271 reuses the engine |
| SWC-123 | Requirement Violation | Yes | ✅ | Custom errors + revert suite |
| SWC-124 | Write to Arbitrary Storage Location | No | N/A | Assembly only reads `r,s,v` from packed calldata |
| SWC-125 | Incorrect Inheritance Order | Yes | ✅ | `ICustodyVault, IERC1271, EIP712, ReentrancyGuardTransient` |
| SWC-126 | Insufficient Gas Griefing | Partial | ⚠️ | An external guard may consume gas / fail — see risks |
| SWC-127 | Arbitrary Jump with Function Type Variable | No | N/A | No dynamic function types |
| SWC-128 | DoS With Block Gas Limit | Partial | ✅ | O(N) signature loop with typically small N = threshold |
| SWC-129 | Typographical Error | Yes | ✅ | Review + `forge test` |
| SWC-130 | Right-To-Left-Override control character | No | N/A | ASCII in NatSpec/tests |
| SWC-131 | Presence of unused variables | Yes | ✅ | No material dead variables |
| SWC-132 | Unexpected Ether balance | Yes | ✅ | `receive()` accepts deposits; balance is not used as an auth invariant |
| SWC-133 | Hash Collisions With Multiple Variable Length Arguments | Yes | ✅ | Typed EIP-712; `keccak256(data)` in the struct hash |
| SWC-134 | Message call with hardcoded gas amount | No | N/A | No `.call{gas: ...}` |
| SWC-135 | Code With No Effects | No | N/A | Stub paths removed in SPEND+ |
| SWC-136 | Unencrypted Private Data On-Chain | Partial | ✅ | Owners / threshold / spent are public by custody design |

---

## Informational risks

### SWC-114 — Signature publication order

**Description:** Several relayers may submit the same signature set; only the first one with the current nonce succeeds.

**Status:** ⚠️ Inherent to meta-txs / multisig.

**Mitigations:** Monotonic nonce; replay tests; `nonce` sync invariant.

### SWC-116 — `block.timestamp` in spending and timelock

**Description:** Miners/sequencers can skew timestamps within protocol tolerances. The daily window and the timelock `eta` depend on it.

**Status:** ⚠️ Standard design (Safe / Governor-style).

**Mitigations:** Window boundary fuzzing; 14d grace period in the timelock; configurable minimum delay.

### SWC-126 — Malicious guard / griefing

**Description:** A guard that reverts on post after a successful call rolls back the nonce and the external effect (if the effect was only an ETH transfer, it is reverted; if the target already emitted irreversible off-chain non-ETH side effects, there is a risk of inconsistency).

**Status:** ⚠️ Trust in the guard module (set only via multisig).

**Mitigations:** `setGuard` self-call; pre/post reject tests; post-v1: timelock for `setGuard` as well.

### Trust in owners / threshold

**Description:** Compromising ≥M keys allows draining the vault (including bypassing the daily limit via quorum).

**Status:** ⚠️ Institutional custody model (off-chain MPC/HSM out of on-chain scope).

**Mitigation:** Timelock for key rotation; daily limit for ops; policy guards.

### Call failure consumes the nonce (by design)

**Description:** If the external call fails, the vault emits `ExecutionFailure`, returns `false` and does **not** revert — the nonce (and under-limit spend) have already been consumed.

**Status:** ⚠️ Intentional (burns the signed payload; prevents infinite retries with the same nonce).

**Mitigation:** Documented tests; signers must re-sign with a new nonce.

---

## SWC → tests mapping

| SWC | Related test(s) |
|-----|-----------------|
| SWC-101 | `SpendingLimit.t.sol`; spent ≤ limit invariant |
| SWC-103 | Fixed compiler (`forge build`) |
| SWC-104 / 105 | `ThresholdExecution.t.sol` ETH + failure path |
| SWC-107 | `nonReentrant` on both exec paths |
| SWC-116 | `fuzz/SpendingWindow.t.sol`; `RecoveryTimelock.t.sol` |
| SWC-117 / 122 | `SignatureSorting.t.sol`; `ERC1271.t.sol` |
| SWC-121 | Nonce replay; sorting/dup |
| SWC-123 | Guard / timelock / spending error paths |
| SWC-126 | `Guard.t.sol` pre/post reject |
| Solvency | `invariant/Custody.invariant.t.sol` |

---

## References

- [SWC Registry](https://swcregistry.io/)
- [EIP-1470](https://eips.ethereum.org/EIPS/eip-1470)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) · [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271)
- [`19-rwa-tokenization/doc/SWC-AUDIT-EN.md`](../../19-rwa-tokenization/doc/SWC-AUDIT-EN.md)
- [`18-liquid-staking-protocol/doc/SWC-AUDIT-EN.md`](../../18-liquid-staking-protocol/doc/SWC-AUDIT-EN.md)

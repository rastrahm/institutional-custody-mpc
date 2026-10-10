# Understanding guide — Module 20: Institutional Custody

A document to understand **what was built**, **why certain decisions were made** and **how the logic flows**.  
Aligned with the v1 code (`forge test` → **69 PASS**).  
**Date:** 2026-09-15.

---

## 1. What this module is (in one sentence)

A **custody smart contract wallet** where N signers control funds with threshold M, transactions are authorized with **EIP-712**, dApps can validate signatures via **ERC-1271**, there is a **daily limit** for small operations, optional **guards** and a **timelock** to change keys.

> "MPC" here is **not** an on-chain cryptographic circuit: it means signatures can be produced off-chain (EOA, HSM or MPC) and the contract only **verifies** M-of-N ECDSA.

---

## 2. Technical decisions

### 2.1 Stack and constraints

| Decision | Choice | Reason |
|----------|--------|--------|
| Compiler | Fixed `pragma solidity 0.8.24` | Suite + `.cursorrules`: no floating pragma |
| Tooling | Foundry | TDD, fuzz ≥1000, invariants, gas snapshot |
| Crypto | OpenZeppelin ECDSA + EIP712 | Anti-malleability, cached domain separator |
| Reentrancy | `ReentrancyGuardTransient` | Cancun `tstore`: cheaper than the classic guard |
| Errors | Custom errors (`CustodyErrors`) | Gas + clarity vs `require("string")` |
| ETH out | `.call{value:}("")` | `transfer`/`send` are forbidden in the suite |

### 2.2 Authorization model (the core)

| Path | Who signs | What it validates | Daily limit |
|------|-----------|-------------------|-------------|
| `execTransaction` | ≥ M owners, **sorted** signatures | Threshold + EIP-712 nonce | **Does not apply** (institutional bypass) |
| `execTransactionUnderLimit` | **1** owner | ECDSA + isOwner + remaining | **Yes** (ETH `value` only) |
| `isValidSignature` | ≥ M owners (same engine) | Soft-check → magic / `0xffffffff` | N/A (view) |

**Why sorted signatures:** it prevents the same signature from being counted twice or a malicious set from "padding" the threshold. Classic Safe-style pattern: `signer[i] > signer[i-1]`.

**Why quorum bypasses the daily limit:** the cap is for cheap **day-to-day ops** (1 signature). Large / emergency movements require M-of-N consensus on purpose.

### 2.3 EIP-712 hash

Typed struct:

```text
CustodyTransaction(address to, uint256 value, bytes data, uint256 nonce)
```

- Domain: name `CustodyVault`, version `1`, `chainId`, `verifyingContract`.
- The signed digest is the one from `getTransactionHash` (= `_hashTypedDataV4(...)`).
- The **nonce** in the hash prevents replay after a successful execution (or a failed one that already consumed the nonce).

### 2.4 Behavior on a failed external call

| Component | If the `call` to the target fails |
|-----------|-----------------------------------|
| `CustodyVault.exec*` | Emits `ExecutionFailure`, **returns `false`**, does **not** revert the tx |
| Nonce / spend | **Already consumed** (CEI: effects before interaction) |
| `RecoveryTimelock.execute` | Reverts `ExecutionFailed` (key-change operation is atomic) |

**Reason for the vault behavior:** burning the signed payload prevents infinite retries with the same nonce; the relayer reports `success=false` and the owners re-sign.

### 2.5 Guards

- `setGuard` only if `msg.sender == address(this)` → it must be reached via a multisig self-call.
- On each exec the guard is **cached** at the start: if the call changes the guard in the same tx, the **post-check uses the old guard**.
- Guard failure → `GuardRejected` (try/catch). A pre-reject does **not** consume the nonce.

### 2.6 Spending window

- **Rolling** window of `1 days` from the first spend (or after expiry).
- Only the ETH `value` of the under-limit path counts (not the "weight" of the calldata).
- `value == 0` does not consume allowance (useful for cheap data calls).

### 2.7 Recovery Timelock

- Separate contract: `schedule` / `cancel` only from the vault; `execute` is permissionless after `eta`.
- Grace period of `14 days` after `eta` → then `TimelockExpired`.
- Vault mutations (`addOwnerWithThreshold`, `removeOwnerWithThreshold`, `changeThreshold`) only if `msg.sender == recoveryTimelock`.
- Timelock binding: only once via `setRecoveryTimelock` (self-call).

### 2.8 What was left out of v1 (on purpose)

- Real cryptographic MPC / BLS / Schnorr on-chain.
- ERC-4337 Account Abstraction.
- Next.js frontend.
- Timelock for `setGuard` / `setDailyLimit` (today `setGuard` is an immediate multisig action).
- Multi-token daily limit (ETH `value` only).

---

## 3. Logic the system follows

### 3.1 Mental map

```text
                    ┌─────────────────┐
                    │  Owners sign    │
                    │  off-chain      │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
    Under daily remaining?          High value / policy
    + 1 owner signature             + M sorted signatures
              │                             │
              ▼                             ▼
   execTransactionUnderLimit      execTransaction
              │                             │
              └──────────┬──────────────────┘
                         │
                         ▼
              Guard pre → nonce(+spend) → call → Guard post
                         │
                         ▼
              Optional dApp: isValidSignature (ERC-1271)

    Owner/threshold change:
      Multisig → timelock.schedule → wait delay → execute → vault mutates
```

### 3.2 `execTransaction` flow (step by step)

1. `to != address(0)`.
2. `txHash = EIP-712(to, value, data, current nonce)`.
3. Validate packed signatures (65·N bytes): recover → ascending order → unique → each one `isOwner` → `count >= threshold`.
4. Guard pre (if any).
5. **Effects:** `nonce++`.
6. **Interaction:** `to.call{value: value}(data)`.
7. Success or Failure event.
8. Guard post (same cached guard).
9. Return `bool success` (no revert if the call failed).

### 3.3 Under-limit flow

1. Signature of exactly 65 bytes; the recovered address must be an owner.
2. `checkCanSpend(value)` (implicit window reset if expired).
3. Guard pre.
4. **Effects:** `nonce++`, `recordSpend(value)`, `DailySpendRecorded` event.
5. Call + guard post + return success.

### 3.4 ERC-1271 flow

1. Same M-of-N / sorted / owners rule.
2. Valid → `0x1626ba7e`.
3. Invalid → `0xffffffff` (**no revert**, so the dApp can branch).

### 3.5 Recovery flow

1. Owners sign an `execTransaction` targeting `RecoveryTimelock.schedule(opId, data, eta)`.
2. After `eta`, anyone calls `execute(opId, data)` with the same `data`.
3. The timelock does `vault.call(data)` → e.g. `addOwnerWithThreshold`.

---

## 4. Possible gas improvements (over what exists)

Already applied in v1: in-place `r,s,v` parsing, OZ ECDSA, transient reentrancy, custom errors, owners mapping, optimizer + `via_ir`.  
Baseline: see [`GAS-EN.md`](./GAS-EN.md).

### 4.1 Medium / high impact improvements

| Idea | Where | Expected savings | Tradeoff |
|------|-------|------------------|----------|
| Validate only the **first M** signatures (not the excess) | `ThresholdSignature` | ~9–10k per extra signature (today 3 excess signatures cost more) | Less "auditability" of the blob; Safe does something similar |
| EIP-2098 compact signatures (64 bytes) | Threshold + under-limit | Less calldata | More complexity; signing tooling |
| Packed owners / bitmap instead of `address[]` + mapping | Storage layout | Fewer SSTOREs on add/remove | More expensive `getOwners` reads or a different API |
| `unchecked` in signature index loops | Threshold loop | Marginal | Only if proven overflow-safe |
| Optional guard "skip post on failure" | Vault | 1 fewer CALL on the Failure path | Changes policy semantics |

### 4.2 Low impact / structural improvements

| Idea | Note |
|------|------|
| Pack `spentInWindow` + `windowStart` into one slot | `SpendingLimit.Data` uses 3× uint256 today; packing + immutable `dailyLimit` would save SLOAD/SSTORE |
| `dailyLimit` as `immutable` | Cannot be changed on-chain without a redeploy / new design |
| Short-circuit ERC-1271 if `signature.length < 65 * threshold` | Already done in `_check`; OK |
| Remove events from the hot path (or fewer indexed) | Gas savings, worse ops observability |
| Custom EIP-712 domain without OZ ShortStrings | Possible micro-savings; higher bug risk |

### 4.3 What you should **not** "optimize" blindly

- Removing signature sorting → double-count risk.
- Recording the spend **after** the call → broken CEI / accounting reentrancy.
- Making a failed call always revert → changes the nonce model (everything would need to be documented and re-tested).

### 4.4 Suggested order if iterating on gas (post-v1)

1. Validate exactly M signatures (biggest practical win + clear API: "send M, no more").
2. Pack spending storage (immutable `dailyLimit` + two uint128/uint64).
3. Measure again with `forge snapshot` and update `GAS-EN.md`.

---

## 5. Code pieces to look at (reading map)

| File | What to learn |
|------|---------------|
| `src/CustodyVault.sol` | Orchestration of exec / under-limit / ERC-1271 / guard / mutations |
| `src/libraries/ThresholdSignature.sol` | M-of-N engine + soft vs hard check |
| `src/libraries/EIP712Custody.sol` | Transaction typehash |
| `src/libraries/SpendingLimit.sol` | Rolling window |
| `src/RecoveryTimelock.sol` | Delay + grace + execute |
| `doc/diagrama-de-flujo-EN.md` | Decision flows |
| `doc/SWC-AUDIT-EN.md` | Documented security risks |
| `doc/GAS-EN.md` | Measured numbers |

---

## 6. Executive summary

1. **Central decision:** two execution paths (quorum vs under-limit) + ERC-1271 reusing the same signature engine.
2. **Security first:** sorting, nonce, CEI, timelock for keys, cached guards.
3. **Gas:** there is already a strong cut from signature assembly; the next big step is **not validating excess signatures** and **compacting spending storage**.
4. **Logic:** sign off-chain → sort → choose path → guard → effects → call → post.

---

## References

- [`planificacion-EN.md`](./planificacion-EN.md) — BOOT→SOLV phases
- [`diagrama-de-clases-EN.md`](./diagrama-de-clases-EN.md) — real API
- [`diagrama-de-flujo-EN.md`](./diagrama-de-flujo-EN.md) — per-function decisions
- [`flujograma-EN.md`](./flujograma-EN.md) — end-to-end cycle
- [`GAS-EN.md`](./GAS-EN.md) — baseline
- [`SWC-AUDIT-EN.md`](./SWC-AUDIT-EN.md) — audit
- [`../portfolio/index.html`](../portfolio/index.html) — visual landing page

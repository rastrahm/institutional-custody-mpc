# Flow diagram — Threshold, ERC-1271, spending, guards and recovery

Internal decision flows of the custody protocol (module 20, **v1 implemented**).  
**Sync:** 2026-09-15 · Phases **BOOT → SOLV** ✅ · 69 PASS.

## 1. execTransaction (M-of-N quorum)

```mermaid
flowchart TD
    A[Caller: execTransaction] --> B{to != 0?}
    B -->|No| Z0[Revert ZeroAddress]
    B -->|Yes| C[txHash = EIP-712 + nonce]
    C --> D[validateThreshold sorted unique owners]
    D -->|fail| Z1[InvalidThreshold / Unsorted / Dup / NotASigner / Length]
    D -->|ok| E[cache guard_]
    E --> F{guard_ set?}
    F -->|Yes| G[checkTransaction]
    G -->|fail| Z2[Revert GuardRejected]
    G -->|ok| H[nonce++]
    F -->|No| H
    H --> I["to.call value data"]
    I -->|ok| J[Emit ExecutionSuccess]
    I -->|fail| K[Emit ExecutionFailure success=false]
    J --> L[checkAfterExecution guard_]
    K --> L
    L -->|fail| Z2
    L -->|ok| Ok([return success])
    Z0 --> End([End — revert])
    Z1 --> End
    Z2 --> End
```

> Guard captured **before** the call: a `setGuard` in the same tx does not affect the post-check.

---

## 2. Threshold validation (detail)

```mermaid
flowchart TD
    A[validateThreshold / isValidThreshold] --> B{length % 65 == 0 and > 0?}
    B -->|No| E1[InvalidSignatureLength]
    B -->|Yes| C{count >= threshold?}
    C -->|No| E2[InvalidThresholdSignature]
    C -->|Yes| D[For each signature: tryRecover r,s,v in-place]
    D --> F{recover OK?}
    F -->|No| E2
    F -->|Yes| G{signer > previous?}
    G -->|equal| E3[DuplicateSignature]
    G -->|lower| E4[UnsortedSignatures]
    G -->|Yes| H{isOwner?}
    H -->|No| E5[NotASigner]
    H -->|Yes| I{more signatures?}
    I -->|Yes| D
    I -->|No| Ok([OK — validate reverts / isValid true])
```

> `execTransaction` uses `validateThreshold` (revert). ERC-1271 uses `isValidThreshold` (bool).

---

## 3. ERC-1271 isValidSignature

```mermaid
flowchart TD
    A[isValidSignature hash, signature] --> B[isValidThreshold same M-of-N engine]
    B -->|true| C["return 0x1626ba7e"]
    B -->|false| D["return 0xffffffff"]
```

> Does not revert on the ERC-1271 path (dApp compatibility).

---

## 4. Daily spending — execTransactionUnderLimit

```mermaid
flowchart TD
    A[UnderLimit to,value,data,sig65] --> B{sig length == 65?}
    B -->|No| Z0[InvalidSignatureLength]
    B -->|Yes| C[recover signer]
    C --> D{isOwner?}
    D -->|No| Z1[NotASigner]
    D -->|Yes| E[checkCanSpend value]
    E -->|fail| Z2[DailyLimitExceeded]
    E -->|ok| F[Guard pre]
    F -->|fail| Z3[GuardRejected]
    F -->|ok| G[nonce++; recordSpend; emit DailySpend]
    G --> H[external call]
    H --> I[Guard post]
    I --> Ok([return success])
    Z0 --> End([revert])
    Z1 --> End
    Z2 --> End
    Z3 --> End
```

> Only `value` (ETH) counts toward the cap. `value == 0` does not consume allowance. Full quorum bypasses the cap.

---

## 5. setGuard / setRecoveryTimelock

```mermaid
flowchart TD
    A[Multisig execTransaction → vault.setGuard / setRecoveryTimelock] --> B{msg.sender == vault?}
    B -->|No| Z[Unauthorized]
    B -->|Yes setGuard| C[guard = new; emit GuardChanged]
    B -->|Yes setTimelock| D{already bound?}
    D -->|Yes| Z
    D -->|No| E[recoveryTimelock = t; emit RecoveryTimelockSet]
```

---

## 6. Recovery Timelock — signer / threshold change

```mermaid
flowchart TD
    A[Multisig → timelock.schedule opId, data, eta] --> B{msg.sender == vault?}
    B -->|No| Z0[Unauthorized]
    B -->|Yes| C{eta >= now + delay?}
    C -->|No| Z1[TimelockNotReady]
    C -->|Yes| D{op already scheduled?}
    D -->|Yes| Z2[OperationAlreadyScheduled]
    D -->|No| E[Store eta + keccak data]

    F[Anyone: execute opId, data] --> G{scheduled?}
    G -->|No| Z3[OperationNotScheduled]
    G -->|Yes| H{now >= eta?}
    H -->|No| Z1
    H -->|Yes| I{now <= eta + 14d?}
    I -->|No| Z4[TimelockExpired]
    I -->|Yes| J{keccak data match?}
    J -->|No| Z0
    J -->|Yes| K[vault.call data]
    K -->|fail| Z5[ExecutionFailed]
    K -->|ok| Ok([Owners/threshold updated])
```

> Typical `data`: `addOwnerWithThreshold` / `removeOwnerWithThreshold` / `changeThreshold`.  
> Vault mutations only accept `msg.sender == recoveryTimelock`.

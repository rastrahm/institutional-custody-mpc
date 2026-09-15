# Diagrama de flujo — Threshold, ERC-1271, spending, guards y recovery

Flujos de decisión internos del protocolo de custodia (módulo 20, **v1 implementado**).  
**Sync:** 2026-09-15 · Fases **BOOT → SOLV** ✅ · 69 PASS.

## 1. execTransaction (quorum M-of-N)

```mermaid
flowchart TD
    A[Caller: execTransaction] --> B{to != 0?}
    B -->|No| Z0[Revert ZeroAddress]
    B -->|Sí| C[txHash = EIP-712 + nonce]
    C --> D[validateThreshold sorted unique owners]
    D -->|fail| Z1[InvalidThreshold / Unsorted / Dup / NotASigner / Length]
    D -->|ok| E[cache guard_]
    E --> F{guard_ set?}
    F -->|Sí| G[checkTransaction]
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
    Z0 --> End([Fin — revert])
    Z1 --> End
    Z2 --> End
```

> Guard capturado **antes** del call: un `setGuard` en el mismo tx no afecta el post-check.

---

## 2. Validación threshold (detalle)

```mermaid
flowchart TD
    A[validateThreshold / isValidThreshold] --> B{length % 65 == 0 y > 0?}
    B -->|No| E1[InvalidSignatureLength]
    B -->|Sí| C{count >= threshold?}
    C -->|No| E2[InvalidThresholdSignature]
    C -->|Sí| D[Para cada firma: tryRecover r,s,v in-place]
    D --> F{recover OK?}
    F -->|No| E2
    F -->|Sí| G{signer > previous?}
    G -->|igual| E3[DuplicateSignature]
    G -->|menor| E4[UnsortedSignatures]
    G -->|Sí| H{isOwner?}
    H -->|No| E5[NotASigner]
    H -->|Sí| I{más firmas?}
    I -->|Sí| D
    I -->|No| Ok([OK — validate revert / isValid true])
```

> `execTransaction` usa `validateThreshold` (revert). ERC-1271 usa `isValidThreshold` (bool).

---

## 3. ERC-1271 isValidSignature

```mermaid
flowchart TD
    A[isValidSignature hash, signature] --> B[isValidThreshold mismo motor M-of-N]
    B -->|true| C["return 0x1626ba7e"]
    B -->|false| D["return 0xffffffff"]
```

> No revierte en el path ERC-1271 (compatibilidad dApp).

---

## 4. Daily spending — execTransactionUnderLimit

```mermaid
flowchart TD
    A[UnderLimit to,value,data,sig65] --> B{sig length == 65?}
    B -->|No| Z0[InvalidSignatureLength]
    B -->|Sí| C[recover signer]
    C --> D{isOwner?}
    D -->|No| Z1[NotASigner]
    D -->|Sí| E[checkCanSpend value]
    E -->|fail| Z2[DailyLimitExceeded]
    E -->|ok| F[Guard pre]
    F -->|fail| Z3[GuardRejected]
    F -->|ok| G[nonce++; recordSpend; emit DailySpend]
    G --> H[call externo]
    H --> I[Guard post]
    I --> Ok([return success])
    Z0 --> End([revert])
    Z1 --> End
    Z2 --> End
    Z3 --> End
```

> Solo `value` (ETH) cuenta al cap. `value == 0` no consume allowance. Quorum completo bypassea el cap.

---

## 5. setGuard / setRecoveryTimelock

```mermaid
flowchart TD
    A[Multisig execTransaction → vault.setGuard / setRecoveryTimelock] --> B{msg.sender == vault?}
    B -->|No| Z[Unauthorized]
    B -->|Sí setGuard| C[guard = new; emit GuardChanged]
    B -->|Sí setTimelock| D{ya bound?}
    D -->|Sí| Z
    D -->|No| E[recoveryTimelock = t; emit RecoveryTimelockSet]
```

---

## 6. Recovery Timelock — cambio de signers / threshold

```mermaid
flowchart TD
    A[Multisig → timelock.schedule opId, data, eta] --> B{msg.sender == vault?}
    B -->|No| Z0[Unauthorized]
    B -->|Sí| C{eta >= now + delay?}
    C -->|No| Z1[TimelockNotReady]
    C -->|Sí| D{op ya scheduled?}
    D -->|Sí| Z2[OperationAlreadyScheduled]
    D -->|No| E[Guardar eta + keccak data]

    F[Anyone: execute opId, data] --> G{scheduled?}
    G -->|No| Z3[OperationNotScheduled]
    G -->|Sí| H{now >= eta?}
    H -->|No| Z1
    H -->|Sí| I{now <= eta + 14d?}
    I -->|No| Z4[TimelockExpired]
    I -->|Sí| J{keccak data match?}
    J -->|No| Z0
    J -->|Sí| K[vault.call data]
    K -->|fail| Z5[ExecutionFailed]
    K -->|ok| Ok([Owners/threshold actualizados])
```

> `data` típico: `addOwnerWithThreshold` / `removeOwnerWithThreshold` / `changeThreshold`.  
> Mutaciones del vault solo aceptan `msg.sender == recoveryTimelock`.

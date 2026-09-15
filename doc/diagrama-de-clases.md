# Diagrama de clases — Institutional Custody, Multisig & MPC Integration

Vista estructural del **diseño objetivo** (módulo 20).  
**Sync:** 2026-09-15 · Fases **BOOT → SOLV** ⏳ · código aún no iniciado.

> **Estándar de referencia:** vault multisig estilo Safe + verificación threshold Secp256k1 on-chain, ERC-1271, spending limits y recovery con timelock.  
> “MPC” en este módulo = firmas generadas off-chain (posiblemente vía MPC) y **verificadas** on-chain como M-of-N ECDSA; no hay circuito MPC en el contrato.

## Diagrama (Mermaid)

```mermaid
classDiagram
    direction TB

    class ICustodyVault {
        <<interface>>
        +getOwners() address[]
        +getThreshold() uint256
        +nonce() uint256
        +execTransaction(to, value, data, signatures) bool
        +execTransactionUnderLimit(to, value, data, signature) bool
        +domainSeparator() bytes32
        +getTransactionHash(to, value, data, nonce) bytes32
    }

    class IERC1271 {
        <<interface>>
        +isValidSignature(hash, signature) bytes4
    }

    class IGuard {
        <<interface>>
        +checkTransaction(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, signatures, msgSender)
        +checkAfterExecution(txHash, success)
    }

    class IRecoveryTimelock {
        <<interface>>
        +schedule(operationId, data, eta)
        +execute(operationId, data)
        +cancel(operationId)
        +delay() uint256
    }

    class CustodyErrors {
        <<errors library>>
        +InvalidThresholdSignature()
        +UnsortedSignatures()
        +DuplicateSignature()
        +NotASigner()
        +DailyLimitExceeded()
        +GuardRejected()
        +TimelockNotReady()
        +ExecutionFailed()
        +ZeroAddress()
        +InvalidNonce()
    }

    class ThresholdSignature {
        <<library>>
        +recoverSortedSigners(hash, signatures) address[]
        +validateThreshold(owners, threshold, hash, signatures)
    }

    class EIP712Custody {
        <<library>>
        +TRANSACTION_TYPEHASH bytes32
        +hashTransaction(to, value, data, nonce) bytes32
        +toTypedDataHash(domainSeparator, structHash) bytes32
    }

    class SpendingLimitModule {
        +dailyLimit uint256
        +spentInWindow uint256
        +windowStart uint256
        +WINDOW uint256
        +canSpend(amount) bool
        +recordSpend(amount)
        +setDailyLimit(newLimit)
        +spentToday() uint256
    }

    class CustodyVault {
        +owners mapping
        +ownerCount uint256
        +threshold uint256
        +nonce uint256
        +guard address
        +execTransaction(to, value, data, signatures) bool
        +execTransactionUnderLimit(to, value, data, signature) bool
        +isValidSignature(hash, signature) bytes4
        +setGuard(guard)
        +isOwner(account) bool
    }

    class RecoveryTimelock {
        +delay uint256
        +scheduled mapping
        +scheduleAddOwner(owner, newThreshold, eta)
        +scheduleRemoveOwner(owner, newThreshold, eta)
        +scheduleChangeThreshold(newThreshold, eta)
        +execute(operationId)
        +cancel(operationId)
    }

    class MockGuard {
        <<mock>>
        +shouldReject bool
        +checkTransaction(...)
        +checkAfterExecution(txHash, success)
    }

    ICustodyVault <|.. CustodyVault
    IERC1271 <|.. CustodyVault
    IGuard <|.. MockGuard
    IRecoveryTimelock <|.. RecoveryTimelock

    CustodyVault --> ThresholdSignature : valida M-of-N
    CustodyVault --> EIP712Custody : typed hash
    CustodyVault --> SpendingLimitModule : cap diario
    CustodyVault --> IGuard : pre/post
    CustodyVault --> RecoveryTimelock : cambios custody
    CustodyVault ..> CustodyErrors : reverts
    RecoveryTimelock --> CustodyVault : muta owners/threshold
    ThresholdSignature ..> CustodyErrors : InvalidThresholdSignature
```

## Responsabilidades

| Artefacto | Responsabilidad |
|-----------|-----------------|
| `CustodyVault` | Estado de owners/threshold; ejecución; ERC-1271; wiring de guard y límites |
| `ThresholdSignature` | ECDSA recover + orden estricto + conteo ≥ M |
| `EIP712Custody` | Domain + typehash de transacciones del vault |
| `SpendingLimitModule` | Ventana temporal y acumulado de gasto |
| `IGuard` / `MockGuard` | Política pre/post execution |
| `RecoveryTimelock` | Delay para add/remove signer y change threshold |
| `CustodyErrors` | Custom errors del módulo |

## Modelo de permisos en ejecución

```
  execTransaction(to, value, data, signatures)
           │
           ▼
  ┌────────────────────┐
  │ Guard pre-check?   │──fail──► GuardRejected
  └─────────┬──────────┘
            │ ok / sin guard
            ▼
  ┌────────────────────┐
  │ Hash EIP-712+nonce │
  └─────────┬──────────┘
            ▼
  ┌────────────────────┐
  │ Threshold M-of-N   │──fail──► InvalidThresholdSignature
  │ (sorted, unique)   │         Unsorted / Duplicate / NotASigner
  └─────────┬──────────┘
            │ ok
            ▼
  ┌────────────────────┐
  │ Effects: nonce++   │  (CEI)
  │ record spend si aplica
  └─────────┬──────────┘
            ▼
  ┌────────────────────┐
  │ Interaction: call  │──fail──► ExecutionFailed
  └─────────┬──────────┘
            │ ok
            ▼
      Guard post-check
      Emit ExecutionSuccess
```

## Roles

| Rol | Mecanismo | Acciones |
|-----|-----------|----------|
| Owner / Signer | lista on-chain | Firmar txs EIP-712; path bajo límite (según diseño SPEND) |
| Executor | cualquiera (relayer) | Enviar `execTransaction` con firmas |
| Guard | contrato `IGuard` | Rechazar/auditar pre/post |
| Recovery admin | owners vía timelock | Schedule/execute cambios de custody |
| dApp | ERC-1271 | `isValidSignature` contra el vault |

## Errores custom (diseño)

| Error | Uso |
|-------|-----|
| `InvalidThresholdSignature()` | Umbral no alcanzado / firma inválida |
| `UnsortedSignatures()` | Array no ordenado por address |
| `DuplicateSignature()` | Misma address recuperada dos veces |
| `NotASigner()` | Recover ∉ owners |
| `DailyLimitExceeded()` | Path rápido supera cap de ventana |
| `GuardRejected()` | Guard pre/post falla |
| `TimelockNotReady()` | Execute antes de `eta` |
| `ExecutionFailed()` | `.call` externo falló |
| `InvalidNonce()` | Hash con nonce incorrecto (si se valida off-hash) |

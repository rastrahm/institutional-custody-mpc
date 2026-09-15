# Diagrama de clases — Institutional Custody, Multisig & MPC Integration

Vista estructural alineada a la implementación v1 (módulo 20).  
**Sync:** 2026-09-15 · Fases **BOOT → SOLV** ✅ · `forge test` → **69 PASS**.

> **Estándar de referencia:** vault multisig estilo Safe + verificación threshold Secp256k1 on-chain, ERC-1271, spending limits y recovery con timelock.  
> “MPC” = firmas off-chain (posiblemente vía MPC) **verificadas** on-chain como M-of-N ECDSA; no hay circuito MPC en el contrato.

## Diagrama (Mermaid)

```mermaid
classDiagram
    direction TB

    class ICustodyVault {
        <<interface>>
        +getOwners() address[]
        +getThreshold() uint256
        +nonce() uint256
        +domainSeparator() bytes32
        +getTransactionHash(to, value, data, nonce) bytes32
        +execTransaction(to, value, data, signatures) bool
        +execTransactionUnderLimit(to, value, data, signature) bool
        +isOwner(account) bool
    }

    class IERC1271 {
        <<interface>>
        +isValidSignature(hash, signature) bytes4
    }

    class IGuard {
        <<interface>>
        +checkTransaction(to, value, data, operation, msgSender)
        +checkAfterExecution(txHash, success)
    }

    class IRecoveryTimelock {
        <<interface>>
        +delay() uint256
        +schedule(operationId, data, eta)
        +execute(operationId, data)
        +cancel(operationId)
    }

    class CustodyErrors {
        <<errors library>>
        +InvalidThresholdSignature()
        +UnsortedSignatures()
        +DuplicateSignature()
        +NotASigner()
        +InvalidSignatureLength()
        +ThresholdTooHigh()
        +ThresholdTooLow()
        +SignerAlreadyExists()
        +SignerDoesNotExist()
        +DailyLimitExceeded()
        +ExecutionFailed()
        +GuardRejected()
        +TimelockNotReady()
        +TimelockExpired()
        +OperationNotScheduled()
        +OperationAlreadyScheduled()
        +ZeroAddress()
        +ZeroValue()
        +Unauthorized()
    }

    class ThresholdSignature {
        <<library>>
        +SIGNATURE_LENGTH uint256
        +validateThreshold(hash, signatures, threshold, owners)
        +isValidThreshold(hash, signatures, threshold, owners) bool
    }

    class EIP712Custody {
        <<library>>
        +TRANSACTION_TYPEHASH bytes32
        +hashTransaction(to, value, data, nonce) bytes32
    }

    class SpendingLimit {
        <<library>>
        +WINDOW uint256
        +Data dailyLimit, spentInWindow, windowStart
        +remaining(self) uint256
        +spentToday(self) uint256
        +checkCanSpend(self, amount)
        +recordSpend(self, amount)
    }

    class CustodyVault {
        +constructor(owners, threshold, dailyLimit, recoveryTimelock)
        +execTransaction(to, value, data, signatures) bool
        +execTransactionUnderLimit(to, value, data, signature) bool
        +isValidSignature(hash, signature) bytes4
        +setGuard(guard)
        +setRecoveryTimelock(timelock)
        +addOwnerWithThreshold(owner, newThreshold)
        +removeOwnerWithThreshold(owner, newThreshold)
        +changeThreshold(newThreshold)
        +dailyLimit() / spentInWindow() / remainingDailyLimit()
        +guard() / recoveryTimelock()
    }

    class RecoveryTimelock {
        +GRACE_PERIOD uint256
        +vault CustodyVault
        +delay uint256
        +schedule(operationId, data, eta)
        +execute(operationId, data)
        +cancel(operationId)
        +getEta(operationId) uint256
    }

    class MockGuard {
        <<mock>>
        +rejectPre / rejectPost bool
        +checkTransaction(...)
        +checkAfterExecution(txHash, success)
    }

    class MockTarget {
        <<mock>>
        +ping()
        +boom()
    }

    ICustodyVault <|.. CustodyVault
    IERC1271 <|.. CustodyVault
    IGuard <|.. MockGuard
    IRecoveryTimelock <|.. RecoveryTimelock

    CustodyVault --> ThresholdSignature : M-of-N / ERC-1271
    CustodyVault --> EIP712Custody : typed hash
    CustodyVault --> SpendingLimit : ventana diaria
    CustodyVault --> IGuard : pre/post
    CustodyVault --> RecoveryTimelock : bind + mutations
    CustodyVault ..> CustodyErrors : reverts
    RecoveryTimelock --> CustodyVault : call add/remove/threshold
    ThresholdSignature ..> CustodyErrors : InvalidThreshold*
```

## Responsabilidades

| Artefacto | Responsabilidad |
|-----------|-----------------|
| `CustodyVault` | Owners/threshold/nonce; exec quorum + under-limit; ERC-1271; guard; bind timelock |
| `ThresholdSignature` | ECDSA recover in-place + orden ascendente + unique owners ≥ M |
| `EIP712Custody` | Typehash `CustodyTransaction(to,value,data,nonce)` |
| `SpendingLimit` | Ventana rolling `1 days`; `remaining` / `recordSpend` |
| `IGuard` / `MockGuard` | Política pre/post (lab) |
| `RecoveryTimelock` | Delay + grace 14d; schedule/cancel solo vault; execute permissionless |
| `CustodyErrors` | Custom errors del módulo |
| `MockTarget` | Target de ejecución en tests |

## Modelo de permisos en ejecución

```
  execTransaction(to, value, data, signatures)
           │
           ▼
  ┌────────────────────┐
  │ Threshold M-of-N   │──fail──► InvalidThreshold* / Unsorted / Dup / NotASigner
  └─────────┬──────────┘
            │ ok
            ▼
  ┌────────────────────┐
  │ Guard pre (cached) │──fail──► GuardRejected
  └─────────┬──────────┘
            │ ok / sin guard
            ▼
  ┌────────────────────┐
  │ Effects: nonce++   │  (CEI)
  └─────────┬──────────┘
            ▼
  ┌────────────────────┐
  │ to.call{value}     │──fail──► ExecutionFailure + return false
  └─────────┬──────────┘
            │ (success o false)
            ▼
      Guard post (mismo guard cacheado)
      Emit Success / Failure
```

> Under-limit: 1 firma owner + `checkCanSpend(value)` + `recordSpend` en effects.  
> Quorum completo **bypassea** el daily cap.  
> Call fallido **no** revierte el outer (nonce/spend ya consumidos).

## Roles

| Rol | Mecanismo | Acciones |
|-----|-----------|----------|
| Owner / Signer | lista on-chain | Firmar EIP-712; under-limit con 1 firma |
| Relayer | cualquiera | `execTransaction` / under-limit / `timelock.execute` |
| Guard | `IGuard` vía multisig `setGuard` | Rechazar pre/post |
| Recovery timelock | bound una vez | Mutar owners/threshold tras delay |
| dApp | ERC-1271 | `isValidSignature` |

## Errores custom (implementados)

| Error | Uso |
|-------|-----|
| `InvalidThresholdSignature()` | Umbral / recover inválido |
| `UnsortedSignatures()` / `DuplicateSignature()` | Orden / dup |
| `NotASigner()` | Recover ∉ owners |
| `InvalidSignatureLength()` | Packed ≠ 65·N |
| `DailyLimitExceeded()` | Under-limit sin allowance |
| `GuardRejected()` | Guard pre/post falla |
| `TimelockNotReady()` / `TimelockExpired()` | Execute fuera de ventana |
| `OperationNotScheduled()` / `AlreadyScheduled()` | Schedule/cancel/execute |
| `ExecutionFailed()` | Timelock call al vault falló |
| `Unauthorized()` | Self-call / timelock / data mismatch |
| `ThresholdTooHigh/Low` / `SignerAlreadyExists/DoesNotExist` | Mutaciones custody |
| `ZeroAddress()` / `ZeroValue()` | Inputs inválidos |

# Diagrama de flujo — Threshold, ERC-1271, spending, guards y recovery

Flujos de decisión internos del protocolo de custodia (módulo 20, **diseño objetivo**).  
**Sync:** 2026-09-15 · Fases **BOOT → SOLV** ⏳.

## 1. execTransaction (quorum M-of-N)

```mermaid
flowchart TD
    A[Caller: execTransaction to,value,data,signatures] --> B{¿guard set?}
    B -->|Sí| C[guard.checkTransaction]
    C -->|reject| Z0[Revert GuardRejected]
    C -->|ok| D[txHash = EIP-712 hash + nonce]
    B -->|No| D
    D --> E[Recover signers from signatures]
    E --> F{¿sorted ascending by address?}
    F -->|No| Z1[Revert UnsortedSignatures]
    F -->|Sí| G{¿duplicados?}
    G -->|Sí| Z2[Revert DuplicateSignature]
    G -->|No| H{¿cada recover isOwner?}
    H -->|No| Z3[Revert NotASigner / InvalidThresholdSignature]
    H -->|Sí| I{¿count >= threshold?}
    I -->|No| Z4[Revert InvalidThresholdSignature]
    I -->|Sí| J[Effects: nonce++ ; opcional recordSpend]
    J --> K["Interaction: to.call value data"]
    K -->|fail| Z5[Revert ExecutionFailed]
    K -->|ok| L{¿guard set?}
    L -->|Sí| M[guard.checkAfterExecution]
    M -->|reject| Z0
    M -->|ok| N[Emit ExecutionSuccess]
    L -->|No| N
    N --> Ok([Fin — OK])
    Z0 --> End([Fin — revert])
    Z1 --> End
    Z2 --> End
    Z3 --> End
    Z4 --> End
    Z5 --> End
```

> CEI: validar firmas → actualizar nonce/spent → call externo → post-guard.

---

## 2. Validación threshold (detalle)

```mermaid
flowchart TD
    A[validateThreshold hash, signatures] --> B{¿signatures.length >= threshold?}
    B -->|No| Z[InvalidThresholdSignature]
    B -->|Sí| C[i = 0; prev = address 0]
    C --> D[Recover signer_i via ECDSA]
    D --> E{¿signer > prev?}
    E -->|No igual| F[DuplicateSignature]
    E -->|No menor| G[UnsortedSignatures]
    E -->|Sí| H{¿isOwner signer?}
    H -->|No| I[NotASigner / InvalidThresholdSignature]
    H -->|Sí| J[prev = signer; i++]
    J --> K{¿i == signatures.length?}
    K -->|No| D
    K -->|Sí| L{¿validCount >= threshold?}
    L -->|No| Z
    L -->|Sí| Ok([return — OK])
```

---

## 3. ERC-1271 isValidSignature

```mermaid
flowchart TD
    A[isValidSignature hash, signature] --> B[Reutilizar motor threshold sobre hash]
    B --> C{¿M-of-N válido + sorted + unique + owners?}
    C -->|Sí| D["return 0x1626ba7e MAGICVALUE"]
    C -->|No| E["return 0xffffffff"]
```

> Diseño provisional: no revertir en el path ERC-1271 (compatibilidad con consumidores que esperan magic value).  
> Se confirma en Fase ERC1271.

---

## 4. Daily spending — path under limit

```mermaid
flowchart TD
    A[Owner: execTransactionUnderLimit to,value,data,sig] --> B{¿msg.sender / recover isOwner?}
    B -->|No| Z0[Revert NotASigner]
    B -->|Sí| C{¿nueva ventana? block.timestamp >= windowStart + WINDOW}
    C -->|Sí| D[windowStart = now; spentInWindow = 0]
    C -->|No| E[usar spentInWindow actual]
    D --> E
    E --> F{¿spent + value <= dailyLimit?}
    F -->|No| Z1[Revert DailyLimitExceeded — usar quorum]
    F -->|Sí| G[Effects: spent += value; nonce++]
    G --> H[call externo]
    H -->|fail| Z2[ExecutionFailed]
    H -->|ok| Ok([Fin — OK])
    Z0 --> End([Fin — revert])
    Z1 --> End
    Z2 --> End
```

> El fuzz de Fase SPEND/SOLV debe cruzar fronteras de `WINDOW` (p. ej. 1 día) sin permitir bypass.

---

## 5. Guard lifecycle

```mermaid
flowchart TD
    A[Admin/Timelock: setGuard] --> B[guard = newGuard]
    B --> C[Próxima execTransaction]
    C --> D[checkTransaction — pre]
    D -->|fail| Z[GuardRejected]
    D -->|ok| E[ejecutar call]
    E --> F[checkAfterExecution — post]
    F -->|fail| Z
    F -->|ok| Ok([OK])
```

---

## 6. Recovery Timelock — cambio de signers / threshold

```mermaid
flowchart TD
    A[Schedule add/remove/changeThreshold] --> B[Guardar operationId + eta = now + delay]
    B --> C[Emit OperationScheduled]
    C --> D{¿cancel?}
    D -->|Sí| E[Borrar schedule]
    D -->|No| F{¿block.timestamp >= eta?}
    F -->|No| Z0[Revert TimelockNotReady]
    F -->|Sí| G[Validar nuevo threshold vs ownerCount]
    G -->|inválido| Z1[ThresholdTooHigh / TooLow]
    G -->|ok| H[Aplicar cambio en CustodyVault]
    H --> I[Emit OperationExecuted]
    I --> Ok([Fin — OK])
    E --> Cancelled([Cancelado])
    Z0 --> End([Fin — revert])
    Z1 --> End
```

# Flujograma — Ciclo completo Institutional Custody & Multisig

Flujo extremo a extremo (módulo 20, **diseño objetivo**).  
**Sync:** 2026-09-15 · Fases **BOOT → SOLV** ⏳.

## Actores

| Actor | Rol |
|-------|-----|
| Institución / Admin | Deploy; configura owners, threshold, daily limit, delay |
| Owners (N) | Firman off-chain (EOA o shares MPC → ECDSA) |
| Relayer / Executor | Envía `execTransaction` on-chain con el payload de firmas |
| Operador under-limit | Owner que ejecuta txs bajo el cap diario |
| Guard | Política pre/post (deny lists, amount caps extra, etc.) |
| dApp / DeFi | Llama `isValidSignature` (ERC-1271) |
| Recovery scheduler | Agenda cambios de custody vía Timelock |
| CI / Foundry | Unit, fuzz spending, invariantes, gas, SWC |

---

## Flujograma — Deploy y wiring (v1)

```mermaid
flowchart TD
    Start([Inicio]) --> Deps[forge install OZ + forge-std]
    Deps --> Vault[Deploy CustodyVault owners, threshold]
    Vault --> Limit[Config dailyLimit + WINDOW]
    Limit --> TL[Deploy / bind RecoveryTimelock delay]
    TL --> Guard[Opcional: setGuard MockGuard]
    Guard --> Fund[Fondear vault con ETH / tokens]
    Fund --> Ready([Vault listo para custody])
```

> Script objetivo: `script/Deploy.s.sol`. Env: `.env.example` (`OWNERS`, `THRESHOLD`, `DAILY_LIMIT`, `TIMELOCK_DELAY`).

---

## Flujograma principal — Propose → Sign → Execute → Limit → Recovery

```mermaid
flowchart TD
    Start([Nueva operación]) --> Hash[Calcular EIP-712 txHash + nonce]
    Hash --> Collect[Owners firman off-chain — posible MPC]
    Collect --> Sort[Ordenar firmas por address recuperada]
    Sort --> Path{¿valor bajo daily limit?}
    Path -->|Sí + 1 owner| Fast[execTransactionUnderLimit]
    Path -->|No / alto valor| Full[execTransaction con M firmas]
    Fast --> Guard1[Guard pre si aplica]
    Full --> Guard1
    Guard1 -->|fail| RevG[GuardRejected]
    Guard1 -->|ok| Exec[call destino + CEI]
    Exec -->|fail| RevE[ExecutionFailed]
    Exec -->|ok| Post[Guard post + eventos]
    Post --> Done([Operación ejecutada])

    Start2([Cambio de custody]) --> Sched[Timelock.schedule]
    Sched --> Wait[Esperar delay]
    Wait --> Apply[execute add/remove/threshold]
    Apply --> Updated([Owners/threshold actualizados])
```

---

## Flujograma — Capas de defensa en ejecución

```mermaid
flowchart TD
    A[Intent ejecutar] --> L1[1. Guard pre-check]
    L1 --> L2[2. EIP-712 hash + nonce]
    L2 --> L3[3. Sorted unique ECDSA recovers]
    L3 --> L4[4. Cada recover ∈ owners]
    L4 --> L5[5. count >= threshold]
    L5 --> L6[6. Effects nonce / spending]
    L6 --> L7[7. External call]
    L7 --> L8[8. Guard post-check]
    L1 -.->|fail| X1[GuardRejected]
    L3 -.->|fail| X2[Unsorted / Duplicate]
    L4 -.->|fail| X3[NotASigner]
    L5 -.->|fail| X4[InvalidThresholdSignature]
    L7 -.->|fail| X5[ExecutionFailed]
    L8 -.->|fail| X1
```

---

## Flujograma — Integración ERC-1271 (dApp)

```mermaid
flowchart TD
    A[dApp pide firma al vault] --> B[Owners firman hash off-chain]
    B --> C[dApp llama vault.isValidSignature]
    C --> D{¿threshold OK?}
    D -->|Sí| E[Magic 0x1626ba7e — aceptar]
    D -->|No| F[0xffffffff — rechazar]
    E --> G[dApp / protocolo continúa]
```

---

## Flujograma — Ventana de spending diario

```mermaid
flowchart TD
    Start([Gasto operativo]) --> W{¿timestamp fuera de ventana?}
    W -->|Sí| Reset[Reset spentInWindow = 0; windowStart = now]
    W -->|No| Acc[Usar acumulado]
    Reset --> Acc
    Acc --> Cap{¿spent + amount <= dailyLimit?}
    Cap -->|Sí| FastPath[Path under-limit]
    Cap -->|No| Multi[Exigir quorum M-of-N completo]
    FastPath --> Rec[recordSpend]
    Multi --> Rec2[recordSpend tras exec multisig — si aplica]
```

---

## Flujograma — Tooling Foundry (lab)

```mermaid
flowchart TD
    A[forge build] --> B[Unit: ThresholdExecution]
    B --> C[Unit: SignatureSorting]
    C --> D[Unit: ERC1271]
    D --> E[Unit: SpendingLimit]
    E --> F[Unit: Guard]
    F --> G[Unit: RecoveryTimelock]
    G --> H[Fuzz: SpendingWindow]
    H --> I[Invariant: Custody]
    I --> J[Gas + snapshot]
    J --> K[forge test — meta SOLV]
```

---

## Relación con otros docs

| Documento | Contenido |
|-----------|-----------|
| [diagrama-de-clases.md](./diagrama-de-clases.md) | Contratos, interfaces, librerías (diseño) |
| [diagrama-de-flujo.md](./diagrama-de-flujo.md) | Decisiones internas por función |
| [planificacion.md](./planificacion.md) | Fases BOOT→SOLV y autorización |

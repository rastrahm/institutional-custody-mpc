# Flujograma — Ciclo completo Institutional Custody & Multisig

Flujo extremo a extremo (módulo 20, **v1 implementado**).  
**Sync:** 2026-09-15 · Fases **BOOT → SOLV** ✅ · 69 PASS.

## Actores

| Actor | Rol |
|-------|-----|
| Institución / Deployer | Deploy vault + timelock; owners iniciales |
| Owners (N) | Firman off-chain (EOA o shares MPC → ECDSA) |
| Relayer | Publica `execTransaction` / under-limit / `timelock.execute` |
| Operador under-limit | Owner con 1 firma bajo daily cap |
| Guard | Política pre/post (opcional) |
| dApp / DeFi | `isValidSignature` (ERC-1271) |
| CI / Foundry | Unit, fuzz, invariantes, gas, SWC |

---

## Flujograma — Deploy y wiring (v1)

```mermaid
flowchart TD
    Start([Inicio]) --> V[Deploy CustodyVault owners, threshold, dailyLimit, timelock=0]
    V --> T[Deploy RecoveryTimelock vault, delay]
    T --> Bind[Multisig: vault.setRecoveryTimelock timelock]
    Bind --> GuardOpt[Opcional: multisig setGuard]
    GuardOpt --> Fund[Fondear vault ETH]
    Fund --> Ready([Vault listo])
```

> Script: `script/Deploy.s.sol` (despliega vault + timelock; bind manual vía multisig).  
> Env: `.env.example` (`OWNER_1..3`, `THRESHOLD`, `DAILY_LIMIT`, `TIMELOCK_DELAY`).

---

## Flujograma principal — Sign → Execute → Limit → Recovery

```mermaid
flowchart TD
    Start([Nueva operación]) --> Hash[EIP-712 txHash + nonce]
    Hash --> Collect[Owners firman off-chain]
    Collect --> Sort[Ordenar firmas por address]
    Sort --> Path{¿bajo daily remaining?}
    Path -->|Sí + 1 owner| Fast[execTransactionUnderLimit]
    Path -->|No / alto valor| Full[execTransaction M-of-N]
    Fast --> Guard[Guard pre si aplica]
    Full --> Guard
    Guard -->|fail| RevG[GuardRejected]
    Guard -->|ok| Exec[CEI + call]
    Exec --> Post[Guard post + eventos]
    Post --> Done([OK o success=false])

    Start2([Cambio custody]) --> Sched[Multisig → timelock.schedule]
    Sched --> Wait[Esperar delay]
    Wait --> Apply[execute → add/remove/threshold]
    Apply --> Updated([Keys/threshold actualizados])
```

---

## Flujograma — Capas de defensa

```mermaid
flowchart TD
    A[Intent ejecutar] --> L1[1. EIP-712 + nonce]
    L1 --> L2[2. Sorted unique ECDSA + owners ≥ M]
    L2 --> L3[3. Guard pre]
    L3 --> L4[4. Effects nonce / spend]
    L4 --> L5[5. External call]
    L5 --> L6[6. Guard post]
    L2 -.->|fail| X1[InvalidThreshold / Unsorted / Dup / NotASigner]
    L3 -.->|fail| X2[GuardRejected]
    L6 -.->|fail| X2
```

---

## Flujograma — ERC-1271 (dApp)

```mermaid
flowchart TD
    A[dApp pide firma] --> B[≥M owners firman hash]
    B --> C[vault.isValidSignature]
    C --> D{threshold OK?}
    D -->|Sí| E[0x1626ba7e]
    D -->|No| F[0xffffffff]
```

---

## Flujograma — Ventana spending

```mermaid
flowchart TD
    Start([Under-limit]) --> W{¿timestamp >= windowStart + 1d?}
    W -->|Sí / windowStart=0| Reset[Reset spent=0; windowStart=now]
    W -->|No| Acc[Usar acumulado]
    Reset --> Acc
    Acc --> Cap{spent + value <= dailyLimit?}
    Cap -->|Sí| Rec[recordSpend + exec]
    Cap -->|No| Multi[DailyLimitExceeded — usar quorum]
```

---

## Flujograma — Tooling Foundry (lab)

```mermaid
flowchart TD
    A[forge build] --> B[Unit: Threshold / Sorting / ERC1271]
    B --> C[Unit: Spending / Guard / Timelock]
    C --> D[Fuzz: SpendingWindow 1000]
    D --> E[Invariant: Custody 256]
    E --> F[Gas: CustodyVaultGasTest + snapshot]
    F --> G[forge test → 69 PASS]
```

---

## Relación con otros docs

| Documento | Contenido |
|-----------|-----------|
| [diagrama-de-clases.md](./diagrama-de-clases.md) | Contratos, interfaces, librerías (API real) |
| [diagrama-de-flujo.md](./diagrama-de-flujo.md) | Decisiones internas por función |
| [planificacion.md](./planificacion.md) | Fases BOOT→SOLV cerradas |
| [SWC-AUDIT.md](./SWC-AUDIT.md) | Matriz SWC-100–136 |
| [GAS.md](./GAS.md) | Baseline gas |

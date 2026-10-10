# Flowchart — Full Institutional Custody & Multisig cycle

End-to-end flow (module 20, **v1 implemented**).  
**Sync:** 2026-09-15 · Phases **BOOT → SOLV** ✅ · 69 PASS.

## Actors

| Actor | Role |
|-------|------|
| Institution / Deployer | Deploys vault + timelock; initial owners |
| Owners (N) | Sign off-chain (EOA or MPC shares → ECDSA) |
| Relayer | Submits `execTransaction` / under-limit / `timelock.execute` |
| Under-limit operator | Owner with 1 signature below the daily cap |
| Guard | Pre/post policy (optional) |
| dApp / DeFi | `isValidSignature` (ERC-1271) |
| CI / Foundry | Unit, fuzz, invariants, gas, SWC |

---

## Flowchart — Deploy and wiring (v1)

```mermaid
flowchart TD
    Start([Start]) --> V[Deploy CustodyVault owners, threshold, dailyLimit, timelock=0]
    V --> T[Deploy RecoveryTimelock vault, delay]
    T --> Bind[Multisig: vault.setRecoveryTimelock timelock]
    Bind --> GuardOpt[Optional: multisig setGuard]
    GuardOpt --> Fund[Fund vault with ETH]
    Fund --> Ready([Vault ready])
```

> Script: `script/Deploy.s.sol` (deploys vault + timelock; manual binding via multisig).  
> Env: `.env.example` (`OWNER_1..3`, `THRESHOLD`, `DAILY_LIMIT`, `TIMELOCK_DELAY`).

---

## Main flowchart — Sign → Execute → Limit → Recovery

```mermaid
flowchart TD
    Start([New operation]) --> Hash[EIP-712 txHash + nonce]
    Hash --> Collect[Owners sign off-chain]
    Collect --> Sort[Sort signatures by address]
    Sort --> Path{Under daily remaining?}
    Path -->|Yes + 1 owner| Fast[execTransactionUnderLimit]
    Path -->|No / high value| Full[execTransaction M-of-N]
    Fast --> Guard[Guard pre if applicable]
    Full --> Guard
    Guard -->|fail| RevG[GuardRejected]
    Guard -->|ok| Exec[CEI + call]
    Exec --> Post[Guard post + events]
    Post --> Done([OK or success=false])

    Start2([Custody change]) --> Sched[Multisig → timelock.schedule]
    Sched --> Wait[Wait for delay]
    Wait --> Apply[execute → add/remove/threshold]
    Apply --> Updated([Keys/threshold updated])
```

---

## Flowchart — Defense layers

```mermaid
flowchart TD
    A[Intent to execute] --> L1[1. EIP-712 + nonce]
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

## Flowchart — ERC-1271 (dApp)

```mermaid
flowchart TD
    A[dApp requests signature] --> B[≥M owners sign hash]
    B --> C[vault.isValidSignature]
    C --> D{threshold OK?}
    D -->|Yes| E[0x1626ba7e]
    D -->|No| F[0xffffffff]
```

---

## Flowchart — Spending window

```mermaid
flowchart TD
    Start([Under-limit]) --> W{timestamp >= windowStart + 1d?}
    W -->|Yes / windowStart=0| Reset[Reset spent=0; windowStart=now]
    W -->|No| Acc[Use accumulated amount]
    Reset --> Acc
    Acc --> Cap{spent + value <= dailyLimit?}
    Cap -->|Yes| Rec[recordSpend + exec]
    Cap -->|No| Multi[DailyLimitExceeded — use quorum]
```

---

## Flowchart — Foundry tooling (lab)

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

## Relation to other docs

| Document | Content |
|----------|---------|
| [diagrama-de-clases-EN.md](./diagrama-de-clases-EN.md) | Contracts, interfaces, libraries (real API) |
| [diagrama-de-flujo-EN.md](./diagrama-de-flujo-EN.md) | Internal per-function decisions |
| [planificacion-EN.md](./planificacion-EN.md) | BOOT→SOLV phases closed |
| [SWC-AUDIT-EN.md](./SWC-AUDIT-EN.md) | SWC-100–136 matrix |
| [GAS-EN.md](./GAS-EN.md) | Gas baseline |

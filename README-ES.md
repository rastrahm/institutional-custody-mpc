# 20 — Institutional Custody, Multisig & MPC Integration

Vault de custodia institucional con consenso **M-of-N** sobre hashes **EIP-712**, verificación threshold Secp256k1, **ERC-1271**, límites diarios de gasto, guards pluggable y timelock de recovery. Solidity `0.8.24` + Foundry.

**Estado:** Fases **BOOT → SOLV** ✅ (módulo v1 cerrado).  
**Suite:** `forge test` → **69 PASS**.  
**Docs sync:** 2026-09-15.

## Docs

| Archivo | Contenido |
|---------|-----------|
| [`doc/README-ES.md`](./doc/README-ES.md) | Índice de documentación |
| [`doc/planificacion-ES.md`](./doc/planificacion-ES.md) | Fases BOOT→SOLV, arquitectura |
| [`doc/COMPRENSION-ES.md`](./doc/COMPRENSION-ES.md) | Decisiones técnicas, lógica y gas |
| [`doc/diagrama-de-clases-ES.md`](./doc/diagrama-de-clases-ES.md) | UML (API real) |
| [`doc/diagrama-de-flujo-ES.md`](./doc/diagrama-de-flujo-ES.md) | Threshold / ERC-1271 / spending / recovery |
| [`doc/flujograma-ES.md`](./doc/flujograma-ES.md) | Ciclo e2e |
| [`doc/SWC-AUDIT-ES.md`](./doc/SWC-AUDIT-ES.md) | Matriz SWC-100–136 (estilo módulo 19) |
| [`doc/GAS-ES.md`](./doc/GAS-ES.md) | Optimizaciones + snapshot |
| [`portfolio/index.html`](./portfolio/index.html) | Landing portfolio (ES/EN) |

## Stack

| Capa | Tecnología |
|------|------------|
| Contratos | Solidity `0.8.24` (pragma fijo) |
| Tooling | Foundry (`forge` / `cast` / `anvil`) |
| Deps | forge-std, OpenZeppelin **v5.2.0** en `lib/` |
| Guard | `ReentrancyGuardTransient` |
| EVM | Cancun (`via_ir = true`) |

## Setup Foundry

```bash
export PATH="$HOME/.foundry/bin:$PATH"

forge build
forge test
```

## Deploy local

```bash
anvil   # otra terminal
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
```

Env: copiar `.env.example` → `.env`.  
Tras deploy: bind `setRecoveryTimelock` vía multisig.

## Gas

```bash
forge test --match-contract CustodyVaultGasTest --gas-report
forge snapshot --match-contract CustodyVaultGasTest
```

## Alcance v1

- Threshold M-of-N + sorting anti-duplicado
- ERC-1271 `isValidSignature`
- Daily spending limit + fuzz de ventana
- Guards pre/post + Timelock recovery
- Fuzz / invariantes / SWC-AUDIT / gas snapshot

Frontend Next.js: **fuera de v1**.

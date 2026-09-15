# 20 — Institutional Custody, Multisig & MPC Integration

Vault de custodia institucional con consenso **M-of-N** sobre hashes **EIP-712**, verificación threshold Secp256k1, **ERC-1271**, límites diarios de gasto, guards pluggable y timelock de recovery. Solidity `0.8.24` + Foundry.

**Estado:** Fases **BOOT → ERC1271** ✅ · restantes ⏳.  
**Suite:** `forge test` → **28 PASS**.  
**Docs sync:** 2026-09-15.

## Docs

| Archivo | Contenido |
|---------|-----------|
| [`doc/README.md`](./doc/README.md) | Índice de documentación |
| [`doc/planificacion.md`](./doc/planificacion.md) | Fases BOOT→SOLV y autorización |
| [`doc/diagrama-de-clases.md`](./doc/diagrama-de-clases.md) | UML (diseño objetivo) |
| [`doc/diagrama-de-flujo.md`](./doc/diagrama-de-flujo.md) | Threshold / ERC-1271 / spending / recovery |
| [`doc/flujograma.md`](./doc/flujograma.md) | Ciclo e2e |

## Stack

| Capa | Tecnología |
|------|------------|
| Contratos | Solidity `0.8.24` (pragma fijo) |
| Tooling | Foundry (`forge` / `cast` / `anvil`) |
| Deps | forge-std, OpenZeppelin **v5.2.0** en `lib/` |
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
**Nota BOOT:** el script es stub; el deploy real llega en THRESH/LOCK.

## Alcance v1

- Threshold M-of-N + sorting anti-duplicado
- ERC-1271 `isValidSignature`
- Daily spending limit + fuzz de ventana
- Guards pre/post + Timelock recovery
- Fuzz / invariantes / SWC-AUDIT / gas snapshot

Frontend Next.js: **fuera de v1**.

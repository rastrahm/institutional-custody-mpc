# 20 — Institutional Custody, Multisig & MPC Integration

Institutional custody vault with **M-of-N** consensus over **EIP-712** hashes, Secp256k1 threshold verification, **ERC-1271**, daily spending limits, pluggable guards and a recovery timelock. Solidity `0.8.24` + Foundry.

**Status:** Phases **BOOT → SOLV** ✅ (module v1 closed).  
**Suite:** `forge test` → **69 PASS**.  
**Docs sync:** 2026-09-15.

## Docs

| File | Content |
|------|---------|
| [`doc/README-EN.md`](./doc/README-EN.md) | Documentation index |
| [`doc/planificacion-EN.md`](./doc/planificacion-EN.md) | BOOT→SOLV phases, architecture |
| [`doc/COMPRENSION-EN.md`](./doc/COMPRENSION-EN.md) | Technical decisions, logic and gas |
| [`doc/diagrama-de-clases-EN.md`](./doc/diagrama-de-clases-EN.md) | UML (real API) |
| [`doc/diagrama-de-flujo-EN.md`](./doc/diagrama-de-flujo-EN.md) | Threshold / ERC-1271 / spending / recovery |
| [`doc/flujograma-EN.md`](./doc/flujograma-EN.md) | End-to-end cycle |
| [`doc/SWC-AUDIT-EN.md`](./doc/SWC-AUDIT-EN.md) | SWC-100–136 matrix (module 19 style) |
| [`doc/GAS-EN.md`](./doc/GAS-EN.md) | Optimizations + snapshot |
| [`portfolio/index.html`](./portfolio/index.html) | Portfolio landing page (ES/EN) |

## Stack

| Layer | Technology |
|-------|------------|
| Contracts | Solidity `0.8.24` (fixed pragma) |
| Tooling | Foundry (`forge` / `cast` / `anvil`) |
| Deps | forge-std, OpenZeppelin **v5.2.0** in `lib/` |
| Guard | `ReentrancyGuardTransient` |
| EVM | Cancun (`via_ir = true`) |

## Foundry setup

```bash
export PATH="$HOME/.foundry/bin:$PATH"

forge build
forge test
```

## Local deploy

```bash
anvil   # another terminal
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
```

Env: copy `.env.example` → `.env`.  
After deploy: bind `setRecoveryTimelock` via multisig.

## Gas

```bash
forge test --match-contract CustodyVaultGasTest --gas-report
forge snapshot --match-contract CustodyVaultGasTest
```

## v1 scope

- M-of-N threshold + anti-duplicate sorting
- ERC-1271 `isValidSignature`
- Daily spending limit + window fuzzing
- Pre/post guards + recovery timelock
- Fuzz / invariants / SWC-AUDIT / gas snapshot

Next.js frontend: **out of v1**.

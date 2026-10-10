# Guía de comprensión — Módulo 20: Institutional Custody

Documento para entender **qué se construyó**, **por qué se tomaron ciertas decisiones** y **cómo fluye la lógica**.  
Alineado al código v1 (`forge test` → **69 PASS**).  
**Fecha:** 2026-09-15.

---

## 1. Qué es este módulo (en una frase)

Un **smart contract wallet de custodia** donde N firmantes controlan fondos con umbral M, las transacciones se autorizan con **EIP-712**, dApps pueden validar firmas vía **ERC-1271**, hay un **límite diario** para operaciones chicas, **guards** opcionales y un **timelock** para cambiar llaves.

> “MPC” aquí **no** es un circuito criptográfico on-chain: significa que las firmas pueden generarse off-chain (EOA, HSM o MPC) y el contrato solo **verifica** ECDSA M-of-N.

---

## 2. Decisiones técnicas

### 2.1 Stack y constraints

| Decisión | Elección | Motivo |
|----------|----------|--------|
| Compilador | `pragma solidity 0.8.24` fijo | Suite + `.cursorrules`: sin floating pragma |
| Tooling | Foundry | TDD, fuzz ≥1000, invariantes, gas snapshot |
| Crypto | OpenZeppelin ECDSA + EIP712 | Anti-malleability, domain separator cacheado |
| Reentrancy | `ReentrancyGuardTransient` | Cancun `tstore`: más barato que el guard clásico |
| Errores | Custom errors (`CustodyErrors`) | Gas + claridad vs `require("string")` |
| ETH out | `.call{value:}("")` | Prohibido `transfer`/`send` en el suite |

### 2.2 Modelo de autorización (el núcleo)

| Path | Quién firma | Qué valida | Límite diario |
|------|-------------|------------|---------------|
| `execTransaction` | ≥ M owners, firmas **ordenadas** | Threshold + nonce EIP-712 | **No aplica** (bypass institucional) |
| `execTransactionUnderLimit` | **1** owner | ECDSA + isOwner + remaining | **Sí** (solo `value` ETH) |
| `isValidSignature` | ≥ M owners (mismo motor) | Soft-check → magic / `0xffffffff` | N/A (view) |

**Por qué firmas ordenadas:** evita que la misma firma se cuente dos veces o que un set malicioso “rellene” el umbral. Patrón clásico estilo Safe: `signer[i] > signer[i-1]`.

**Por qué el quorum bypassea el daily limit:** el cap es para **ops cotidianas** baratas (1 firma). Movimientos grandes / emergencia requieren consenso M-of-N a propósito.

### 2.3 Hash EIP-712

Tipo tipado:

```text
CustodyTransaction(address to, uint256 value, bytes data, uint256 nonce)
```

- Domain: nombre `CustodyVault`, versión `1`, `chainId`, `verifyingContract`.
- El digest firmado es el de `getTransactionHash` (= `_hashTypedDataV4(...)`).
- El **nonce** en el hash impide replay tras una ejecución exitosa (o fallida que ya consumió nonce).

### 2.4 Comportamiento ante call externo fallido

| Componente | Si el `call` al destino falla |
|------------|-------------------------------|
| `CustodyVault.exec*` | Emite `ExecutionFailure`, **retorna `false`**, **no** revierte el tx |
| Nonce / spend | **Ya consumidos** (CEI: effects antes de interaction) |
| `RecoveryTimelock.execute` | Revierte `ExecutionFailed` (operación de cambio de keys es atómica) |

**Motivo del vault:** quemar el payload firmado evita reintentos infinitos con el mismo nonce; el relayer reporta `success=false` y los owners re-firman.

### 2.5 Guards

- `setGuard` solo si `msg.sender == address(this)` → hay que llegar vía multisig self-call.
- En cada exec se **cachea** el guard al inicio: si el call cambia el guard en el mismo tx, el **post-check usa el guard viejo**.
- Fallo del guard → `GuardRejected` (try/catch). Pre-reject **no** consume nonce.

### 2.6 Spending window

- Ventana **rolling** de `1 days` desde el primer spend (o tras expirar).
- Solo cuenta el ETH `value` del under-limit (no el “peso” del calldata).
- `value == 0` no consume allowance (útil para calls de datos baratos).

### 2.7 Recovery Timelock

- Contrato separado: `schedule` / `cancel` solo desde el vault; `execute` permissionless tras `eta`.
- Grace `14 days` tras `eta` → luego `TimelockExpired`.
- Mutaciones del vault (`addOwnerWithThreshold`, `removeOwnerWithThreshold`, `changeThreshold`) solo si `msg.sender == recoveryTimelock`.
- Bind del timelock: una sola vez vía `setRecoveryTimelock` (self-call).

### 2.8 Qué quedó fuera de v1 (a propósito)

- MPC criptográfico real / BLS / Schnorr on-chain.
- ERC-4337 Account Abstraction.
- Frontend Next.js.
- Timelock para `setGuard` / `setDailyLimit` (hoy `setGuard` es multisig inmediato).
- Límite diario multi-token (solo ETH `value`).

---

## 3. Lógica que sigue el sistema

### 3.1 Mapa mental

```text
                    ┌─────────────────┐
                    │  Owners firman  │
                    │  off-chain      │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
    Bajo remaining diario?          Alto valor / política
    + 1 firma owner                 + M firmas ordenadas
              │                             │
              ▼                             ▼
   execTransactionUnderLimit      execTransaction
              │                             │
              └──────────┬──────────────────┘
                         │
                         ▼
              Guard pre → nonce(+spend) → call → Guard post
                         │
                         ▼
              dApp opcional: isValidSignature (ERC-1271)

    Cambio de owners/threshold:
      Multisig → timelock.schedule → espera delay → execute → vault muta
```

### 3.2 Flujo `execTransaction` (paso a paso)

1. `to != address(0)`.
2. `txHash = EIP-712(to, value, data, nonce actual)`.
3. Validar packed signatures (65·N bytes): recover → orden ascendente → unique → cada uno `isOwner` → `count >= threshold`.
4. Guard pre (si hay).
5. **Effects:** `nonce++`.
6. **Interaction:** `to.call{value: value}(data)`.
7. Evento Success o Failure.
8. Guard post (mismo guard cacheado).
9. Return `bool success` (sin revert si el call falló).

### 3.3 Flujo under-limit

1. Firma exactamente 65 bytes; recover debe ser owner.
2. `checkCanSpend(value)` (reset implícito de ventana si expiró).
3. Guard pre.
4. **Effects:** `nonce++`, `recordSpend(value)`, evento `DailySpendRecorded`.
5. Call + guard post + return success.

### 3.4 Flujo ERC-1271

1. Misma regla M-of-N / sorted / owners.
2. Válido → `0x1626ba7e`.
3. Inválido → `0xffffffff` (**sin revert**, para que la dApp ramifique).

### 3.5 Flujo recovery

1. Owners firman un `execTransaction` hacia `RecoveryTimelock.schedule(opId, data, eta)`.
2. Tras `eta`, cualquiera llama `execute(opId, data)` con el mismo `data`.
3. Timelock hace `vault.call(data)` → p.ej. `addOwnerWithThreshold`.

---

## 4. Mejoras de gas posibles (sobre lo existente)

Ya aplicado en v1: parse `r,s,v` in-place, ECDSA OZ, transient reentrancy, custom errors, mapping owners, optimizer + `via_ir`.  
Baseline: ver [`GAS-ES.md`](./GAS-ES.md).

### 4.1 Mejoras de impacto medio / alto

| Idea | Dónde | Ahorro esperado | Tradeoff |
|------|-------|-----------------|----------|
| Validar solo las **primeras M** firmas (no el excess) | `ThresholdSignature` | ~9–10k por firma extra (hoy excess 3 firmas cuesta más) | Menos “auditabilidad” del blob; Safe hace algo similar |
| Compact signatures EIP-2098 (64 bytes) | Threshold + under-limit | Menos calldata | Más complejidad; tooling de firma |
| Packed owners / bitmap en vez de `address[]` + mapping | Storage layout | Menos SSTORE en add/remove | Lecturas `getOwners` más caras o API distinta |
| `unchecked` en loops de índice de firmas | Threshold loop | Marginal | Solo si se prueba overflow-safe |
| Guard opcional “skip post on failure” | Vault | 1 CALL menos en path Failure | Cambia semántica de política |

### 4.2 Mejoras de impacto bajo / estructural

| Idea | Nota |
|------|------|
| Empaquetar `spentInWindow` + `windowStart` en un slot | `SpendingLimit.Data` hoy usa 3× uint256; packing + `dailyLimit` immutable ahorraría SLOAD/SSTORE |
| `dailyLimit` como `immutable` | No se puede cambiar on-chain sin redeploy / nuevo diseño |
| Short-circuit ERC-1271 si `signature.length < 65 * threshold` | Ya se hace en `_check`; OK |
| Quitar eventos en hot path (o indexed menos) | Ahorro gas, peor observabilidad ops |
| Custom domain EIP-712 sin OZ ShortStrings | Posible micro-ahorro; más riesgo de bugs |

### 4.3 Lo que **no** conviene “optimizar” a ciegas

- Sacar el sorting de firmas → riesgo de double-count.
- Poner spend **después** del call → CEI roto / reentrancy de contabilidad.
- Hacer que call fallido revierta siempre → cambia el modelo de nonce (habría que documentar y re-testear todo).

### 4.4 Orden sugerido si se itera gas (post-v1)

1. Validar exactamente M firmas (mayor win práctico + API clara: “envíen M, no más”).
2. Packear storage de spending (`dailyLimit` immutable + dos uint128/uint64).
3. Medir de nuevo con `forge snapshot` y actualizar `GAS-ES.md`.

---

## 5. Piezas de código a mirar (mapa de lectura)

| Archivo | Qué aprender |
|---------|----------------|
| `src/CustodyVault.sol` | Orquestación exec / under-limit / ERC-1271 / guard / mutations |
| `src/libraries/ThresholdSignature.sol` | Motor M-of-N + soft vs hard check |
| `src/libraries/EIP712Custody.sol` | Typehash de la tx |
| `src/libraries/SpendingLimit.sol` | Ventana rolling |
| `src/RecoveryTimelock.sol` | Delay + grace + execute |
| `doc/diagrama-de-flujo-ES.md` | Flujos de decisión |
| `doc/SWC-AUDIT-ES.md` | Riesgos de seguridad documentados |
| `doc/GAS-ES.md` | Números medidos |

---

## 6. Resumen ejecutivo

1. **Decisión central:** dos caminos de ejecución (quorum vs under-limit) + ERC-1271 reutilizando el mismo motor de firmas.
2. **Seguridad primero:** sorting, nonce, CEI, timelock para keys, guards cacheados.
3. **Gas:** ya hay un corte fuerte por assembly de firmas; el siguiente gran paso es **no validar firmas en exceso** y **compactar storage del spending**.
4. **Lógica:** firmar off-chain → ordenar → elegir path → guard → effects → call → post.

---

## Referencias

- [`planificacion-ES.md`](./planificacion-ES.md) — fases BOOT→SOLV
- [`diagrama-de-clases-ES.md`](./diagrama-de-clases-ES.md) — API real
- [`diagrama-de-flujo-ES.md`](./diagrama-de-flujo-ES.md) — decisiones por función
- [`flujograma-ES.md`](./flujograma-ES.md) — ciclo e2e
- [`GAS-ES.md`](./GAS-ES.md) — baseline
- [`SWC-AUDIT-ES.md`](./SWC-AUDIT-ES.md) — auditoría
- [`../portfolio/index.html`](../portfolio/index.html) — landing visual

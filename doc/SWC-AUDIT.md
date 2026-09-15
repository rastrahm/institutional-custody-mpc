# Auditoría SWC — Institutional Custody, Multisig & MPC Integration

Verificación del vault de custodia institucional (módulo 20) contra el [SWC Registry](https://swcregistry.io/) (EIP-1470). Estilo alineado a [`19-rwa-tokenization/doc/SWC-AUDIT.md`](../../19-rwa-tokenization/doc/SWC-AUDIT.md) y [`18-liquid-staking-protocol/doc/SWC-AUDIT.md`](../../18-liquid-staking-protocol/doc/SWC-AUDIT.md).

> **Nota:** El SWC Registry no se mantiene activamente desde ~2020. Complementar con [SCSVS](https://github.com/ComposableSecurity/SCSVS) y [EEA EthTrust](https://entethalliance.org/specs/ethtrust/).

**Contratos auditados (prod / core):**  
`src/CustodyVault.sol`,  
`src/RecoveryTimelock.sol`,  
`src/libraries/ThresholdSignature.sol`,  
`src/libraries/EIP712Custody.sol`,  
`src/libraries/SpendingLimit.sol`,  
`src/errors/CustodyErrors.sol`,  
`src/interfaces/ICustodyVault.sol`,  
`src/interfaces/IERC1271.sol`,  
`src/interfaces/IGuard.sol`,  
`src/interfaces/IRecoveryTimelock.sol`

**Dependencias de confianza:** forge-std, OpenZeppelin Contracts v5.2 (`ECDSA`, `EIP712`, `ReentrancyGuardTransient`)

**Mocks (fuera de prod):** `MockTarget`, `MockGuard`  
**Fecha:** 2026-09-15 (Fase SOLV / cierre v1)  
**Referencia tests:** `test/ThresholdExecution.t.sol`, `test/SignatureSorting.t.sol`, `test/ERC1271.t.sol`, `test/SpendingLimit.t.sol`, `test/Guard.t.sol`, `test/RecoveryTimelock.t.sol`, `test/fuzz/SpendingWindow.t.sol`, `test/invariant/Custody.invariant.t.sol`, `test/gas/CustodyVault.gas.t.sol`  
**Índice:** [`README.md`](./README.md) · README módulo: [`../README.md`](../README.md)

---

## Resumen ejecutivo

| Estado | Cantidad |
|--------|----------|
| ✅ Mitigado / No aplicable | 31 |
| ⚠️ Informativo (diseño custody / trust ops) | 5 |
| ❌ Vulnerable | 0 |

**Conclusión:** Sin vulnerabilidades SWC explotables en el alcance v1. El vault exige **M-of-N** sobre hashes **EIP-712** con firmas **ordenadas** (anti-duplicado), expone **ERC-1271**, aplica **límite diario** en el path under-limit, soporta **guards** pre/post y **timelock** para cambios de custody keys. ETH vía **`.call{value}`** con CEI + `ReentrancyGuardTransient`. Pragma fijo **`0.8.24`**.

**Principios del suite / módulo 20 verificados:**

| Principio | Estado |
|-----------|--------|
| Custom errors (no `require` strings) | ✅ `CustodyErrors` |
| Pragma fijo `0.8.24` | ✅ |
| CEI + reentrancy en ejecución | ✅ `ReentrancyGuardTransient` |
| Threshold M-of-N + sorting | ✅ `InvalidThresholdSignature` / unsorted / dup |
| ERC-1271 `isValidSignature` | ✅ magic / `0xffffffff` |
| Daily spending window + fuzz | ✅ `DailyLimitExceeded` |
| Guards pluggable | ✅ `GuardRejected` |
| Timelock recovery | ✅ `TimelockNotReady` / `TimelockExpired` |
| ETH `.call` (no transfer/send) | ✅ |
| Fuzz ≥ 1000 + invariantes | ✅ `foundry.toml` |

---

## Matriz completa SWC-100 — SWC-136

| ID | Título | Aplica | Estado | Evidencia en custody vault |
|----|--------|--------|--------|----------------------------|
| SWC-100 | Function Default Visibility | Sí | ✅ | Visibilidad explícita en `src/` |
| SWC-101 | Integer Overflow and Underflow | Sí | ✅ | Solidity `0.8.24`; `spentInWindow += amount` checked; threshold bounds |
| SWC-102 | Outdated Compiler Version | Sí | ✅ | `pragma solidity 0.8.24` + `foundry.toml` |
| SWC-103 | Floating Pragma | Sí | ✅ | Pragma exacto (sin `^`) en todos los `.sol` |
| SWC-104 | Unchecked Call Return Value | Sí | ✅ | `(success,) = to.call{value}(data)` capturado; fallo → evento / `ExecutionFailed` en timelock |
| SWC-105 | Unprotected Ether Withdrawal | Sí | ✅ | Salida ETH solo vía `execTransaction` / under-limit con firmas válidas |
| SWC-106 | Unprotected SELFDESTRUCT | No | N/A | Sin `selfdestruct` |
| SWC-107 | Reentrancy | Sí | ✅ | `nonReentrant` + CEI (nonce/spend antes del call); guard post tras call |
| SWC-108 | State Variable Default Visibility | Sí | ✅ | `private` / `immutable` / `public` explícitos |
| SWC-109 | Uninitialized Storage Pointer | No | N/A | Sin punteros storage legacy |
| SWC-110 | Assert Violation | No | N/A | Sin `assert` de producción |
| SWC-111 | Deprecated Solidity Functions | Sí | ✅ | Sin `suicide` / `throw` / `tx.origin` / ETH `transfer`/`send` |
| SWC-112 | Delegatecall to Untrusted Callee | No | N/A | Sin `delegatecall` (operation DelegateCall reservado, no expuesto) |
| SWC-113 | DoS with Failed Call | Parcial | ✅ | Call fallido no revierte el outer en vault (retorna `false`, nonce consumido); timelock sí revierte `ExecutionFailed` |
| SWC-114 | Transaction Order Dependence | Sí | ⚠️ | Relayers compiten por publicar firmas; nonce fija el orden — ver riesgos |
| SWC-115 | Authorization through tx.origin | No | N/A | Auth vía owners ECDSA / self-call / timelock; no `tx.origin` |
| SWC-116 | Block values as a proxy for time | Sí | ⚠️ | Ventana daily + timelock `eta` usan `block.timestamp` — ver riesgos |
| SWC-117 | Signature Malleability | Sí | ✅ | OZ `ECDSA` rechaza `s` alto / `v` inválido |
| SWC-118 | Incorrect Constructor Name | No | N/A | `constructor` 0.8+ |
| SWC-119 | Shadowing State Variables | Sí | ✅ | Sin shadowing material |
| SWC-120 | Weak Sources of Randomness | No | N/A | Sin RNG on-chain |
| SWC-121 | Missing Protection against Signature Replay | Sí | ✅ | Nonce en EIP-712; sorting anti-dup; replay tests |
| SWC-122 | Lack of Proper Signature Verification | Sí | ✅ | ECDSA recover + `isOwner` + threshold; ERC-1271 reutiliza motor |
| SWC-123 | Requirement Violation | Sí | ✅ | Custom errors + suite de reverts |
| SWC-124 | Write to Arbitrary Storage Location | No | N/A | Assembly solo lee `r,s,v` de calldata packed |
| SWC-125 | Incorrect Inheritance Order | Sí | ✅ | `ICustodyVault, IERC1271, EIP712, ReentrancyGuardTransient` |
| SWC-126 | Insufficient Gas Griefing | Parcial | ⚠️ | Guard externo puede consumir gas / fallar — ver riesgos |
| SWC-127 | Arbitrary Jump with Function Type Variable | No | N/A | Sin function types dinámicos |
| SWC-128 | DoS With Block Gas Limit | Parcial | ✅ | Loop de firmas O(N) con N = threshold típico pequeño |
| SWC-129 | Typographical Error | Sí | ✅ | Revisión + `forge test` |
| SWC-130 | Right-To-Left-Override control character | No | N/A | ASCII en NatSpec/tests |
| SWC-131 | Presence of unused variables | Sí | ✅ | Sin variables muertas materiales |
| SWC-132 | Unexpected Ether balance | Sí | ✅ | `receive()` acepta depósitos; saldo no se usa como invariant de auth |
| SWC-133 | Hash Collisions With Multiple Variable Length Arguments | Sí | ✅ | EIP-712 tipado; `keccak256(data)` en struct hash |
| SWC-134 | Message call with hardcoded gas amount | No | N/A | Sin `.call{gas: ...}` |
| SWC-135 | Code With No Effects | No | N/A | Paths stub eliminados en SPEND+ |
| SWC-136 | Unencrypted Private Data On-Chain | Parcial | ✅ | Owners / threshold / spent públicos por diseño custody |

---

## Riesgos informativos

### SWC-114 — Orden de publicación de firmas

**Descripción:** Varios relayers pueden enviar el mismo set de firmas; solo el primero con el nonce actual tiene éxito.

**Estado:** ⚠️ Inherente a meta-txs / multisig.

**Mitigaciones:** Nonce monotónico; tests de replay; invariante `nonce` sync.

### SWC-116 — `block.timestamp` en spending y timelock

**Descripción:** Mineros/secuenciadores pueden sesgar timestamps dentro de tolerancias del protocolo. La ventana daily y el `eta` del timelock dependen de ello.

**Estado:** ⚠️ Diseño estándar (Safe / Governor-style).

**Mitigaciones:** Fuzz de fronteras de ventana; grace period 14d en timelock; delay mínimo configurable.

### SWC-126 — Guard malicioso / griefing

**Descripción:** Un guard que revierte en post tras un call exitoso hace rollback del nonce y del efecto externo (si el efecto era solo ETH transfer, se revierte; si el destino ya emitió side-effects no-ETH irreversibles off-chain, hay riesgo de inconsistencia).

**Estado:** ⚠️ Trust en el módulo guard (seteado solo vía multisig).

**Mitigaciones:** `setGuard` self-call; tests pre/post reject; post-v1: timelock también para `setGuard`.

### Trust en owners / umbral

**Descripción:** Compromiso de ≥M keys permite drenar el vault (incluido bypass del daily limit vía quorum).

**Estado:** ⚠️ Modelo custody institucional (MPC/HSM off-chain fuera de alcance on-chain).

**Mitigación:** Timelock para rotación de keys; daily limit para ops; guards de política.

### Call failure consume nonce (diseño)

**Descripción:** Si el call externo falla, el vault emite `ExecutionFailure`, retorna `false` y **no** revierte — el nonce (y spend under-limit) ya se consumieron.

**Estado:** ⚠️ Intencional (quema el payload firmado; evita reintentos infinitos con el mismo nonce).

**Mitigación:** Tests documentados; firmantes deben re-firmar con nonce nuevo.

---

## Mapeo SWC → tests

| SWC | Test(s) relacionado(s) |
|-----|------------------------|
| SWC-101 | `SpendingLimit.t.sol`; invariante spent ≤ limit |
| SWC-103 | Compilador fijo (`forge build`) |
| SWC-104 / 105 | `ThresholdExecution.t.sol` ETH + failure path |
| SWC-107 | `nonReentrant` en ambos exec paths |
| SWC-116 | `fuzz/SpendingWindow.t.sol`; `RecoveryTimelock.t.sol` |
| SWC-117 / 122 | `SignatureSorting.t.sol`; `ERC1271.t.sol` |
| SWC-121 | Replay nonce; sorting/dup |
| SWC-123 | Guard / timelock / spending error paths |
| SWC-126 | `Guard.t.sol` pre/post reject |
| Solvencia | `invariant/Custody.invariant.t.sol` |

---

## Referencias

- [SWC Registry](https://swcregistry.io/)
- [EIP-1470](https://eips.ethereum.org/EIPS/eip-1470)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) · [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271)
- [`19-rwa-tokenization/doc/SWC-AUDIT.md`](../../19-rwa-tokenization/doc/SWC-AUDIT.md)
- [`18-liquid-staking-protocol/doc/SWC-AUDIT.md`](../../18-liquid-staking-protocol/doc/SWC-AUDIT.md)

# Planificación — Módulo 20: Institutional Custody, Multisig & MPC Integration

**Estado:** Fases **BOOT → ERC1271** ✅ · **SPEND → SOLV** ⏳.  
**Regla de avance:** no se escribe código de una fase hasta: *“Autorizo Fase \<ID\>”*.  
**Suite:** `forge test` → **28 PASS**.  
**Docs sync:** 2026-09-15 — ERC-1271 operativo sobre el motor threshold.  
**Nota de diseño:** las fases se organizan por **dominios de custody institucional** (no esquema genérico 0–7).

---

## 1. Objetivo

Construir un **vault de custodia institucional** (smart contract wallet) que permita:

- Ejecutar transacciones con consenso **M-of-N** sobre hashes **EIP-712**.
- Verificar firmas threshold con array **ordenado** (anti-duplicado / anti-replay intra-payload).
- Exponer **ERC-1271** (`isValidSignature`) para que dApps/DeFi traten el vault como firmante válido.
- Aplicar **límites de gasto diarios** (ventana por timestamp) sin requerir quorum completo en operaciones de bajo valor.
- Soportar **Guard modules** pluggable (pre/post execution) y **Timelock** de recuperación/emergencia para cambiar firmantes o umbral.

Stack: **Foundry + Solidity `0.8.24`**. Frontend Next.js queda **fuera de alcance v1**.

---

## 2. Alcance

| Incluido (v1) | Excluido (v1) |
|---------------|---------------|
| `CustodyVault` multisig M-of-N + EIP-712 | MPC criptográfico real off-chain (solo verificación on-chain de firmas Secp256k1) |
| Threshold engine + sorting de firmas | BLS / Schnorr threshold nativo on-chain |
| ERC-1271 `isValidSignature` | Account Abstraction completa (ERC-4337) |
| Daily spending limit + reset por ventana | Multi-token allowance complex (v1: ETH + opcional ERC-20 simple) |
| `IGuard` pre/post execution | Policy engine off-chain / ZK policies |
| Timelock recovery (add/remove signer, change threshold) | Social recovery con guardians externos de producción |
| Tests: threshold, sorting/dup, ERC-1271, fuzz spending window | Frontend Next.js (App Router) |
| `Deploy.s.sol` + gas snapshot + SWC-AUDIT | Mainnet custody legal packaging / HSM integration |

---

## 3. Stack y restricciones técnicas

### Suite (`evm-smart-contracts-suite` + `solidity.cursorrules`)

- Solidity **exacto** `0.8.24` (sin floating pragma).
- OpenZeppelin Contracts v5.x (`ECDSA`, `MessageHashUtils`, `ReentrancyGuardTransient`, `Ownable2Step` / roles según diseño).
- Foundry: unit + fuzz (`runs >= 1000`) + invariant + gas.
- **Custom errors** (no `require` strings).
- CEI estricto; ETH vía **`.call{value: ...}("")`** (nunca `transfer`/`send`).
- NatSpec en toda API pública/externa.
- Layout: Interfaces → Libraries → Contracts → State → Events → Errors → Modifiers → Functions.
- TDD: tests primero en cada fase de contratos.
- Arquitectura explicada antes de codear (este documento + diagramas).

### Módulo 20 (`.cursorrules` local)

- Threshold M-of-N sobre hash EIP-712 → `error InvalidThresholdSignature()`.
- Firmas **ordenadas** por address recuperada; rechazar duplicados / unsorted.
- ERC-1271: `isValidSignature(bytes32, bytes) → bytes4`.
- Daily spending cap con reset por ventana de timestamp.
- Guards pluggable + Timelock para cambios de custody keys / threshold.

### Next.js (`nextjs.cursorrules`) — post-v1

- UI: proponer tx, recolectar firmas, ejecutar, ver límite diario, panel recovery.
- App Router, Zod, Vitest + RTL, JSDoc, sin `any`.
- **Fuera** de las fases de esta planificación.

---

## 4. Arquitectura (diseño objetivo)

```
20-institutional-custody-mpc/
├── README.md
├── .cursorrules
├── .gitignore
├── .env.example
├── .gas-snapshot
├── foundry.toml
├── remappings.txt
├── doc/
│   ├── README.md
│   ├── planificacion.md
│   ├── diagrama-de-clases.md
│   ├── diagrama-de-flujo.md
│   ├── flujograma.md
│   ├── SWC-AUDIT.md          # Fase SOLV
│   └── GAS.md                # Fase SOLV
├── src/
│   ├── CustodyVault.sol
│   ├── SpendingLimit.sol          # o library / módulo interno
│   ├── RecoveryTimelock.sol       # o módulo en vault
│   ├── interfaces/
│   │   ├── ICustodyVault.sol
│   │   ├── IERC1271.sol
│   │   ├── IGuard.sol
│   │   └── IRecoveryTimelock.sol
│   ├── libraries/
│   │   ├── ThresholdSignature.sol
│   │   └── EIP712Custody.sol
│   ├── guards/
│   │   └── (ej. DenyCallGuard.sol — lab mínimo)
│   ├── errors/
│   │   └── CustodyErrors.sol
│   └── mocks/
│       └── MockGuard.sol
├── test/
│   ├── ThresholdExecution.t.sol
│   ├── SignatureSorting.t.sol
│   ├── ERC1271.t.sol
│   ├── SpendingLimit.t.sol
│   ├── Guard.t.sol
│   ├── RecoveryTimelock.t.sol
│   ├── helpers/CustodyTestBase.sol
│   ├── fuzz/SpendingWindow.t.sol
│   ├── invariant/
│   │   ├── CustodyHandler.sol
│   │   └── Custody.invariant.t.sol
│   └── gas/CustodyVault.gas.t.sol
└── script/
    └── Deploy.s.sol
```

### Contratos y responsabilidades

| Artefacto | Responsabilidad |
|-----------|-----------------|
| `CustodyVault` | Wallet multisig: propose/execute, EIP-712, nonce, value calls |
| `ThresholdSignature` | Recupera signers, ordena, valida M-of-N |
| `EIP712Custody` | Domain separator + typed hashes de transacciones |
| ERC-1271 | Valida mensajes off-chain con el mismo umbral |
| Spending limit | Cap diario; path “fast” bajo límite sin quorum completo (o con umbral reducido — definir en BOOT) |
| `IGuard` | `checkTransaction` / `checkAfterExecution` |
| Recovery Timelock | Schedule → delay → execute cambios de signers/threshold |
| `CustodyErrors` | Custom errors del módulo |

---

## 5. Errores custom (módulo — diseño)

```solidity
error InvalidThresholdSignature(); // obligatorio (.cursorrules)
error UnsortedSignatures();
error DuplicateSignature();
error NotASigner();
error InvalidSignatureLength();
error ThresholdTooHigh();
error ThresholdTooLow();
error SignerAlreadyExists();
error SignerDoesNotExist();
error DailyLimitExceeded();
error ExecutionFailed();
error GuardRejected();
error TimelockNotReady();
error TimelockExpired();
error OperationNotScheduled();
error OperationAlreadyScheduled();
error ZeroAddress();
error ZeroValue();
error InvalidNonce();
error Unauthorized();
```

> Lista provisional; se ajustará en BOOT/THRESH según implementación concreta.

---

## 6. Gobernanza de fases (autorización obligatoria)

| Regla | Detalle |
|-------|---------|
| **Gate** | No se escribe código de una fase hasta: *“Autorizo Fase \<ID\>”*. |
| **Entrega** | Al cerrar: checklist de aceptación + archivos tocados. |
| **Bloqueo** | Alcance nuevo → documentar y esperar nueva autorización. |
| **TDD** | En fases de contratos: tests primero, luego implementación. |
| **IDs** | Fases con nombres de dominio custody (BOOT, THRESH, …). |

### Tablero de fases

| Fase | Nombre | Estado | Autorización |
|------|--------|--------|--------------|
| **BOOT** | Scaffold Foundry + errores + interfaces base | ✅ Completada | ✅ Autorizada |
| **THRESH** | Vault EIP-712 + motor M-of-N + sorting | ✅ Completada | ✅ Autorizada |
| **ERC1271** | `isValidSignature` + tests integración dApp-like | ✅ Completada | ✅ Autorizada |
| **SPEND** | Daily spending limit + reset por ventana | ⏳ Pendiente | ❌ No autorizada |
| **GUARD** | Guards pluggable pre/post execution | ⏳ Pendiente | ❌ No autorizada |
| **LOCK** | Timelock recovery (signers / threshold) | ⏳ Pendiente | ❌ No autorizada |
| **SOLV** | Fuzz spending + invariantes + Deploy/gas + SWC-AUDIT | ⏳ Pendiente | ❌ No autorizada |

**Cómo autorizar:** escribir exactamente  
`Autorizo Fase SPEND` (o GUARD / LOCK / SOLV).

---

## 7. Detalle por fase

### Fase BOOT — Scaffold Foundry + base ✅

**Objetivo:** repo Foundry compilable con layout, deps OZ, errores e interfaces.

1. Scaffold: `foundry.toml` (solc `0.8.24`, fuzz `runs >= 1000`), remappings, OZ v5, `src/` / `test/` / `script/`.
2. `CustodyErrors.sol` con `InvalidThresholdSignature` y errores base.
3. Interfaces: `ICustodyVault`, `IERC1271`, `IGuard`, `IRecoveryTimelock`.
4. Stub `Deploy.s.sol`, `.env.example`, `README.md` del módulo.
5. Smoke test: `forge build` OK.

**Criterio de salida:** `forge build` verde; árbol de carpetas alineado a §4.

**Depende de:** nada (primera fase de código).

**Hecho (2026-09-15):**
- `foundry.toml` (solc `0.8.24`, Cancun, optimizer `10_000`, `via_ir`, fuzz `runs = 1000`).
- `remappings.txt`; deps en `lib/` (forge-std, OpenZeppelin **v5.2.0**, copiadas del módulo 19).
- `CustodyErrors.sol` + interfaces `ICustodyVault`, `IERC1271`, `IGuard`, `IRecoveryTimelock`.
- Stub `script/Deploy.s.sol`, `.env.example`, `README.md`.
- Smoke: `test/BootScaffold.t.sol`.
- **`forge test` → 3 PASS**.

---

### Fase THRESH — Threshold + EIP-712 execution ✅

**Objetivo:** ejecutar llamadas con M-of-N firmas válidas sobre typed data.

1. TDD primero: exact threshold OK; excess signatures OK; unsorted / duplicate → revert; non-signer → revert.
2. `CustodyVault`: owners, threshold, nonce, `execTransaction` (o equivalente).
3. Library `ThresholdSignature` + hashing EIP-712.
4. CEI + `ReentrancyGuard`; ETH con `.call{value:}("")`.
5. Eventos de ejecución / fallos.

**Criterio de salida:** tests de threshold + sorting/duplicate en verde.

**Depende de:** BOOT.

**Hecho (2026-09-15):**
- `EIP712Custody.sol` — typehash `CustodyTransaction(to,value,data,nonce)`.
- `ThresholdSignature.sol` — recover ECDSA (OZ), orden ascendente estricto, anti-duplicado, `count >= threshold`.
- `CustodyVault.sol` — EIP-712 OZ + `ReentrancyGuardTransient`; `execTransaction` CEI; call failure → `ExecutionFailure` + `return false` (nonce consumido).
- `execTransactionUnderLimit` stub → `Unauthorized` (Fase SPEND).
- `MockTarget.sol`; tests `ThresholdExecution.t.sol` + `SignatureSorting.t.sol` + helper `CustodyTestBase`.
- `Deploy.s.sol` despliega vault con `OWNER_1..3` / `THRESHOLD`.
- **`forge test` → 19 PASS**.

---

### Fase ERC1271 — Smart contract signature validation ✅

**Objetivo:** dApps puedan validar mensajes firmados por el umbral del vault.

1. TDD: mensaje EIP-712 / hash firmado por ≥M owners → magic value `0x1626ba7e`.
2. Firmas insuficientes / inválidas → `0xffffffff` o revert según diseño documentado.
3. Reutilizar motor threshold (sin divergencia de reglas).

**Criterio de salida:** suite ERC-1271 en verde.

**Depende de:** THRESH.

**Hecho (2026-09-15):**
- `ThresholdSignature.isValidThreshold` (soft-check) + `validateThreshold` (revert con error específico) comparten `_check`.
- `CustodyVault.isValidSignature` → `0x1626ba7e` / `0xffffffff` (sin revert en el path ERC-1271).
- Mismas reglas: M-of-N, sorted, unique, owners; aplica a hash arbitrario o digest EIP-712 del vault.
- Tests: `test/ERC1271.t.sol` (exact, excess, typed hash, insufficient, unsorted, dup, non-signer, empty, wrong hash).
- **`forge test` → 28 PASS**.

---

### Fase SPEND — Daily spending limit ⏳

**Objetivo:** cap operativo diario con reset por ventana temporal.

1. TDD + fuzz: volumen acumulado; cruce de frontera de timestamp; no bypass por manipulación de `block.timestamp` dentro de la ventana.
2. Estado: `spentInWindow`, `windowStart` (o day bucket).
3. Path de ejecución bajo límite (definir: ¿1 firma? ¿cualquier owner? — documentar en entrega).
4. Exceder límite → `DailyLimitExceeded` o forzar path multisig completo.

**Criterio de salida:** unit + fuzz de ventana en verde.

**Depende de:** THRESH.

---

### Fase GUARD — Pluggable guards ⏳

**Objetivo:** hooks pre/post que puedan rechazar ejecución.

1. `setGuard` con control de acceso adecuado (timelock en LOCK o admin restringido).
2. `IGuard.checkTransaction` / `checkAfterExecution`.
3. TDD: MockGuard rechaza → `GuardRejected`; sin guard → flujo normal.

**Criterio de salida:** tests de guard en verde.

**Depende de:** THRESH.

---

### Fase LOCK — Emergency recovery Timelock ⏳

**Objetivo:** cambios sensibles (add/remove signer, change threshold) con delay.

1. Schedule operación → esperar delay → execute; cancel opcional.
2. TDD: early execute → `TimelockNotReady`; post-delay OK; threshold inválido → revert.
3. Integrar con estado de owners del vault.

**Criterio de salida:** tests de recovery/timelock en verde.

**Depende de:** THRESH (idealmente tras GUARD si `setGuard` también va por timelock).

---

### Fase SOLV — Hardening y cierre v1 ⏳

**Objetivo:** demostrar robustez y cerrar lab.

1. Fuzz spending across timestamp boundaries (requisito `.cursorrules`).
2. Invariantes: threshold ≤ owners; spent ≤ limit por ventana; nonce monotónico.
3. `Deploy.s.sol`, NatSpec completo, gas snapshot.
4. `doc/SWC-AUDIT.md` + `doc/GAS.md` + sync de diagramas si hubo desviaciones.
5. Marcar fases ✅ en este documento.

**Criterio de salida:** `forge test` (unit + fuzz + invariant) verde; deploy local OK.

**Depende de:** BOOT + THRESH + ERC1271 + SPEND + GUARD + LOCK.

---

## 8. Checklist de aceptación global (v1)

- [x] Scaffold Foundry + solc `0.8.24` (Fase BOOT)
- [x] Ejecución M-of-N sobre EIP-712 con sorting anti-duplicado
- [x] `InvalidThresholdSignature` / unsorted / duplicate cubiertos por tests
- [x] ERC-1271 `isValidSignature` operativo
- [ ] Daily spending limit con reset por ventana + fuzz
- [ ] Guards pre/post execution
- [ ] Timelock para cambios de signers/threshold
- [ ] CEI + custom errors + NatSpec + `.call` para ETH
- [ ] Frontend Next.js **no** incluido (post-v1)
- [ ] `doc/SWC-AUDIT.md` + gas snapshot + `Deploy.s.sol`

---

## 9. Próximo paso

Esperando autorización explícita: **`Autorizo Fase SPEND`**.

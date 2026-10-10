# Planning — Module 20: Institutional Custody, Multisig & MPC Integration

**Status:** Phases **BOOT → SOLV** ✅ (module v1 closed).  
**Progress rule:** the per-phase authorization rule applied during construction; v1 has no pending phases.  
**Suite:** `forge test` → **69 PASS**.  
**Docs sync:** 2026-09-15 — SWC-AUDIT + GAS + invariants + snapshot; **diagrams = code**.  
**Design note:** phases are organized by **institutional custody domains** (not a generic 0–7 scheme).

---

## 1. Objective

Build an **institutional custody vault** (smart contract wallet) that allows:

- Executing transactions with **M-of-N** consensus over **EIP-712** hashes.
- Verifying threshold signatures with a **sorted** array (anti-duplicate / intra-payload anti-replay).
- Exposing **ERC-1271** (`isValidSignature`) so dApps/DeFi treat the vault as a valid signer.
- Enforcing **daily spending limits** (timestamp window) without requiring full quorum for low-value operations.
- Supporting pluggable **Guard modules** (pre/post execution) and a recovery/emergency **Timelock** to change signers or the threshold.

Stack: **Foundry + Solidity `0.8.24`**. The Next.js frontend is **out of v1 scope**.

---

## 2. Scope

| Included (v1) | Excluded (v1) |
|---------------|---------------|
| `CustodyVault` M-of-N multisig + EIP-712 | Real off-chain cryptographic MPC (only on-chain verification of Secp256k1 signatures) |
| Threshold engine + signature sorting | Native on-chain BLS / Schnorr threshold |
| ERC-1271 `isValidSignature` | Full Account Abstraction (ERC-4337) |
| Daily spending limit + window reset | Complex multi-token allowance (v1: ETH + optional simple ERC-20) |
| `IGuard` pre/post execution | Off-chain policy engine / ZK policies |
| Recovery timelock (add/remove signer, change threshold) | Production social recovery with external guardians |
| Tests: threshold, sorting/dup, ERC-1271, spending window fuzz | Next.js frontend (App Router) |
| `Deploy.s.sol` + gas snapshot + SWC-AUDIT | Mainnet custody legal packaging / HSM integration |

---

## 3. Stack and technical constraints

### Suite (`evm-smart-contracts-suite` + `solidity.cursorrules`)

- **Exact** Solidity `0.8.24` (no floating pragma).
- OpenZeppelin Contracts v5.x (`ECDSA`, `MessageHashUtils`, `ReentrancyGuardTransient`, `Ownable2Step` / roles depending on design).
- Foundry: unit + fuzz (`runs >= 1000`) + invariant + gas.
- **Custom errors** (no `require` strings).
- Strict CEI; ETH via **`.call{value: ...}("")`** (never `transfer`/`send`).
- NatSpec on every public/external API.
- Layout: Interfaces → Libraries → Contracts → State → Events → Errors → Modifiers → Functions.
- TDD: tests first in every contract phase.
- Architecture explained before coding (this document + diagrams).

### Module 20 (local `.cursorrules`)

- M-of-N threshold over an EIP-712 hash → `error InvalidThresholdSignature()`.
- Signatures **sorted** by recovered address; reject duplicates / unsorted.
- ERC-1271: `isValidSignature(bytes32, bytes) → bytes4`.
- Daily spending cap with timestamp window reset.
- Pluggable guards + Timelock for custody key / threshold changes.

### Next.js (`nextjs.cursorrules`) — post-v1

- UI: propose tx, collect signatures, execute, view daily limit, recovery panel.
- App Router, Zod, Vitest + RTL, JSDoc, no `any`.
- **Outside** the phases of this plan.

---

## 4. Architecture (v1 implemented)

```
20-institutional-custody-mpc/
├── README.md               # ES/EN index
├── README-ES.md / README-EN.md
├── .cursorrules
├── .gitignore
├── .env.example
├── .gas-snapshot
├── foundry.toml
├── remappings.txt
├── doc/                    # every document in -ES.md and -EN.md
│   ├── README.md           # ES/EN index
│   ├── README-ES/EN.md
│   ├── planificacion-ES/EN.md
│   ├── COMPRENSION-ES/EN.md
│   ├── diagrama-de-clases-ES/EN.md
│   ├── diagrama-de-flujo-ES/EN.md
│   ├── flujograma-ES/EN.md
│   ├── SWC-AUDIT-ES/EN.md
│   └── GAS-ES/EN.md
├── portfolio/
│   ├── index.html
│   └── i18n.js
├── src/
│   ├── CustodyVault.sol
│   ├── RecoveryTimelock.sol
│   ├── interfaces/
│   │   ├── ICustodyVault.sol
│   │   ├── IERC1271.sol
│   │   ├── IGuard.sol
│   │   └── IRecoveryTimelock.sol
│   ├── libraries/
│   │   ├── ThresholdSignature.sol
│   │   ├── EIP712Custody.sol
│   │   └── SpendingLimit.sol
│   ├── errors/
│   │   └── CustodyErrors.sol
│   └── mocks/
│       ├── MockGuard.sol
│       └── MockTarget.sol
├── test/
│   ├── BootScaffold.t.sol
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

### Contracts and responsibilities

| Artifact | Responsibility |
|----------|----------------|
| `CustodyVault` | M-of-N multisig, under-limit, ERC-1271, guard, timelock binding, timelock-only mutations |
| `ThresholdSignature` | In-place recover + order + unique + ≥ M (validate / soft isValid) |
| `EIP712Custody` | `CustodyTransaction` struct hash |
| `SpendingLimit` | Rolling 1d window; remaining / recordSpend |
| `RecoveryTimelock` | schedule/cancel (vault); execute after delay; 14d grace |
| `IGuard` / `MockGuard` | Pre/post checks |
| `CustodyErrors` | Custom errors |
| `MockTarget` | Lab execution target |

---

## 5. Custom errors (module — implemented)

```solidity
error InvalidThresholdSignature(); // mandatory (.cursorrules)
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
error InvalidNonce(); // reserved
error Unauthorized();
```

---

## 6. Phase governance (mandatory authorization)

| Rule | Detail |
|------|--------|
| **Gate** | No code for a phase is written until: *"I authorize Phase \<ID\>"*. |
| **Delivery** | On close: acceptance checklist + touched files. |
| **Block** | New scope → document it and wait for a new authorization. |
| **TDD** | In contract phases: tests first, then implementation. |
| **IDs** | Phases named after custody domains (BOOT, THRESH, …). |

### Phase board

| Phase | Name | Status | Authorization |
|-------|------|--------|---------------|
| **BOOT** | Foundry scaffold + errors + base interfaces | ✅ Completed | ✅ Authorized |
| **THRESH** | EIP-712 vault + M-of-N engine + sorting | ✅ Completed | ✅ Authorized |
| **ERC1271** | `isValidSignature` + dApp-like integration tests | ✅ Completed | ✅ Authorized |
| **SPEND** | Daily spending limit + window reset | ✅ Completed | ✅ Authorized |
| **GUARD** | Pluggable pre/post execution guards | ✅ Completed | ✅ Authorized |
| **LOCK** | Recovery timelock (signers / threshold) | ✅ Completed | ✅ Authorized |
| **SOLV** | Spending fuzz + invariants + Deploy/gas + SWC-AUDIT | ✅ Completed | ✅ Authorized |

**How to authorize:** module v1 closed; there are no pending phases.

---

## 7. Phase details

### Phase BOOT — Foundry scaffold + base ✅

**Objective:** a compilable Foundry repo with layout, OZ deps, errors and interfaces.

1. Scaffold: `foundry.toml` (solc `0.8.24`, fuzz `runs >= 1000`), remappings, OZ v5, `src/` / `test/` / `script/`.
2. `CustodyErrors.sol` with `InvalidThresholdSignature` and base errors.
3. Interfaces: `ICustodyVault`, `IERC1271`, `IGuard`, `IRecoveryTimelock`.
4. Stub `Deploy.s.sol`, `.env.example`, module `README.md`.
5. Smoke test: `forge build` OK.

**Exit criterion:** green `forge build`; folder tree aligned with §4.

**Depends on:** nothing (first code phase).

**Done (2026-09-15):**
- `foundry.toml` (solc `0.8.24`, Cancun, optimizer `10_000`, `via_ir`, fuzz `runs = 1000`).
- `remappings.txt`; deps in `lib/` (forge-std, OpenZeppelin **v5.2.0**, copied from module 19).
- `CustodyErrors.sol` + interfaces `ICustodyVault`, `IERC1271`, `IGuard`, `IRecoveryTimelock`.
- Stub `script/Deploy.s.sol`, `.env.example`, `README.md`.
- Smoke: `test/BootScaffold.t.sol`.
- **`forge test` → 3 PASS**.

---

### Phase THRESH — Threshold + EIP-712 execution ✅

**Objective:** execute calls with M-of-N valid signatures over typed data.

1. TDD first: exact threshold OK; excess signatures OK; unsorted / duplicate → revert; non-signer → revert.
2. `CustodyVault`: owners, threshold, nonce, `execTransaction` (or equivalent).
3. `ThresholdSignature` library + EIP-712 hashing.
4. CEI + `ReentrancyGuard`; ETH with `.call{value:}("")`.
5. Execution / failure events.

**Exit criterion:** threshold + sorting/duplicate tests green.

**Depends on:** BOOT.

**Done (2026-09-15):**
- `EIP712Custody.sol` — typehash `CustodyTransaction(to,value,data,nonce)`.
- `ThresholdSignature.sol` — ECDSA recover (OZ), strict ascending order, anti-duplicate, `count >= threshold`.
- `CustodyVault.sol` — OZ EIP-712 + `ReentrancyGuardTransient`; CEI `execTransaction`; call failure → `ExecutionFailure` + `return false` (nonce consumed).
- `execTransactionUnderLimit` stub → `Unauthorized` (SPEND phase).
- `MockTarget.sol`; tests `ThresholdExecution.t.sol` + `SignatureSorting.t.sol` + helper `CustodyTestBase`.
- `Deploy.s.sol` deploys the vault with `OWNER_1..3` / `THRESHOLD`.
- **`forge test` → 19 PASS**.

---

### Phase ERC1271 — Smart contract signature validation ✅

**Objective:** dApps can validate messages signed by the vault's threshold.

1. TDD: EIP-712 message / hash signed by ≥M owners → magic value `0x1626ba7e`.
2. Insufficient / invalid signatures → `0xffffffff` or revert per documented design.
3. Reuse the threshold engine (no rule divergence).

**Exit criterion:** ERC-1271 suite green.

**Depends on:** THRESH.

**Done (2026-09-15):**
- `ThresholdSignature.isValidThreshold` (soft-check) + `validateThreshold` (revert with a specific error) share `_check`.
- `CustodyVault.isValidSignature` → `0x1626ba7e` / `0xffffffff` (no revert on the ERC-1271 path).
- Same rules: M-of-N, sorted, unique, owners; applies to an arbitrary hash or the vault's EIP-712 digest.
- Tests: `test/ERC1271.t.sol` (exact, excess, typed hash, insufficient, unsorted, dup, non-signer, empty, wrong hash).
- **`forge test` → 28 PASS**.

---

### Phase SPEND — Daily spending limit ✅

**Objective:** daily operational cap with time-window reset.

1. TDD + fuzz: accumulated volume; timestamp boundary crossing; no bypass via `block.timestamp` manipulation within the window.
2. State: `spentInWindow`, `windowStart` (or day bucket).
3. Under-limit execution path (define: 1 signature? any owner? — document on delivery).
4. Exceeding the limit → `DailyLimitExceeded` or force the full multisig path.

**Exit criterion:** unit + window fuzz green.

**Depends on:** THRESH.

**Done (2026-09-15):**
- `SpendingLimit.sol` — rolling window `WINDOW = 1 days`; `remaining` / `recordSpend` / `checkCanSpend`.
- `CustodyVault(owners, threshold, dailyLimit)` — getters `dailyLimit`, `spentInWindow`, `windowStart`, `remainingDailyLimit`.
- **Under-limit path:** **1 ECDSA signature from any owner**; only the ETH `value` counts toward the cap; `value == 0` does not consume allowance.
- **Full quorum** (`execTransaction`) **bypasses** the daily cap (institutional override).
- Excess → `DailyLimitExceeded`; a target failure still consumes nonce + spend (CEI).
- Tests: `SpendingLimit.t.sol` + fuzz `test/fuzz/SpendingWindow.t.sol` (1000 runs).
- **`forge test` → 39 PASS**.

---

### Phase GUARD — Pluggable guards ✅

**Objective:** pre/post hooks that can reject execution.

1. `setGuard` with proper access control (timelock in LOCK or restricted admin).
2. `IGuard.checkTransaction` / `checkAfterExecution`.
3. TDD: MockGuard rejects → `GuardRejected`; no guard → normal flow.

**Exit criterion:** guard tests green.

**Depends on:** THRESH.

**Done (2026-09-15):**
- `setGuard` only via self-call (`msg.sender == address(this)` → multisig); EOA → `Unauthorized`.
- Pre/post in `execTransaction` and `execTransactionUnderLimit`; guard captured at the start (post does not use a guard set in the same tx).
- Guard failure → `GuardRejected` (try/catch); a pre-reject does not consume nonce/spend.
- `MockGuard.sol` + tests `Guard.t.sol`.
- **`forge test` → 48 PASS**.

---

### Phase LOCK — Emergency recovery Timelock ✅

**Objective:** sensitive changes (add/remove signer, change threshold) with a delay.

1. Schedule operation → wait for delay → execute; optional cancel.
2. TDD: early execute → `TimelockNotReady`; post-delay OK; invalid threshold → revert.
3. Integrate with the vault's owner state.

**Exit criterion:** recovery/timelock tests green.

**Depends on:** THRESH (ideally after GUARD if `setGuard` also goes through the timelock).

**Done (2026-09-15):**
- `RecoveryTimelock.sol` — `schedule`/`cancel` only from the vault; `execute` permissionless after `eta`; `14 days` grace → `TimelockExpired`.
- Vault: `setRecoveryTimelock` (self-call, once); `addOwnerWithThreshold` / `removeOwnerWithThreshold` / `changeThreshold` timelock-only.
- Vault constructor: 4th arg `recoveryTimelock_` (can be `0` and bound later).
- Flow: multisig → `timelock.schedule` → warp → `timelock.execute(data)`.
- Tests: `RecoveryTimelock.t.sol` (threshold, add/remove, cancel, expiry, wrong data, unauthorized).
- **`forge test` → 60 PASS**.

---

### Phase SOLV — Hardening and v1 close ✅

**Objective:** demonstrate robustness and close the lab.

1. Spending fuzz across timestamp boundaries (`.cursorrules` requirement).
2. Invariants: threshold ≤ owners; spent ≤ limit per window; monotonic nonce.
3. `Deploy.s.sol`, complete NatSpec, gas snapshot.
4. `doc/SWC-AUDIT-EN.md` + `doc/GAS-EN.md` + diagram sync if there were deviations.
5. Mark phases ✅ in this document.

**Exit criterion:** green `forge test` (unit + fuzz + invariant); local deploy OK.

**Depends on:** BOOT + THRESH + ERC1271 + SPEND + GUARD + LOCK.

**Done (2026-09-15):**
- Invariants: `test/invariant/Custody.invariant.t.sol` + `CustodyHandler` (threshold, spent, nonce).
- Gas: `test/gas/CustodyVault.gas.t.sol` + `.gas-snapshot`.
- Optimization: `ThresholdSignature` in-place `r,s,v` parsing (assembly) → ≈−24 % on exact-threshold exec.
- `doc/SWC-AUDIT-EN.md` (SWC-100–136 matrix, module 19 style), `doc/GAS-EN.md`.
- Spending fuzz already in SPEND; Deploy wires vault + timelock.
- **`forge test` → 69 PASS**.

---

## 8. Global acceptance checklist (v1)

- [x] Foundry scaffold + solc `0.8.24` (BOOT phase)
- [x] M-of-N execution over EIP-712 with anti-duplicate sorting
- [x] `InvalidThresholdSignature` / unsorted / duplicate covered by tests
- [x] ERC-1271 `isValidSignature` operational
- [x] Daily spending limit with window reset + fuzz
- [x] Pre/post execution guards
- [x] Timelock for signer/threshold changes
- [x] CEI + custom errors + NatSpec + `.call` for ETH
- [x] Next.js frontend **not** included (post-v1)
- [x] `doc/SWC-AUDIT-EN.md` + gas snapshot + `Deploy.s.sol`

---

## 9. Next step

**Module v1 closed (Phases BOOT → SOLV ✅).**  
Optional post-v1: Next.js frontend, timelock for `setGuard`/`setDailyLimit`, Account Abstraction (ERC-4337).

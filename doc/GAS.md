# Optimización de gas — Institutional Custody Vault

Regenerar:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge test --match-contract CustodyVaultGasTest --gas-report
forge snapshot --match-contract CustodyVaultGasTest
```

**Fecha baseline:** 2026-09-15 (Fase SOLV / cierre v1)  
**Snapshot:** `.gas-snapshot` (`test/gas/CustodyVault.gas.t.sol`)  
**Optimizer:** `optimizer_runs = 10_000`, `via_ir = true`, solc `0.8.24`, EVM Cancun  
**Suite:** `forge test` → **69 PASS**

---

## Baseline operaciones (snapshot)

| Path | Gas (snapshot) | Notas |
|------|----------------|-------|
| `testGas_execTransaction_ExactThreshold` | **120 011** | 2 firmas M-of-N + ping |
| `testGas_execTransaction_ExcessSignatures` | **129 725** | 3 firmas (excess OK) |
| `testGas_execTransaction_EthTransfer` | **105 293** | Quorum + ETH `.call` |
| `testGas_execTransactionUnderLimit` | **130 900** | 1 firma + spend window |
| `testGas_isValidSignature` | **37 698** | ERC-1271 view path |

### Gas report (funciones del vault)

| Función | Min | Avg | Median | Max |
|---------|-----|-----|--------|-----|
| `execTransaction` | 101 143 | 112 813 | 115 243 | 122 054 |
| `execTransactionUnderLimit` | 140 518 | 140 518 | 140 518 | 140 518 |
| `isValidSignature` | 14 478 | 14 478 | 14 478 | 14 478 |
| `getTransactionHash` | 1 466 | 1 472 | 1 472 | 1 478 |

> El gas del **test** incluye setup de firmas off-chain en el runner; el **gas-report** mide el call on-chain al vault.

---

## Optimizaciones aplicadas

| Técnica | Dónde | Efecto |
|---------|-------|--------|
| Parse `r,s,v` in-place (assembly) | `ThresholdSignature._tryRecoverAt` | Evita `new bytes(65)` + copia O(65) por firma |
| `ECDSA.tryRecover(hash,v,r,s)` | Threshold engine | Sin alloc intermedio de `bytes` signature |
| Transient reentrancy (`tstore`) | `CustodyVault` | Sin SSTORE del guard clásico |
| Custom errors | `CustodyErrors` | vs `require` strings |
| CEI (nonce/spend antes del call) | exec paths | Menos rollback / patrón Safe-like |
| EIP-712 OZ cached domain | `EIP712` | Domain separator immutable-cache |
| `mapping(address=>bool)` owners | Vault | Lookup O(1) vs scan array en recover loop |
| `optimizer_runs = 10_000` + `via_ir` | `foundry.toml` | Inlining hot paths |

### Antes → después (threshold exact, test gas)

| Métrica | Pre-optim (copia bytes) | Post-assembly | Δ |
|---------|-------------------------|---------------|---|
| `testGas_execTransaction_ExactThreshold` | ~158 k (suite THRESH) | **120 011** | ≈ **−24 %** |
| `test_IsValidSignature_ExactThreshold` | ~73 k | **~38 k** | ≈ **−48 %** |

### Tradeoffs

- **`via_ir = true`:** OK en este módulo; compilación más lenta.
- **Loop de firmas:** gas ∝ número de firmas enviadas (validamos todas, no solo M). Preferir enviar exactamente M en prod.
- **Guard externo:** coste adicional de 2 CALLs si está seteado.
- **Under-limit** puede costar más que un ETH transfer quorum simple por SSTOREs de spending window.

---

## Referencias

- [`foundry.toml`](../foundry.toml)
- [`test/gas/CustodyVault.gas.t.sol`](../test/gas/CustodyVault.gas.t.sol)
- [`.gas-snapshot`](../.gas-snapshot)
- [SWC-AUDIT.md](./SWC-AUDIT.md)

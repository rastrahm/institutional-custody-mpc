# Gas optimization — Institutional Custody Vault

Regenerate:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge test --match-contract CustodyVaultGasTest --gas-report
forge snapshot --match-contract CustodyVaultGasTest
```

**Baseline date:** 2026-09-15 (SOLV phase / v1 close)  
**Snapshot:** `.gas-snapshot` (`test/gas/CustodyVault.gas.t.sol`)  
**Optimizer:** `optimizer_runs = 10_000`, `via_ir = true`, solc `0.8.24`, EVM Cancun  
**Suite:** `forge test` → **69 PASS**

---

## Operations baseline (snapshot)

| Path | Gas (snapshot) | Notes |
|------|----------------|-------|
| `testGas_execTransaction_ExactThreshold` | **120 011** | 2 M-of-N signatures + ping |
| `testGas_execTransaction_ExcessSignatures` | **129 725** | 3 signatures (excess OK) |
| `testGas_execTransaction_EthTransfer` | **105 293** | Quorum + ETH `.call` |
| `testGas_execTransactionUnderLimit` | **130 900** | 1 signature + spend window |
| `testGas_isValidSignature` | **37 698** | ERC-1271 view path |

### Gas report (vault functions)

| Function | Min | Avg | Median | Max |
|----------|-----|-----|--------|-----|
| `execTransaction` | 101 143 | 112 813 | 115 243 | 122 054 |
| `execTransactionUnderLimit` | 140 518 | 140 518 | 140 518 | 140 518 |
| `isValidSignature` | 14 478 | 14 478 | 14 478 | 14 478 |
| `getTransactionHash` | 1 466 | 1 472 | 1 472 | 1 478 |

> The **test** gas includes off-chain signature setup in the runner; the **gas-report** measures the on-chain call to the vault.

---

## Applied optimizations

| Technique | Where | Effect |
|-----------|-------|--------|
| In-place `r,s,v` parsing (assembly) | `ThresholdSignature._tryRecoverAt` | Avoids `new bytes(65)` + O(65) copy per signature |
| `ECDSA.tryRecover(hash,v,r,s)` | Threshold engine | No intermediate `bytes` signature allocation |
| Transient reentrancy (`tstore`) | `CustodyVault` | No SSTORE from the classic guard |
| Custom errors | `CustodyErrors` | vs `require` strings |
| CEI (nonce/spend before the call) | exec paths | Less rollback / Safe-like pattern |
| OZ EIP-712 cached domain | `EIP712` | Immutable-cached domain separator |
| `mapping(address=>bool)` owners | Vault | O(1) lookup vs array scan in the recover loop |
| `optimizer_runs = 10_000` + `via_ir` | `foundry.toml` | Hot path inlining |

### Before → after (exact threshold, test gas)

| Metric | Pre-optim (bytes copy) | Post-assembly | Δ |
|--------|------------------------|---------------|---|
| `testGas_execTransaction_ExactThreshold` | ~158 k (THRESH suite) | **120 011** | ≈ **−24 %** |
| `test_IsValidSignature_ExactThreshold` | ~73 k | **~38 k** | ≈ **−48 %** |

### Tradeoffs

- **`via_ir = true`:** fine for this module; slower compilation.
- **Signature loop:** gas ∝ number of signatures sent (we validate all of them, not just M). Prefer sending exactly M in production.
- **External guard:** additional cost of 2 CALLs if set.
- **Under-limit** can cost more than a simple quorum ETH transfer because of the spending window SSTOREs.

---

## References

- [`foundry.toml`](../foundry.toml)
- [`test/gas/CustodyVault.gas.t.sol`](../test/gas/CustodyVault.gas.t.sol)
- [`.gas-snapshot`](../.gas-snapshot)
- [SWC-AUDIT-EN.md](./SWC-AUDIT-EN.md)

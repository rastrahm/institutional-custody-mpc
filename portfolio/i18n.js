const I18N = {
  es: {
    'html.lang': 'es',
    'meta.title': 'Institutional Custody · Multisig & MPC — Rolando Strahm',
    'meta.description':
      'Vault de custodia institucional M-of-N (EIP-712), ERC-1271, daily spending limits, guards y recovery timelock. Foundry · Solidity 0.8.24 · SWC.',

    'nav.overview': 'Proyecto',
    'nav.pillars': 'Pilares',
    'nav.gas': 'Gas',
    'nav.swc': 'SWC',
    'nav.process': 'Proceso',
    'nav.attacks': 'Defensa',
    'nav.repos': 'Repos',
    'nav.close': '← Cerrar',

    'hero.tag': '// MÓDULO 20 · PORTFOLIO WEB3',
    'hero.title': 'INSTITUTIONAL CUSTODY<br>MULTISIG &amp; MPC',
    'hero.role': 'Solidity 0.8.24 · Foundry · EIP-712 · ERC-1271 · SWC',
    'hero.sub':
      'Vault M-of-N con firmas EIP-712, ERC-1271, límites diarios, guards pluggable y timelock de recovery — gas documentado y auditoría SWC-100–136.',
    'hero.cta1': 'Ver en GitHub',
    'hero.cta2': 'Ver en GitLab',

    'ov.eyebrow': '// 01 — CONTEXTO',
    'ov.title': 'Por qué este proyecto',
    'ov.lead':
      'La custodia institucional no es una EOA: exige <strong>consenso M-of-N</strong>, validación on-chain de firmas (EIP-712 / ERC-1271), <strong>límites operativos</strong> y rotación de keys con delay. Este módulo construye ese vault con Foundry y cierra con <strong>gas</strong>, <strong>fuzz/invariantes</strong> y <strong>matriz SWC</strong>.',

    'pi.eyebrow': '// 02 — TRES PILARES',
    'pi.title': 'Qué entrega el módulo',
    'p1.num': '// PILAR_01',
    'p1.title': 'Threshold + EIP-712',
    'p1.desc':
      'CustodyVault ejecuta calls con firmas M-of-N ordenadas sobre typed data; anti-duplicado y replay por nonce.',
    'p1.l1': 'InvalidThresholdSignature',
    'p1.l2': 'Unsorted / Duplicate reject',
    'p1.l3': 'ETH vía .call + CEI',
    'p2.num': '// PILAR_02',
    'p2.title': 'ERC-1271 + spending',
    'p2.desc':
      'isValidSignature para dApps; path under-limit con 1 owner y cap diario rolling (1d); quorum bypassea el límite.',
    'p2.l1': 'Magic 0x1626ba7e',
    'p2.l2': 'DailyLimitExceeded',
    'p2.l3': 'Fuzz ventana 1000 runs',
    'p3.num': '// PILAR_03',
    'p3.title': 'Guards + Timelock + SWC',
    'p3.desc':
      'Guards pre/post, recovery timelock para owners/threshold, gas snapshot y auditoría SWC-100–136 con 0 vulnerables.',
    'p3.l1': 'GuardRejected · self-call setGuard',
    'p3.l2': '69 tests (unit/fuzz/invariant)',
    'p3.l3': '0 SWC vulnerables',

    'gas.eyebrow': '// 03 — OPTIMIZACIÓN DE GAS',
    'gas.title': 'Hot paths medidos',
    'gas.lead':
      'Fase <strong>SOLV</strong>: baseline en <code>.gas-snapshot</code> y tradeoffs en <code>doc/GAS-ES.md</code>. Parse <code>r,s,v</code> in-place en ThresholdSignature evita allocs por firma.',
    'gas.th1': 'Optimización / path',
    'gas.th2': 'Tradeoff / efecto',
    'gas.r1a': 'Assembly r,s,v in-place',
    'gas.r1b': '≈−24% exec threshold · ≈−48% ERC-1271 vs copia bytes',
    'gas.r2a': 'ReentrancyGuardTransient',
    'gas.r2b': 'Guard con tstore Cancun; sin SSTORE del guard clásico',
    'gas.r3a': 'Custom errors (CustodyErrors)',
    'gas.r3b': 'Reverts compactos vs require con strings',
    'gas.r4a': 'mapping isOwner O(1)',
    'gas.r4b': 'Lookup por recover sin escanear array en el loop',
    'gas.r5a': 'exec exact ≈ 120k · excess ≈ 130k',
    'gas.r5b': 'Gas ∝ firmas enviadas (se validan todas)',
    'gas.r6a': 'under-limit ≈ 131k · ERC-1271 ≈ 38k',
    'gas.r6b': 'Spend SSTOREs vs view path de magic value',
    'gas.r7a': 'optimizer_runs 10_000 + via_ir',
    'gas.r7b': 'Inlining de hot paths; solc 0.8.24 Cancun',

    'swc.eyebrow': '// 04 — VERIFICACIÓN SWC',
    'swc.title': 'SWC Registry · EIP-1470',
    'swc.lead':
      'Matriz completa <strong>SWC-100 → SWC-136</strong> contra el vault de custodia. Informe en <code>doc/SWC-AUDIT-ES.md</code> (estilo módulo 19). Conclusión: <strong>0 vulnerabilidades explotables</strong>.',
    'swc.s1': 'Mitigados / N/A',
    'swc.s2': 'Informativos (diseño)',
    'swc.s3': 'Vulnerables',
    'swc.th1': 'SWC clave',
    'swc.th2': 'Mitigación en el protocolo',
    'swc.r104': 'ETH .call con success capturado; salida solo con firmas válidas',
    'swc.r107': 'Reentrancy: CEI + ReentrancyGuardTransient en exec paths',
    'swc.r117': 'ECDSA OZ (anti-malleability) + isOwner + threshold',
    'swc.r121': 'Replay: nonce EIP-712 + sorting anti-dup',
    'swc.r123': 'Requirement: InvalidThreshold / DailyLimit / GuardRejected / Timelock*',
    'swc.r116': 'Timestamp: ventana daily + eta timelock; fuzz de fronteras',
    'swc.info': 'INFORMATIVO',
    'swc.i1t': 'Guard griefing',
    'swc.i1d':
      'Un guard malicioso puede revertir post-exec. Mitigación: setGuard solo vía multisig self-call; trust en el módulo.',
    'swc.i2t': 'Compromiso de umbral',
    'swc.i2d':
      '≥M keys drenan el vault (quorum bypassea daily limit). MPC/HSM off-chain; timelock para rotar keys.',

    'pr.eyebrow': '// 05 — PROCESO',
    'pr.title': 'Fases por dominio',
    'pr.lead':
      'Gates de autorización por dominio custody: scaffold → threshold → ERC-1271 → spending → guards → timelock → solvencia.',
    'ph.1': 'Scaffold Foundry + interfaces',
    'ph.2': 'Vault EIP-712 + M-of-N',
    'ph.3': 'isValidSignature',
    'ph.4': 'Daily spending limit',
    'ph.5': 'Guards pre/post',
    'ph.6': 'Recovery Timelock',
    'ph.7': 'Fuzz + SWC + gas',
    'st.1': 'Fases',
    'st.2': 'Tests PASS',
    'st.3': 'SWC críticos',
    'st.4': 'Campañas def.',

    'term.label': 'rolando@strahm:~/20-institutional-custody-mpc',
    'term.1': 'forge test',
    'term.2': '[PASS] suite · 69 passed',
    'term.3': 'cat doc/SWC-AUDIT-ES.md | head',
    'term.4': 'Vulnerable: 0 · Informativos: 5 · Mitigados/N/A: 31',
    'term.5': 'echo status',
    'term.6': 'MODULE_20_CLOSED · BOOT→SOLV_OK',

    'at.eyebrow': '// 06 — CAMPAÑAS DEFENSIVAS',
    'at.title': 'Custody que debe fallar',
    'at.lead':
      'Cada campaña es un suite Foundry donde el “ataque” (firmas unsorted, over-spend, guard reject, early timelock) debe revertir. Sin PoCs ofensivos: integridad del vault.',
    'cA.t': 'Threshold',
    'cA.d': 'Unsorted / dup / non-signer / under-M → revert.',
    'cB.t': 'Replay',
    'cB.d': 'Mismas firmas tras nonce++ fallan.',
    'cC.t': 'Spending',
    'cC.d': 'Over daily cap → DailyLimitExceeded; fuzz ventana.',
    'cD.t': 'Guards',
    'cD.d': 'Pre/post reject → GuardRejected; nonce intacto en pre.',
    'cE.t': 'Timelock',
    'cE.d': 'Early / expired / wrong data → Timelock* / Unauthorized.',

    're.eyebrow': '// 07 — CÓDIGO ABIERTO',
    're.title': 'Repositorios',
    're.lead':
      'El mismo código está publicado en GitHub y GitLab. Contratos, tests, fases, auditoría SWC y gas snapshot.',
    're.cta': 'Contactar',
    're.linkedin': 'LinkedIn',

    'ft.left': 'ROLANDO STRAHM — CUSTODY · MULTISIG · MPC · Portfolio',
    'ft.right': 'FOUNDRY · SOLC 0.8.24 · ALL_SYSTEMS_OPERATIONAL',
  },

  en: {
    'html.lang': 'en',
    'meta.title': 'Institutional Custody · Multisig & MPC — Rolando Strahm',
    'meta.description':
      'Institutional M-of-N custody vault (EIP-712), ERC-1271, daily spending limits, pluggable guards, and recovery timelock. Foundry · Solidity 0.8.24 · SWC.',

    'nav.overview': 'Project',
    'nav.pillars': 'Pillars',
    'nav.gas': 'Gas',
    'nav.swc': 'SWC',
    'nav.process': 'Process',
    'nav.attacks': 'Defense',
    'nav.repos': 'Repos',
    'nav.close': '← Close',

    'hero.tag': '// MODULE 20 · WEB3 PORTFOLIO',
    'hero.title': 'INSTITUTIONAL CUSTODY<br>MULTISIG &amp; MPC',
    'hero.role': 'Solidity 0.8.24 · Foundry · EIP-712 · ERC-1271 · SWC',
    'hero.sub':
      'M-of-N vault with EIP-712 signatures, ERC-1271, daily limits, pluggable guards, and recovery timelock — documented gas and a full SWC-100–136 audit.',
    'hero.cta1': 'View on GitHub',
    'hero.cta2': 'View on GitLab',

    'ov.eyebrow': '// 01 — CONTEXT',
    'ov.title': 'Why this project',
    'ov.lead':
      'Institutional custody is not an EOA: it needs <strong>M-of-N consensus</strong>, on-chain signature checks (EIP-712 / ERC-1271), <strong>operational spend caps</strong>, and delayed key rotation. This module builds that vault with Foundry and closes with <strong>gas</strong>, <strong>fuzz/invariants</strong>, and an <strong>SWC matrix</strong>.',

    'pi.eyebrow': '// 02 — THREE PILLARS',
    'pi.title': 'What the module ships',
    'p1.num': '// PILLAR_01',
    'p1.title': 'Threshold + EIP-712',
    'p1.desc':
      'CustodyVault executes calls with sorted M-of-N signatures over typed data; anti-duplicate and nonce-based replay protection.',
    'p1.l1': 'InvalidThresholdSignature',
    'p1.l2': 'Unsorted / Duplicate reject',
    'p1.l3': 'ETH via .call + CEI',
    'p2.num': '// PILLAR_02',
    'p2.title': 'ERC-1271 + spending',
    'p2.desc':
      'isValidSignature for dApps; under-limit path with one owner and a rolling 1-day cap; full quorum bypasses the limit.',
    'p2.l1': 'Magic 0x1626ba7e',
    'p2.l2': 'DailyLimitExceeded',
    'p2.l3': 'Window fuzz 1000 runs',
    'p3.num': '// PILLAR_03',
    'p3.title': 'Guards + Timelock + SWC',
    'p3.desc':
      'Pre/post guards, recovery timelock for owners/threshold, gas snapshot, and SWC-100–136 audit with 0 vulnerable findings.',
    'p3.l1': 'GuardRejected · self-call setGuard',
    'p3.l2': '69 tests (unit/fuzz/invariant)',
    'p3.l3': '0 vulnerable SWCs',

    'gas.eyebrow': '// 03 — GAS OPTIMIZATION',
    'gas.title': 'Measured hot paths',
    'gas.lead':
      '<strong>SOLV</strong> phase: baseline in <code>.gas-snapshot</code> and tradeoffs in <code>doc/GAS-EN.md</code>. In-place <code>r,s,v</code> parsing in ThresholdSignature avoids per-signature allocations.',
    'gas.th1': 'Optimization / path',
    'gas.th2': 'Tradeoff / effect',
    'gas.r1a': 'In-place r,s,v assembly',
    'gas.r1b': '≈−24% exec threshold · ≈−48% ERC-1271 vs byte copies',
    'gas.r2a': 'ReentrancyGuardTransient',
    'gas.r2b': 'Cancun tstore guard; no classic guard SSTORE',
    'gas.r3a': 'Custom errors (CustodyErrors)',
    'gas.r3b': 'Compact reverts vs string requires',
    'gas.r4a': 'O(1) isOwner mapping',
    'gas.r4b': 'Recover lookup without scanning the owners array',
    'gas.r5a': 'exec exact ≈ 120k · excess ≈ 130k',
    'gas.r5b': 'Gas ∝ signatures submitted (all are validated)',
    'gas.r6a': 'under-limit ≈ 131k · ERC-1271 ≈ 38k',
    'gas.r6b': 'Spend SSTOREs vs magic-value view path',
    'gas.r7a': 'optimizer_runs 10_000 + via_ir',
    'gas.r7b': 'Hot-path inlining; solc 0.8.24 Cancun',

    'swc.eyebrow': '// 04 — SWC VERIFICATION',
    'swc.title': 'SWC Registry · EIP-1470',
    'swc.lead':
      'Full <strong>SWC-100 → SWC-136</strong> matrix against the custody vault. Report in <code>doc/SWC-AUDIT-EN.md</code> (module-19 style). Conclusion: <strong>0 exploitable vulnerabilities</strong>.',
    'swc.s1': 'Mitigated / N/A',
    'swc.s2': 'Informational (design)',
    'swc.s3': 'Vulnerable',
    'swc.th1': 'Key SWC',
    'swc.th2': 'Mitigation in the protocol',
    'swc.r104': 'ETH .call with captured success; outflow only with valid signatures',
    'swc.r107': 'Reentrancy: CEI + ReentrancyGuardTransient on exec paths',
    'swc.r117': 'OZ ECDSA (anti-malleability) + isOwner + threshold',
    'swc.r121': 'Replay: EIP-712 nonce + anti-dup sorting',
    'swc.r123': 'Requirement: InvalidThreshold / DailyLimit / GuardRejected / Timelock*',
    'swc.r116': 'Timestamp: daily window + timelock eta; boundary fuzz',
    'swc.info': 'INFORMATIONAL',
    'swc.i1t': 'Guard griefing',
    'swc.i1d':
      'A malicious guard can revert post-exec. Mitigation: setGuard only via multisig self-call; module trust.',
    'swc.i2t': 'Threshold compromise',
    'swc.i2d':
      '≥M keys drain the vault (quorum bypasses the daily limit). Off-chain MPC/HSM; timelock to rotate keys.',

    'pr.eyebrow': '// 05 — PROCESS',
    'pr.title': 'Domain phases',
    'pr.lead':
      'Authorization gates by custody domain: scaffold → threshold → ERC-1271 → spending → guards → timelock → solvency.',
    'ph.1': 'Foundry scaffold + interfaces',
    'ph.2': 'EIP-712 vault + M-of-N',
    'ph.3': 'isValidSignature',
    'ph.4': 'Daily spending limit',
    'ph.5': 'Pre/post guards',
    'ph.6': 'Recovery Timelock',
    'ph.7': 'Fuzz + SWC + gas',
    'st.1': 'Phases',
    'st.2': 'Tests PASS',
    'st.3': 'Critical SWCs',
    'st.4': 'Def. campaigns',

    'term.label': 'rolando@strahm:~/20-institutional-custody-mpc',
    'term.1': 'forge test',
    'term.2': '[PASS] suite · 69 passed',
    'term.3': 'cat doc/SWC-AUDIT-EN.md | head',
    'term.4': 'Vulnerable: 0 · Informational: 5 · Mitigated/N/A: 31',
    'term.5': 'echo status',
    'term.6': 'MODULE_20_CLOSED · BOOT→SOLV_OK',

    'at.eyebrow': '// 06 — DEFENSIVE CAMPAIGNS',
    'at.title': 'Custody that must fail',
    'at.lead':
      'Each campaign is a Foundry suite where the “attack” (unsorted sigs, over-spend, guard reject, early timelock) must revert. No offensive PoCs — vault integrity.',
    'cA.t': 'Threshold',
    'cA.d': 'Unsorted / dup / non-signer / under-M → revert.',
    'cB.t': 'Replay',
    'cB.d': 'Same signatures after nonce++ fail.',
    'cC.t': 'Spending',
    'cC.d': 'Over daily cap → DailyLimitExceeded; window fuzz.',
    'cD.t': 'Guards',
    'cD.d': 'Pre/post reject → GuardRejected; nonce intact on pre.',
    'cE.t': 'Timelock',
    'cE.d': 'Early / expired / wrong data → Timelock* / Unauthorized.',

    're.eyebrow': '// 07 — OPEN SOURCE',
    're.title': 'Repositories',
    're.lead':
      'The same codebase is published on GitHub and GitLab: contracts, tests, phases, SWC audit, and gas snapshot.',
    're.cta': 'Contact',
    're.linkedin': 'LinkedIn',

    'ft.left': 'ROLANDO STRAHM — CUSTODY · MULTISIG · MPC · Portfolio',
    'ft.right': 'FOUNDRY · SOLC 0.8.24 · ALL_SYSTEMS_OPERATIONAL',
  },
};

function setLanguage(lang) {
  const dict = I18N[lang] || I18N.es;
  document.documentElement.lang = dict['html.lang'];
  document.title = dict['meta.title'];

  const metaDesc = document.querySelector('meta[name="description"]');
  if (metaDesc && dict['meta.description']) {
    metaDesc.setAttribute('content', dict['meta.description']);
  }

  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    const val = dict[key];
    if (val == null) return;
    if (el.hasAttribute('data-i18n-html')) el.innerHTML = val;
    else el.textContent = val;
  });

  document.querySelectorAll('.lang-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });

  localStorage.setItem('custody-portfolio-lang', lang);

  const url = new URL(window.location.href);
  url.searchParams.set('lang', lang);
  history.replaceState(null, '', url);
}

function initI18n() {
  const params = new URLSearchParams(window.location.search);
  const fromQuery = params.get('lang');
  const saved = localStorage.getItem('custody-portfolio-lang');
  const preferred =
    (fromQuery === 'en' || fromQuery === 'es' ? fromQuery : null) ||
    saved ||
    (navigator.language?.startsWith('en') ? 'en' : 'es');

  setLanguage(preferred);

  document.querySelectorAll('.lang-btn').forEach((btn) => {
    btn.addEventListener('click', () => setLanguage(btn.dataset.lang));
  });
}

document.addEventListener('DOMContentLoaded', initI18n);

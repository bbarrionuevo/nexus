// Corre los tests del harness con EDR (motor de tests Solidity de Hardhat 3, cheatcodes compatibles con forge), en
// la EVM local: FFI apagado, sin RPC ni forks. Sirve donde forge no se puede instalar (la nube de Claude).
// Uso: node run_edr.js <clon> <salida.out.json> <fuzzRuns> <invRuns> <invDepth> [patrón de test|-] [semilla]
// LOGS=N muestra N líneas de log por test; una secuencia que rompe una invariante queda en seq_<Suite>.json.
const edr = require(require('path').join(__dirname, 'node_modules', '@nomicfoundation', 'edr'));
const fs = require('fs');
const [root, artFile, fuzzRuns, invRuns, invDepth, pattern, seed] = process.argv.slice(2);
const A = JSON.parse(fs.readFileSync(artFile, 'utf8'));
const all = Object.values(A).flat(); // aplana los grupos del .out.json (morpho/metamorpho/harness, o v2, etc.)
const suites = all.filter(a => a.id.source.startsWith('test/nexus/') && /Test$/.test(a.id.name) && a.contract.bytecode).map(a => a.id);
const big = (k, v) => typeof v === 'bigint' ? v.toString() : (v instanceof Uint8Array ? '0x' + Buffer.from(v).toString('hex') : v);
(async () => {
  const ctx = new edr.EdrContext();
  await ctx.registerSolidityTestRunnerFactory(edr.L1_CHAIN_TYPE, edr.l1SolidityTestRunnerFactory());
  const cfg = { projectRoot: root, hardfork: 'cancun', ffi: false,
    fuzz: { runs: +fuzzRuns, maxTestRejects: 150000, ...(seed ? { seed } : {}) },
    invariant: { runs: +invRuns, depth: +invDepth, failOnRevert: false },
    ...(pattern && pattern !== '-' ? { testPattern: pattern } : {}) };
  const t0 = Date.now(); let pass = 0, fail = 0, skip = 0;
  await ctx.runSolidityTests(edr.L1_CHAIN_TYPE, all, suites, cfg, { buildInfos: [] }, s => {
    console.log(`\n== ${s.id.name} (${Number(s.durationNs / 1000000n) / 1000} s)`); for (const w of s.warnings) console.log('  aviso:', w);
    for (const t of s.testResults) {
      const k = t.kind; const kind = 'calls' in k ? `runs=${k.runs} calls=${k.calls} reverts=${k.reverts}` : ('runs' in k ? `runs=${k.runs}` : '');
      if (t.status === 'Success') pass++; else if (t.status === 'Failure') fail++; else skip++;
      console.log(`  ${t.status.padEnd(7)} ${t.name} ${kind}${t.reason ? '  motivo: ' + t.reason : ''}`);
      if (t.status === 'Failure' && t.counterexample) {
        const ce = t.counterexample;
        if (ce.sequence) { fs.writeFileSync(`seq_${s.id.name}.json`, JSON.stringify(ce.sequence.map(c => [c.signature, '0x' + Buffer.from(c.calldata).toString('hex')]), null, 0));
          console.log(`    secuencia (${ce.sequence.length} de ${ce.originalSequenceSize}):`); for (const c of ce.sequence) console.log('     ', c.signature, (c.args || '').replace(/\u001b\[[0-9;]*m/g, '').slice(0, 200)); }
        else console.log('    contraejemplo:', JSON.stringify(ce, big).replace(/\\u001b\[[0-9;]*m/g, '').slice(0, 3000)); }
      if (t.status === 'Failure' || /invariant/.test(t.name) || process.env.LOGS) for (const l of t.decodedLogs.slice(0, +(process.env.LOGS || 12))) console.log('    log:', l);
    }
  });
  console.log(`\nTOTAL ${pass} pasan · ${fail} fallan · ${skip} omitidos · ${(Date.now() - t0) / 1000} s`);
})().catch(e => { console.error('ERROR', e); process.exit(2); });

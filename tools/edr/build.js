// Compila un clon de MetaMorpho con el harness de nexus en test/nexus/, como forge: una versión de solc por grupo
// (Morpho 0.8.19, MetaMorpho 0.8.21, harness 0.8.26), via_ir, optimizer 200, evm paris (su foundry.toml).
// Uso: node build.js <clon> <salida.out.json> [unidad...]   unidades: morpho metamorpho harness
// MUTATION='{"file": "src/MetaMorpho.sol", "old": "...", "new": "..."}' compila con un defecto inyectado.
const path = require('path'), fs = require('fs');
const [root, outFile, ...only] = process.argv.slice(2);
const M = p => path.join(__dirname, 'node_modules', p);
const units = {
  morpho: { solc: M('solc8_19'), files: ['lib/morpho-blue/src/Morpho.sol'] },
  metamorpho: { solc: M('solc8_21'), files: ['src/MetaMorpho.sol'] },
  harness: { solc: M('solc8_26'), files: fs.readdirSync(path.join(root, 'test/nexus')).filter(f => f.endsWith('.t.sol')).map(f => 'test/nexus/' + f) },
};
const prev = fs.existsSync(outFile) ? JSON.parse(fs.readFileSync(outFile, 'utf8')) : {};
for (const [name, u] of Object.entries(units)) {
  if (only.length && !only.includes(name)) continue;
  const solc = require(u.solc);
  const sources = {};
  const mut = process.env.MUTATION ? JSON.parse(process.env.MUTATION) : null;
  const read = f => { let c = fs.readFileSync(path.join(root, f), 'utf8');
    if (mut && f === mut.file) { if (!c.includes(mut.old)) { console.log('mutación no aplica'); process.exit(3); } c = c.replace(mut.old, mut.new); }
    return c; };
  for (const f of u.files) sources[f] = { content: read(f) };
  const input = { language: 'Solidity', sources, settings: {
    remappings: ['forge-std/=lib/forge-std/src/'], optimizer: { enabled: true, runs: 200 }, viaIR: true,
    evmVersion: 'paris', metadata: { bytecodeHash: 'none' },
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.bytecode.linkReferences', 'evm.deployedBytecode.object', 'evm.deployedBytecode.linkReferences'] } } } };
  const t0 = Date.now();
  const out = JSON.parse(solc.compile(JSON.stringify(input), { import: p => {
    const full = path.join(root, p); return fs.existsSync(full) ? { contents: fs.readFileSync(full, 'utf8') } : { error: 'no existe ' + p }; } }));
  const errs = (out.errors || []).filter(e => e.severity === 'error');
  for (const e of errs) console.log(e.formattedMessage);
  if (errs.length) process.exit(1);
  const version = solc.version().split('+')[0];
  const arts = [];
  for (const [src, cs] of Object.entries(out.contracts || {}))
    for (const [cname, c] of Object.entries(cs))
      arts.push({ id: { name: cname, source: src, solcVersion: version }, contract: { abi: JSON.stringify(c.abi),
        bytecode: c.evm.bytecode.object, deployedBytecode: c.evm.deployedBytecode.object,
        linkReferences: c.evm.bytecode.linkReferences, deployedLinkReferences: c.evm.deployedBytecode.linkReferences } });
  prev[name] = arts;
  console.log(name, 'solc', version, arts.length, 'artefactos', (Date.now() - t0) / 1000, 's');
}
fs.writeFileSync(outFile, JSON.stringify(prev));

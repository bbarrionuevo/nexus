// Compila un clon de vault-v2 con el harness en test/nexus/, en una unidad (solc 0.8.28, via_ir, optimizer 100000,
// evm cancun). Uso: node build_v2.js <clon> <salida.out.json> [archivos .sol extra del harness...]
const path = require('path'), fs = require('fs');
const [root, outFile, ...extra] = process.argv.slice(2);
const solc = require(path.join(__dirname, 'node_modules', 'solc8_28'));
const harnessFiles = fs.readdirSync(path.join(root, 'test/nexus')).filter(f => f.endsWith('.sol')).map(f => 'test/nexus/' + f);
const roots = ['src/VaultV2.sol', 'src/VaultV2Factory.sol', 'test/mocks/AdapterMock.sol', 'test/mocks/ERC20Mock.sol', ...harnessFiles, ...extra];
const sources = {};
const mut = process.env.MUTATION ? JSON.parse(process.env.MUTATION) : null;
const seen = new Set();
function add(f) {
  if (seen.has(f)) return; seen.add(f);
  let c = fs.readFileSync(path.join(root, f), 'utf8');
  if (mut && f === mut.file) { if (!c.includes(mut.old)) { console.log('mutación no aplica'); process.exit(3); } c = c.replace(mut.old, mut.new); }
  sources[f] = { content: c };
}
roots.forEach(add);
const input = { language: 'Solidity', sources, settings: {
  remappings: ['forge-std/=lib/forge-std/src/', 'openzeppelin-contracts/=lib/openzeppelin-contracts/'],
  optimizer: { enabled: true, runs: 100000 }, viaIR: true, evmVersion: 'cancun', metadata: { bytecodeHash: 'none' },
  outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.bytecode.linkReferences', 'evm.deployedBytecode.object', 'evm.deployedBytecode.linkReferences'] } } } };
const t0 = Date.now();
const out = JSON.parse(solc.compile(JSON.stringify(input), { import: p => {
  // resuelve imports relativos y de lib/
  for (const base of [root, path.join(root, 'src'), path.join(root, 'test'), path.join(root, 'test/nexus')]) {
    const full = path.join(base, p); if (fs.existsSync(full)) return { contents: fs.readFileSync(full, 'utf8') };
  }
  const full = path.join(root, p); return fs.existsSync(full) ? { contents: fs.readFileSync(full, 'utf8') } : { error: 'no existe ' + p };
} }));
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
fs.writeFileSync(outFile, JSON.stringify({ v2: arts }));
console.log('v2 solc', version, arts.length, 'artefactos', (Date.now() - t0) / 1000, 's');

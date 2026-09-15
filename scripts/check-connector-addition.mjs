// Prove an implementation addition in an isolated tree, not by inferring
// extensibility from names or a successful test against an already-built core.
import {cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {checkComputeAssembly} from './connector-compute-bundles.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const git = args => {
  const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
  if (result.error || result.status !== 0) throw result.error ?? new Error('Cannot identify source revision');
  return result.stdout.trim();
};
const sourceHead = git(['rev-parse', 'HEAD']);
if (git(['status', '--porcelain', '--', 'src', 'moon.mod'])) {
  throw new Error('Commit product sources before the connector-addition check');
}
const isolated = mkdtempSync(join(tmpdir(), 'actql-connector-addition-'));
const allowed = path => path.startsWith('src/connectors/reference_compute/') ||
  path.startsWith('src/connectors_builtin/') || path.startsWith('src/query_integration/');
const omitted = new Set(['connectors_builtin', 'query_integration']);
cpSync(join(root, 'moon.mod'), join(isolated, 'moon.mod'));
mkdirSync(join(isolated, 'src'));
for (const name of readdirSync(join(root, 'src'))) {
  if (omitted.has(name)) continue;
  if (name === 'connectors') {
    mkdirSync(join(isolated, 'src/connectors'));
    for (const connector of readdirSync(join(root, 'src/connectors'))) {
      if (connector === 'reference_compute') continue;
      cpSync(join(root, 'src/connectors', connector), join(isolated, 'src/connectors', connector), {recursive: true});
    }
  } else {
    cpSync(join(root, 'src', name), join(isolated, 'src', name), {recursive: true});
  }
}

const hash = data => createHash('sha256').update(data).digest('hex');
function inventory(directory, prefix = '') {
  const result = new Map();
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    const name = prefix + entry.name;
    if (entry.isDirectory()) {
      for (const [path, digest] of inventory(join(directory, entry.name), name + '/')) result.set(path, digest);
    } else result.set(name, hash(readFileSync(join(directory, entry.name))));
  }
  return result;
}
function run(label, args) {
  console.log(JSON.stringify({phase: label, command: ['moon', ...args], isolated}));
  const result = spawnSync('moon', args, {
    cwd: isolated, env: process.env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  writeFileSync(join(isolated, label + '.log'), (result.stdout ?? '') + (result.stderr ?? ''));
  if (result.error || result.status !== 0) {
    process.stderr.write((result.stdout ?? '') + (result.stderr ?? ''));
    throw result.error ?? new Error(`${label} failed: ${result.status}`);
  }
  const totals = result.stdout.match(/Total tests: [^\n]+/g) ?? [];
  console.log(JSON.stringify({phase: label, success: true, totals}));
  return totals;
}

if (checkComputeAssembly(isolated, true) !== 2) throw new Error('Expected the declared two-implementation baseline');
if (existsSync(join(isolated, 'src/connectors/reference_compute'))) throw new Error('Third implementation leaked into baseline');
const before = inventory(join(isolated, 'src'), 'src/');
run('baseline-check', ['check', '--target', 'all', '--deny-warn']);

for (const path of ['src/connectors/reference_compute', 'src/query_integration']) {
  cpSync(join(root, path), join(isolated, path), {recursive: true});
}
if (checkComputeAssembly(isolated, true) !== 3) throw new Error('Third declaration was not assembled');
const after = inventory(join(isolated, 'src'), 'src/');
const changed = [...new Set([...before.keys(), ...after.keys()])].filter(path => before.get(path) !== after.get(path)).sort();
for (const path of changed) if (!allowed(path)) throw new Error(`Common implementation changed: ${path}`);
if (!changed.some(path => path.startsWith('src/connectors/reference_compute/'))) throw new Error('No independent connector added');
run('extended-check', ['check', '--target', 'all', '--deny-warn']);
const tests = {};
for (const target of ['js', 'wasm', 'native']) {
  tests[target] = run('third-' + target, ['test', '--target', target,
    'src/query_integration/installed_numeric_host_wbtest.mbt']);
  if (!tests[target].some(total => total === 'Total tests: 1, passed: 1, failed: 0.')) {
    throw new Error(`Independent connector test was not executed on ${target}`);
  }
}
const final = inventory(join(isolated, 'src'), 'src/');
for (const path of new Set([...before.keys(), ...final.keys()])) {
  if (!allowed(path) && final.get(path) !== before.get(path)) throw new Error(`Verification changed common source: ${path}`);
}
if (git(['rev-parse', 'HEAD']) !== sourceHead || git(['status', '--porcelain', '--', 'src', 'moon.mod'])) {
  throw new Error('Source state changed during verification; isolated evidence remains available');
}
const report = {
  sourceHead, environment: {platform: process.platform, arch: process.arch, node: process.version},
  isolated, unchangedFiles: [...before.keys()].filter(path => !allowed(path)).length,
  changed, tests,
};
writeFileSync(join(isolated, 'connector-addition.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({sourceHead: report.sourceHead, isolated,
  unchangedFiles: report.unchangedFiles, changedFiles: changed.length, tests}));
console.log('Independent connector addition verified; isolated sources and logs retained.');

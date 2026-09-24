// Prove an implementation addition in an isolated tree, not by inferring
// extensibility from names or a successful test against an already-built core.
import {cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {checkComputeAssembly} from './connector-compute-bundles.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const git = args => {
  const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
  if (result.error || result.status !== 0) throw result.error ?? new Error('Cannot identify source revision');
  return result.stdout.trim();
};
const sourceHead = git(['rev-parse', 'HEAD']);
const sourcePaths = ['src', 'adapters', 'scripts', 'moon.mod'];
if (git(['status', '--porcelain', '--', ...sourcePaths])) {
  throw new Error('Commit product sources and assembly checks before the connector-addition check');
}
const isolated = mkdtempSync(join(tmpdir(), 'actql-connector-addition-'));
const artifactDirectory = process.env.ACTQL_CONNECTOR_ADDITION_ARTIFACTS;
if (artifactDirectory) process.on('exit', code => {
  mkdirSync(artifactDirectory, {recursive:true});
  for (const file of readdirSync(isolated)) {
    if (/\.(?:log|json)$/.test(file)) cpSync(join(isolated,file),join(artifactDirectory,file));
  }
  writeFileSync(join(artifactDirectory,'execution.json'),JSON.stringify({sourceHead,exitCode:code,
    platform:process.platform,arch:process.arch,node:process.version},null,2)+'\n');
});
const allowed = path => path.startsWith('src/connectors/reference_compute/') ||
  path.startsWith('src/connectors_builtin/') || path.startsWith('src/connectors_builtin_node/') ||
  path.startsWith('src/query_integration/') || path.startsWith('src/connector_conformance/') ||
  path.startsWith('src/connectors/duckdb/conformance/') || path.startsWith('adapters/reference-compute-node/') ||
  path.startsWith('adapters/connectors-builtin/');
// The independent async Workers probe intentionally uses the third connector.
// It is a separate conformance composition, not part of the two-connector
// product baseline. Keep the Local-only Workers assembly in that baseline.
const omitted = new Set(['connectors_builtin', 'connectors_builtin_node',
  'query_integration', 'connector_conformance',
  'workers_conformance', 'node_host_conformance', 'connectors_workers_async', 'connectors_workers_async_bridge']);
cpSync(join(root, 'moon.mod'), join(isolated, 'moon.mod'));
cpSync(join(root, 'scripts/templates'), join(isolated, 'scripts/templates'), {recursive:true});
cpSync(join(root, 'adapters'), join(isolated, 'adapters'), {recursive:true,
  filter: path => !path.includes('/node_modules') && !path.includes('/reference-compute-node') && !path.includes('/connectors-builtin'),
});
symlinkSync(join(root, 'adapters/connectors/duckdb/node/node_modules'), join(isolated, 'adapters/connectors/duckdb/node/node_modules'), 'dir');
cpSync(join(root, 'spec'), join(isolated, 'spec'), {recursive:true});
mkdirSync(join(isolated, 'packages'), {recursive:true});
cpSync(join(root, 'packages/client-wire'),
  join(isolated, 'packages/client-wire'), {recursive:true});
mkdirSync(join(isolated, 'vendor/duckdb'), {recursive:true});
cpSync(join(root, 'vendor/duckdb/1.4.3'), join(isolated, 'vendor/duckdb/1.4.3'), {
  recursive: true,
});
mkdirSync(join(isolated, 'src'));
for (const name of readdirSync(join(root, 'src'))) {
  if (omitted.has(name)) continue;
  if (name === 'connectors') {
    mkdirSync(join(isolated, 'src/connectors'));
    for (const connector of readdirSync(join(root, 'src/connectors'))) {
      if (connector === 'reference_compute') continue;
      cpSync(join(root, 'src/connectors', connector),
        join(isolated, 'src/connectors', connector), {
          recursive: true,
          filter: path => connector !== 'duckdb' ||
            !path.includes('/duckdb/conformance'),
        });
    }
  } else {
    cpSync(join(root, 'src', name), join(isolated, 'src', name), {recursive: true});
  }
}
// Rebuild generated composition packages in isolation while retaining their
// handwritten common Carrier and execution-authorization adapters. Omitting
// the whole package silently changes managed execution semantics instead of
// testing connector addition.
for (const path of [
  'src/connectors_builtin/local_carrier_dispatch.mbt',
  'src/connectors_builtin_node/local_carrier_bridge.mbt',
  'src/connectors_builtin_node/authorization_bridge.mbt',
]) {
  mkdirSync(dirname(join(isolated, path)), {recursive: true});
  cpSync(join(root, path), join(isolated, path));
}

const hash = data => createHash('sha256').update(data).digest('hex');
function inventory(directory, prefix = '') {
  const result = new Map();
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    if (entry.isSymbolicLink()) continue;
    const name = prefix + entry.name;
    if (entry.isDirectory()) {
      for (const [path, digest] of inventory(join(directory, entry.name), name + '/')) result.set(path, digest);
    } else result.set(name, hash(readFileSync(join(directory, entry.name))));
  }
  return result;
}
function run(label, args, executable = 'moon') {
  console.log(JSON.stringify({phase: label, command: [executable, ...args], isolated}));
  const result = spawnSync(executable, args, {
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
checkNodeAssembly(isolated, true);
if (existsSync(join(isolated, 'src/connectors/reference_compute'))) throw new Error('Third implementation leaked into baseline');
const snapshot = () => new Map([...inventory(join(isolated, 'src'), 'src/'),
  ...inventory(join(isolated, 'adapters'), 'adapters/'), ...inventory(join(isolated, 'scripts/templates'), 'scripts/templates/')]);
const before = snapshot();
writeFileSync(join(isolated,'common-before.json'),JSON.stringify(
  Object.fromEntries([...before].filter(([path]) => !allowed(path))),null,2)+'\n');
run('baseline-check', ['check', '--target', 'all', '--deny-warn']);

for (const path of ['src/connectors/reference_compute', 'src/query_integration', 'src/connector_conformance', 'src/connectors/duckdb/conformance', 'adapters/reference-compute-node']) {
  cpSync(join(root, path), join(isolated, path), {recursive: true});
}
if (checkComputeAssembly(isolated, true) !== 3) throw new Error('Third declaration was not assembled');
checkNodeAssembly(isolated, true);
const after = snapshot();
const changed = [...new Set([...before.keys(), ...after.keys()])].filter(path => before.get(path) !== after.get(path)).sort();
for (const path of changed) if (!allowed(path)) throw new Error(`Common implementation changed: ${path}`);
if (!changed.some(path => path.startsWith('src/connectors/reference_compute/'))) throw new Error('No independent connector added');
run('extended-check', ['check', '--target', 'all', '--deny-warn']);
const tests = {};
for (const target of ['js', 'wasm', 'native']) {
  tests[target] = run('third-' + target, ['test', '--target', target,
    'src/query_integration/standard_subset_wbtest.mbt']);
  if (!tests[target].some(total => total === 'Total tests: 1, passed: 1, failed: 0.')) {
    throw new Error(`Independent connector test was not executed on ${target}`);
  }
}
tests.node = run('standard-node', ['--test', '--test-name-pattern=standard native and broad Node Hosts',
  'adapters/connectors/duckdb/node/test/standard-host.test.mjs'], process.execPath);
const final = snapshot();
writeFileSync(join(isolated,'common-after.json'),JSON.stringify(
  Object.fromEntries([...final].filter(([path]) => !allowed(path))),null,2)+'\n');
for (const path of new Set([...before.keys(), ...final.keys()])) {
  if (!allowed(path) && final.get(path) !== before.get(path)) throw new Error(`Verification changed common source: ${path}`);
}
if (git(['rev-parse', 'HEAD']) !== sourceHead || git(['status', '--porcelain', '--', ...sourcePaths])) {
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

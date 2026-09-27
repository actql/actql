// Build from this checkout, never from committed runtime output. Package users
// receive these files in the tarball and do not need MoonBit or install hooks.
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {occurrences, violations} from './check-owned-contract-versions.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const local = ['connectors_builtin_node', 'connectors/duckdb/host_node',
  'retained_host_bridge', 'process_host_bridge', 'checkpoint_runtime_node'];
const packages = {
  'run-host-core': {sources: ['client_values_host_abi'],
    script: 'build-run-host-core-package', args: ['--runtime-only'],
    files: ['packages/run-host-core/dist/client_values_host_abi.js']},
  'coordinator-core': {sources: ['remote_coordinator_abi'],
    script: 'build-remote-coordinator-package',
    files: ['packages/coordinator-core/dist/remote_coordinator_abi.js']},
  'transfer-core': {sources: ['remote_transfer_abi'],
    script: 'build-remote-transfer-package',
    files: ['packages/transfer-core/dist/remote_transfer_abi.js']},
  'local-node': {sources: local, script: 'build-local-node-assets',
    files: local.map(path => `packages/local-node/_build/js/release/build/${path}/${path.split('/').at(-1)}.js`)},
};
const requested = process.argv.slice(2);
for (const name of requested) {
  if (!Object.hasOwn(packages, name)) throw new Error(`Unknown runtime package: ${name}`);
}
const selected = new Set(requested.length ? requested : Object.keys(packages));
// Local adapters import the Run Host wrapper while discovering their graph.
if (selected.has('local-node')) selected.add('run-host-core');
const entries = [...selected].map(name => packages[name]);
execFileSync('moon', ['build', '--target', 'js', '--release',
  ...new Set(entries.flatMap(item => item.sources.map(path => `src/${path}`)))],
{cwd: root, stdio: 'inherit'});
for (const item of entries) {
  execFileSync(process.execPath, [`scripts/${item.script}.mjs`, ...(item.args ?? [])],
    {cwd: root, stdio: 'inherit'});
  // Tracked wrapper copies still have to match their source; preparation must
  // not repair them silently and hide a source/wrapper mismatch from CI.
  execFileSync(process.execPath, [`scripts/${item.script}.mjs`, '--check'],
    {cwd: root, stdio: 'inherit'});
}
const inventory = JSON.parse(readFileSync(join(root,
  'scripts/owned-contract-version-legacy.json'), 'utf8'));
const rejected = violations(entries.flatMap(item => item.files.flatMap(path =>
  occurrences(readFileSync(join(root, path), 'utf8'), path))), inventory);
if (rejected.length) throw new Error('Generated runtime contract versions must remain at 0.1:\n' +
  rejected.map(item => `${item.path}:${item.line}: ${item.token}`).join('\n'));

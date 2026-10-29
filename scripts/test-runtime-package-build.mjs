// Packaging must work when a checkout contains no prebuilt runtime bundles.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, rmSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {normalNpmPackJsonArgs, parseNpmPackJson} from './packed-client-packages.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
execFileSync(process.execPath, ['--test', 'scripts/build-runtime-packages.test.mjs'],
  {cwd: root, stdio: 'inherit'});
const expected = {
  'run-host-core': ['dist/client_values_host_abi.js',
    'dist/checkpoint_runtime_node.js', 'dist/workers_finite.js',
    'dist/workers_finite_payload.js'],
  'coordinator-core': ['dist/remote_coordinator_abi.js'],
  'transfer-core': ['dist/remote_transfer_abi.js'],
  'local-node': localNodePackageInputs(root).runtimeFiles
    .map(path => `_build/js/release/build/${path}`),
};
mkdirSync(join(root, '_build'), {recursive: true});
const destination = mkdtempSync(join(root, '_build/runtime-package-build-'));
for (const [name, paths] of Object.entries(expected)) {
  for (const path of paths) rmSync(join(root, 'packages', name, path), {force: true});
}
for (const [name, paths] of Object.entries(expected)) {
  const output = execFileSync('npm', normalNpmPackJsonArgs(['pack', '--json', '--pack-destination', destination]),
    {cwd: join(root, 'packages', name), encoding: 'utf8', timeout: 180000,
      maxBuffer: 16 * 1024 * 1024});
  const metadata = parseNpmPackJson(output);
  const pack = metadata[0] ?? metadata[`@actql/${name}`];
  for (const path of paths) {
    assert(pack.files.some(file => file.path === path && file.size > 0),
      `${name}: missing runtime payload ${path}`);
  }
}
console.log('All four runtime packages build and pack without prebuilt bundles.');

import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
test('Local package carries the finite optional Table worker and dependency pins', () => {
  // Exercise the actual adapter graph copier, not an independently implemented
  // packer. This prepares JS/assets only and does not pack or compile MoonBit.
  for (const args of [[], ['--check']]) {
    const result = spawnSync(process.execPath, ['scripts/build-local-node-adapters.mjs', ...args],
      {cwd: root, encoding: 'utf8', timeout: 30000});
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
  }
  const files = ['README.md', 'catalog.py', 'custody.py', 'physical.py',
    'process_worker.py', 'requirements.in', 'requirements.lock'];
  const destination = join(root, 'packages/local-node/adapters/table-iceberg');
  assert.deepEqual(readdirSync(destination).sort(), files);
  for (const name of files) {
    assert.ok(readFileSync(join(destination, name)).equals(
      readFileSync(join(root, 'adapters/table-iceberg', name))), name);
  }
  const worker = readFileSync(join(destination, 'process_worker.py'), 'utf8');
  assert.match(worker, /from catalog import/u);
  const requirements = readFileSync(join(destination, 'requirements.in'), 'utf8');
  assert.match(requirements, /^pyiceberg\[sql-sqlite\]==0\.10\.0$/mu);
  assert.match(requirements, /^pyarrow==21\.0\.0$/mu);
  const dependencies = JSON.parse(readFileSync(join(root, 'packages/local-node/package.json'))).dependencies;
  assert.deepEqual(Object.keys(dependencies).sort(), ['@actql/client-wire', '@actql/sdk']);
  const installed = readFileSync(join(root, 'packages/local-node/adapters/host-node/installed-table-installation.mjs'), 'utf8');
  assert.match(installed, /from '@actql\/sdk\/host-port'/u);
  assert.doesNotMatch(installed, /packages\/sdk/u);
});

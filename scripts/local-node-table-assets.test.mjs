import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync,
  symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
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
  const files = ['README.md', 'catalog.py', 'custody.py', 'manifest_read.py', 'physical.py',
    'process_worker.py', 'requirements.in', 'requirements.lock'];
  const destination = join(root, 'packages/local-node/adapters/connectors/local/iceberg');
  assert.deepEqual(readdirSync(destination).sort(), files);
  for (const name of files) {
    assert.ok(readFileSync(join(destination, name)).equals(
      readFileSync(join(root, 'adapters/connectors/local/iceberg', name))), name);
  }
  const worker = readFileSync(join(destination, 'process_worker.py'), 'utf8');
  assert.match(worker, /from catalog import/u);
  const requirements = readFileSync(join(destination, 'requirements.in'), 'utf8');
  assert.match(requirements, /^pyiceberg\[sql-sqlite\]==0\.10\.0$/mu);
  assert.match(requirements, /^pyarrow==21\.0\.0$/mu);
  const dependencies = JSON.parse(readFileSync(join(root, 'packages/local-node/package.json'))).dependencies;
  assert.deepEqual(Object.keys(dependencies).sort(), ['@actql/client-wire', '@actql/sdk']);
  const installed = readFileSync(join(root, 'packages/local-node/adapters/connectors/local/host/installed-local-table.mjs'), 'utf8');
  assert.match(installed, /from '@actql\/sdk\/host-port'/u);
  assert.doesNotMatch(installed, /packages\/sdk/u);
});

test('Local packing refuses a removed or undeclared Connector asset', () => {
  const stale = join(root, 'packages/local-node/src/connectors/github/undeclared-fixture.json');
  writeFileSync(stale, '{"fixture":"no-longer-declared"}\n', {flag: 'wx'});
  try {
    for (const args of [[], ['--check']]) {
      const result = spawnSync(process.execPath, ['scripts/build-local-node-adapters.mjs', ...args],
        {cwd: root, encoding: 'utf8', timeout: 30000});
      assert.ifError(result.error);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /StaleLocalNodeConnectorData:src\/connectors\/github\/undeclared-fixture.json/);
    }
  } finally {
    unlinkSync(stale);
  }
});

test('Local packing refuses a physical worker link before changing its target', () => {
  const outside = mkdtempSync(join(tmpdir(), 'local-worker-target-'));
  const sentinel = join(outside, 'process_worker.py');
  writeFileSync(sentinel, '# independent outside worker\n');
  const destination = join(root, 'packages/local-node/adapters/connectors/local/iceberg/process_worker.py');
  const backup = `${destination}.fixture-backup`;
  renameSync(destination, backup);
  try {
    symlinkSync(sentinel, destination);
    for (const args of [[], ['--check']]) {
      const result = spawnSync(process.execPath, ['scripts/build-local-node-adapters.mjs', ...args],
        {cwd: root, encoding: 'utf8', timeout: 30000});
      assert.ifError(result.error);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /StaleLocalNodeAdapter:adapters\/connectors\/local\/iceberg\/process_worker.py/);
      assert.equal(readFileSync(sentinel, 'utf8'), '# independent outside worker\n');
    }
  } finally {
    unlinkSync(destination);
    renameSync(backup, destination);
    rmSync(outside, {recursive: true});
  }
});

test('Local packing refuses destination links before changing any target', () => {
  const outside = mkdtempSync(join(tmpdir(), 'connector-data-target-'));
  const sentinel = join(outside, 'source-views.json');
  writeFileSync(sentinel, 'independent outside bytes\n');
  for (const directory of ['github', 'connectors/github']) {
    mkdirSync(join(outside, directory), {recursive: true});
    writeFileSync(join(outside, directory, 'source-views.json'), 'independent outside bytes\n');
  }
  try {
    for (const path of ['src/connectors/github/source-views.json', 'src/connectors', 'src']) {
      const destination = join(root, 'packages/local-node', path);
      const backup = `${destination}.fixture-backup`;
      renameSync(destination, backup);
      try {
        symlinkSync(path.endsWith('.json') ? sentinel : outside, destination);
        for (const args of [[], ['--check']]) {
          const result = spawnSync(process.execPath, ['scripts/build-local-node-adapters.mjs', ...args],
            {cwd: root, encoding: 'utf8', timeout: 30000});
          assert.ifError(result.error);
          assert.notEqual(result.status, 0);
          assert.match(result.stderr, /StaleLocalNodeConnectorData:/);
          for (const file of ['source-views.json', 'github/source-views.json',
            'connectors/github/source-views.json']) {
            assert.equal(readFileSync(join(outside, file), 'utf8'), 'independent outside bytes\n');
          }
        }
      } finally {
        unlinkSync(destination);
        renameSync(backup, destination);
      }
    }
  } finally {
    rmSync(outside, {recursive: true});
  }
});

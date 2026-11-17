import assert from 'node:assert/strict';
import test from 'node:test';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {nativeCliPublicSelection, nativeCliPublicInstallCommand, admitPublicCliLock} from './test-native-cli-public-install.mjs';

test('public Native consumer binds one original digest and a separate new receipt without registry overrides', () => {
  const root = join(tmpdir(), 'public-cli-selection'), rc = join(root, 'rc'), receipt = join(root, 'receipt.json');
  assert.deepEqual(nativeCliPublicSelection([rc, 'a'.repeat(64), receipt]), {directory: rc, manifestSha256: 'a'.repeat(64), receiptPath: receipt});
  for (const args of [[rc, 'changed', receipt], [rc, 'a'.repeat(64), join(rc, 'receipt.json')],
    [rc, 'a'.repeat(64), receipt, '--registry', 'https://foreign.invalid/'], ['relative', 'a'.repeat(64), receipt]]) {
    assert.throws(() => nativeCliPublicSelection(args));
  }
  assert.deepEqual(nativeCliPublicInstallCommand(), ['install', '--save-exact', '--ignore-scripts', '--engine-strict',
    '--no-audit', '--no-fund', '--registry', 'https://registry.npmjs.org/', 'actql@0.0.2']);
});

function fixture() {
  const manifest = {packages: ['@actql/cli-linux-x64-gnu', '@actql/cli-darwin-arm64', 'actql'].map(name =>
    ({name, version: '0.0.2', integrity: 'sha512-' + name}))};
  const lock = {lockfileVersion: 3, packages: {'': {dependencies: {actql: '0.0.2'}}, ...Object.fromEntries(manifest.packages.map(item =>
    ['node_modules/' + item.name, {version: item.version, integrity: item.integrity,
      resolved: 'https://registry.npmjs.org/' + item.name + '/-/fixture-0.0.2.tgz'}]))}};
  return {manifest, lock};
}

test('public Native lock requires the real entry and selected OS, permits only original optional OS metadata', () => {
  const {manifest, lock} = fixture();
  assert.equal(admitPublicCliLock(lock, manifest, 'linux-x64-gnu').length, 3);
  delete lock.packages['node_modules/@actql/cli-darwin-arm64'];
  assert.equal(admitPublicCliLock(lock, manifest, 'linux-x64-gnu').length, 2);
  delete lock.packages['node_modules/@actql/cli-linux-x64-gnu'];
  assert.throws(() => admitPublicCliLock(lock, manifest, 'linux-x64-gnu'));
});

test('public Native lock rejects foreign registry, changed SRI, links, extra dependencies and copied selection', () => {
  const mutations = [
    lock => {lock.packages['node_modules/actql'].resolved = 'https://foreign.invalid/actql.tgz';},
    lock => {lock.packages['node_modules/actql'].resolved += '?token=secret';},
    lock => {lock.packages['node_modules/actql'].integrity = 'sha512-other';},
    lock => {lock.packages['node_modules/actql'].link = true;},
    lock => {lock.packages['node_modules/extra'] = {};},
    lock => {lock.packages[''].dependencies = {actql: '^0.0.2'};},
    lock => {lock.packages['node_modules/actql/node_modules/@actql/cli-linux-x64-gnu'] = lock.packages['node_modules/@actql/cli-linux-x64-gnu'];},
  ];
  for (const mutate of mutations) {
    const {manifest, lock} = fixture(); mutate(lock);
    assert.throws(() => admitPublicCliLock(lock, manifest, 'linux-x64-gnu'));
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {releaseReadmeSelection, releaseReadmeEnvironment} from './test-package-release-readme.mjs';

test('release README consumer names one original cohort and a separate fresh receipt', () => {
  const root = join(tmpdir(), 'release-readme-selection');
  const rc = join(root, 'original'), receipt = join(root, 'new-receipt.json');
  assert.deepEqual(releaseReadmeSelection([rc, receipt]), {kind: 'private-loopback', directory: rc, receiptPath: receipt});
  assert.throws(() => releaseReadmeSelection([rc, 'relative.json']));
  assert.throws(() => releaseReadmeSelection([rc, join(rc, 'receipt.json')]));
  assert.throws(() => releaseReadmeSelection([rc, receipt, '--skip-files']));
});

test('release README public mode reuses exact original child and optional upper binding', () => {
  const root = join(tmpdir(), 'release-readme-public-selection');
  const rc = join(root, 'original'), receipt = join(root, 'receipt.json');
  const child = 'a'.repeat(64), upper = 'b'.repeat(64), fixed = join(root, 'fixed');
  const selected = releaseReadmeSelection([rc, receipt, '--public-registry', child,
    '--release-set', fixed, upper, '--target', 'node']);
  assert.equal(selected.kind, 'public-npm'); assert.equal(selected.manifestSha256, child);
  assert.deepEqual(selected.releaseSet, {directory: fixed, manifestSha256: upper, targetId: 'node'});
  assert.throws(() => releaseReadmeSelection([rc, receipt, '--public-registry', 'changed']));
  assert.throws(() => releaseReadmeSelection([rc, receipt, '--public-registry', child,
    '--release-set', fixed, 'changed', '--target', 'node']));
});

test('both registry modes strip publisher credentials and source/compiler injections', () => {
  const root = join(tmpdir(), 'release-readme-environment');
  for (const registry of ['https://registry.npmjs.org/', 'http://127.0.0.1:12345/']) {
    const env = releaseReadmeEnvironment({LANG: 'C', PATH: '/unrelated/compiler',
      NPM_TOKEN: 'publisher-only', NODE_AUTH_TOKEN: 'publisher-only', GH_TOKEN: 'publisher-only',
      NODE_OPTIONS: '--require changed.cjs', NODE_PATH: '/unrelated/modules',
      MOON_HOME: '/unrelated/compiler', ACTQL_LOCAL_SOURCE_PROFILE: '/unrelated/source',
      npm_config_userconfig: '/unrelated/npmrc', HTTPS_PROXY: 'http://unrelated/'}, root, process.execPath, registry);
    for (const key of ['NPM_TOKEN', 'NODE_AUTH_TOKEN', 'GH_TOKEN', 'NODE_OPTIONS', 'NODE_PATH',
      'MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE', 'HTTPS_PROXY']) assert.equal(Object.hasOwn(env, key), false);
    assert.equal(env.npm_config_registry, registry); assert.equal(env.HOME, join(root, 'home'));
    assert.equal(env.npm_config_userconfig, join(root, 'npmrc'));
    assert(!env.PATH.includes('/unrelated/')); assert.equal(env.LANG, 'C');
  }
});

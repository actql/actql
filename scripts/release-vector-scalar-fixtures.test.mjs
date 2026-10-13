import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {releaseVectorScalarFixturePaths, releaseVectorScalarEnvironment} from './release-vector-scalar-fixtures.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
function closure(paths) {
  const delivered = new Set(paths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-vector-scalar-worker.mjs')];
  const seen = new Set(), missing = [];
  while (pending.length) {
    const path = pending.pop(); if (seen.has(path)) continue; seen.add(path);
    if (!delivered.has(path)) { missing.push(path); continue; }
    for (const match of readFileSync(path, 'utf8').matchAll(
      /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
      pending.push(resolve(dirname(path), match[2]));
    }
  }
  return {seen, missing};
}
test('normal release Vector worker has a complete test-only relative import closure', () => {
  const actual = closure(releaseVectorScalarFixturePaths);
  assert.deepEqual(actual.missing, []);
  assert.equal(actual.seen.size, 8);
  assert.ok(actual.seen.has(resolve(root, 'scripts/fixtures/vector-scalar-installed-source.mjs')));
  assert.ok(actual.seen.has(resolve(root, 'scripts/fixtures/public-query-input.mjs')));
});
test('normal release closure rejects a missing installed Source supplier before consumer execution', () => {
  const missing = closure(releaseVectorScalarFixturePaths.filter(path =>
    path !== 'scripts/fixtures/vector-scalar-installed-source.mjs'));
  assert.deepEqual(missing.missing, [resolve(root, 'scripts/fixtures/vector-scalar-installed-source.mjs')]);
});
test('normal release entry and prepared recipe parse without running a producer or consumer', () => {
  for (const path of ['scripts/test-package-release-vector-scalar.mjs',
    'scripts/fixtures/release-vector-scalar-worker.mjs',
    'reviews/2026-10-13-vector-scalar-installed-source/prepared-release-public.mjs']) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});
test('release consumer cannot inherit checkout loaders runtime paths or another selected corpus', () => {
  const base = {NODE_PATH: '/checkout/modules', NODE_OPTIONS: '--import=/checkout/overlay.mjs',
    MOON_HOME: '/checkout/toolchain', MOON_EXPERIMENTAL_CORE_OVERRIDE: '/checkout/core',
    ACTQL_LOCAL_SOURCE_PROFILE: '/checkout/source.json', ACTQL_PACKED_CLIENT_PACKAGES: '/old/cohort',
    ACTQL_TEST_QUERY_TRANSPORT: 'wrong', ACTQL_TEST_PRESERVE_SCRATCH: '1', PATH: '/checkout/bin',
    npm_config_registry: 'https://wrong.invalid', harmless: 'retained'};
  const before = {...base};
  const env = releaseVectorScalarEnvironment(base, {registry: 'http://127.0.0.1:1234/',
    root: '/private/tmp/consumer', node: '/pinned/node/bin/node'});
  assert.deepEqual(base, before);
  assert.equal(env.PATH, '/pinned/node/bin:/usr/bin:/bin:/usr/sbin:/sbin');
  assert.equal(env.npm_config_registry, 'http://127.0.0.1:1234/');
  assert.equal(env.npm_config_cache, '/private/tmp/consumer/npm-cache');
  assert.equal(env.harmless, 'retained');
  for (const key of Object.keys(base).filter(key => key.startsWith('ACTQL_') || key.startsWith('MOON_') ||
    ['MOON_HOME', 'NODE_PATH', 'NODE_OPTIONS'].includes(key))) assert.equal(Object.hasOwn(env, key), false);
});

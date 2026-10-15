import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
const fixture = fileURLToPath(new URL('./infer-trusted-node-startup.fixture.mjs', import.meta.url));
const preceding = fileURLToPath(new URL('./infer-prior-pool-mutation.fixture.cjs', import.meta.url));
function child(args, mode, extra = {}) {
  // No inherited Node loader/allocator selection or credentials enter this
  // isolated startup. This does not exercise a live Provider or stock grant.
  const result = spawnSync(process.execPath, [...args, fixture, mode], {
    env: {PATH: process.env.PATH, ...extra}, timeout: 10000, encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {mode, checked: true,
    providerCalls: 0, physicalAcks: 0, coreScopes: 0, normalNumericProfile: null, publicE2E: 0});
}

test('late ordinary embedded import cannot issue stock-startup responsibility', () => child([], 'absent'));
test('selected real Node preload retains exact Host and borrowed Scope reference originals', () =>
  child(['--require', preload], 'selected'));
test('selected startup excludes pool/allocator replacement and retains invalidation through restoration', () =>
  child(['--require', preload], 'mutation'));
test('prior preload with a larger historical slab is refused despite restored visible poolSize', () =>
  child(['--require', preceding, '--require', preload], 'absent'));
test('NODE_OPTIONS preload cannot supply the selected original startup', () =>
  child(['--require', preload], 'absent', {NODE_OPTIONS: `--require=${preceding}`}));

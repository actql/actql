import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
const fixture = fileURLToPath(new URL('../../packages/provider-ai-sdk/sdk-static-startup.fixture.mjs', import.meta.url));
const unselected = fileURLToPath(new URL('./infer-trusted-sdk-eager.fixture.mjs', import.meta.url));
const preceding = fileURLToPath(new URL('./infer-prior-pool-mutation.fixture.cjs', import.meta.url));
const eager = ['--no-lazy', '--require', preload];
function child(args, mode, entry = fixture, extra = {}) {
  // Isolated synthetic environment, never an operator credential/env rewrite.
  const result = spawnSync(process.execPath, [...args, entry, mode], {
    env: {PATH: process.env.PATH, ...extra}, encoding: 'utf8', timeout: 10000,
    maxBuffer: 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  return result;
}
function checked(args, mode, entry) {
  const result = child(args, mode, entry);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {mode, checked: true,
    providerCalls: 0, physicalAcks: 0, actualCore: false,
    normalNumericProfile: null, publicE2E: 0});
}

test('exact early eager recipe binds same SDK instances and original Host/Scope lifetime', () =>
  checked(eager, 'eager-current'));
test('old two-argument recipe retains static duty without acquiring eager duty from later flags', () =>
  checked(['--require', preload], 'eager-old-recipe'));
test('late flags cannot reconstruct eager startup history', () =>
  checked([], 'eager-late-flags'));
test('eager flag without real early preload is unavailable', () =>
  checked(['--no-lazy'], 'eager-absent'));
test('early eager preload cannot adopt an SDK imported later from another resolution scope', () =>
  checked(eager, 'eager-unselected-sdk', unselected));
for (const [name, args] of [
  ['reordered recipe', ['--require', preload, '--no-lazy']],
  ['extra flag', ['--no-lazy', '--no-warnings', '--require', preload]],
  ['prior preload', ['--require', preceding, ...eager]],
]) {
  test(`${name} cannot issue the exact eager startup original`, () => checked(args, 'eager-absent'));
}
test('NODE_OPTIONS cannot supply eager recipe provenance', () => {
  const result = child(eager, 'eager-absent', fixture, {NODE_OPTIONS: `--require=${preceding}`});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout.trim()).mode, 'eager-absent');
});
for (const value of ['', 'synthetic-unsupported-eager-input']) {
  test(`eager startup refuses ${value === '' ? 'empty' : 'nonempty'} ambient SDK input before entry`, () => {
    const result = child(eager, 'entry-unreachable', fixture, {OPENAI_BASE_URL: value});
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /InferTrustedStartupUnavailable/u);
    assert.equal(result.stderr.includes('synthetic-unsupported-eager-input'), false);
  });
}

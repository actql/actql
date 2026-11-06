import assert from 'node:assert/strict';
import {test} from 'node:test';
import {nativeCliCompileBudget, nativeLocalCompilerArguments} from './native-cli-artifact.mjs';

test('Local artifact compiler selection preserves the actual platform and SDK boundary', () => {
  assert.deepEqual(nativeLocalCompilerArguments('linux-x64-gnu', {clang: '/selected/clang'}),
    ['--clang', '/selected/clang', '--target', 'linux-x64']);
  assert.deepEqual(nativeLocalCompilerArguments('darwin-arm64', {clang: '/selected/clang', sdk: '/selected/sdk'}),
    ['--clang', '/selected/clang', '--sdk', '/selected/sdk', '--target', 'darwin-arm64']);
  for (const [platform, options] of [
    ['linux-x64', {clang: '/clang'}], ['linux-arm64-gnu', {clang: '/clang'}],
    ['linux-x64-gnu', {clang: '/clang', sdk: '/sdk'}],
    ['darwin-arm64', {clang: '/clang'}], ['linux-x64-gnu', {clang: 'clang'}],
  ]) assert.throws(() => nativeLocalCompilerArguments(platform, options));
});

test('default Native compilation budgets keep the existing selected deadlines', () => {
  assert.deepEqual(nativeCliCompileBudget(undefined), {seconds: 300, timeoutMs: 300000});
  assert.deepEqual(nativeCliCompileBudget(undefined, true), {seconds: 900, timeoutMs: 930000});
});

test('an explicit finite optimized compile budget reaches both scoped and outer deadlines', () => {
  assert.deepEqual(nativeCliCompileBudget(7200, true), {seconds: 7200, timeoutMs: 7230000});
  assert.deepEqual(nativeCliCompileBudget(7200), {seconds: 7200, timeoutMs: 7200000});
  assert.deepEqual(nativeCliCompileBudget(1, true), {seconds: 1, timeoutMs: 31000});
  assert.deepEqual(nativeCliCompileBudget(86400, true), {seconds: 86400, timeoutMs: 86430000});
});

test('invalid or unbounded compile budgets refuse instead of falling back', () => {
  for (const value of [null, false, '7200', 0, -1, 1.5, NaN, Infinity, 86401, Number.MAX_SAFE_INTEGER]) {
    assert.throws(() => nativeCliCompileBudget(value));
    assert.throws(() => nativeCliCompileBudget(value, true));
  }
  assert.throws(() => nativeCliCompileBudget(7200, 'scoped'));
});

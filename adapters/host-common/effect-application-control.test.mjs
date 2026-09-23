import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';

const effect = runtimeCore(moon).effectApplicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

test('standard Host bridge uses the portable logical Effect identities', () => {
  const scope = effect.logicalRequestScope(cid('a'), 'request-1', 32);
  assert.equal(effect.logicalRequestScopeCid(scope),
    'sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3');
  const key = effect.dispatchKey(scope, cid('b'), '"row-1"', 32, 8, 3);
  assert.equal(effect.dispatchKeyCid(key),
    'sha256:753d888dba41f4ce14250676698394baa4a7a84c73eb301b35a86fc406de1e72');
  assert.equal(effect.recoveryAction(key, cid('c'), '', '', -1, false), 0);
  assert.equal(effect.recoveryAction(key, cid('c'), effect.dispatchKeyCid(key),
    cid('c'), 1, false), 3);
  assert.equal(effect.recoveryAction(key, cid('d'), effect.dispatchKeyCid(key),
    cid('c'), 2, false), 8);
});

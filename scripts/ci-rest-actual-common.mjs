// Selected compiled-boundary controls, using the Host job's already-built
// original Common namespace. Canned page ports are a separate test selection.
import assert from 'node:assert/strict';
import {isAbsolute, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runFocusedTests} from './test-execution.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

export function runRestActualCommon({env = process.env, run = runFocusedTests} = {}) {
  assert(typeof env.ACTQL_METADATA_COMMON_RUNTIME === 'string' &&
    isAbsolute(env.ACTQL_METADATA_COMMON_RUNTIME),
  'Select the original prepared Host Common through ACTQL_METADATA_COMMON_RUNTIME');
  return run('node', ['--test-name-pattern',
    '^REST actual (?:Common|checked GET capacity preserves original reference Options$)',
    'adapters/host-node/rest-source-page-typed.test.mjs'],
  {cwd: root, env, expectedTests: 4, timeout: 120000});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 2, 'ci-rest-actual-common.mjs accepts no selection overrides');
  process.exitCode = runRestActualCommon();
}

import assert from 'node:assert/strict';
import {isAbsolute} from 'node:path';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, directory, python, scope, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0); assert.equal(process.version, 'v22.22.0');
assert([directory, python, scope].every(isAbsolute));
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert(before.clean);
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: true, timeoutSeconds: 300,
  graceSeconds: 5, steps: [{name: 'Normal installed real DuckDB + GCS -> approved Local Iceberg and separate Host recovery',
    command: process.execPath, args: ['scripts/test-real-cross-connector-release.mjs',
      source, directory, python, scope], env: {ACTQL_TEST_PRESERVE_SCRATCH: '1'}}]});
assert.deepEqual(checkoutState(process.cwd()), before);

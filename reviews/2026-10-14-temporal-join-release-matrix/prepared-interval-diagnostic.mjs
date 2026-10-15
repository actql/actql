import assert from 'node:assert/strict';
import {isAbsolute} from 'node:path';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, ...args] = process.argv.slice(2);
assert.equal(args.length, 3); assert(args.every(isAbsolute));
const before = checkoutState(process.cwd());
assert.equal(before.clean, true); assert.equal(before.revision, source);
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: true,
  timeoutSeconds: 300, graceSeconds: 5, steps: [{
    name: 'One fresh original SQL interval-left safe installed Host observation',
    command: process.execPath,
    args: ['reviews/2026-10-14-temporal-join-release-matrix/one-interval-diagnostic.mjs', ...args],
  }]});
assert.deepEqual(checkoutState(process.cwd()), before);

// Preparation only; the coordinator allocates the original shared window.
import assert from 'node:assert/strict';
import {isAbsolute, relative, resolve} from 'node:path';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [mode, source, directory, receipt, ...extra] = process.argv.slice(2);
assert.ok(['--producer', '--consumer'].includes(mode));
assert.equal(extra.length, 0); assert.match(source, /^[a-f0-9]{40}$/u);
assert.ok(isAbsolute(directory));
const state = checkoutState(process.cwd());
assert.equal(state.revision, source); assert.equal(state.clean, true);
assert.ok(relative(resolve(process.cwd()), resolve(directory)).startsWith('../'));
if (mode === '--consumer') assert.ok(isAbsolute(receipt));
else assert.equal(receipt, undefined);
const steps = mode === '--producer'
  ? [{name: 'Same-clean-source normal four-release-package producer', command: 'node',
    args: ['--input-type=module', '-e',
      "import {preparePackageRelease} from './scripts/package-release.mjs'; await preparePackageRelease({destination:process.argv[1]});", directory]}]
  : [{name: 'Registry-installed NEAREST typed Carrier Local HTTPS original controls', command: 'node',
    args: ['scripts/test-package-release-carrier-peer-scope.mjs', directory, receipt],
    env: {ACTQL_TEST_PRESERVE_SCRATCH: '1'}}];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: true,
  timeoutSeconds: 300, graceSeconds: 5, steps});

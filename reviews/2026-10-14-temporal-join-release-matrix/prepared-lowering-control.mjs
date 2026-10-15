import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
import {isAbsolute} from 'node:path';
const before = checkoutState(process.cwd());
assert.equal(before.clean, true); assert.equal(before.revision, process.argv[2]);
const mode = process.argv[3] ?? 'lowering';
assert(['lowering', 'selected', 'plan'].includes(mode));
const args = ['--target', 'js', '-j', '1',
  mode === 'lowering' ? 'src/query_program/temporal_public_lowering_control_test.mbt'
    : 'src/execution_relation/temporal_public_selected_interval_wbtest.mbt'];
const code = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
const planArgs = process.argv.slice(4);
if (mode === 'plan') assert.equal(planArgs.length, 3);
if (mode === 'plan') assert(planArgs.every(isAbsolute));
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: mode === 'plan' ? 60 : 270, graceSeconds: 5, steps: [{name: 'Original interval-left independent Program and lowering control',
    command: process.execPath, args: mode === 'plan'
      ? ['reviews/2026-10-14-temporal-join-release-matrix/pure-installed-plan.mjs', ...planArgs]
      : ['--input-type=module', '-e', code]}]});
assert.deepEqual(checkoutState(process.cwd()), before);

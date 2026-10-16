import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, mode = 'category', ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0);
const selections = {
  category: ['src/program_check/diagnostic_category_wbtest.mbt',
    'sequence temporal diagnostics separate invalid bounds settings and work'],
  public: ['src/connectors_builtin_node/client_check_binding_preparation_wbtest.mbt',
    'public zero sequence window retains the common input rejection'],
};
assert(Object.hasOwn(selections, mode));
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert.equal(before.clean, true);
const [file, name] = selections[mode];
const args = ['--target', 'js', '-j', '1', file, '--filter', name];
const runner = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 270, graceSeconds: 5,
  steps: [{name: 'Original Sequence temporal diagnostic ' + mode,
    command: process.execPath, args: ['--input-type=module', '-e', runner]}]});
assert.deepEqual(checkoutState(process.cwd()), before);

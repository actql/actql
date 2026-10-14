import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const source = process.argv[2];
const selection = process.argv[3] ?? 'syntax';
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
const selections = {
  public_form: ['src/source_frontend/nearest_shorthand_form_test.mbt'],
  capacity: ['src/client_local_host/nearest_installed_capacity_wbtest.mbt', 'src/client_local_host/retained_capacity_wbtest.mbt'],
  syntax: ['src/query_syntax/nearest_shorthand_test.mbt', 'src/query_syntax/nearest_test.mbt', 'src/query_syntax/nearest_optional_roles_test.mbt'],
  lowering: ['src/query_program/nearest_shorthand_test.mbt', 'src/query_program/nearest_test.mbt', 'src/query_program/nearest_carrier_roles_test.mbt'],
  adjacent: ['src/query_program/nearest_member_test.mbt','src/query_program/nearest_script_test.mbt','src/query_program/nearest_expression_test.mbt','src/query_program/nearest_pipe_continuation_test.mbt','src/query_program/nearest_join_continuation_test.mbt','src/query_program/nearest_composite_roles_wbtest.mbt'],
  node: ['scripts/nearest-shorthand.test.mjs','scripts/release-nearest-carrier-fixtures.test.mjs','scripts/compilation-manifests.test.mjs','scripts/frontend-profile.test.mjs'],
};
assert(Object.hasOwn(selections, selection));
const runner = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests(${JSON.stringify(selection === 'node' ? 'node' : 'moon')},${JSON.stringify(selection === 'node' ? selections.node : ['--target', 'js', '-j', '1', ...selections[selection]])},{cwd:process.cwd(),timeout:240000});`;
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 270, graceSeconds: 5,
  steps: [{name: 'Short NEAREST and explicit-role parser counterexamples', command: process.execPath,
    args: ['--input-type=module', '-e', runner]}]});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');

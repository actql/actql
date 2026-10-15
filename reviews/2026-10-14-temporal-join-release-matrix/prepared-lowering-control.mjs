import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
import {isAbsolute} from 'node:path';
const before = checkoutState(process.cwd());
assert.equal(before.clean, true); assert.equal(before.revision, process.argv[2]);
const mode = process.argv[3] ?? 'lowering';
assert(['lowering', 'selected', 'append', 'pipeline', 'final', 'plan'].includes(mode));
const args = ['--target', 'js', '-j', '1',
  mode === 'lowering' ? 'src/query_program/temporal_public_lowering_control_test.mbt'
    : mode === 'pipeline' ? 'src/execution_relation/temporal_public_pipeline_wbtest.mbt'
      : mode === 'append' ? 'src/execution_relation/temporal_append_projection_wbtest.mbt'
      : 'src/execution_relation/temporal_public_selected_interval_wbtest.mbt'];
if (mode === 'final') args.splice(4, 1,
  'src/query_syntax/temporal_public_identifier_fixture_test.mbt',
  'src/query_program/temporal_public_lowering_control_test.mbt',
  'src/execution_relation/temporal_public_selected_interval_wbtest.mbt',
  'src/execution_relation/temporal_public_pipeline_wbtest.mbt');
if (mode === 'pipeline' || mode === 'final') args.push(
  'src/execution_relation/temporal_append_projection_wbtest.mbt',
  'src/execution_relation/append_rows_wbtest.mbt');
const code = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
const planArgs = process.argv.slice(4);
if (mode === 'plan') assert.equal(planArgs.length, 3);
if (mode === 'plan') assert(planArgs.every(isAbsolute));
const planCode = "import {spawnSync} from 'node:child_process';const result=spawnSync(process.execPath,process.argv.slice(1),{stdio:'inherit',timeout:30000,killSignal:'SIGTERM'});if(result.error)throw result.error;process.exitCode=result.status??1;";
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: mode === 'plan' ? 60 : 270, graceSeconds: 5, steps: [{name: 'Original interval-left independent Program and lowering control',
    command: process.execPath, args: mode === 'plan'
      ? ['--input-type=module', '-e', planCode,
        'reviews/2026-10-14-temporal-join-release-matrix/pure-installed-plan.mjs', ...planArgs]
      : ['--input-type=module', '-e', code]}]});
assert.deepEqual(checkoutState(process.cwd()), before);

import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0);
assert.match(source, /^[a-f0-9]{40}$/u);
assert.equal(process.version, 'v22.22.0');
const before = checkoutState(process.cwd());
assert.equal(before.revision, source);
assert(before.clean);
const runner = kind => 'import{runFocusedTests}from"./scripts/test-execution.mjs";' +
  `process.exitCode=runFocusedTests(${JSON.stringify(kind)},process.argv.slice(1),` +
  '{cwd:process.cwd(),timeout:30000});';
const formatter = 'import{readFileSync}from"node:fs";' +
  'import{spawnSync}from"node:child_process";' +
  'const path="src/query_integration/ctas_retained_result_input_wbtest.mbt";' +
  'const result=spawnSync("moonfmt",[path],{encoding:"utf8",timeout:30000});' +
  'if(result.status!==0||result.stdout!==readFileSync(path,"utf8"))process.exitCode=1;';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Complete Result Manifest Host sequencing and cleanup', command: process.execPath,
      args: ['--input-type=module', '-e', runner('node'), '--',
        'adapters/host-node/effect-member-source-bindings.test.mjs']},
    {name: 'Actual Common captured Artifacts: incomplete refusal and full Manifest',
      command: process.execPath, args: ['--input-type=module', '-e', runner('moon'), '--',
        '--target', 'js', '-j', '1', 'src/query_integration/ctas_retained_result_input_wbtest.mbt']},
    {name: 'Read-only Moon formatting', command: process.execPath,
      args: ['--input-type=module', '-e', formatter]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);

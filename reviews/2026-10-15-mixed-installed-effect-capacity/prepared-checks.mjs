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
const files = ['src/client_local_host/captured_ledger.mbt',
  'src/connectors_builtin_node/client_multi_source_host_bridge.mbt',
  'src/query_integration/mixed_effect_capacity_fixture_wbtest.mbt',
  'src/query_integration/mixed_effect_capacity_wbtest.mbt'];
const format = 'import{readFileSync}from"node:fs";import{spawnSync}from"node:child_process";' +
  'for(const path of process.argv.slice(1)){const r=spawnSync("moonfmt",[path],{encoding:"utf8",timeout:30000});' +
  'if(r.status!==0||r.stdout!==readFileSync(path,"utf8"))process.exitCode=1;}';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Mixed Source selection, original capacities, existing acquired Effect controls',
      command: process.execPath, args: ['--input-type=module', '-e', runner('node'), '--',
        'adapters/host-node/acquired-effect-installed-capacity.test.mjs',
        'adapters/host-node/acquired-effect-computation.test.mjs']},
    {name: 'Actual Common mixed Effect capacity', command: process.execPath,
      args: ['--input-type=module', '-e', runner('moon'), '--', '--target', 'js', '-j', '1',
        'src/query_integration/mixed_effect_capacity_wbtest.mbt']},
    {name: 'Existing Pure installed capacity and original transfer refusal', command: process.execPath,
      args: ['--input-type=module', '-e', runner('moon'), '--', '--target', 'js', '-j', '1',
        'src/client_local_host/nearest_installed_capacity_wbtest.mbt']},
    {name: 'Read-only affected Moon formatting', command: process.execPath,
      args: ['--input-type=module', '-e', format, '--', ...files]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);

import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, mode, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0); assert.match(source, /^[a-f0-9]{40}$/u);
assert(['calendar', 'graph', 'oracle'].includes(mode));
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert.equal(before.clean, true);
const args = mode === 'calendar'
  ? ['--target', 'js', '-j', '1', 'src/query_program/calendar_source_test.mbt',
    '--filter', '*Calendar source context retains*']
  : ['--target', 'js', '-j', '1', 'src/query_integration/graph_plan_wbtest.mbt',
    '--filter', '*formal Graph Plan retains*'];
const runner = mode === 'oracle'
  ? 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});'
  : 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",' + JSON.stringify(args) + ',{cwd:process.cwd(),timeout:240000});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: mode === 'oracle' ? 60 : 270, graceSeconds: 5, steps: [
    {name: 'Current normative Frontend control: ' + mode, command: process.execPath,
      args: ['--input-type=module', '-e', runner,
        ...(mode === 'oracle' ? ['--', '--test',
          'reviews/2026-10-15-frontend-core-current-expectations/independent-oracle.test.mjs'] : [])]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);

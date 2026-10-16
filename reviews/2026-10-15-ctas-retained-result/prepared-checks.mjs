import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0); assert.match(source, /^[a-f0-9]{40}$/u);
assert.equal(process.version, 'v22.22.0');
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert(before.clean);
const syntaxFiles = ['adapters/host-node/table-public-commit.test.mjs',
  'adapters/host-node/fixtures/table-physical-fixture.mjs',
  'adapters/host-node/fixtures/table-text-restart.mjs',
  'scripts/packed-table-private-input.test.mjs'];
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    ...syntaxFiles.map(path => ({name:'Parse '+path, command:process.execPath,args:['--check',path]})),
    {name:'CTAS independent controls, real copy closure and original normal4 admission',
      command:process.execPath,args:['--input-type=module','-e',runner,'--','--test',
        '--test-concurrency=1','scripts/table-ctas-result-controls.test.mjs',
        'scripts/composition-release-input.test.mjs']},
    {name:'Whitespace',command:'git',args:['diff','--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);

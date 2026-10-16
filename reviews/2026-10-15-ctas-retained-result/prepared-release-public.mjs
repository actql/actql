// Consumer only: all product modules and Python worker assets must come from
// one exact normal4 release, never from checkout build output or overlays.
import assert from 'node:assert/strict';
import {isAbsolute} from 'node:path';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {admitCompositionRelease} from '../../scripts/composition-release-input.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, directory, python, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0); assert.match(source, /^[a-f0-9]{40}$/u);
assert.equal(process.version, 'v22.22.0');
assert(isAbsolute(directory)); assert(isAbsolute(python));
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert(before.clean);
const release = await admitCompositionRelease({repository:process.cwd(),directory});
assert.equal(release.manifest.sourceSha, source);
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:1140000});';
// Two selected groups retain their original child360s budgets, normal install
// retains120s and optional Python setup20s. One finite1200s outer budget covers
// both groups and setup; it does not change any product or checkpoint limit.
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:true,
  timeoutSeconds:1200,graceSeconds:5,steps:[{
    name:'Normal4 original CTAS4 plus independent retained Result/filter6 Local HTTPS controls',
    command:process.execPath,args:['--input-type=module','-e',runner,'--','--test',
      '--test-concurrency=1','scripts/packed-table-private-input.test.mjs'],
    env:{ACTQL_TABLE_NORMAL_RELEASE:directory,ACTQL_TABLE_CASE_GROUP:'ctas',
      ACTQL_TABLE_PYTHON:python,ACTQL_TEST_PRESERVE_SCRATCH:'1'},
  }]});
await release.verifyUnchanged();
assert.deepEqual(checkoutState(process.cwd()), before);

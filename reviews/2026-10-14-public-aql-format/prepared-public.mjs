import assert from 'node:assert/strict';
import {isAbsolute} from 'node:path';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [mode, source, directory, receipt] = process.argv.slice(2);
assert(['--producer', '--consumer'].includes(mode));
assert.match(source, /^[a-f0-9]{40}$/u);assert(isAbsolute(directory));
assert.deepEqual(checkoutState(process.cwd()), {revision:source,clean:true});
const steps=mode==='--producer' ? [{name:'Normal four-package AQL format producer',command:process.execPath,
 args:['--input-type=module','-e',"import {preparePackageRelease} from './scripts/package-release.mjs';await preparePackageRelease({destination:process.argv[1]});",directory]}] :
 [{name:'Empty-installed public AQL Local HTTPS',command:process.execPath,
 args:['scripts/test-package-release-sourcefree-query.mjs',directory,receipt,'--aql-format-only'],
 env:{ACTQL_TEST_PRESERVE_SCRATCH:'1'}}];
if(mode==='--consumer')assert(isAbsolute(receipt));
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:true,timeoutSeconds:300,graceSeconds:5,steps});
assert.deepEqual(checkoutState(process.cwd()), {revision:source,clean:true});

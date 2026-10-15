import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2];assert.match(source,/^[a-f0-9]{40}$/u);
const git=(...a)=>execFileSync('git',a,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const code="import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('node',['adapters/host-node/installed-calendar.test.mjs','scripts/release-calendar-query-cases.test.mjs','scripts/calendar-source-input.test.mjs','scripts/release-sourcefree-query-cases.test.mjs'],{cwd:process.cwd(),timeout:30000});";
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[{name:'Explicit Calendar installation and original public6 closed release preparation',command:process.execPath,args:['--input-type=module','-e',code]}]});
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');

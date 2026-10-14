import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2],selection=process.argv[3]??'diagnostic';
const git=(...a)=>execFileSync('git',a,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const files=selection==='diagnostic'?['src/query_program/event_dedupe_current_diagnostic_test.mbt']:
 ['src/query_program/event_dedupe_current_diagnostic_test.mbt','src/query_program/event_dedupe_source_test.mbt'];
assert(['diagnostic','original'].includes(selection));
const runner=`import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(['--target','js','-j','1',...files])},{cwd:process.cwd(),timeout:240000});`;
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:270,graceSeconds:5,
 steps:[{name:'Exact event dedupe lowering and independent common control',command:process.execPath,args:['--input-type=module','-e',runner]}]});
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');

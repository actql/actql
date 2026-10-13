import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2];assert.match(source,/^[a-f0-9]{40}$/u);
const git=(...args)=>execFileSync('git',args,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
{name:'Independent current and retained identity preimages',command:'node',args:['--input-type=module','-e',runner,'node','reviews/2026-10-13-frontend-integration-identity-repair/identity-controls.test.mjs']},
{name:'Original integration Graph and policy consumers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_integration/physical_search_wbtest.mbt','src/query_integration/graph_plan_wbtest.mbt']},
{name:'Whitespace',command:'git',args:['diff','--check']}
]});
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');

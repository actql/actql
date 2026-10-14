import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2], mode=process.argv[3]??'counter';
assert.match(source,/^[a-f0-9]{40}$/u);
assert(['counter','registry','node','freshness'].includes(mode));
const git=(...args)=>execFileSync('git',args,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const args=mode==='node'?['scripts/calendar-registration.test.mjs','scripts/pipeline-registry.test.mjs','scripts/query-dependency-boundary.test.mjs']:
  ['--target','js','-j','1','src/execution_relation/calendar_registry_admission_wbtest.mbt',...(mode==='registry'?['src/execution_relation/registry_wbtest.mbt']:[])];
const code=`import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests(${JSON.stringify(mode==='node'?'node':'moon')},${JSON.stringify(args)},{cwd:process.cwd(),timeout:${mode==='node'?30000:240000}});`;
const steps=mode==='freshness'?[{name:'Ordinary runtime registry/consumer generator read-only',command:process.execPath,args:['scripts/lowering-registry-vectors.mjs']}]:
  [{name:'Exact Calendar runtime registry admission '+mode,command:process.execPath,args:['--input-type=module','-e',code]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:['node','freshness'].includes(mode)?60:270,graceSeconds:5,steps});
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');

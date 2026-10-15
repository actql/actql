import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2],mode=process.argv[3]??'kernel';
assert.match(source,/^[a-f0-9]{40}$/u);assert(['kernel','api','generator'].includes(mode));
const git=(...a)=>execFileSync('git',a,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const code="import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',['--target','js','-j','1','src/local_tea/calendar_series_wbtest.mbt'],{cwd:process.cwd(),timeout:240000});";
const steps=mode==='api'?['js','wasm','native'].map(target=>({name:'Calendar original bounded buffer/kernel/provider API '+target,command:'moon',args:['info','--target',target,'src/execution_relation','src/local_tea','src/local_tea_provider']})):
  mode==='generator'?[{name:'Original registry consumer generator read-only',command:process.execPath,args:['scripts/lowering-registry-vectors.mjs']}]:
  [{name:'Calendar bounded series actual component controls',command:process.execPath,args:['--input-type=module','-e',code]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:mode==='generator'?60:270,graceSeconds:5,steps});
assert.equal(git('rev-parse','HEAD'),source);if(mode!=='api')assert.equal(git('status','--porcelain'),'');

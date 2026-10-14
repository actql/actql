import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2],mode=process.argv[3]??'root';
const git=(...a)=>execFileSync('git',a,{encoding:'utf8'}).trim();
assert.match(source,/^[a-f0-9]{40}$/u);
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const files={provider:'src/local_tea_provider/calendar_series_wbtest.mbt',root:'src/lowering_relation/calendar_preparation_test.mbt',kernel:'src/local_tea/calendar_series_wbtest.mbt',installed:'src/connectors_builtin_node/client_calendar_environment_wbtest.mbt'};
assert(Object.hasOwn(files,mode)||['api','freshness','format'].includes(mode));
const args=['--target','js','-j','1',files[mode]??files.root];
if(mode==='root')args.push('--filter','selected original UTC Calendar series reaches normal lowering');
const code=`import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
const steps=mode==='api'?['js','wasm','native'].map(target=>({name:'Calendar existing selected installation API '+target,command:'moon',args:['info','--target',target,'src/execution_relation','src/connectors/local','src/connectors/local/driver','src/local_tea_provider','src/physical_strategy']})):
mode==='format'?[{name:'Authored Calendar formatting read-only',command:process.execPath,args:['--input-type=module','-e',"import {execFileSync} from 'node:child_process';import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';const paths=execFileSync('git',['diff','--name-only','1335e23ae1ed553414a5a576d29d6f068facf816','HEAD'],{encoding:'utf8'}).trim().split('\\n').filter(p=>p.endsWith('.mbt')&&!p.endsWith('calendar_contracts_wbtest.mbt'));assert(paths.length>0);for(const path of paths)assert.deepEqual(execFileSync('moonfmt',[path],{timeout:20000}),readFileSync(path),path);execFileSync('git',['diff','--check']);console.log('Read-only Moonfmt:',paths.length,'authored files; diff check complete');"]}]:
mode==='freshness'?[{name:'Original registry consumer freshness',command:process.execPath,args:['scripts/lowering-registry-vectors.mjs']},{name:'Actual owned contract scan',command:process.execPath,args:['scripts/check-owned-contract-versions.mjs']}]:
[{name:'Calendar original selected installation '+mode,command:process.execPath,args:['--input-type=module','-e',code]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:['freshness','format'].includes(mode)?60:270,graceSeconds:5,steps});
assert.equal(git('rev-parse','HEAD'),source);if(mode!=='api')assert.equal(git('status','--porcelain'),'');

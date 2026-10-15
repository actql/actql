import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2],mode=process.argv[3]??'presence';
const git=(...a)=>execFileSync('git',a,{encoding:'utf8'}).trim();
assert.match(source,/^[a-f0-9]{40}$/u);assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
const choices={presence:['src/calendar_typing/admission_test.mbt','Calendar bucket preserves conditional payload independently of NULL'],kernel:['src/local_tea/calendar_bucket_wbtest.mbt',null],reader:['src/execution_relation/producer_presence_calendar_wbtest.mbt',null],typing:['src/calendar_typing/admission_test.mbt',null],provider:['src/local_tea_provider/calendar_bucket_wbtest.mbt',null]};
assert(Object.hasOwn(choices,mode)||['api','format'].includes(mode));const [file,filter]=choices[mode]??choices.presence;
const args=['--target','js','-j','1',file];if(filter)args.push('--filter',filter);
const code=`import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
const steps=mode==='api'?['js','wasm','native'].map(target=>({name:'Calendar bucket existing API '+target,command:'moon',args:['info','--target',target,'src/execution_relation','src/local_tea','src/local_tea_provider','src/calendar_typing','src/connectors/local','src/connectors/local/driver']})):
mode==='format'?[{name:'Bucket authored formatting read-only',command:process.execPath,args:['--input-type=module','-e',"import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';import {readFileSync} from 'node:fs';const paths=execFileSync('git',['diff','--name-only','3ba914e871c68536c1757b28321ec60a6dcdb06e','HEAD'],{encoding:'utf8'}).trim().split('\\n').filter(p=>p.endsWith('.mbt'));assert(paths.length>0);for(const path of paths)assert.deepEqual(execFileSync('moonfmt',[path],{timeout:20000}),readFileSync(path),path);execFileSync('git',['diff','--check']);console.log('Bucket readonly Moonfmt:',paths.length);"]}]:
[{name:'Calendar original bucket '+mode,command:process.execPath,args:['--input-type=module','-e',code]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:mode==='format'?60:270,graceSeconds:5,steps});
assert.equal(git('rev-parse','HEAD'),source);if(mode!=='api')assert.equal(git('status','--porcelain'),'');

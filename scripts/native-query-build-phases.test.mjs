import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {nativeQueryCoverage,runNativeQueryTests,readNativeQuerySources,selectNativeQueryTests} from './native-query-coverage.mjs';
const cwd=fileURLToPath(new URL('../',import.meta.url));
function fixture(t){
 const root=mkdtempSync(join(tmpdir(),'actql-query-build-phases-'));t.after(()=>rmSync(root,{recursive:true,force:true}));
 const moon=join(root,'moon.mjs'),commands=join(root,'commands.jsonl'),executions=join(root,'executions');
 writeFileSync(moon,'#!'+process.execPath+'\n'+String.raw`
import {appendFileSync,existsSync,writeFileSync} from 'node:fs';
const args=process.argv.slice(2),compile=args.includes('--build-only');
appendFileSync(process.env.FIXTURE_COMMANDS,JSON.stringify({args,original:process.env.FIXTURE_ORIGINAL})+'\n');
if(compile){
 if(process.env.FIXTURE_BUILD_FAIL){console.error('original compiler refusal');process.exit(17);}
 writeFileSync(process.env.FIXTURE_ARTIFACT,'same original generated software');
 console.log('Finished build only; no cases executed');
}else{
 if(!existsSync(process.env.FIXTURE_ARTIFACT))throw Error('original compiled software missing');
 appendFileSync(process.env.FIXTURE_EXECUTIONS,'one original case group\n');
 const n=process.env.FIXTURE_SHORT?11:12;console.log('Total tests: '+n+', passed: '+n+', failed: 0.');
}
`,{mode:0o700});
 const env={...process.env,...Object.fromEntries(nativeQueryCoverage.requiredEnvironment['remote-runtime'].map(name=>[name,'1'])),
  FIXTURE_COMMANDS:commands,FIXTURE_EXECUTIONS:executions,FIXTURE_ARTIFACT:join(root,'compiled'),FIXTURE_ORIGINAL:'same original'};
 const selection=selectNativeQueryTests('remote-runtime',readNativeQuerySources(cwd),env),targetDirectory=join(root,'target');
 const calls=()=>readFileSync(commands,'utf8').trim().split('\n').map(JSON.parse);
 return {moon,env,cwd,targetDirectory,calls,executions,selection};
}
async function observations(operation,{broken=false}={}){
 const records=[],original=console.error;
 console.error=line=>{if(typeof line==='string'&&line.startsWith('ACTQL_NATIVE_CI_PHASE ')){
  if(broken)throw new Error('reporting unavailable');records.push(JSON.parse(line.slice('ACTQL_NATIVE_CI_PHASE '.length)));
 }else original(line);};
 try{return {value:await operation(),records};}finally{console.error=original;}
}
test('Query build and execution keep identical original inputs and execute the actual case group once',async t=>{
 const f=fixture(t),{records}=await observations(()=>runNativeQueryTests(f.moon,'remote-runtime',f));
 const original=['test',...f.selection.paths,'--target','native','--target-dir',f.targetDirectory];
 assert.deepEqual(f.calls(),[{args:[...original,'--build-only'],original:'same original'},{args:original,original:'same original'}]);
 assert.equal(readFileSync(f.executions,'utf8'),'one original case group\n');
 assert.deepEqual(records.map(x=>[x.scope,x.owner,x.phase,x.succeeded]),[['native-query','remote-runtime','compile',true],['native-query','remote-runtime','execute',true]]);
 assert(records.every(x=>Number.isSafeInteger(x.milliseconds)&&x.milliseconds>=0));
 assert(!original.includes('--strip')&&!original.includes('--release'));
});
test('Query original build failure stops before any case execution and retains compiler refusal',async t=>{
 const f=fixture(t);f.env.FIXTURE_BUILD_FAIL='1';let failure;
 const {records}=await observations(async()=>{try{await runNativeQueryTests(f.moon,'remote-runtime',f);}catch(error){failure=error;}});
 assert(failure);assert.match(failure.message,/original compiler refusal/u);
 assert.equal(f.calls().length,1);assert(f.calls()[0].args.includes('--build-only'));
 assert.deepEqual(records.map(x=>[x.phase,x.succeeded]),[['compile',false]]);
 assert.throws(()=>readFileSync(f.executions),{code:'ENOENT'});
});
test('Query successful build cannot qualify missing required execution cases',async t=>{
 const f=fixture(t);f.env.FIXTURE_SHORT='1';let failure;
 const {records}=await observations(async()=>{try{await runNativeQueryTests(f.moon,'remote-runtime',f);}catch(error){failure=error;}});
 assert(failure);assert.match(failure.message,/coverage mismatch/u);
 assert.deepEqual(records.map(x=>[x.phase,x.succeeded]),[['compile',true],['execute',false]]);
 assert.equal(readFileSync(f.executions,'utf8'),'one original case group\n');
});
test('Query timing output failure cannot replace original success or compiler failure',async t=>{
 const f=fixture(t);await observations(()=>runNativeQueryTests(f.moon,'remote-runtime',f),{broken:true});
 assert.equal(readFileSync(f.executions,'utf8'),'one original case group\n');
 const failed=fixture(t);failed.env.FIXTURE_BUILD_FAIL='1';
 await assert.rejects(()=>observations(()=>runNativeQueryTests(failed.moon,'remote-runtime',failed),{broken:true}),/original compiler refusal/u);
 assert.equal(failed.calls().length,1);
});

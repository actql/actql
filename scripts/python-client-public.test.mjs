// Actual HTTPS Host; Python is an external wheel consumer, never a TS SDK wrapper.
import assert from 'node:assert/strict';
import test from 'node:test';
import {spawn} from 'node:child_process';
import {appendFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {openPythonPublicHost as publicHost} from './fixtures/python-public-host.mjs';

async function python(args,cwd) {
  assert.ok(process.env.ACTQL_PYTHON_WHEEL,'ACTQL_PYTHON_WHEEL must select the externally installed wheel interpreter');
  const child=spawn(process.env.ACTQL_PYTHON_WHEEL,args,{cwd,env:{...process.env,PYTHONPATH:''},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',value=>{stdout+=value;});child.stderr.on('data',value=>{stderr+=value;});
  await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>{
    appendFile(join(cwd,'python-processes.jsonl'),JSON.stringify({pid:child.pid,code,signal})+'\n',{mode:0o600}).then(()=>{
    if(code!==0)reject(new Error(`Python public consumer failed: code=${code}; signal=${signal}\n${stderr}`));else resolve();},reject);});});
  return JSON.parse(stdout);
}


test('wheel: async and sync normal, separate-process attach, text and structured diagnostics over actual HTTPS',async t=>{
  const {root,certificates,counts,endpoint}=await publicHost(t);
  const results=[];
  for(const facade of ['async','sync'])for(const phase of ['normal','reattach','diagnostics','structured']){
    const receipt=await python([resolve('scripts/fixtures/python-client-public.py'),phase,facade,endpoint,certificates.caPath,join(root,`${facade}.custody.json`)],root);
    assert.deepEqual(receipt,{phase,facade,success:true});results.push(receipt);
  }
  assert.equal(counts.computed,2,'Only the two explicit valid submissions compute; lookup, attach, reads and diagnostics do not recompute.');
  for(const facade of ['async','sync']){
    const phase='numbers';
    const receipt=await python([resolve('scripts/fixtures/python-client-public.py'),phase,facade,endpoint,certificates.caPath,join(root,`${facade}.custody.json`)],root);
    assert.deepEqual(receipt,{phase,facade,success:true});results.push(receipt);
  }
  assert.equal(counts.computed,6,'Only four additional explicit binary64 submissions compute.');
  await writeFile(join(root,'receipt.json'),JSON.stringify({results,counts},null,2)+'\n');
});

test('wheel: async and sync explicit structured Program and AQL execution over actual HTTPS',async t=>{
  const {root,certificates,counts,endpoint}=await publicHost(t),results=[];
  for(const facade of ['async','sync']){
    const phase='authored';
    const receipt=await python([resolve('scripts/fixtures/python-client-public.py'),phase,facade,endpoint,certificates.caPath,join(root,`${facade}.custody.json`)],root);
    assert.deepEqual(receipt,{phase,facade,success:true});results.push(receipt);
  }
  assert.equal(counts.computed,4,'Exactly four explicit structured/AQL submissions compute.');
  await writeFile(join(root,'authored-receipt.json'),JSON.stringify({results,counts},null,2)+'\n');
});

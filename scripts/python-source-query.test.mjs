// Actual Common/SQLite/HTTPS and an externally installed SDK-only wheel.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {appendFileSync} from 'node:fs';
import {writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {openPythonPublicHost} from './fixtures/python-public-host.mjs';

async function consume(args,cwd,output) {
  assert.ok(process.env.ACTQL_PYTHON_WHEEL,'Use the ordinary externally installed SDK-only wheel');
  const child=spawn(process.env.ACTQL_PYTHON_WHEEL,['-I','-B',resolve('scripts/fixtures/python-source-query.py'),...args],
    {cwd,env:{...process.env,PYTHONPATH:''},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',bytes=>{stdout+=bytes;appendFileSync(output+'.stdout.log',bytes,{mode:0o600});});
  child.stderr.on('data',bytes=>{stderr+=bytes;appendFileSync(output+'.stderr.log',bytes,{mode:0o600});});
  const result=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
  appendFileSync(output+'.process.jsonl',JSON.stringify({pid:child.pid,...result})+'\n',{mode:0o600});
  assert.deepEqual(result,{code:0,signal:null},stderr);
  return {pid:child.pid,...JSON.parse(stdout)};
}

for(const facade of ['sync','async'])
  test(`installed Python ${facade} lazy SQL/Pipe query uses the original Run for reads and separate-process attach`,async t=>{
    const {root,certificates,counts,endpoint}=await openPythonPublicHost(t);
    const custody=join(root,facade+'.query-custody.json'),results=[];
    for(const phase of ['query','restore']){
      const result=await consume([phase,facade,endpoint,certificates.caPath,custody],root,join(root,phase));
      assert.equal(result.phase,phase);assert.equal(result.facade,facade);assert.equal(result.success,true);
      results.push(result);
      assert.equal(counts.computed,2,'Only the two original read-only queries compute; explicit rereads/lookup/attach never resubmit');
    }
    assert.equal(new Set(results.map(item=>item.pid)).size,2,'Restore uses a separate real Python process');
    await writeFile(join(root,'query-receipt.json'),JSON.stringify({facade,results,counts},null,2)+'\n',{mode:0o600});
  });

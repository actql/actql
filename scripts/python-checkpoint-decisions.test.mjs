// Actual HTTPS, signed original resolutions, SQLite Journal and Host reopen.
import assert from 'node:assert/strict';
import {fork,spawn} from 'node:child_process';
import {appendFileSync} from 'node:fs';
import {chmod,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {readComputeEffectInstallation,expectedOrgAfterSuccess,expectedBodies,storedRecords} from
  '../adapters/connectors/salesforce/test/read-compute-effect.fixture.mjs';

async function openHost(path,t) {
  const child=fork(resolve('scripts/fixtures/python-client-source-host.mjs'),[path],
    {stdio:['ignore','ignore','pipe','ipc']});
  child.stderr.on('data',bytes=>appendFileSync(`${path}.host-${child.pid}.stderr.log`,bytes,{mode:0o600}));
  const exited=new Promise(resolve=>child.once('exit',(code,signal)=>resolve({code,signal})));
  const endpoint=await new Promise((resolve,reject)=>{
    child.once('error',reject);child.once('exit',()=>reject(new Error('Host exited before opening')));
    child.once('message',value=>{assert.equal(value.pid,child.pid);resolve(value.endpoint);});
  });
  let closed=false;
  const close=async()=>{if(closed)return;child.send('close');
    assert.deepEqual(await exited,{code:0,signal:null});closed=true;};
  t.after(close);
  return {endpoint,close,pid:child.pid};
}

async function consume(args,cwd,output) {
  assert.ok(process.env.ACTQL_PYTHON_WHEEL,'Select an external ordinary SDK-only installation');
  const child=spawn(process.env.ACTQL_PYTHON_WHEEL,['-I','-B',resolve('scripts/fixtures/python-checkpoint-decisions.py'),...args],
    {cwd,env:{...process.env,PYTHONPATH:''},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',bytes=>{stdout+=bytes;appendFileSync(output+'.stdout.log',bytes,{mode:0o600});});
  child.stderr.on('data',bytes=>{stderr+=bytes;appendFileSync(output+'.stderr.log',bytes,{mode:0o600});});
  const result=await new Promise((resolve,reject)=>{
    child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
  appendFileSync(output+'.process.jsonl',JSON.stringify({pid:child.pid,...result})+'\n',{mode:0o600});
  assert.deepEqual(result,{code:0,signal:null},stderr);
  return {pid:child.pid,...JSON.parse(stdout)};
}

for(const facade of ['async','sync'])for(const decision of ['approve','reject'])
  test(`installed Python ${facade} configured signer ${decision}s the original ID through HTTPS and Host reopen`,async t=>{
    const fixture=await readComputeEffectInstallation(t),requestId=`checkpoint-${facade}-${decision}`;
    await fixture.embedded(requestId,fixture.program(),{transport:'https'});
    const installation=join(fixture.root,`embedded-${requestId}.json`);
    await chmod(installation,0o600);
    const custody=join(fixture.root,`${requestId}.custody.json`),phases=[],hosts=[];
    let host=await openHost(installation,t);hosts.push(host.pid);
    const phase=async name=>{
      const result=await consume([name,facade,decision,host.endpoint,installation,custody],fixture.root,
        `${installation}.${name}`);
      assert.equal(result.phase,name);assert.equal(result.facade,facade);assert.equal(result.decision,decision);
      phases.push(result);
    };
    await phase('submit');
    assert.equal(fixture.queries(),1);assert.equal(fixture.writes().length,0);
    await host.close();host=await openHost(installation,t);hosts.push(host.pid);
    await phase('decide');
    assert.equal(fixture.queries(),1);assert.equal(fixture.writes().length,0);
    await host.close();host=await openHost(installation,t);hosts.push(host.pid);
    await phase('finish');
    const writes=decision==='approve'?2:0;
    assert.equal(fixture.writes().length,writes);
    for(const write of fixture.writes())assert.equal(write.body,expectedBodies[write.path.split('/').at(-1)]);
    assert.deepEqual(fixture.org.records(),decision==='approve'?expectedOrgAfterSuccess:storedRecords);
    await host.close();host=await openHost(installation,t);hosts.push(host.pid);
    await phase('observe');
    assert.equal(fixture.queries(),1,'Same Run recovery never reacquires the Source');
    assert.equal(fixture.writes().length,writes,'Reopen never resends an approved Effect or rejected answer');
    assert.equal(new Set(hosts).size,4);
    assert.equal(new Set(phases.map(value=>value.pid)).size,4);
    const requests=(await readFile(`${installation}.python-requests.jsonl`,'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(requests.filter(value=>value.operation==='checkpoints').length,1,'One exact ID lookup, not a paging search');
    assert.equal(requests.filter(value=>value.operation==='resolve').length,1,'Only the original answer is sent');
    await host.close();
    await writeFile(`${installation}.decisions-receipt.json`,JSON.stringify({facade,decision,hosts,phases,
      requests,queries:fixture.queries(),writes},null,2)+'\n',{mode:0o600});
  });

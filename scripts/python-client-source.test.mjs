// Independent Source/Effect expectations, real Host restarts, external wheels.
import assert from 'node:assert/strict';
import {fork,spawn} from 'node:child_process';
import {appendFileSync} from 'node:fs';
import {chmod,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {readComputeEffectInstallation,expectedOrgAfterSuccess,expectedBodies} from
  '../adapters/connectors/salesforce/test/read-compute-effect.fixture.mjs';

async function python(args,cwd){
  assert.ok(process.env.ACTQL_PYTHON_WHEEL,'Select an external wheel interpreter');
  const child=spawn(process.env.ACTQL_PYTHON_WHEEL,args,{cwd,env:{...process.env,PYTHONPATH:''},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',value=>{stdout+=value;});child.stderr.on('data',value=>{stderr+=value;});
  await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>{
    if(code!==0||signal!==null)reject(new Error(`Python Source acceptance failed: ${code}, ${signal}\n${stderr}`));else resolve();});});
  return JSON.parse(stdout);
}

async function openHost(path,t){
  const child=fork(resolve('scripts/fixtures/python-client-source-host.mjs'),[path],{stdio:['ignore','ignore','pipe','ipc']});
  child.stderr.on('data',bytes=>appendFileSync(`${path}.host-${child.pid}.stderr.log`,bytes,{mode:0o600}));
  const exited=new Promise(resolve=>child.once('exit',(code,signal)=>resolve({code,signal})));
  const endpoint=await new Promise((resolve,reject)=>{
    child.once('error',reject);child.once('exit',()=>reject(new Error('Host exited before opening')));
    child.once('message',value=>{assert.equal(value.pid,child.pid);resolve(value.endpoint);});
  });
  let done=false;
  const close=async()=>{
    if(done)return;
    child.send('close');
    assert.deepEqual(await exited,{code:0,signal:null});done=true;
  };
  t.after(close);
  return {endpoint,close,pid:child.pid};
}

for(const facade of ['async','sync'])test(`wheel: ${facade} Source, explicit approval, same Run after actual Host restart`,async t=>{
  const fixture=await readComputeEffectInstallation(t);
  const requestId=`python-${facade}`;
  // Only serialize the shared installation; do not invoke its TS consumer.
  await fixture.embedded(requestId,fixture.program(),{transport:'https'});
  const installation=join(fixture.root,`embedded-${requestId}.json`);
  await chmod(installation,0o600);
  const custody=join(fixture.root,`${requestId}.custody.json`);
  const phases=[],pids=[];
  let host=await openHost(installation,t);pids.push(host.pid);
  const consume=async phase=>{
    const receipt=await python([resolve('scripts/fixtures/python-client-source.py'),phase,facade,host.endpoint,installation,custody],fixture.root);
    assert.deepEqual(receipt,{phase,facade,success:true});phases.push(receipt);
  };
  await consume('submit');
  assert.equal(fixture.queries(),1,'one original acquisition before approval');
  assert.equal(fixture.writes().length,0,'no writes before explicit approval');
  await host.close();host=await openHost(installation,t);pids.push(host.pid);
  await consume('approve');
  assert.equal(fixture.queries(),1,'restart and approval do not reacquire');
  assert.equal(fixture.writes().length,0,'the shared fixture resumes the committed answer on the next Host startup');
  await host.close();host=await openHost(installation,t);pids.push(host.pid);
  await consume('finish');
  assert.equal(fixture.writes().length,2,'exactly two approved provider writes');
  for(const write of fixture.writes())assert.equal(write.body,expectedBodies[write.path.split('/').at(-1)]);
  assert.deepEqual(fixture.org.records(),expectedOrgAfterSuccess);
  assert.equal(fixture.queries(),1,'reconnecting to the original Run does not reacquire');
  assert.equal(fixture.writes().length,2,'reconnecting does not resend writes');
  assert.equal(new Set(pids).size,3);
  const events=(await readFile(`${installation}.python-owner-events.jsonl`,'utf8')).trim().split('\n').map(JSON.parse);
  await writeFile(`${installation}.python-receipt.json`,JSON.stringify({phases,pids,queries:fixture.queries(),writes:fixture.writes().length,events},null,2)+'\n',{mode:0o600});
});

for(const facade of ['async','sync'])test(`wheel: ${facade} live waiting Run cancellation and conflict survive Host restart`,async t=>{
  const fixture=await readComputeEffectInstallation(t),requestId=`python-cancel-${facade}`;
  await fixture.embedded(requestId,fixture.program(),{transport:'https'});
  const installation=join(fixture.root,`embedded-${requestId}.json`);
  await chmod(installation,0o600);
  const custody=join(fixture.root,`${requestId}.custody.json`),pids=[];
  let host=await openHost(installation,t);pids.push(host.pid);
  const consume=async phase=>assert.deepEqual(await python([
    resolve('scripts/fixtures/python-client-source.py'),phase,facade,host.endpoint,installation,custody],fixture.root),
    {phase,facade,success:true});
  await consume('submit');
  assert.equal(fixture.queries(),1);
  assert.equal(fixture.writes().length,0);
  await consume('cancel');
  assert.equal(fixture.queries(),1);
  assert.equal(fixture.writes().length,0,'Conflicted or cancelled Runs never write');
  await host.close();host=await openHost(installation,t);pids.push(host.pid);
  await consume('cancelled');
  assert.equal(fixture.queries(),1,'Cancellation recovery does not reacquire Source');
  assert.equal(fixture.writes().length,0,'Restart does not approve or send Effects');
  assert.equal(new Set(pids).size,2);
  await writeFile(`${installation}.python-cancel-receipt.json`,JSON.stringify({facade,pids,queries:1,writes:0},null,2)+'\n',{mode:0o600});
});

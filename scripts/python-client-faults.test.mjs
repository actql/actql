import assert from 'node:assert/strict';
import {fork,spawn} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {appendFileSync} from 'node:fs';
import {mkdir,mkdtemp,readFile,rm,writeFile} from 'node:fs/promises';
import {userInfo} from 'node:os';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {fixtureCertificates} from '../adapters/site-node/https-exchange-fixture.mjs';

async function host(path,fault,t){
  const child=fork(resolve('scripts/fixtures/python-client-source-host.mjs'),[path,fault],{stdio:['ignore','ignore','pipe','ipc']});
  child.stderr.on('data',bytes=>appendFileSync(`${path}.host-${child.pid}.stderr.log`,bytes,{mode:0o600}));
  const exited=new Promise(resolve=>child.once('exit',(code,signal)=>resolve({code,signal})));
  const endpoint=await new Promise((resolve,reject)=>{
    child.once('error',reject);child.once('exit',()=>reject(new Error('Host exited before opening')));
    child.once('message',value=>{assert.equal(value.pid,child.pid);resolve(value.endpoint);});
  });
  let closed=false;
  const close=async()=>{if(closed)return;child.send('close');assert.deepEqual(await exited,{code:0,signal:null});closed=true;};
  t.after(close);return {endpoint,close,pid:child.pid};
}

async function consume(phase,facade,endpoint,ca,custody,root){
  assert.ok(process.env.ACTQL_PYTHON_WHEEL);
  const child=spawn(process.env.ACTQL_PYTHON_WHEEL,[resolve('scripts/fixtures/python-client-faults.py'),phase,facade,endpoint,ca,custody],
    {cwd:root,env:{...process.env,PYTHONPATH:''},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',bytes=>{stdout+=bytes;});
  child.stderr.on('data',bytes=>{stderr+=bytes;appendFileSync(join(root,`${facade}-${phase}.stderr.log`),bytes,{mode:0o600});});
  await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>{
    if(code!==0||signal!==null)reject(new Error(`Python ${facade} ${phase} failed: ${code}, ${signal}\n${stderr}`));else resolve();});});
  assert.deepEqual(JSON.parse(stdout),{phase,facade,success:true});
}

for(const facade of ['async','sync'])test(`wheel: ${facade} original response loss, partial read, revocation, expiry and closed status`,async t=>{
  const scratch=resolve('_build/python-client-faults');await mkdir(scratch,{recursive:true});
  const root=await mkdtemp(join(scratch,'public-'));
  t.after(async()=>{if(process.env.ACTQL_TEST_PRESERVE_SCRATCH!=='1')await rm(root,{recursive:true,force:true});});
  const keys=generateKeyPairSync('ed25519'),principalId=userInfo().username;
  const cert=await fixtureCertificates(root);
  const keyPath=join(root,'host.key'),certificatePath=join(root,'host.crt');
  await writeFile(keyPath,cert.key,{mode:0o600});await writeFile(certificatePath,cert.cert);
  const config={directory:join(root,'host'),hostTls:{keyPath,certificatePath},authorization:{
    accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',account_id:'python-faults',
      entries:[{entry_id:'run',outcome:'allow',principal:{all:true},connection:{all:true},resource:{all:true},operation:{any_of:['write']},exclusions:[]}]}),
    reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId,publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
    hostKey:{keyId:'host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})}}};
  const path=join(root,'installation.json');await writeFile(path,JSON.stringify(config),{mode:0o600});
  const custody=join(root,'original.json'),phases=[],pids=[];
  const phase=async(name,fault)=>{
    const running=await host(path,fault,t);pids.push(running.pid);
    await consume(name,facade,running.endpoint,cert.caPath,custody,root);phases.push(name);
    if(name==='submit-loss')await consume('lookup',facade,running.endpoint,cert.caPath,custody,root);
    await running.close();
  };
  await phase('submit-loss','submit-intent');
  await phase('lookup','');
  await phase('cancel-loss','cancel');
  await phase('read-loss','read-prefix');
  await phase('malformed','status-extra-field');
  await phase('revoked','revoked');
  const requests=(await readFile(`${path}.python-requests.jsonl`,'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(requests.filter(item=>item.operation==='submit-intent').length,1,'Only the original explicit submit is sent');
  assert.equal(requests.filter(item=>item.operation==='cancel').length,1,'Only the original explicit cancel is sent');
  assert.equal(requests.filter(item=>item.operation==='read').length,3,'Lookup reads and the one interrupted original reader; no hidden replacement read');
  const events=(await readFile(`${path}.python-owner-events.jsonl`,'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(events.filter(item=>item.name==='computed').length,1,'Recovery never executes a new Run');
  assert.equal(events.filter(item=>item.name==='acquisition_started'||item.name==='effect_started'||item.name==='model_started').length,0);
  // A fresh original reference expires without ever admitting a Run.
  const expiryConfig={...config,directory:join(root,'expiry-host'),epochNow:1_800_000_000_000};
  const expiryPath=join(root,'expiry-installation.json'),expiryCustody=join(root,'expiry-original.json');
  await writeFile(expiryPath,JSON.stringify(expiryConfig),{mode:0o600});
  let running=await host(expiryPath,'',t);
  await consume('issue',facade,running.endpoint,cert.caPath,expiryCustody,root);await running.close();
  await writeFile(expiryPath,JSON.stringify({...expiryConfig,epochNow:1_800_000_001_100}),{mode:0o600});
  running=await host(expiryPath,'',t);
  await consume('expired',facade,running.endpoint,cert.caPath,expiryCustody,root);await running.close();
  let expiryEvents=[];try{expiryEvents=(await readFile(`${expiryPath}.python-owner-events.jsonl`,'utf8')).trim().split('\n').map(JSON.parse);}
  catch(error){if(error.code!=='ENOENT')throw error;}
  assert.equal(expiryEvents.filter(item=>item.name==='computed'||item.name==='acquisition_started').length,0);
  await writeFile(join(root,'receipt.json'),JSON.stringify({facade,phases,pids,requests,events,expiryEvents},null,2)+'\n',{mode:0o600});
});

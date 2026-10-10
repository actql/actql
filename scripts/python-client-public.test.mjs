// Actual HTTPS Host; Python is an external wheel consumer, never a TS SDK wrapper.
import assert from 'node:assert/strict';
import test from 'node:test';
import {spawn} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir,mkdtemp,rm,writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join,resolve} from 'node:path';
import {openInstalledRemoteHttpHost} from '../adapters/host-node/embedded-local.mjs';
import {fixtureCertificates} from '../adapters/site-node/https-exchange-fixture.mjs';

async function python(args,cwd) {
  assert.ok(process.env.ACTQL_PYTHON_WHEEL,'ACTQL_PYTHON_WHEEL must select the externally installed wheel interpreter');
  const child=spawn(process.env.ACTQL_PYTHON_WHEEL,args,{cwd,env:{...process.env,PYTHONPATH:''},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',value=>{stdout+=value;});child.stderr.on('data',value=>{stderr+=value;});
  await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>{
    if(code!==0)reject(new Error(`Python public consumer failed: code=${code}; signal=${signal}\n${stderr}`));else resolve();});});
  return JSON.parse(stdout);
}

test('wheel: async and sync normal, separate-process attach, text and structured diagnostics over actual HTTPS',async t=>{
  const scratch=resolve('_build/python-client-public');await mkdir(scratch,{recursive:true});
  const root=await mkdtemp(join(scratch,'public-'));
  const keys=generateKeyPairSync('ed25519'),principalId=userInfo().username;
  const counts={computed:0};
  const certificates=await fixtureCertificates(root);
  const host=await openInstalledRemoteHttpHost({directory:join(root,'host'),
    authenticate:header=>header==='Bearer fixture-token'?principalId:undefined,
    authorization:{accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',
      account_id:'python-public',entries:[{entry_id:'execution',outcome:'allow',principal:{all:true},
        connection:{all:true},resource:{all:true},operation:{any_of:['write']},exclusions:[]}]}),
      reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId,publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
      hostKey:{keyId:'host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
      observe(name){if(name==='computed')counts.computed++;}}});
  const server=createServer({key:certificates.key,cert:certificates.cert},(request,response)=>host.handler(request,response));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(async()=>{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await host.close();
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH!=='1')await rm(root,{recursive:true,force:true});});
  const endpoint=`https://127.0.0.1:${server.address().port}/`;
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
  for(const facade of ['async','sync']){
    const phase='authored';
    const receipt=await python([resolve('scripts/fixtures/python-client-public.py'),phase,facade,endpoint,certificates.caPath,join(root,`${facade}.custody.json`)],root);
    assert.deepEqual(receipt,{phase,facade,success:true});results.push(receipt);
  }
  assert.equal(counts.computed,10,'Exactly four explicit structured/AQL submissions compute.');
  await writeFile(join(root,'receipt.json'),JSON.stringify({results,counts},null,2)+'\n');
});

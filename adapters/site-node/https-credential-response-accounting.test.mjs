import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:https';
import test from 'node:test';
import {fixtureCertificates} from './https-exchange-fixture.mjs';
import * as resource from './https-credential-resource.mjs';

// Real original HTTPS binding/request/socket and explicit authority/Journal
// ports. This does not issue a Common grant or prove a normal funded Effect.
async function fixture(t, handle) {
  const root = await mkdtemp(join(process.env.ACTQL_TEST_SCRATCH_PARENT ?? tmpdir(), 'actql-response-accounting-'));
  const {ca, cert, key} = await fixtureCertificates(root);
  const server = createServer({cert, key}, handle);
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  const origin = `https://127.0.0.1:${server.address().port}`;
  const scope = Object.freeze({issuerAuthority:'authority',principal:'principal',namespaceId:'namespace',environment:'fixture',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:'runtime',connectorRegistration:'fixture',connectorRevision:'fixture/1',
    resourceOrigin:origin,runInvocationCid:'run',taskAttempt:1,dispatchRequestCid:'dispatch',operation:'create'});
  const grant = {}, use = {}, outcomes = [];
  let claims = 0;
  const control = {identity: () => 'original-grant'};
  const journal = {claim(){claims++;return {replayed:false,grant,use,record:{useCid:'original-use',grantCid:'original-grant'}};},
    authorize(){},finish(id, outcome){assert.equal(id,'original-use');outcomes.push(outcome);}};
  const resolveSecret = async () => 'fixture-secret';
  const binding = resource.openHttpsCredentialBinding({scope,control,journal,resolveSecret,maxSecretBytes:64,assertCurrent(){}});
  t.after(async()=>{
    assert.equal(resource.closeHttpsCredentialBinding(binding),'closed');
    await new Promise(resolve=>server.close(resolve));
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH==='1')t.diagnostic(`Retained owned TLS fixture: ${root}`);
    else await rm(root,{recursive:true,force:true});
  });
  const call = options => resource.callHttpsCredentialResource({grant,useId:'use',scope,control,journal,resolveSecret,binding,ca,
    currentBeforeSend:async()=>{},maxRequestBytes:1024,maxResponseBytes:64,
    operations:new Map([['create',{method:'POST',path:'/create',body:'{}'}]]),...options});
  return {call,outcomes,claims:()=>claims,binding};
}

test('bounded original response reader charges the actual refusal byte before discarding its oversized body',async t=>{
  let requests=0;
  const f=await fixture(t,(request,response)=>{requests++;response.writeHead(200);response.end('x'.repeat(8192));});
  const lengths=[];
  await assert.rejects(f.call({observeResponseBytes:n=>{lengths.push(n);}}),{code:'RemoteCredentialResponseLimitExceeded'});
  assert.deepEqual(lengths,[65]);
  assert.equal(requests,1);assert.equal(f.claims(),1);assert.deepEqual(f.outcomes,['unknown']);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding),'closed');
});

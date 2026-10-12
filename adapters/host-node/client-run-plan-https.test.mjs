// Real TLS ingress with independent service facts. No compiler/Run execution
// fixture is installed here; this is transport evidence, not public product E2E.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates,setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {ref,cid} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
import {planOriginal} from './fixtures/original-plan-journal.mjs';
test('TLS Run.plan preserves the original ref and rejects foreign envelopes without submit',async t=>{
  const root=await mkdtemp(join(tmpdir(),'actql-d-run-plan-tls-'));
  const trust=getCACertificates('default');let server,client,reads=0,starts=0,foreign=false,complete=false;
  t.after(async()=>{try {
    await client?.close();if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
    if(complete) await rm(root,{recursive:true,force:true});else t.diagnostic(`Failure fixture retained at ${root}`);
  } finally {setDefaultCACertificates(trust);}});
  const certificates=await fixtureCertificates(root);setDefaultCACertificates([...trust,certificates.ca.toString('utf8')]);
  const profile={version:'actql-client-host/0.1',mode:'remote',owner:'remote',durability:'volatile',
    scopeRef:'run-plan-tls',capabilities:[],limits:{maxReadWireBytes:4096,maxRowWireBytes:1024,
      maxRowRetainedValueBytes:1024,maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:10,maxBatchRetainedValueBytes:2048}};
  server=createServer({key:certificates.key,cert:certificates.cert},createClientHttpHandler({
    authenticate:()=> 'original-caller',authorizeConnection:()=> true,negotiate:()=>profile,
    attach:value=>({ref:value.ref,durability:'volatile',revision:0}),
    runPlan(value){reads++;assert.deepEqual(value.ref,ref);return {version:'actql-run-plan-view/0.1',
      run_ref:foreign?{...ref,runDefinitionCid:cid('0')}:{...ref},plan_view:JSON.parse(planOriginal.planViewWire)};},
    submit(){starts++;throw Error('unexpected submit');}}));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  client=await connect({mode:'remote',token:'fixture-caller',endpoint:`https://127.0.0.1:${server.address().port}/`});
  const run=await client.attach(ref);assert.deepEqual((await run.plan()).run_ref,ref);
  // Existing HTTP redaction masks a Host's invalid reply as ClientHostFailure.
  foreign=true;await assert.rejects(run.plan(),{code:'ClientHostFailure'});
  assert.equal(reads,2);assert.equal(starts,0);complete=true;
});

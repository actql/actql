import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {getCACertificates,setDefaultCACertificates} from 'node:tls';
import {tmpdir,userInfo} from 'node:os';
import {join} from 'node:path';
import {connect as remote, explainOwnerObservations, formatOwnerObservations} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal,openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';

for(const entrance of ['local','https']) {
  test(`${entrance}: actual Run snapshots report unsupported history without repeating Compute`,async t=>{
    const root=await mkdtemp(join(tmpdir(),'actql-owner-observation-public-'));
    const principalId=userInfo().username,keys=generateKeyPairSync('ed25519');
    let computes=0,client,host,server;
    const authorization={accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',
      account_id:'owner-observation',entries:[{entry_id:'execution',outcome:'allow',principal:{all:true},
        connection:{all:true},resource:{all:true},operation:{any_of:['write']},exclusions:[]},
        {entry_id:'host-read',outcome:'allow',principal:{any_of:[principalId]},
          connection:{any_of:['actql-remote-host']},resource:{any_of:['result/main','run']},
          operation:{any_of:['read']},exclusions:[]}]}),
      reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId,publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
      hostKey:{keyId:'host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
      observe(name){if(name==='computed')computes++;}};
    const installation={directory:join(root,'host'),authorization};
    const trust=getCACertificates('default');
    t.after(async()=>{await client?.close();if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
      await host?.close();setDefaultCACertificates(trust);await rm(root,{recursive:true,force:true});});
    if(entrance==='local')client=await connectEmbeddedLocal({mode:'local',owner:'local',durability:'durable',installation});
    else {
      const certificates=await fixtureCertificates(root);
      setDefaultCACertificates([...trust,certificates.ca.toString('utf8')]);
      host=await openInstalledRemoteHttpHost({...installation,authenticate:()=>principalId});
      server=createServer({key:certificates.key,cert:certificates.cert},(request,response)=>host.handler(request,response));
      await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
      client=await remote({mode:'remote',token:'fixture-caller',durability:'durable',endpoint:`https://127.0.0.1:${server.address().port}/`});
    }
    const run=await client.startSource('SELECT 1 AS n',{format:'sql',submissionRef:client.newSubmission({nonce:'observe-original'})});
    const state=await run.wait({signal:AbortSignal.timeout(15000)});
    assert.equal(state.status,'succeeded');assert.deepEqual(await run.result('main').all(),[{n:1}]);
    const first=await run.observeOwners();
    assert.equal(first.consistency,'non_atomic');assert.equal(first.ordering,'owner_local');
    assert.deepEqual(first.ref,run.ref);assert.equal(first.owners.length,1);
    assert.equal(first.owners[0].history.kind,'not_provided');
    assert.equal(first.owners[0].snapshot.value.status,'succeeded');
    assert.equal(first.owners[0].snapshot.revision,undefined);
    assert.equal(first.revisionVector[0].snapshotRevision,undefined);
    assert.match(first.revisionVector[0].snapshotCid,/^sha256:[a-f0-9]{64}$/u);
    const explanation=explainOwnerObservations(first);
    assert.equal(explanation.owners[0].history.kind,'not_provided');
    assert.equal(explanation.owners[0].history.summary,'This Owner provides a current view without transition history.');
    assert.equal(explanation.consistency,'non_atomic');
    assert.equal(explanation.controlRevision,undefined);
    assert.equal(explanation.owners[0].snapshot.revision,undefined);
    assert.deepEqual(explanation.ref,run.ref);
    assert.equal(explainOwnerObservations(structuredClone(first)),undefined);
    assert.deepEqual(JSON.parse(formatOwnerObservations(first,{format:'json'})).explanation,explanation);
    const second=await run.observeOwners({cursors:[{owner:first.owners[0].ownerRef,value:'expired-or-foreign'}]});
    assert.equal(second.owners[0].history.kind,'cursor_mismatch');
    assert.equal(explainOwnerObservations(second).owners[0].history.kind,'cursor_mismatch');
    assert.deepEqual(explainOwnerObservations(first),explanation);
    assert.equal(second.owners[0].snapshot.value.control.revision,state.control.revision);
    assert.equal((await run.status()).control.revision,state.control.revision);
    assert.equal(computes,1);
  });
}

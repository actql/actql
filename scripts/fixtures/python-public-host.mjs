// Shared existing normal Remote Host fixture; no SDK or permission substitute.
import {generateKeyPairSync} from 'node:crypto';
import {mkdir,mkdtemp,rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join,resolve} from 'node:path';
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';
import {fixtureCertificates} from '../../adapters/site-node/https-exchange-fixture.mjs';

export async function openPythonPublicHost(t,{workspaceId}={}){
  const scratch=resolve('_build/python-client-public');await mkdir(scratch,{recursive:true});
  const root=await mkdtemp(join(scratch,'public-'));
  const keys=generateKeyPairSync('ed25519'),principalId=userInfo().username;
  const counts={computed:0};
  const certificates=await fixtureCertificates(root);
  const options={directory:join(root,'host'),
    ...(workspaceId===undefined?{}:{workspaceId}),
    authenticate:header=>header==='Bearer fixture-token'?principalId:undefined,
    authorization:{accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',
      account_id:'python-public',entries:[{entry_id:'execution',outcome:'allow',principal:{all:true},
        connection:{all:true},resource:{all:true},operation:{any_of:['write']},exclusions:[]}]}),
      reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId,publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
      hostKey:{keyId:'host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
      observe(name){if(name==='computed')counts.computed++;}}};
  let host=await openInstalledRemoteHttpHost(options);
  const server=createServer({key:certificates.key,cert:certificates.cert},(request,response)=>host.handler(request,response));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(async()=>{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await host.close();
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH!=='1')await rm(root,{recursive:true,force:true});});
  const endpoint=`https://127.0.0.1:${server.address().port}/`;
  return {root,certificates,counts,endpoint,reopen:async()=>{
    // Same directory/config/keys, after the original Host confirms close.
    // A failed close stops here and leaves that same Host for t.after cleanup.
    await host.close();
    host=await openInstalledRemoteHttpHost(options);
  }};
}


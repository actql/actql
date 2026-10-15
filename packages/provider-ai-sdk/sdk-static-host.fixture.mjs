import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {originalMaterialsConfiguration} from './original-materials.fixture.mjs';
import {createInstalledOpenAIChatRegistration,createInstalledUndiciOpenAIChatRegistration} from './index.mjs';
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';

// Same existing independent material vectors, actual matching Common readers,
// actual selected startup/Host and SQLite. No Run or resource grant is issued.
const route=process.argv[2];
assert.ok(['generic','Undici'].includes(route));
const config=originalMaterialsConfiguration();
if(route==='Undici'){
  delete config.fetch;
  config.physicalAcquisitionLimits={maxPlaintextBytes:65536,maxBorrowedBackingBytes:131072,maxReads:64};
}
const create=route==='Undici'?createInstalledUndiciOpenAIChatRegistration:createInstalledOpenAIChatRegistration;
const register=create(config);
const moon=await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
const root=await mkdtemp(join(tmpdir(),'actql-original-materials-static-host-'));
let host,callbacks=0;
try{
  const options={directory:root,authenticate:()=> 'owner',registerModelProviders:actual=>{
    callbacks++;assert.strictEqual(actual,moon);return register(actual);
  }};
  host=await openInstalledRemoteHttpHost(options);
  await host.close();await host.close();host=undefined;
  assert.equal(callbacks,1);
  await assert.rejects(openInstalledRemoteHttpHost(options),error=>
    error.code==='OpenAIOriginalInstallationReused'||error.cause?.code==='OpenAIOriginalInstallationReused');
  assert.equal(callbacks,2);
}finally{
  if(host!==undefined)await host.close();
  await rm(root,{recursive:true,force:true});
}
console.log(JSON.stringify({route,callbacks,hostClosed:true,providerCalls:0,coreScopes:0,
  normalNumericProfile:null,publicE2E:0}));

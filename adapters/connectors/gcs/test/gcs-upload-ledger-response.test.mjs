// Actual existing Core/Effect Ledger and request provider. The physical port
// is controlled: this is not GCS, Account approval or installed STORE acceptance.
import assert from 'node:assert/strict';
import {mkdtemp,mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {captureClaimedEffectResponse} from '../../../host-node/effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from '../../../host-node/effect-response-recovery.mjs';
import {prepareGcsCollectionTarget,prepareGcsCollectionUploadBinding} from '../host/gcs-collection-target.mjs';
import {admitGcsUploadObservation,prepareOwnedGcsMultipartUpload,sendOwnedGcsUpload,
  projectOwnedGcsUploadResponse} from '../site/gcs-owned-upload-request.mjs';

const token=digit=>`sha256:${digit.repeat(64)}`;
async function fixture(t){
 const collection=prepareGcsCollectionTarget(provider,{project:'project',bucket:'bucket',
  prefix:'in/',targetRef:'connector://exports/objects',resourceKind:'file_collection',
  catalogCid:token('a'),installationCid:token('b'),maxBytes:8192,maxNodes:100,maxDepth:8});
 const binding=prepareGcsCollectionUploadBinding(collection,{commandCid:token('c'),
  permissions:['storage.objects.create','storage.objects.delete','storage.objects.get'],
  metadata:{maxBytes:8192,maxNodes:100,maxDepth:8,maxEntries:4},maxContentBytes:32,
  maxBodyBytes:2048,maxPathBytes:4096,maxIdentityBytes:4096});
 const before=admitGcsUploadObservation(provider,binding,{name:'in/a.bin',statusCode:404,body:Buffer.from('{}')});
 const request=prepareOwnedGcsMultipartUpload({moon:provider,binding,before,
  contentBytes:Buffer.from([0,255,13,10]),contentRefCid:token('f'),
  contentCid:'sha256:e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be',
  mediaType:'application/octet-stream',marker:token('d'),maxProjectionBytes:8192});
 const control=runtimeCore(common).effectApplicationControl;
 const scope=control.logicalRequestScope(token('a'),'upload-request',64);
 const key=control.dispatchKey(scope,token('b'),'"row-1"',64,8,3);
 const locator=control.logicalItemLocator(scope,'program','stage','Upload','{"row":"1"}',64,128,8,3);
 const basis=control.ledgerBasis(scope,locator,key,token('c'),token('d'),token('e'),
  request.request_cid,token('0'),'unavailable',token('1'),token('2'));
 const claim={scope,locator,key,basis,intentFingerprintCid:token('e'),canonicalRequestCid:request.request_cid};
 const parent=new URL('../../../../_build/gcs-upload-ledger-evidence/',import.meta.url).pathname;
 await mkdir(parent,{recursive:true});
 const root=await mkdtemp(join(parent,'original-'));
 // These fresh original Ledger/response files are retained, including failures
 // and possible-dispatch records. No old Run/DB or Provider attempt is touched.
 t.diagnostic(`Original upload Ledger evidence retained at ${root}`);
 const handles=new Set();
 const open=()=>{const value=openEffectLedger({moon:common,root,authorityScopeCid:token('a'),
  callerRequestId:'upload-request',maxEntryBytes:8192});handles.add(value);return value;};
 const close=handle=>{handle.close();handles.delete(handle);};
 t.after(()=>{for(const handle of handles)close(handle);});
 const send=callResource=>sendOwnedGcsUpload({request,
  authorization:{grant:{},useId:'controlled-response-only',scope:{
   resourceOrigin:'https://storage.googleapis.com',operation:'gcs:object:upload'}},
  credential:{},callResource,maxRequestBytes:2048,maxResponseBytes:8192});
 return{control,claim,request,open,close,send};
}

test('actual Core upload response reopens from the same Ledger after evidence authorization without a resend',async t=>{
 const f=await fixture(t),ledger=f.open();let sends=0;
 const bytes=Buffer.from(JSON.stringify({bucket:'bucket',name:'in/a.bin',generation:'9007199254740994',
  metageneration:'1',size:'4',contentType:'application/octet-stream',crc32c:'crxyRA==',
  metadata:{'actql-request':token('d')}}));
 const captured=await captureClaimedEffectResponse({ledger,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>f.send(async()=>{sends++;return{useCid:token('3'),accepted:true,statusCode:200,body:bytes,headers:[]};})});
 assert.deepEqual(projectOwnedGcsUploadResponse(f.request,captured.physical.observation,1024),
  {kind:'typed-success-response',outcome:{state:'applied',result:{}}});
 f.close(ledger);const restarted=f.open();
 let views=0;
 const recovery={ledger:restarted,claims:f.claim,commonMoon:common,
  expectedRequestCid:f.request.request_cid,authorizeEvidenceRead:async binding=>{
   views++;assert.equal(binding.canonicalRequestCid,f.request.request_cid);return true;},
  projectStored:stored=>projectOwnedGcsUploadResponse(f.request,
   {statusCode:stored.statusCode,body:stored.responseBytes},1024)};
 const recovered=await recoverProjectedEffectResponse(recovery);
 assert.equal(recovered.recovered.outcome.state,'applied');assert.equal(views,1);
 await assert.rejects(recoverProjectedEffectResponse({...recovery,authorizeEvidenceRead:async()=>false}),
  {code:'EffectEvidenceAccessDenied'});
 const otherScope=f.control.logicalRequestScope(token('b'),'upload-request',64);
 await assert.rejects(recoverProjectedEffectResponse({...recovery,claims:{...f.claim,scope:otherScope}}),
  {code:'ForeignEffectResponse'});
 const again=await captureClaimedEffectResponse({ledger:restarted,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>assert.fail('Core possible-dispatch custody cannot authorize another send')});
 assert.equal(again.claimed,false);assert.equal(sends,1);
});

test('actual Core unknown upload retains the original lost reply and rejects a new send after reopen',async t=>{
 const f=await fixture(t),ledger=f.open();let sends=0;
 const failure=Object.freeze(Object.assign(new Error('original upload response lost'),{cleanupPending:true}));
 await assert.rejects(captureClaimedEffectResponse({ledger,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>f.send(async()=>{sends++;throw failure;})}),error=>error===failure);
 assert.equal(ledger.readClaimedResponse(f.claim),undefined);
 f.close(ledger);const restarted=f.open();
 const again=await captureClaimedEffectResponse({ledger:restarted,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>assert.fail('Unknown is never an unsent upload')});
 assert.equal(again.claimed,false);assert.equal(sends,1);
 assert.equal(restarted.readClaimedResponse(f.claim),undefined);
});

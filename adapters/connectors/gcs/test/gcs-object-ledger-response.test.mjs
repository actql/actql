// Actual existing Core/Effect Ledger with separately qualified retained Common
// runtime and fresh GCS bridge; explicit physical ports, no Account or GCS call.
import assert from 'node:assert/strict';
import {mkdir,mkdtemp} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {captureClaimedEffectResponse} from '../../../host-node/effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from '../../../host-node/effect-response-recovery.mjs';
import {admitGcsObjectMetadata,prepareGcsObjectBinding,prepareOwnedGcsMetadataPatch,
  prepareOwnedGcsObjectDelete,projectOwnedGcsObjectResponse,sendOwnedGcsObjectRequest}
  from '../site/gcs-owned-object-request.mjs';

const token=digit=>`sha256:${digit.repeat(64)}`;
async function fixture(t,kind){
 const metadata={maxBytes:8192,maxNodes:1000,maxDepth:12,maxEntries:16};
 const original=admitGcsObjectMetadata(provider,{bucket:'bucket',prefix:'in/',limits:metadata,
  bytes:Buffer.from(JSON.stringify({bucket:'bucket',name:'in/a.csv',generation:'9007199254740993',
   metageneration:'2',size:'7',metadata:{drop:'old',keep:'kept','actql-request':'old'}}))});
 const binding=prepareGcsObjectBinding(provider,{kind,bucket:'bucket',prefix:'in/',
  catalogCid:token('a'),installationCid:token('b'),contractCid:token('c'),
  permissions:[kind==='delete'?'storage.objects.delete':'storage.objects.update'],
  metadata,maxPathBytes:4096,maxBodyBytes:8192,maxIdentityBytes:16384});
 const request=kind==='delete'?prepareOwnedGcsObjectDelete({moon:provider,binding,original,maxProjectionBytes:8192})
  :prepareOwnedGcsMetadataPatch({moon:provider,binding,original,value:{content_type:'text/csv',
   metadata:{keep:'kept',new:'=e\u0301\r\n'}},marker:token('d'),maxProjectionBytes:8192});
 const control=runtimeCore(common).effectApplicationControl;
 const scope=control.logicalRequestScope(token('a'),'mutation-'+kind,64);
 const key=control.dispatchKey(scope,token('b'),'"row-1"',64,8,3);
 const locator=control.logicalItemLocator(scope,'program','stage','Mutation','{"row":"1"}',64,128,8,3);
 const basis=control.ledgerBasis(scope,locator,key,token('c'),token('d'),token('e'),request.request_cid,
  token('0'),'unavailable',token('1'),token('2'));
 const claim={scope,locator,key,basis,intentFingerprintCid:token('e'),canonicalRequestCid:request.request_cid};
 const parent=new URL('../../../../_build/gcs-object-ledger-evidence/',import.meta.url).pathname;
 await mkdir(parent,{recursive:true});const root=await mkdtemp(join(parent,'original-'));
 t.diagnostic(`Original mutation Ledger/response evidence retained at ${root}`);
 const handles=new Set();
 const open=()=>{const ledger=openEffectLedger({moon:common,root,authorityScopeCid:token('a'),
  callerRequestId:'mutation-'+kind,maxEntryBytes:8192});handles.add(ledger);return ledger;};
 const close=ledger=>{ledger.close();handles.delete(ledger);};
 t.after(()=>{for(const ledger of handles)close(ledger);});
 const send=callResource=>sendOwnedGcsObjectRequest({request,authorization:{grant:{},useId:'physical-counter',
  scope:{resourceOrigin:'https://storage.googleapis.com',operation:request.operation}},credential:{},callResource,
  maxRequestBytes:16384,maxResponseBytes:8192});
 return{control,claim,request,open,close,send};
}

for(const kind of ['patch_metadata','delete'])test(`actual Core ${kind} direct response reopens without resend and refuses unauthorized evidence`,async t=>{
 const f=await fixture(t,kind),ledger=f.open();let sends=0;
 const body=kind==='delete'?Buffer.alloc(0):Buffer.from(JSON.stringify({bucket:'bucket',name:'in/a.csv',
  generation:'9007199254740993',metageneration:'3',size:'7',contentType:'text/csv',
  metadata:{keep:'kept',new:'=e\u0301\r\n','actql-request':token('d')}}));
 const statusCode=kind==='delete'?204:200;
 const captured=await captureClaimedEffectResponse({ledger,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>f.send(async()=>{sends++;return{accepted:true,useCid:token('3'),statusCode,body,headers:[]};})});
 assert.equal(projectOwnedGcsObjectResponse(f.request,captured.physical.observation,1024).outcome.state,'applied');
 f.close(ledger);const reopened=f.open();let reads=0;
 const recovery={ledger:reopened,claims:f.claim,commonMoon:common,expectedRequestCid:f.request.request_cid,
  authorizeEvidenceRead:async binding=>{reads++;assert.equal(binding.canonicalRequestCid,f.request.request_cid);return true;},
  projectStored:stored=>projectOwnedGcsObjectResponse(f.request,{statusCode:stored.statusCode,body:stored.responseBytes},1024)};
 assert.equal((await recoverProjectedEffectResponse(recovery)).recovered.outcome.state,'applied');
 assert.equal(reads,1);
 await assert.rejects(recoverProjectedEffectResponse({...recovery,authorizeEvidenceRead:async()=>false}),
  {code:'EffectEvidenceAccessDenied'});
 const again=await captureClaimedEffectResponse({ledger:reopened,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>assert.fail('Original possible-dispatch cannot authorize a resend')});
 assert.equal(again.claimed,false);assert.equal(sends,1);
});

test('actual Core lost delete reply stays unknown after reopen and later absence cannot settle or resend',async t=>{
 const f=await fixture(t,'delete'),ledger=f.open();let sends=0;
 const failure=Object.freeze(Object.assign(new Error('original delete reply lost'),{cleanupPending:true}));
 await assert.rejects(captureClaimedEffectResponse({ledger,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>f.send(async()=>{sends++;throw failure;})}),error=>error===failure);
 assert.equal(ledger.readClaimedResponse(f.claim),undefined);
 assert.deepEqual(projectOwnedGcsObjectResponse(f.request,{statusCode:404,body:Buffer.from('{}')},1024),
  {kind:'provider-response'});
 f.close(ledger);const reopened=f.open();
 const again=await captureClaimedEffectResponse({ledger:reopened,claim:f.claim,requestCid:f.request.request_cid,
  execute:()=>assert.fail('Unknown delete is not unsent')});
 assert.equal(again.claimed,false);assert.equal(sends,1);
 assert.equal(reopened.readClaimedResponse(f.claim),undefined);
});

// Actual portable request and original preparation child. Credential/transport
// controls below are explicit: not installed funding, authority or dispatch.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsObjectBinding, createGcsMutationRequestChild,
  borrowOwnedGcsObjectDeleteTarget, ownedGcsObjectRequestCid}
  from '../site/gcs-owned-object-request.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const raw = Buffer.from('{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7","metadata":{"keep":"=é\\r\\n","actql-request":"old"}}');
function fixture(overrides = {}) {
  const kind = overrides.kind ?? 'delete';
  const binding = prepareGcsObjectBinding(moon, {kind, bucket:'bucket',prefix:'in/',
    catalogCid:cid('a'),installationCid:cid('b'),contractCid:cid('c'),
    permissions:['storage.objects.get',kind === 'delete' ? 'storage.objects.delete':'storage.objects.update'],
    metadata:{maxBytes:8192,maxNodes:1000,maxDepth:12,maxEntries:16},
    maxPathBytes:4096,maxBodyBytes:8192,maxIdentityBytes:16384});
  const scope = {issuerAuthority:'fixture',principal:'operator',namespaceId:'fixture',environment:'test',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:cid('a'),connectorRegistration:'gcs',
    connectorRevision:'gcs/0.1',resourceOrigin:'https://storage.googleapis.com',operation:'gcs:file:read',
    runInvocationCid:cid('b'),taskAttempt:1,dispatchRequestCid:cid('c'),
    expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:1};
  let reads=0,fences=0,current=true;
  const child=createGcsMutationRequestChild({moon,binding,kind,name:'in/é%2F.csv',
    value:kind==='delete'?{}:{content_type:'text/csv'},marker:cid('d'),
    maxProjectionBytes:8192,maxRequestBytes:4096,maxSecretBytes:128,
    credential:{control:{identity:()=>cid('a')},journal:{claim(){},authorize(){},finish(){}},
      resolveSecret:async()=>'fixture-only'},
    authorizationForRow:async()=>({scope,grant:{},useId:'original-read'}),
    assertCurrent(){fences++;if(!current)throw new Error('OriginalSiteRetired');},
    callResource:async()=>{reads++;return{accepted:true,statusCode:200,useCid:cid('e'),body:raw,headers:[]};},
    ...overrides});
  return{child,binding,reads:()=>reads,fences:()=>fences,revoke:()=>{current=false;}};
}

test('original DELETE child projects its one before read with exact guard and no after/value',async t=>{
  const f=fixture();t.after(()=>f.child.release());
  const{request}=await f.child.prepare();
  const view=borrowOwnedGcsObjectDeleteTarget(request,8192,f.binding);
  const fences=f.fences(),row=view.readFor(request);
  assert.equal(f.fences(),fences+2);
  assert.deepEqual(row,{identity:'in/é%2F.csv',versionCid:hash(raw),
    before:{name:'in/é%2F.csv',content_type:null,metadata:{$json:{keep:'=é\r\n'}}},
    requestCid:ownedGcsObjectRequestCid(request,f.binding)});
  assert.equal(request.method,'DELETE');assert.equal(request.body,'');
  assert(request.path.endsWith('ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2'));
  assert.equal(f.reads(),1);assert.equal(f.child.status().pending,true);
  assert(Object.isFrozen(row.before.metadata.$json));
  view.retire();
  assert.throws(()=>view.readFor(request),{code:'ForeignGcsObjectPreview'});
  assert.equal(f.child.status().pending,true,'view retirement is not child/physical ACK');
  assert.equal(await f.child.release(),true);
});

test('DELETE target rejects copied receiver/request, foreign purpose and retired original child',async t=>{
  const f=fixture(),patch=fixture({kind:'patch_metadata'});
  t.after(async()=>{await f.child.release();await patch.child.release();});
  const{request}=await f.child.prepare();
  const view=borrowOwnedGcsObjectDeleteTarget(request,8192,f.binding);
  assert.throws(()=>({...view}).readFor(request),{code:'ForeignGcsObjectPreview'});
  assert.throws(()=>view.readFor({...request}),{code:'ForeignGcsObjectPreview'});
  const patchRequest=(await patch.child.prepare()).request;
  assert.throws(()=>borrowOwnedGcsObjectDeleteTarget(patchRequest,8192),{code:'GcsInvalidObjectBinding'});
  f.revoke();assert.throws(()=>view.readFor(request),/OriginalSiteRetired/u);
  assert.equal(f.reads(),1);
  assert.equal(await f.child.release(),true);
  assert.throws(()=>view.readFor(request),{code:'ForeignGcsObjectRequest'});
});

test('DELETE target does not escape after projection callback retires the original child',async t=>{
  let child,retireOnProjection=false;
  const selected={...moon,gcsObjectDeleteEffectTarget(...args){
    const row=moon.gcsObjectDeleteEffectTarget(...args);
    if(retireOnProjection)void child.release();
    return row;
  }};
  const f=fixture({moon:selected});child=f.child;t.after(()=>child.release());
  const{request}=await child.prepare();
  const view=borrowOwnedGcsObjectDeleteTarget(request,8192,f.binding);
  retireOnProjection=true;
  assert.throws(()=>view.readFor(request),{code:'ForeignGcsObjectRequest'});
  assert.equal(f.reads(),1);
  await child.release();
  assert.equal(child.status().pending,false);
});

// Actual Common/GCS, SQLite journals and encrypted Store capture. The finite
// credential/transport preparation below is an explicit component control,
// not a normal original resource supplier or an installed GCS send route.
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as gcs from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {createInstalledRowEffect} from '../../../host-node/installed-row-effect.mjs';
import {installRowSourceAuthorization,rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {effectHost} from '../../../host-node/fixtures/installed-row-effect.fixture.mjs';
import {restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';
import {openGcsCredentialSite} from '../site/gcs-credential-site.mjs';
import {prepareGcsObjectBinding,createGcsMutationRequestChild,
  borrowOwnedGcsObjectDeleteTarget,ownedGcsObjectRequestCid} from '../site/gcs-owned-object-request.mjs';

const rootURL=new URL('../../../../',import.meta.url);
const wire=value=>canonicalJson(value,{dataKeys:true});
const cid=value=>`sha256:${createHash('sha256').update(typeof value==='string'||Buffer.isBuffer(value)?value:wire(value)).digest('hex')}`;
const name='in/é%2F.csv';
const raw=Buffer.from('{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7","metadata":{"keep":"=é\\r\\n","actql-request":"previous-marker"}}');
const program=mapping=>({version:'actql/0.1',id:'gcs-original-delete-capture',stages:[{
 id:'original',inputs:{},steps:[{values:{schema:{name:{type:'string',nullable:false}},rows:[{name}]},as:'rows'}],
 results:{selected:{from:'rows',fields:['name']}},effects:{remove:{delete:{target:mapping.target_ref,
  mapping:mapping.mapping_ref,from:{result:'selected'},id:'name'}}}}],
 results:{answer:{from:{stage:'original',result:'selected'}}}});

async function fixture(t,{substituteTarget=false}={}){
 const scratch=await createOwnedScratch({parent:new URL('../../../../_build/',import.meta.url).pathname,
  prefix:'gcs-common-delete-',label:'Actual Common/GCS original DELETE capture'});
 const root=scratch.path,closes=[],children=[],views=new WeakMap();
 let site,effect,closed=false;
 const state={reads:0,sends:0,children:0,readUses:[]};
 t.after(async()=>{
  for(const close of closes.reverse())await close();
  effect?.close();
  if(site!==undefined)site.close();
  closed=true;
  for(const child of children){if(child.status().pending)await child.retry();assert.equal(child.status().pending,false);}
  scratch.passed();
 });
 const account=wire({version:'actql-execution-account-config/0.1',account_id:'gcs-delete-component',
  entries:[{entry_id:'read',outcome:'allow',principal:{all:true},connection:{any_of:['gcs:project/bucket']},
    resource:{any_of:['objects']},operation:{any_of:['read']},exclusions:[]}]});
 const profile={version:'actql-installed-gcs-source/0.1',connectorId:'exports',project:'project',bucket:'bucket',prefix:'in/',
  mediaType:'application/pdf',siteProfilePath:join(root,'site.json'),accountConfigurationWire:account,
  limits:{maxListingItems:3,maxExaminedItems:9,maxPages:4,maxAttempts:4,maxListingBytes:32768,
   maxDurationMs:10000,maxPathBytes:1024,maxPageBytes:8192,maxPageItems:9,maxRequestBytes:4096,maxContentBytes:4096}};
 const{declared}=restoreGcsSourceDeclaration(common,profile,undefined,{includeObjects:true});
 const declarationWire=JSON.stringify(declared);
 const bindingWith=contractCid=>prepareGcsObjectBinding(gcs,{kind:'delete',bucket:'bucket',prefix:'in/',
  catalogCid:declared.catalog_cid,installationCid:cid('same original installation'),contractCid,
  permissions:['storage.objects.get','storage.objects.delete'],metadata:{maxBytes:8192,maxNodes:1000,maxDepth:16,maxEntries:16},
  maxPathBytes:4096,maxBodyBytes:8192,maxIdentityBytes:16384});
 const mappingOf=binding=>checked(gcs.gcsObjectMutationMappingJson(binding,declarationWire,'exports',1000000,100000,64));
 const mappingWire=mappingOf(bindingWith(cid('declaration preparation only'))),mapping=JSON.parse(mappingWire);
 const binding=bindingWith(mapping.mapping_contract_cid);
 assert.equal(mappingOf(binding),mappingWire,'actual binding and same Mapping must have exact correspondence');
 const environment=rowSourceCheckEnvironment(await readFile(new URL('spec/local-check-environment.json',rootURL),'utf8'),declared,[mapping]);
 const authorization=await installRowSourceAuthorization({root,principalId:'principal-a',connectorRegistration:'gcs',accountConfiguration:account});
 const keys=generateKeyPairSync('ed25519'),key=join(root,'credential.key');
 await writeFile(key,keys.privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600});
 const runtimeBundleCid=cid(await readFile(new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',rootURL)));
 site=await openGcsCredentialSite({profile:{credentialPrivateKeyPath:key,credentialAuthorityId:'component-authority',
  credentialKeyId:'component-key',journalRoot:join(root,'credential-journal'),namespaceId:'namespace-a',environment:'test',
  siteKey:'same-original-site',siteGeneration:1,resourceOrigin:'https://storage.googleapis.com'},
  principalId:'principal-a',authorization,connection:'gcs:project/bucket',connectorRegistration:'gcs',connectorRevision:'gcs/0.1',
  runtimeBundleCid,commonMoon:common,admitsApprovalTarget:()=>false,
  resolveSecret:async()=>assert.fail('The explicit transport control never resolves a credential')});
 const requestCid=request=>ownedGcsObjectRequestCid(request,binding);
 const driver={kinds:['delete'],targetRead:{operation:'gcs:file:read'},writeOperation:()=> 'gcs:object:delete',
  prepareRequest(){assert.fail('Original DELETE capture must not use a pure fallback');},
  prepareRequestChild(context){
   assert.equal(context.member.kind,'delete');assert.equal(context.member.resource,'objects');
   assert.equal(context.value,undefined);assert.equal(context.selector,name);assert.equal(context.rowIndex,0);
   assert.equal(typeof context.authorizationForRow,'function');state.children++;
   const child=createGcsMutationRequestChild({moon:gcs,binding,kind:'delete',name:context.selector,value:{},
    maxRequestBytes:4096,maxProjectionBytes:8192,maxSecretBytes:128,credential:site.credential,
    authorizationForRow:async()=>{const grant=await context.authorizationForRow();state.readUses.push(grant.useId);return grant;},
    assertCurrent(){if(closed||!site.referenceCurrent())throw new Error('OriginalSiteRetired');context.assertCurrent?.();},
    signal:context.signal,callResource:async options=>{
     assert.equal(options.operations.get('gcs:file:read').method,'GET');state.reads++;
     return{accepted:true,useCid:cid('original read control'),statusCode:200,headers:[],body:raw};}});
   children.push(child);
   return Object.freeze({async prepare(){const original=await child.prepare();
     views.set(original.request,borrowOwnedGcsObjectDeleteTarget(original.request,8192,binding));return original;},
    release:()=>child.release(),retry:()=>child.retry(),status:()=>child.status()});
  },
  requestFacts(request){requestCid(request);return{target:substituteTarget?'in/foreign':request.before.name};},requestCid,
  recheckRequests({entries}){for(const entry of entries)requestCid(entry.request);},
  async observeTargets({entries}){return entries.map(entry=>{
    const view=views.get(entry.request);assert(view,'the same original child must supply before');return view.readFor(entry.request);
  });},
  footprint:()=>({providerNamespace:'gcs',resourceKind:'file',boundaryCid:declared.catalog_cid}),
  recoveryEntry:({entries})=>({kind:'gcs-delete-component-originals',observationCid:cid(raw),
    wire:wire({request_cids:entries.map(entry=>requestCid(entry.request))})}),
  recoverRequests(){assert.fail('Authenticated cold recovery is a separate existing-Owner boundary');},
  send(){state.sends++;assert.fail('Required approval capture must never send');},
  project(){assert.fail('No mutation response is available before approval');}};
 effect=await createInstalledRowEffect({moon:common,mappings:[{resource:'objects',mappingRef:mapping.mapping_ref,
  mappingCid:mapping.mapping_contract_cid,body:mappingWire}],environmentWire:environment.wire,
  connectorId:'exports',connectorRegistration:'gcs',connectorRevision:'gcs/0.1',connection:'gcs:project/bucket',
  site,authorization,runtimeBundleCid,bindingCid:cid('same original installation'),ledgerRoot:join(root,'effect-ledger'),driver});
 const host=await effectHost(t,{onClose:close=>closes.push(close)},join(root,'host'),{effect,stopBeforeApply:true});
 return{root,host,state,mapping,children};
}

test('actual Common captures same GCS DELETE child before/version with absent after and required approval',async t=>{
 const f=await fixture(t),result=await f.host.run(program(f.mapping),'same-gcs-delete');
 assert.equal(result.started.kind,'started');assert.equal(result.started.value.status,'captured');
 const stage=f.host.outcomes[0].stage;
 const preview=JSON.parse(f.host.control.effectComputationPreviewWire(stage.preview)),member=preview.effects[0],row=member.changes[0];
 assert.equal(member.effect_kind,'delete');assert.equal(member.preview_strength,'full_diff');assert.equal(member.approval,'required');
 assert.equal(row.target_row_identity,name);assert.deepEqual(row.target_guard,{state:'version',version_cid:cid(raw)});
 assert.deepEqual(row.before,{state:'present',value:{name,content_type:null,metadata:{$json:{keep:'=é\r\n'}}}});
 assert.deepEqual(row.after,{state:'absent'});assert.deepEqual(row.intended_changes,{state:'not_applicable'});
 assert.equal(f.state.children,1);assert.equal(f.state.reads,1);assert.equal(f.state.readUses.length,1);assert.equal(f.state.sends,0);
 await stage.dispose();assert(f.children.every(child=>child.status().pending===false));
});

test('actual Common refuses a substituted GCS request target and retires its same child without send',async t=>{
 const f=await fixture(t,{substituteTarget:true});
 await assert.rejects(f.host.run(program(f.mapping),'foreign-gcs-delete'),error=>error?.code==='ForeignInstalledRowEffectRequest');
 assert.equal(f.state.children,1);assert.equal(f.state.reads,1);assert.equal(f.state.sends,0);
 assert(f.children.every(child=>child.status().pending===false));
});

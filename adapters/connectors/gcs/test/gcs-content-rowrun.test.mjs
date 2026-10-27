import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Actual ordinary GCS declaration, same-Ledger RowRuns, Content/Value owners
// and encrypted Store. Credential/Account and HTTP are explicit finite ports,
// not a normally installed or live-service acceptance campaign.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {inspect} from 'node:util';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {selectInstalledHostEnvironment} from '../../../host-node/installed-host-policy.mjs';
import {retainCapturedContent} from '../../../host-node/captured-content-holding.mjs';
import {openLocalPublicationStore} from '../../../store-local/publication-store.mjs';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {canonical, cid, token} from '../../../host-node/fixtures/file-listing-source.fixture.mjs';
import {restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';
import {readGcsFileListing} from '../site/gcs-file-listing.mjs';
import {readGcsKeyedContent} from '../site/gcs-keyed-content.mjs';

const read = path => readFile(new URL(`../../../../${path}`, import.meta.url), 'utf8');
const generation = '9007199254740993';
const metageneration = '9007199254740995';
const name = 'in/e\u0301%2F.pdf';
const contentLimits = {maxBytes:8192,maxNodes:256,maxDepth:32,maxTextUnits:8192};
const storeAuthorityCid = token('1'), workspaceScopeCid = token('2');
const profile = {version:'actql-installed-gcs-source/0.1',connectorId:'storage',
  project:'fixture-project',bucket:'actql-fixture',prefix:'in/',mediaType:'application/pdf',
  siteProfilePath:'/fixture/site.json',accountConfigurationWire:'{}',
  limits:{maxListingItems:3,maxExaminedItems:9,maxPages:4,maxAttempts:4,
    maxListingBytes:32768,maxDurationMs:10000,maxPathBytes:1024,maxPageBytes:8192,
    maxPageItems:3,maxRequestBytes:4096,maxContentBytes:4096}};

async function fixture(t, {gzip = false, objectName = name} = {}) {
  const name = objectName;
  const scratch = await createOwnedScratch({parent:new URL('../../../../_build/',import.meta.url).pathname,
    prefix:'gcs-content-columns-',label:'original five-column GCS Content RowRun and encrypted Store'});
  const core = runtimeCore(moon), control = core.contentCaptureControl;
  const storeOptions = {directory:join(scratch.path,'store'),storeAuthorityCid,
    capacityBytes:65536,maxObjectBytes:4096,maxObjects:8,maxContractNodes:1000,maxContractDepth:32};
  let store = await openLocalPublicationStore(storeOptions,core.publicationControl);
  const state = {calls:[],raw:[],operations:[],captures:0,verified:0,allowed:true};
  const writers = [], preparations = [], holdings = [], issued = new Set();
  let captured, lookup, disposed = false;
  const dispose = async () => {
    if (disposed) return;
    await lookup?.close();
    await captured?.close();
    state.allowed = false;
    for (const holding of holdings) await store.retirePhysicalHolding(holding.holding_cid);
    for (const prepared of preparations) await prepared.retry();
    for (const writer of writers) await writer.cancel();
    await store.close();
    disposed = true;
  };
  t.after(dispose);
  const payload = gzip ? Buffer.from('1f8b080000000000001333343236313533b7b004002639f4cb09000000','hex')
    : Buffer.from('123456789');
  const contentCid = gzip ? 'sha256:50362a01a8d29d0eaceb7640872bab3f6d7f980e33804a57e21c79a18fe25cb8'
    : 'sha256:15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225';
  const reportedMediaType = gzip ? 'Application/PDF' : 'application/pdf';
  const metadata = {bucket:profile.bucket,name,generation,metageneration,size:String(payload.length),
    contentType:reportedMediaType,crc32c:gzip?'zCyQIQ==':'4waSgw==',
    ...(gzip?{contentEncoding:'gzip'}:{})};
  const original = restoreGcsSourceDeclaration(moon,profile,undefined,{includeObjects:true});
  const resource = Object.freeze({$actql_ref:'resource',version:'actql-resource-ref/0.1',
    provider_namespace:'gcs',resource_kind:'file',provider_identity_cid:cid({bucket:profile.bucket}),
    authority_scope_cid:original.scopeCid,boundary_cid:original.declared.catalog_cid,
    identity_cid:cid({name})});
  const policy = {version:'actql-lookup-execution-policy/0.1',max_network_attempts_per_request:3,
    max_request_bytes_per_attempt:4096,max_total_request_bytes:73728,max_total_response_bytes:49152,
    max_total_decoded_response_bytes:49152,max_total_duration_ms:30000};
  const environment = rowSourceCheckEnvironment(selectInstalledHostEnvironment(moon,
    (await read('spec/local-check-environment.json')).trimEnd(),undefined,policy),original.declared);
  const admittedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid,false,false,true,false,false,false,false);
  assert.ok(admittedEnvironment);
  const fields = ['resource','version','name','media_type','content'];
  const program = {version:'actql/0.1',id:'gcs-original-five-column-capture',stages:[{id:'s',inputs:{
    files:{connector:'storage',resource:'files',view:'records',request:{paths:null,glob:null}},
    contents:{connector:'storage',resource:'contents',view:'records'},
  },steps:[
    {from:'files',filter:'name IS NOT NULL',as:'listed'},
    {from:'listed',select:['resource','version','name','path','media_type','size_bytes','modified_at'],as:'listing'},
    {join:{left:'listing',with:'contents',kind:'inner',
      on:[{left:'resource',right:'resource'},{left:'version',right:'version'}],
      select:Object.fromEntries(fields.map(field=>[field,`right.${field}`]))},as:'rows'},
    {from:'rows',assert_rows:{unique_by:['name']},as:'unique_names'},
    {from:'unique_names',sort:[{name:'asc'}],as:'ordered'}],
    results:{r:{from:'ordered',fields}}}],results:{r:{from:{stage:'s',result:'r'}}}};
  const prepared = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),'json',admittedEnvironment,undefined);
  const preparedProgram = moon.clientProgramPreparationReady(prepared);
  assert.ok(preparedProgram,inspect(moon.clientProgramPreparationIssue(prepared),{depth:8}));
  const acquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram));
  const direct = moon.clientProgramKeyedDirectAcquisitionCoordinates(acquisition);
  const occurrence = {stage:runtimeField(direct,0),input:runtimeField(direct,1),task:runtimeField(direct,2)};
  const [registry,aoa] = await Promise.all([read('spec/dependencies/aoa-pipeline-registry.json'),read('spec/contracts/actql-aoa.json').then(JSON.parse)]);
  const contracts = {registry,values:JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment:JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered:JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  const scope = operation => ({operation,resourceOrigin:'https://storage.googleapis.com',siteGeneration:1,
    connectorRegistration:'gcs',connectorRevision:'gcs/0.1'});
  const credential = {journal:{explicitPhysicalCounter:true}};
  const callResource = async call => {
    state.calls.push(call);
    const operation = [...call.operations.keys()][0];
    const media = operation==='gcs:file:read' && state.calls.filter(call=>call.operations.has('gcs:file:read')).length===2;
    const body = operation==='gcs:file:list' ? Buffer.from(JSON.stringify({kind:'storage#objects',items:[metadata]}))
      : media ? payload : Buffer.from(JSON.stringify(metadata));
    state.raw.push(body);
    return {accepted:true,statusCode:media&&gzip?206:200,
      headers:media&&gzip?[['content-encoding','gzip'],['content-range','bytes 0-28/29']]:[],body};
  };
  let expectedRef;
  const adapter = await createInstalledRowSource({moon,declaration:original.declaration,declared:original.declared,
    environmentWire:environment.wire,connectorId:'storage',connectorRegistration:'gcs',connectorRevision:'gcs/0.1',
    bindingCid:token('9'),referenceIssuer:moon.clientProgramResourceReferenceIssuer(
      (kind,wire)=>kind==='file'&&wire===canonical(resource),()=>state.allowed),
    readOperation:{files:'gcs:file:list',objects:'gcs:file:list',contents:'gcs:file:read'},
    physicalTarget:(resource,fields)=>({resource,fields}),
    authorization:{authorize:async()=>({action:state.allowed?'dispatch':'deny'}),
      accountConfiguration:'{}',context:{contextCid:token('8')}},
    site:{connection:'gcs:fixture-project/actql-fixture',close(){},issueReadGrant({operation,resource}){
      state.operations.push([resource,operation]);return {grant:{},scope:scope(operation)};
    }},limits:{maxPages:4,maxPageBytes:8192,maxPageRows:3,maxCaptureRows:3},
    readPages:options=>options.resource==='files'
      ? readGcsFileListing({target:{bucket:profile.bucket,prefix:profile.prefix},
        limits:{maxPageBytes:8192,maxPageItems:3,maxRequestBytes:4096,maxTimeMs:5000},
        listing:options.listing,authorizationFor:options.authorizationFor,chargePage:options.chargePage,
        signal:options.signal,credential,callResource,resourceFor:target=>{
          assert.deepEqual(target,{bucket:profile.bucket,objectName:name});return resource;
        }})
      : readGcsKeyedContent({...options,moon:provider,credential,callResource,
        limits:{maxMetadataBytes:8192,maxContentBytes:payload.length,maxRequestBytes:4096,maxAttempts:2,maxTimeMs:5000},
        resolveResource:async observed=>{
          assert.deepEqual(observed,resource);
          assert.equal(await options.capturedResourcePath(),name);
          return {bucket:profile.bucket,prefix:profile.prefix,objectName:name};
        },chargeVerification:async bytes=>{await options.chargeVerification(bytes);state.verified+=bytes;}})});
  const preparedSource = await adapter.prepare({preparedProgram,...contracts,occurrence});
  // Independent finite component envelope, never a normal Host numerical quote.
  const ledger = checked(moon.clientProgramAcquisitionLedger(8,8,131072n,268435456n,268435456n,100000));
  const capture = async ({bytes,mediaType,keyedAcquisition,request,readSubjectCid,verifyRead,signal})=>{
    state.captures++;
    assert.deepEqual(bytes,payload);
    assert.equal(mediaType,reportedMediaType);
    await verifyRead();
    const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
    const binding = {content_store_id:'fixture',content_store_cid:storeAuthorityCid,
      workspace_scope_cid:workspaceScopeCid,storage_scope:'workspace',retention_class:'fixture',
      availability_evidence_cid:token('3'),effective_data_policy_cid:facts[3],data_classification:facts[4],
      issuer_contract_cid:token('5'),capture_authority_cid:readSubjectCid};
    const candidate = control.candidate(keyedAcquisition,request,binding,
      {mediaType,contentCid,sizeBytes:payload.length},contentLimits);
    const issuer = {version:'actql-content-issuer-evidence/0.1',issuer_kind:'connector_capture',
      issuer_contract_cid:token('5'),content_store_cid:storeAuthorityCid,workspace_scope_cid:workspaceScopeCid,
      content_cid:contentCid,effective_data_policy_cid:facts[3],capture_authority_cid:readSubjectCid,
      reported_media_type:reportedMediaType};
    const body = {$actql_ref:'content',version:'actql-content-ref/0.1',media_type:'application/pdf',
      metadata:{content_store_id:'fixture',content_cid:contentCid,media_type:'application/pdf',storage_scope:'workspace',
        retention_class:'fixture',availability_evidence_cid:token('3'),capture_authority:'read_content',
        data_classification:facts[4],effective_data_policy_cid:facts[3],size_bytes:payload.length,truncated:false,
        issuer_evidence:{...issuer,evidence_cid:cid(issuer)}}};
    expectedRef = {...body,content_ref_cid:cid(body)};
    assert.equal(control.inspect(candidate).wire,canonical(expectedRef));
    const retained = await retainCapturedContent({store,control,candidate,bytes,
      holdingCid:cid({capture:readSubjectCid,content:expectedRef.content_ref_cid}),workspaceScopeCid,
      effectiveDataPolicyCid:facts[3],limits:contentLimits,available:()=>state.allowed&&!signal.aborted,
      authorize:()=>state.allowed&&!signal.aborted,signal,retainCustody:({writer,prepared,holding})=>{
        if(writer)writers.push(writer);if(prepared)preparations.push(prepared);if(holding)holdings.push(holding);
      }});
    issued.add(retained.wire);
    return JSON.parse(retained.wire);
  };
  return {state,ledger,adapter,preparedSource,preparedProgram,acquisition,scratch,payload,gzip,reportedMediaType,resource,
    async start(){
      captured = await adapter.openCapture({preparedProgram,...contracts,occurrence,preparedSource,ledger});
      const left = checked(moon.clientProgramKeyedCaptureLeftRead(acquisition,captured.capture.source()));
      const requestIdentity = moon.clientProgramRequestIdentity(preparedProgram,token('a'),
        'gcs-original-five-column-capture',moon.clientProgramSourceFreeInputIntentCid());
      const selected = await adapter.prepareKeyed({preparedProgram,keyedAcquisition:acquisition,requestIdentity});
      lookup = await adapter.openKeyedLookup({preparedProgram,keyedAcquisition:acquisition,left,ledger,
        originalCapture:captured.capture,preparedKeyed:selected.prepared,keyedContent:{capture,
          referenceIssuer:moon.clientProgramRowReferenceIssuer(()=>false,
            (media,wire)=>media==='application/pdf'&&issued.has(wire),()=>state.allowed)}});
      return {lookup,left,expectedRef};
    },
    async readStored(){
      const pieces=[];
      await store.consumePhysicalHolding(holdings[0].holding_cid,0,part=>pieces.push(Buffer.from(part)));
      return Buffer.concat(pieces);
    },
    async reopenStore(){await store.close();store=await openLocalPublicationStore(storeOptions,core.publicationControl);},
    storeStatus:()=>store.status(),
    async closeRows(){await lookup?.close();await captured?.close();},
    async refuseInsufficientLedger(){
      const short=checked(moon.clientProgramAcquisitionLedger(8,8,131072n,1n,1n,100000));
      const before=moon.clientProgramMultiCapturedLedgerUsage(short);
      await assert.rejects(adapter.openCapture({preparedProgram,...contracts,occurrence,preparedSource,ledger:short}));
      assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(short),before);
    },
    dispose};
}

for(const gzip of [false,true]) {
  test(`five-column GCS keyed capture retains original name/report/ref and same-Store bytes, gzip=${gzip}`,async t=>{
    const f = await fixture(t,{gzip});
    const {lookup,left,expectedRef} = await f.start();
    const expected = [{resource:f.resource,version:generation,name,
      media_type:f.reportedMediaType,content:expectedRef}];
    assert.equal(lookup.capture.identity(),cid(expected));
    assert.equal(expectedRef.media_type,'application/pdf');
    assert.equal(expectedRef.metadata.issuer_evidence.reported_media_type,f.reportedMediaType);
    assert.equal(f.state.calls.length,3);
    assert.equal(f.state.captures,1);
    assert.equal(f.state.verified,f.payload.length);
    assert.deepEqual(f.state.operations,[['files','gcs:file:list'],['contents','gcs:file:read']]);
    const media=f.state.calls[2].operations.get('gcs:file:read');
    assert.equal(media.path,'/storage/v1/b/actql-fixture/o/in%2Fe%CC%81%252F.pdf?generation=9007199254740993&ifGenerationMatch=9007199254740993&alt=media&ifMetagenerationMatch=9007199254740995');
    assert.deepEqual(media.headers,[['accept-encoding',gzip?'gzip':'identity'],
      ...(gzip?[['range','bytes=0-28']]:[])]);
    assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(f.ledger)).transferredBytes,
      BigInt(f.state.raw.reduce((sum,body)=>sum+body.length,0)));
    assert.deepEqual(await f.readStored(),f.payload);
    await lookup.close();
    assert.equal(moon.clientProgramKeyedLeftReadRows(left),1,
      'right cleanup must not release the original left metadata');
    assert.throws(()=>lookup.capture.identity(),{code:'InstalledSourceClosed'});
    await f.closeRows();
    assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(f.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),[0n,0n,0n,0n]);
    assert.equal(f.storeStatus().storedBytes,f.payload.length,
      'RowRun cleanup does not retire the separately held physical Content');
    await f.reopenStore();
    assert.deepEqual(await f.readStored(),f.payload,
      'same original holding retains exact bytes across Store close/reopen');
    assert.equal(f.state.calls.length,3,'Store recovery never reacquires GCS');
    await f.dispose();f.scratch.passed();
  });
}

test('five-column GCS capture refuses original insufficient capacity before grants or I/O',async t=>{
  const f=await fixture(t);
  await f.refuseInsufficientLedger();
  assert.equal(f.state.calls.length,0);
  assert.equal(f.state.operations.length,0);
  assert.equal(f.state.captures,0);
  await f.dispose();f.scratch.passed();
});

test('JSON object names retain legal controls through actual same-Ledger capture and encrypted Store',async t=>{
  const name='in/e\u0301\t\u0000\u007f%2F#?.pdf';
  const f=await fixture(t,{objectName:name});
  const {lookup,expectedRef}=await f.start();
  assert.equal(lookup.capture.identity(),cid([{resource:f.resource,version:generation,name,
    media_type:f.reportedMediaType,content:expectedRef}]));
  assert.equal(f.state.calls.length,3);
  const path='/storage/v1/b/actql-fixture/o/in%2Fe%CC%81%09%00%7F%252F%23%3F.pdf'+
    '?generation=9007199254740993&ifGenerationMatch=9007199254740993';
  assert.equal(f.state.calls[1].operations.get('gcs:file:read').path,path);
  assert.equal(f.state.calls[2].operations.get('gcs:file:read').path,
    path+'&alt=media&ifMetagenerationMatch=9007199254740995');
  assert.deepEqual(await f.readStored(),f.payload);
  assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(f.ledger)).transferredBytes,
    BigInt(f.state.raw.reduce((sum,body)=>sum+body.length,0)));
  await f.closeRows();
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(f.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),[0n,0n,0n,0n]);
  await f.reopenStore();
  assert.deepEqual(await f.readStored(),f.payload);
  assert.equal(f.state.calls.length,3);
  await f.dispose();f.scratch.passed();
});

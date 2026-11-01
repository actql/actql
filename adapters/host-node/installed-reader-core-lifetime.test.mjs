import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {checked} from '../host-common/runtime-result.mjs';
import {ledgerUsageSnapshot} from '../host-common/runtime-core.mjs';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';

// One namespace per component. The explicit retained artifact override is
// source-scoped evidence only, never a new-SHA normal/ABI acceptance claim.
const moduleUrl = process.env.ACTQL_TEST_CORE_MODULE === undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url)
  : pathToFileURL(process.env.ACTQL_TEST_CORE_MODULE);
const moon = await import(moduleUrl.href);

// Actual Reader + RowRun/adapter JS + actual Core capture/Resource state.
// Authority, credential transport and its physical-close observation remain
// explicit ports. The small declaration is not a normal numerical profile.
async function fixture({pendingBinding = false} = {}) {
  const read = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views:[{resource:'records',
      resource_kind:'record',fields:[{name:'id',type:'number',nullable:false}]}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const preparedProgram = moon.clientProgramPreparationReady(moon.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify({version:'actql/0.1',id:'reader-core-lifetime',stages:[{
      id:'scan',inputs:{remote:{connector:'fixture',resource:'records'}},
      steps:[{filter:'true',as:'all_rows'},{select:['id'],as:'output'}],
      results:{r:{from:'output',fields:['id']}}},{id:'compute',
      inputs:{x:{result:{stage:'scan',result:'r'}}},
      steps:[{filter:'id > 0'},{select:['id'],as:'out'}],
      results:{r:{from:'out',fields:['id']}}}],
      results:{r:{from:{stage:'compute',result:'r'}}}}), 'json', checkedEnvironment, undefined));
  assert.ok(preparedProgram);
  const aoa = JSON.parse(await read('spec/contracts/actql-aoa.json'));
  const preparation = {preparedProgram, registry:await read('spec/dependencies/aoa-pipeline-registry.json'),
    values:JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment:JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered:JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  // The current actual bridge consumes the original typed installation
  // contracts, never the old raw registry String used by retired fixtures.
  preparation.registry = checked(moon.clientPrepareInstalledSequenceContracts(
    preparation.registry,preparation.values,preparation.fragment,preparation.ordered));
  const capacity = moon.clientProgramRowSourceProviderCapacity(4096n,8192n);
  const authorization = {grant:{},scope:{operation:'read'},useId:'reader-core-use'};
  const credential = {}, site = {}, events = [];
  let bindingClosed = !pendingBinding, reader;
  const response = Object.freeze({accepted:true,statusCode:200,body:Buffer.from('{"records":[{"id":1}]}')});
  const originalSite = Object.freeze({site,referenceCurrent(){return true;},
    authorizationPurpose(original){assert.equal(original,authorization);return {kind:'read'};},
    bindRunAcquisition(original, callbacks){
      assert.equal(original,authorization);callbacks.assertCurrent();events.push('bind');
      return Object.freeze({credential,close(){events.push('binding-close');return bindingClosed?'closed':'pending';}});
    },
    callResource(input){assert.equal(this,site);events.push('receive');input.responseCustody.retain(response);return response;},
  });
  const factory = createInstalledCredentialSourceReader({capacity,originalSite,assertCurrent(){},
    operation:'read',maxResponses:1,maxResponseBytes:128,maxSecretBytes:128,
    preparePageReader(){return Object.freeze({
      fetchPage(){return {method:'GET',path:'/one',headers:[],query:[],responseHeaders:[]};},
      decodePage(original){assert.equal(original,response);return {rows:[{id:1}],done:true};},
    });}});
  const providerReader = Object.freeze({capacity,prepare(options){
    assert.equal(this,providerReader);reader=Reflect.apply(factory.prepare,factory,[options]);return reader;
  }});
  const adapter = await createInstalledRowSource({moon,declaration,declared,
    environmentWire:environment.wire,connectorId:'fixture',connectorRegistration:'fixture',
    connectorRevision:'fixture/0.1',bindingCid:`sha256:${'a'.repeat(64)}`,
    site:{connection:'fixture:records',issueReadGrant:()=>authorization,close(){}},
    authorization:{authorize:async()=>({action:'dispatch'}),accountConfiguration:'{}',context:{contextCid:'context'}},
    readOperation:'read',physicalTarget:(resource,fields)=>({resource,fields}),providerReader,
    limits:{maxPages:1,maxPageBytes:1024,maxPageRows:10,maxCaptureRows:10}});
  const preparedSource=await adapter.prepare(preparation),planned=adapter.ledgerCapacity(preparedSource);
  const ledger=moon.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
    planned.capacity,planned.transferBytes,planned.executionBytes,
    preparation.registry,preparation.values,preparation.fragment,preparation.ordered);
  assert.ok(ledger);
  const capture=await adapter.openCapture({...preparation,preparedSource,ledger});
  return {capture,reader:()=>reader,events,allowBindingClose(){bindingClosed=true;},
    usage:()=>ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(ledger))};
}

async function closeOriginal(capture) {
  for(let index=0;index<128;index++) {
    try {capture.close();return;}
    catch(error){assert.equal(error.code,'MoonBitHostFailure');}
  }
  assert.fail('same original Core capture did not finish bounded cleanup');
}

test('actual Reader and Core retain live captured Source and evidence after reader-only retirement',async()=>{
  const f=await fixture(),source=f.capture.capture.source(),read=f.capture.capture.originalRead();
  assert.ok(source);assert.ok(read);
  const held=f.usage();assert.ok(held.reservedExecutionBytes>0n);
  f.reader().requestStop();assert.equal(f.reader().observe().cleanupConfirmed,true);
  assert.deepEqual(f.usage(),held,'reader stop alone must not credit the real Core reservation');
  assert.equal(f.capture.capture.source(),source);
  assert.ok(f.capture.capture.originalRead());
  const evidence=await f.capture.issueSourceEvidence({authorityScopeCid:`sha256:${'a'.repeat(64)}`,
    effectiveDataPolicyCid:f.capture.checkedSource.sourceDataPolicyCid});
  assert.equal(typeof evidence,'string');
  assert.equal(f.usage().reservedExecutionBytes,held.reservedExecutionBytes);
  await closeOriginal(f.capture);
  assert.equal(f.usage().reservedExecutionBytes,0n);
  assert.equal(f.usage().reservedRetentionBytes,0n);
  assert.equal(f.usage().heldBytes,0n);
  assert.throws(()=>f.capture.capture.source(),{code:'MoonBitHostFailure'});
  assert.equal(f.events.filter(name=>name==='receive').length,1);
});

test('actual pending Reader binding keeps Core reservation until same original late cleanup',async()=>{
  const f=await fixture({pendingBinding:true}),source=f.capture.capture.source(),held=f.usage();
  f.reader().requestStop();assert.equal(f.reader().observe().cleanupConfirmed,false);
  assert.deepEqual(f.usage(),held);assert.equal(f.capture.capture.source(),source);
  assert.throws(()=>f.capture.close(),{code:'MoonBitHostFailure'});
  assert.deepEqual(f.usage(),held,'pending original cleanup cannot credit Core backing');
  // Core close invalidates its Source even while cleanup remains pending.
  assert.throws(()=>f.capture.capture.source(),{code:'MoonBitHostFailure'});
  f.allowBindingClose();f.reader().retry();
  assert.equal(f.reader().observe().cleanupConfirmed,true);
  await closeOriginal(f.capture);
  assert.equal(f.usage().reservedExecutionBytes,0n);assert.equal(f.usage().heldBytes,0n);
  assert.equal(f.events.filter(name=>name==='receive').length,1);
});

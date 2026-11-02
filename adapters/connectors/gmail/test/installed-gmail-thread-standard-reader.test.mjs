import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {captureInstalledSourceServices,createInstalledHostServices,retainInstalledHostServiceInstallation}
  from '../../../host-node/installed-host-services.mjs';
import {installedJsonSourceReaderLimitNames,installedJsonSourceReaderProfileLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {checkGmailThreadReaderLimits,gmailThreadReaderLimitNames} from '../site/gmail-thread-limits.mjs';

// Actual loader body and original service receivers, with explicit Core/Site
// ports. This does not issue capacity, an Account grant or a physical read.
const source = readFileSync(new URL('../host/installed-gmail-source.mjs', import.meta.url), 'utf8');
const body = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(value => value.declaration ?? value)
  .filter(value => ['VariableDeclaration', 'FunctionDeclaration'].includes(value.type))
  .map(value => source.slice(value.start, value.end)).join('\n');
const limits = Object.freeze({maxResponseBytes:4096,maxTotalResponseBytes:16384,maxNodes:256,maxDepth:8,
  pageSize:2,maxPages:2,maxThreads:3,maxMailboxBytes:128,maxTargetBytes:1024,maxIdBytes:128,maxTokenBytes:128,
  maxMessages:4,maxLabels:4,maxHeaders:8,maxHeaderUnits:512,maxCommentDepth:8,maxValueNodes:32,
  maxValueTextBytes:1024,maxRowsWireBytes:4096,maxRowsWireNodes:64,maxRowsWireDepth:6,
  maxDeclarationBytes:4096,maxDeclarationNodes:256,maxSecretBytes:128,maxCaBytes:16384});
function fixture({sourceFailure} = {}) {
  const events=[],cleanup=[],quoteCalls=[],installation={},capacity={},declaration={},result={};
  let implementationInput;
  const moon={clientProgramInstalledGmailThreadReaderCapacity(...args){
    assert.equal(this,moon);quoteCalls.push(args);return capacity;}};
  const environment={wire:'original-environment'},declared={views:[{resource:'threads',fields:['id','labels']}]};
  const profile={version:'actql-installed-gmail-source/0.1',resource:'threads',connectorId:'mailbox',
    mailbox:'support+box@example.test',siteProfilePath:'/UNOPENED/site.json',accountConfigurationWire:'{}',limits};
  const siteProfile={version:'actql-installed-gmail-site/0.1',apiOrigin:'https://gmail.invalid',
    credentialAuthorityId:'authority',credentialKeyId:'key',credentialPrivateKeyPath:'/UNOPENED/key',
    environment:'test',journalRoot:'/UNOPENED/journal',namespaceId:'test',siteGeneration:1,siteKey:'gmail'};
  const sourceInitialization={prepareDeclaration(views) {
    assert.equal(this,sourceInitialization);events.push('declaration');
    assert.equal(views[0].resource,'threads');assert.equal(views[0].resource_kind,'gmail_threads');
    return {declaration,declared,environment};
  }};
  const provider={gmailThreadSchemaWire(){assert.equal(this,provider);events.push('schema');return {$tag:1,_0:'schema'};},
    gmailThreadRelationFactsWire(){assert.equal(this,provider);return 'facts';},
    gmailThreadColumnNames(){assert.equal(this,provider);return ['id','labels','last_message_date','message_count','subject'];}};
  for(const name of ['gmailPrepareThreadRead','gmailNextThreadRequest','gmailThreadRequestJson','gmailThreadRequestMatches',
    'gmailAcceptThreadList','gmailAcceptThread','gmailThreadProjectionMatchesRequest','gmailThreadReadCompleted',
    'gmailCloseThreadRead','gmailThreadRowsWire']) provider[name]=()=>assert.fail('No response in loader scope');
  const site={},authorization={context:{contextCid:'original-context'}},reader={capacity};
  const implementation=Object.freeze({capacity,runAcquisitionLimits:{}});let readerInput;
  const services={
    sourceReaderImplementationProfile(input){assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.metadataResponses,3);
      events.push('profile');return {...Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map(name=>[name,100000])),
        maxDeclarationBytes:4096,maxDeclarationNodes:256};},
    sourceReaderImplementation(input){assert.equal(this,services);assert.equal(input.sourceInitialization,sourceInitialization);
      implementationInput=input;assert.equal(input.columnCount,5);events.push('implementation');return implementation;},
    openRowSite(input){assert.equal(this,services);assert.equal(input.sourceInitialization,sourceInitialization);
      assert.equal(input.runAcquisitionLimits,implementation.runAcquisitionLimits);events.push('site');return {site,authorization};},
    createSourceReader(input){assert.equal(this,services);assert.equal(input.implementation,implementation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.site,site);
      readerInput=input;events.push('reader');return reader;},
  };
  const configurationReader={readJson(path){assert.equal(this,configurationReader);assert.equal(path,profile.siteProfilePath);
    events.push('configuration');return siteProfile;},readText(){assert.fail('No CA selected');}};
  const ports={createHash,isAbsolute,nodeTypes,canonicalJson,checked,captureConfigurationReaders,captureInstalledSourceServices,
    checkGmailThreadReaderLimits,gmailThreadReaderLimitNames,installedJsonSourceReaderLimitNames,GMAIL_THREAD_LIST_OPERATION:'gmail:threads:list',
    prepareGmailThreadReadSequence(){assert.fail('No acquisition in loader scope');},
    createInstalledRowSource(input){assert.equal(input.sourceInitialization,sourceInitialization);
      assert.equal(input.declaration,declaration);assert.equal(input.environment,environment);assert.equal(input.providerReader,reader);
      assert.equal(input.readOperation,'gmail:threads:list');
      assert.deepEqual(input.limits,{maxPages:5,maxPageBytes:4096,maxPageRows:1,maxCaptureRows:3});
      events.push('source');if(sourceFailure)throw sourceFailure;return result;},
    retainInstalledHostInitializationFailure(cause,original){cleanup.push(original);return cause;},
  };
  const load=Function(...Object.keys(ports),body+'\nreturn loadInstalledGmailSource;')(...Object.values(ports));
  return {events,cleanup,result,reader,site,capacity,quoteCalls,implementationInput:()=>implementationInput,readerInput:()=>readerInput,
    load:()=>load(profile,{moon,providerMoon:provider,runtimeBundleCid:'runtime',installation,sourceInitialization,
      installationServices:services,configurationReader,resolveSecret(){assert.fail('No secret resolution');}})};
}

test('Gmail THREADS uses the original Source constructor and managed sequence without external readerCapacity',async()=>{
  const f=fixture();assert.equal(await f.load(),f.result);
  assert.deepEqual(f.events,['configuration','profile','implementation','schema','declaration','site','reader','source']);
  assert.equal(typeof f.readerInput().prepareReadSequence,'function');
  assert.equal(Object.hasOwn(f.readerInput(),'preparePageReader'),false);
});

test('Gmail THREADS retains the same failed reader and original Site for Source cleanup',async()=>{
  const primary=Object.freeze({code:'original-construction-failure',cleanupPending:true}),f=fixture({sourceFailure:primary});
  await assert.rejects(f.load(),cause=>cause===primary);
  assert.deepEqual(f.cleanup,[{sourceReader:f.reader,sourceProfile:f.site}]);
});

test('generic Source service retains the original connector-selected complete recipe without recomputing it',async()=>{
  const f=fixture();await f.load();const input=f.implementationInput();
  const installation=Object.freeze({registration:'not-a-dispatch-key'});
  const moon={clientProgramInstalledSourceReaderPolicy:()=>[65536,100000,100],
    clientProgramInstalledJsonSourceReaderProfile:()=>({$tag:1,_0:installedJsonSourceReaderProfileLimitNames.map(()=>100000)}),
    clientProgramInstalledJsonSourceReaderCapacity(){assert.fail('The original complete recipe must not be replaced');}};
  const services=createInstalledHostServices({root:'/UNOPENED',principalId:'component',moon,assertCurrent(){}});
  retainInstalledHostServiceInstallation(services,installation,'sha256:'+'a'.repeat(64));
  services.sourceReaderImplementationProfile({installation,metadataResponses:3,originUnits:20});
  const selection={installation,columnCount:5,limits:input.limits,readSequenceConstruction:input.readSequenceConstruction};
  const selected=services.sourceReaderImplementation(selection);
  assert.equal(selected.capacity,f.capacity);assert.equal(f.quoteCalls.length,1);
  assert.equal(services.sourceReaderImplementation({...selection,limits:{...input.limits}}),selected);
  assert.throws(()=>services.sourceReaderImplementation({...selection,
    readSequenceConstruction:Object.freeze({...input.readSequenceConstruction,
      originalLimits:Object.freeze({...limits,maxHeaderUnits:limits.maxHeaderUnits+1})})}),
    {code:'InstalledSourceReaderSelectionChanged'});
  assert.equal(f.quoteCalls.length,1);
});

test('actual RowRun child admission spends each original before current reentry and keeps separate get grant uses',async()=>{
  const original=readFileSync(new URL('../../../host-node/installed-row-source.mjs',import.meta.url),'utf8');
  let arrow;
  const visit=node=>{
    if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.key?.name==='authorizeReadChild'&&node.value.type==='ArrowFunctionExpression'){
      assert.equal(arrow,undefined);arrow=original.slice(node.value.start,node.value.end);
    }
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);
    else if(value&&typeof value==='object')visit(value);
  };
  visit(parse(original,{ecmaVersion:'latest',sourceType:'module'}));assert(arrow);
  const grant={},child={},decision={},events=[];let authorize,reenter;
  const site={issueReadGrant(input){assert.equal(this,site);assert.equal(input.decision,decision);
    assert.equal(input.operation,'gmail:threads:get');assert.equal(input.maxUses,3);events.push('grant');return child;}};
  const ports={readerDemand:{responses:5,sequence:{operation:'gmail:threads:list',maxUses:2,
    children:[{operation:'gmail:threads:get',maxUses:3}]}},operation:'gmail:threads:list',nodeTypes,
    fail:code=>{throw Object.assign(new Error(code),{code});},
    currentRead:async()=>{events.push('current');await reenter?.();return decision;},
    prepared:{},access:{},signal:undefined,owner:{},site,runInvocationCid:'run',dispatchRequestCid:'dispatch',grant,
    directReadIdentity:undefined,nonce:'request',text:value=>typeof value==='string'&&value.length>0};
  authorize=Function(...Object.keys(ports),'let readChildIndex=0,rootReadUses=0,propertyOccurrences=0;'+
    'const readChildOriginals=new WeakMap(),readChildGrants=new Map(),readChildUses=new Map();return '+arrow+';')(...Object.values(ports));
  const list={};assert.equal((await authorize('gmail:threads:list',0,list)).originalAuthorization,grant);
  const get={};reenter=async()=>{
    reenter=undefined;await assert.rejects(authorize('gmail:threads:get',1,get),{code:'InvalidInstalledSourceReadChild'});
  };
  assert.equal((await authorize('gmail:threads:get',1,get)).originalAuthorization,child);
  assert.equal((await authorize('gmail:threads:get',2,{})).originalAuthorization,child);
  await assert.rejects(authorize('gmail:threads:get',3,get),{code:'InvalidInstalledSourceReadChild'});
  await assert.rejects(authorize('foreign:read',3,{}),{code:'InvalidInstalledSourceReadChild'});
  assert.deepEqual(events,['current','current','grant','current']);
});


test('Gmail Source hands its complete original list-get capacity and occurrences to the generic service',async()=>{
  const f=fixture();await f.load();
  assert.deepEqual(f.quoteCalls,[[[4096,16384,256,8,1,3,5,2,128,128,1024,32,1024,4096,64,6],5,128,2,128]]);
  const selected=f.implementationInput();
  assert.equal(selected.readSequenceConstruction.capacity,f.capacity);
  assert.deepEqual(selected.readSequenceConstruction.originalLimits,limits);
  assert.deepEqual(selected.readSequenceConstruction.sequence,{operation:'gmail:threads:list',maxUses:2,
    children:[{operation:'gmail:threads:get',maxUses:3}]});
  assert.equal(selected.limits.maxPages,5);assert.equal(selected.limits.maxTotalRows,3);
});


test('generic Source refuses invalid own construction fields without callbacks or capacity fallback',async()=>{
  const f=fixture();await f.load();const input=f.implementationInput(),installation=Object.freeze({});let observed=0;
  const moon={clientProgramInstalledSourceReaderPolicy:()=>[65536,100000,100],
    clientProgramInstalledJsonSourceReaderProfile:()=>({$tag:1,_0:installedJsonSourceReaderProfileLimitNames.map(()=>100000)}),
    clientProgramInstalledJsonSourceReaderCapacity(){assert.fail('No fallback for an invalid selected construction');}};
  const services=createInstalledHostServices({root:'/UNOPENED',principalId:'component',moon,assertCurrent(){}});
  retainInstalledHostServiceInstallation(services,installation,'sha256:'+'a'.repeat(64));
  services.sourceReaderImplementationProfile({installation,metadataResponses:3,originUnits:20});
  const original=input.readSequenceConstruction;
  for(const construction of [null,{...original},Object.freeze({...original,capacity:undefined}),
    Object.freeze({...original,sequence:undefined}),Object.freeze({...original,sequences:Object.freeze({})}),
    Object.freeze({...original,originalLimits:{...limits}}),Object.freeze({...original,maxRequestBytes:0}),
    Object.freeze({...original,get capacity(){observed++;throw new Error('Must not invoke accessor');}}),
    new Proxy(Object.freeze({...original}),{get(){observed++;throw new Error('Must not invoke Proxy');}})]){
    assert.throws(()=>services.sourceReaderImplementation({installation,columnCount:5,limits:input.limits,
      readSequenceConstruction:construction}),{code:'InvalidInstalledSourceSequenceConstruction'});
  }
  assert.equal(observed,0);assert.equal(f.quoteCalls.length,1);
});

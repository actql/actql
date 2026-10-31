// Actual shared Reader, Common/RowRun, Account, signed Site, SQLite and TLS.
// The RowRun fixture is the existing explicit component parent, not the normal
// Host's Request-owned backing. Its retained test observations cannot certify
// normal capture, full parent retirement or an installed Source workflow.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {readFileSync as sourceText} from 'node:fs';
import {join} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
const common=await import(process.env.ACTQL_TEST_GMAIL_COMMON_MODULE ??
  new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
import {installRowSourceAuthorization,openRowSourceCredentialSite,installedRowCredentialOperationSite}
  from '../../../host-node/installed-row-source.mjs';
import {createInstalledHostServices,retainInstalledHostServiceInstallation}
  from '../../../host-node/installed-host-services.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {prepareGmailThreadReadSequence,GMAIL_THREAD_LIST_OPERATION}
  from '../site/gmail-thread-read.mjs';
import {threadReadFixture,threadRowOwner,threadReadLimits,threadRowSchema} from './gmail-thread-read.fixture.mjs';

// Consume the actual Host's two original authorization callbacks. The fixture
// supplies their existing current/Site ports; it defines no second grant rule.
const hostSource=sourceText(new URL('../../../host-node/installed-row-source.mjs',import.meta.url),'utf8');
const callbacks={};
function visit(node){
  if(!node||typeof node!=='object')return;
  if(node.type==='Property'&&['authorizeReadChild','authorizationFor'].includes(node.key?.name)&&
      node.value.type==='ArrowFunctionExpression'){
    const text=hostSource.slice(node.value.start,node.value.end);
    if(node.key.name==='authorizeReadChild'||text.includes('directReadIdentity')){
      assert.equal(callbacks[node.key.name],undefined);callbacks[node.key.name]=text;
    }
  }
  for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);
  else if(value&&typeof value==='object')visit(value);
}
visit(parse(hostSource,{ecmaVersion:'latest',sourceType:'module'}));
assert.deepEqual(Object.keys(callbacks).sort(),['authorizationFor','authorizeReadChild']);
const pending=new Set();
export async function threadFactoryFixture(t,{account='allow'}={}){
  const f=await threadReadFixture(t,{accounted:false,account});
  const authorization=await installRowSourceAuthorization({root:f.root,principalId:'operator',connectorRegistration:'gmail',
    accountConfiguration:await readFile(join(f.root,'account.json'),'utf8')});
  const policy=common.clientProgramInstalledSourceReaderPolicy();
  const site=await openRowSourceCredentialSite({profile:Object.freeze({credentialPrivateKeyPath:join(f.root,'credential-authority.key'),
    credentialAuthorityId:'installed-gmail',credentialKeyId:'key',journalRoot:join(f.root,'installed-thread-journal'),
    namespaceId:'installed-gmail',environment:'test',siteKey:'installed-gmail',siteGeneration:1,resourceOrigin:f.scope.resourceOrigin}),
    principalId:'operator',authorization,connection:'gmail:fixture',connectorRegistration:'gmail',connectorRevision:'gmail/0.1',
    runtimeBundleCid:f.scope.runtimeBundleCid,commonMoon:common,ca:f.options.credential.ca,
    resolveSecret:f.options.credential.resolveSecret,admitsApprovalTarget:()=>false,
    runAcquisitionLimits:{maxBindings:policy[1],maxSecretBytes:128}});
  const row=await threadRowOwner(()=>false,'{"relation_keys":{"candidate_keys":[["id"]]}}',
    'sql','id, labels, last_message_date, message_count, subject');
  const rowRun=Object.freeze({...row.originals,runInvocationCid:f.scope.runInvocationCid,dispatchRequestCid:f.scope.dispatchRequestCid});
  const hooks={afterCurrent:undefined},decisions=[],grants=[],observations=[],factories=[];
  const suppliedSite={issueReadGrant(input){assert.equal(this,suppliedSite);
    const original=Reflect.apply(site.issueReadGrant,site,[input]);grants.push({options:input,original});return original;},
    callResource(...args){assert.equal(this,suppliedSite);return Reflect.apply(site.callResource,site,args);}};
  const original=installedRowCredentialOperationSite(site.credential);
  const physical=Object.freeze({...original,async callResource(...args){
    const response=await Reflect.apply(original.callResource,original.site,args);observations.push(response);return response;}});
  const selected=Object.freeze({registration:'gmail'});
  const services=createInstalledHostServices({root:f.root,principalId:'operator',moon:common,assertCurrent(){
    if(!site.referenceCurrent())throw Object.assign(new Error('RowSourceSiteClosed'),{code:'RowSourceSiteClosed'});}});
  retainInstalledHostServiceInstallation(services,selected,f.scope.runtimeBundleCid);
  services.sourceReaderImplementationProfile({installation:selected,metadataResponses:threadReadLimits.maxThreads,
    originUnits:f.scope.resourceOrigin.length});
  const limits=Object.freeze({...threadReadLimits,maxDeclarationBytes:4096,maxDeclarationNodes:100,maxSecretBytes:128,maxCaBytes:16384});
  const implementation=services.sourceReaderImplementation({installation:selected,limits,columnCount:5});
  const options={resource:'threads',operation:GMAIL_THREAD_LIST_OPERATION,rowRun,columns:Object.keys(threadRowSchema),signal:undefined,
    async verifyRead(){assert.equal(this,options);
      const decision=await authorization.authorize('acquisition',{connection:'gmail:fixture',resource:'threads',operation:'read'},
        {subjectCid:rowRun.runInvocationCid});decisions.push(decision);await hooks.afterCurrent?.(decision);
      if(decision.action!=='dispatch')throw Object.assign(new Error('GmailReadDenied'),{code:'GmailReadDenied'});return decision;},
    chargePage(body){assert.equal(this,options);f.state.charges++;return row.charge(body);},
    consumeObservation(charge){assert.equal(this,options);return row.observation(charge);},
    consumePage(value,{charge}){assert.equal(this,options);row.page(value,charge);f.state.rows.push(...value);}};
  const makeFactory=(overrides={})=>{
    const moon=Object.hasOwn(overrides,'moon')?overrides.moon:f.options.moon;
    const capacity=Object.hasOwn(overrides,'capacity')?overrides.capacity:implementation.capacity;
    const factory=createInstalledCredentialSourceReader({capacity,originalSite:physical,assertCurrent(){
      if(!site.referenceCurrent())throw Object.assign(new Error('RowSourceSiteClosed'),{code:'RowSourceSiteClosed'});},
      maxResponses:threadReadLimits.maxPages+threadReadLimits.maxThreads,maxResponseBytes:threadReadLimits.maxResponseBytes,
      maxTotalResponseBytes:threadReadLimits.maxTotalResponseBytes,
      prepareReadSequence({columns},apply){return prepareGmailThreadReadSequence({moon,mailbox:f.options.mailbox,
        names:columns,limits:threadReadLimits},apply);}});factories.push(factory);return factory;
  };
  const makeReader=async overrides=>{
    const factory=makeFactory(overrides),methods=Object.freeze({verifyRead:options.verifyRead,chargePage:options.chargePage,
      consumeObservation:options.consumeObservation,consumePage:options.consumePage});
    const currentRead=()=>Reflect.apply(methods.verifyRead,options,[]);
    const issuer=suppliedSite.issueReadGrant;
    const capturedSite=Object.freeze({issueReadGrant:(...args)=>Reflect.apply(issuer,suppliedSite,args)});
    const decision=await currentRead();
    const grant=capturedSite.issueReadGrant({operation:GMAIL_THREAD_LIST_OPERATION,decision,resource:'threads',
      runInvocationCid:rowRun.runInvocationCid,dispatchRequestCid:rowRun.dispatchRequestCid,maxUses:threadReadLimits.maxPages});
    const ports={readerDemand:{responses:threadReadLimits.maxPages+threadReadLimits.maxThreads,sequence:{
      operation:GMAIL_THREAD_LIST_OPERATION,maxUses:threadReadLimits.maxPages,childOperation:'gmail:threads:get',
      childMaxUses:threadReadLimits.maxThreads}},operation:GMAIL_THREAD_LIST_OPERATION,nodeTypes,currentRead,
      fail:code=>{throw Object.assign(new Error(code),{code});},prepared:{},access:{},signal:options.signal,
      owner:{resource:options.resource},site:capturedSite,
      runInvocationCid:rowRun.runInvocationCid,dispatchRequestCid:rowRun.dispatchRequestCid,grant,directReadIdentity:undefined,
      nonce:rowRun.requestId,text:value=>typeof value==='string'&&value.length>0};
    const actual=Function(...Object.keys(ports),'let readChildIndex=0,rootReadUses=0,propertyOccurrences=0;'+
      'const readChildOriginals=new WeakMap(),readChildGrants=new Map();return {'+
      'authorizationFor:'+callbacks.authorizationFor+',authorizeReadChild:'+callbacks.authorizeReadChild+'};')(...Object.values(ports));
    const readerOptions={resource:options.resource,columns:options.columns,signal:options.signal,originalAuthorization:grant,
      verifyRead:currentRead,...actual,
      chargePage:(...args)=>Reflect.apply(methods.chargePage,options,args),
      consumeObservation:(...args)=>Reflect.apply(methods.consumeObservation,options,args),
      consumePage:(...args)=>Reflect.apply(methods.consumePage,options,args)};
    return {factory,reader:factory.prepare(readerOptions),readerOptions};
  };
  t.after(async()=>{
    for(const factory of factories)factory.retire();
    pending.add({f,site,row,rowRun,options,observations});row.close();await site.close();
    await writeFile(join(f.root,'pending-thread-factory-custody.json'),JSON.stringify({cleanupConfirmed:false,
      reason:'Explicit component parent and observational test aliases remain; shared-reader retirement is not normal parent/capture proof',
      usage:row.usage().map(value=>typeof value==='bigint'?value.toString():value)}));
  });
  return {...f,provider:f.options.moon,site,suppliedSite,authorization,row,rowRun,options,hooks,decisions,grants,observations,
    capacity:implementation.capacity,makeFactory,makeReader};
}

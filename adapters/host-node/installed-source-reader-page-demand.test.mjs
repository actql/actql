import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {createInstalledCredentialSourceReader, installedJsonSourceReaderLimitNames,
  installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {createProcessFrameReader} from './process-frames.mjs';

const ok=value=>({$tag:1,_0:value});
const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=path=>readFileSync(new URL(path,import.meta.url),'utf8');
function body(source,name){
  const node=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body
    .map(value=>value.declaration??value).find(value=>value.type==='FunctionDeclaration'&&value.id.name===name);
  assert(node,name);return source.slice(node.start,node.end);
}

// Complete existing service constructor, with explicit private association,
// Core capacity and Site ports. No nominal Source material, permission, FD,
// Account, physical child or ordinary Host is issued by this component.
function serviceFixture(){
  const source=text('./installed-host-services.mjs');
  const installations=new WeakMap(),sourceContexts=new WeakMap(),installation=Object.freeze({});
  const scope={};sourceContexts.set(installation,{scope});
  const capacity={},credential={};
  const originalSite=Object.freeze({site:{},callResource(){assert.fail('no send');},
    referenceCurrent(){return true;},authorizationPurpose(){assert.fail('no grant');},
    bindRunAcquisition(){assert.fail('no physical child');}});
  const site={credential};
  const policy=Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map(name=>[name,1000]));
  const limits={...Object.fromEntries([...installedJsonSourceReaderLimitNames,'maxSecretBytes'].map(name=>[name,100])),
    maxPages:3,maxResponseBytes:256,maxRows:2,maxTotalRows:4,maxNodes:64,maxDepth:6,maxCursorBytes:32};
  const moon={clientProgramInstalledSourceReaderPolicy:()=>[1000,1000,100],
    clientProgramInstalledJsonSourceReaderProfile:()=>ok(installedJsonSourceReaderProfileLimitNames.map(name=>policy[name])),
    clientProgramInstalledJsonSourceReaderCapacity(actual,columns,secret){
      assert.deepEqual(actual,installedJsonSourceReaderLimitNames.map(name=>limits[name]));
      assert.equal(columns,3);assert.equal(secret,100);return capacity;}};
  const ports={installations,sourceContexts,fail,checked,runtimeField,runtimeIsBoxedSome,nodeTypes,
    createInstalledCredentialSourceReader,installedJsonSourceReaderLimitNames,installedJsonSourceReaderProfileLimitNames,
    installedRowCredentialOperationSite(actual){assert.equal(actual,credential);return originalSite;}};
  const create=Function(...Object.keys(ports),body(source,'requireSourceConstructor')+'\n'+
    body(source,'createInstalledHostServices')+'\nreturn createInstalledHostServices;')(...Object.values(ports));
  const services=create({root:'/UNOPENED',principalId:'component',moon,assertCurrent(){}});
  const state=installations.get(services),runtimeBundleCid='sha256:'+'a'.repeat(64);
  state.selected.set(installation,runtimeBundleCid);
  state.siteInstallations.set(site,installation);
  services.sourceReaderImplementationProfile({installation,metadataResponses:0,originUnits:20});
  const implementation=services.sourceReaderImplementation({installation,limits,columnCount:3});
  const reader=services.createSourceReader({installation,implementation,site,operation:'rest:read',
    preparePageReader(){assert.fail('no read preparation');}});
  return{scope,reader,limits,capacity,services,installation,implementation,site};
}

function pageSelection(reader,readerDemand,originalPageLimits,prepareSourceRead){
  const source=text('./installed-row-source.mjs');
  const start=source.indexOf('  let pageLimits;'),end=source.indexOf('  if (prepareAcquisition !== undefined',start);
  assert(start>0&&end>start);
  const moon=Object.fromEntries(['InstalledProviderRowCaptureCapacity','InstalledProviderRowCaptureCapacityMatches',
    'RowSourceStartProviderAccounted','RowSourceBorrowResponses','RowSourceBindResponseCleanup',
    'RowSourceBeginWithPageLimits'].map(name=>['clientProgram'+name,()=>{}]));
  const ports={originalPageLimits,prepareSourceRead,readerDemand,providerReader:reader,listingReportCapacity:undefined,
    moon,nodeTypes,fail};
  return Function(...Object.keys(ports),'let originalReader;\n'+source.slice(start,end)+
    '\nreturn {pageLimits,managedPageLimits,originalReader};')(...Object.values(ports));
}

test('same managed service reader demand supplies original whole page bounds without a legacy preparer',()=>{
  const f=serviceFixture();
  try{
    assert.equal(Object.isFrozen(f.scope.readerDemand),true);
    assert.equal(f.scope.readerDemand.transferUnitBytes,256n);
    assert.deepEqual({maxNodes:f.scope.readerDemand.maxNodes,maxDepth:f.scope.readerDemand.maxDepth},{maxNodes:64,maxDepth:6});
    const selected=pageSelection(f.reader,f.scope.readerDemand);
    assert.equal(selected.pageLimits,undefined);
    assert.deepEqual(selected.managedPageLimits,{maxNodes:64,maxDepth:6});
    assert(Object.isFrozen(selected.managedPageLimits));
    assert.equal(selected.originalReader.capacity,f.capacity);
    const source=text('./installed-row-source.mjs');
    const start=source.indexOf('  function managedWholeSourceCapacity('),end=source.indexOf('  const captureCapacity = owner =>',start);
    const prepared={},selection={},declaration={},contracts={},capacity={};
    const moon={clientProgramPrepareWholeSourceCapacity(...args){
      assert.deepEqual(args,[prepared,selection,declaration,contracts,f.capacity,4,256,64,6,2]);return ok(capacity);}};
    const ports={moon,checked,fail,declaration,originalReader:selected.originalReader,
      providerSiteCurrent(){return true;},site:{},limits:{maxCaptureRows:4,maxPageBytes:256,maxPageRows:2},
      pageLimits:selected.pageLimits,managedPageLimits:selected.managedPageLimits,maxTransferBytes:768n};
    const select=Function(...Object.keys(ports),source.slice(start,end)+'\nreturn managedWholeSourceCapacity;')(...Object.values(ports));
    assert.equal(select({preparedProgram:prepared,sourceSelection:selection,installedContracts:contracts}).capacity,capacity);
    const begin=source.indexOf('      const beginPageLimits ='),stop=source.indexOf('      const isListing =',begin);
    assert(begin>0&&stop>begin);
    for(const wholeInput of [true,false]){
      let calls=0;
      const moon={clientProgramRowSourceBegin(...args){assert.equal(wholeInput,false);assert.deepEqual(args,[run,256,2,4,undefined]);calls++;return ok();},
        clientProgramRowSourceBeginWithPageLimits(...args){assert.equal(wholeInput,true);assert.deepEqual(args,[run,256,64,6,2,4,undefined]);calls++;return ok();}};
      const run={};const p={moon,run,checked,owner:{wholeInput},pageLimits:undefined,managedPageLimits:selected.managedPageLimits,
        limits:{maxPageBytes:256,maxPageRows:2,maxCaptureRows:4},referenceIssuer:undefined};
      Function(...Object.keys(p),source.slice(begin,stop))(...Object.values(p));assert.equal(calls,1);
    }
  }finally{assert.equal(f.reader.retire(),true);}
});

test('managed page demand does not weaken the legacy originalPageLimits guard or accept malformed original fields',()=>{
  const f=serviceFixture();
  try{
    assert.throws(()=>pageSelection(f.reader,f.scope.readerDemand,{maxNodes:64,maxDepth:6}),{code:'InvalidInstalledSourcePageLimits'});
    let observed=0;
    for(const demand of [{...f.scope.readerDemand,maxDepth:0},{...f.scope.readerDemand,maxNodes:undefined},
      {...f.scope.readerDemand,get maxNodes(){observed++;return 64;}}]){
      assert.throws(()=>pageSelection(f.reader,demand),{code:'InvalidInstalledSourceReaderPageDemand'});
    }
    assert.equal(observed,0);
    const selected=pageSelection(undefined,undefined,{maxNodes:11,maxDepth:7},()=>{});
    assert.deepEqual(selected.pageLimits,{maxNodes:11,maxDepth:7});assert.equal(selected.managedPageLimits,undefined);
  }finally{assert.equal(f.reader.retire(),true);}
});


test('normal service refuses obsolete mixed and missing protocols before opening a Site',()=>{
  const f=serviceFixture();
  try {
    const base={installation:f.installation,implementation:f.implementation,site:f.site};
    for(const selected of [{...base,createReader(){}},{...base,readPages(){}},base,
      {...base,operation:'rest:read',preparePageReader(){},prepareReadSequence(){}}]) {
      assert.throws(()=>f.services.createSourceReader(selected),{code:'InvalidInstalledSourceReaderSelection'});
    }
  }finally {assert.equal(f.reader.retire(),true);}
});


test('scalar request byte limits cannot revive the retired unbacked query-property reader projection',()=>{
  const f=serviceFixture();
  try{
    for(const patch of [{maxRequestBytes:2},{maxRequestBytes:2,maxPropertyPages:1}]){
      assert.throws(()=>f.services.sourceReaderImplementation({installation:f.installation,columnCount:3,
        limits:{...f.limits,...patch}}),{code:'InstalledSourceReaderRequestCapacityUnavailable'});
    }
  }finally{assert.equal(f.reader.retire(),true);}
});

// Exercise the exact Table reader and the existing shared admission callbacks.
// Core/physical ports are explicit: this counts Host encoding, not admission
// authority, provider I/O, managed Plan funding or ordinary Table acceptance.
function tablePageEncodingFixture({rows = [{text:'e\u0301\r\n',zero:0,flag:false,nullable:null}, {}],
  receivedCount = rows.length} = {}) {
  const table = text('./installed-table-source.mjs'), row = text('./installed-row-source.mjs');
  const find = (source, predicate) => {
    const found = [];
    function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (predicate(node)) found.push(node);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit); else visit(value);
      }
    }
    visit(parse(source, {ecmaVersion:'latest',sourceType:'module'}));
    assert.equal(found.length,1); return source.slice(found[0].start,found[0].end);
  };
  const arrow = name => find(table,node=>node.type==='VariableDeclarator'&&node.id.name===name)
    .slice(name.length+3);
  // Select by the actual readerOptions owner, avoiding unrelated keyed callbacks.
  const optionsNode = find(row,node=>node.type==='VariableDeclarator'&&node.id.name==='readerOptions');
  const options = parse(`const ${optionsNode};`,{ecmaVersion:'latest'}).body[0].declarations[0].init;
  const callback = name => {
    const property = options.properties.filter(node=>node.key?.name===name);
    assert.equal(property.length,1);
    const code = `const ${optionsNode};`;
    return code.slice(property[0].value.start,property[0].value.end);
  };
  let serializations = 0, consumed, charged;
  const calls = [], schema = 'original-schema', selector = {catalog_identity_cid:'catalog',table_uuid:'table',schema_cid:'schema'};
  const receipt = {catalog_identity_cid:'catalog',table_uuid:'table',schema_cid:'schema',storage_mapping_cid:'mapping',
    generation_cid:'sha256:'+'a'.repeat(64),row_count:receivedCount};
  const ports = {Buffer,fail,JSON:{stringify(value){serializations++;return JSON.stringify(value);}},
    identifier:value=>/^sha256:[0-9a-f]{64}$/u.test(value??''),
    byResource:new Map([['rows',{selector,schemaWire:schema}]]),declared:{views:[{resource:'rows',fields:['text','zero','flag','nullable']}]},
    bridge:{async resolveGeneration(actual){assert.equal(actual,selector);calls.push('metadata');return {ok:true,result:{receipt,mapping:{schema_cid:'schema',mapping_cid:'mapping'},schema_wire:schema}};},
      async read(actual,mapping){assert.equal(actual,receipt);assert.equal(mapping.mapping_cid,'mapping');calls.push('read');return {ok:true,result:rows};}}};
  const ownKeys=arrow('keys'),closed=arrow('closedReply');
  const readPages=Function(...Object.keys(ports),`const text=value=>typeof value==='string'&&value.length>0;const keys=${ownKeys};const closedReply=${closed};return ${arrow('readPages')};`)(...Object.values(ports));
  const run={},ticket={};
  const runtime={clientProgramRowSourceAcceptChargedPage(actual,charge,bytes){assert.equal(actual,run);assert.equal(charge,ticket);assert.deepEqual(bytes,charged);consumed=bytes;return ok();}};
  const consume = name => Function('Buffer','JSON','moon','run','checked','return '+callback(name))(Buffer,ports.JSON,runtime,run,checked);
  return {calls,async read(){await readPages({resource:'rows',columns:['text','zero','flag','nullable'],
    async authorizationFor(index){calls.push(`authorize-${index}`);},
    chargePage(bytes){assert.equal(charged,undefined);charged=bytes;return ticket;},
    consumePage:consume('consumePage'),consumePageWire:consume('consumePageWire')});},
    count:()=>serializations,consumed:()=>consumed};
}

test('Table Source encodes one original row page once before the same charged admission',async()=>{
  const f=tablePageEncodingFixture();await f.read();
  assert.equal(f.count(),1,'the same row page must not be JSON-encoded again in the shared admission callback');
  assert.equal(f.consumed().toString('utf8'),'[{"text":"é\\r\\n","zero":0,"flag":false,"nullable":null},{}]');
  assert.deepEqual(f.calls,['authorize-0','metadata','authorize-1','read','authorize-2']);
});

test('Table Source empty generation keeps one encoded page and the original generation refusal precedes encoding',async()=>{
  const empty=tablePageEncodingFixture({rows:[]});await empty.read();assert.equal(empty.count(),1);
  assert.equal(empty.consumed().toString('utf8'),'[]');
  const mismatch=tablePageEncodingFixture({receivedCount:99});
  await assert.rejects(mismatch.read(),{code:'InvalidTableReadReply'});
  assert.equal(mismatch.count(),0);assert.equal(mismatch.consumed(),undefined);
});

// Actual authored Table reader + its actual readPages body. The explicit
// transport/Core ports inspect correspondence and ordering only. They issue
// no Resource/Ledger, Page, Source, authority, Python/Catalog or ordinary Run.
function tableManagedReaderFixture({rows=[{name:'e\u0301\r\n',zero:0,nullable:null},{}],
  growthFailure, returnedFailure, metadataRows=rows.length, actualFacade=false}={}) {
  const source=text('./installed-table-source.mjs'),ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const found=[];
  const visit=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&node.id?.name==='readPages')found.push(node.init);
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);else visit(value);};
  visit(ast);assert.equal(found.length,1);
  const events=[],schemaWire='original-schema',selector={catalog_identity_cid:'catalog',table_uuid:'table',schema_cid:'schema'};
  const receipt={catalog_identity_cid:'catalog',table_uuid:'table',schema_cid:'schema',storage_mapping_cid:'mapping',
    generation_cid:'sha256:'+'a'.repeat(64),row_count:metadataRows};
  const frozen={receipt,mapping:{schema_cid:'schema',mapping_cid:'mapping'},schema_wire:schemaWire};
  const raw=[],tickets=[],bodyQuotes=[],serializeQuotes=[],reserveCalls=[];
  let nativeTicket,chargedBytes=0,encoded=0,readCalls=0,resolving=0;
  const initial=Object.freeze({original:'initial'}),run=Object.freeze({original:'row-run'});let capacity=initial;
  const moon={clientProgramInstalledTableSourceBodyCapacity(previous,bytes,depth){
    assert.equal(this,moon);assert.equal(previous,capacity);assert.equal(depth,32);
    const next=Object.freeze({previous,bytes,kind:'body'});bodyQuotes.push(next);events.push('quote-body');return ok(next);
  },clientProgramInstalledTableSourceSerializationCapacity(previous,bytes){
    assert.equal(this,moon);assert.equal(previous,capacity);const next=Object.freeze({previous,bytes,kind:'serialization'});
    serializeQuotes.push(next);events.push('quote-serialization');return ok(next);
  },clientProgramRowSourceChargeResponseBody(actual,body){
    assert.equal(this,moon);assert.equal(actual,run);assert.equal(nativeTicket,undefined);assert.equal(body,raw.at(-1));
    chargedBytes+=body.length;nativeTicket=Object.freeze({body});tickets.push(nativeTicket);events.push('charge-raw');return ok(nativeTicket);
  }};
  const reserve=(next,phase)=>{
    assert.equal(next.previous,capacity);
    if(phase===undefined)assert.notEqual(nativeTicket,undefined,'final unconsumed response uses charged growth');
    else{assert.equal(phase,'announced-body');assert.equal(nativeTicket,undefined,'previous observation retired before constructor grow');}
    reserveCalls.push({next,phase});events.push('reserve');if(growthFailure!==undefined&&reserveCalls.length===1)throw growthFailure;
    capacity=next;
  };
  const receive=(physical,value)=>{
    const body=Buffer.from(JSON.stringify(value));raw.push(body);
    physical.beforeBodyAllocation(body.length);events.push('allocate');physical.bodyReceived(body);events.push('received');
  };
  const bridge={async resolveGeneration(actual,signal,beforeBodyAllocation,bodyReceived){
    assert.equal(actual,selector);resolving++;events.push('metadata');signal.throwIfAborted();
    const p={beforeBodyAllocation,bodyReceived};receive(p,{kind:'ready'});receive(p,{ok:true,result:frozen});return {ok:true,result:frozen};
  },async read(actualReceipt,actualMapping,signal,beforeBodyAllocation,bodyReceived){
    assert.equal(actualReceipt,receipt);assert.equal(actualMapping,frozen.mapping);readCalls++;events.push('read');signal.throwIfAborted();
    const p={beforeBodyAllocation,bodyReceived};receive(p,{kind:'ready'});receive(p,{ok:true,result:rows});
    if(returnedFailure!==undefined)throw returnedFailure;
    return {ok:true,result:rows};
  }};
  let consumed;
  const wireBuffers=[];let facadeAdmissions=0,facadeConsumer;
  if(actualFacade) {
    // Enter the actual installed Source facade, without a replacement parser,
    // wrapper encoding or Common image. Its original Core port is explicit.
    const facadeSource=text('./installed-row-source.mjs'),facades=[];
    const find=node=>{if(!node||typeof node!=='object')return;
      if(node.type==='Property'&&node.key?.name==='consumePageWire')facades.push(node.value);
      for(const value of Object.values(node))if(Array.isArray(value))value.forEach(find);else find(value);};
    find(parse(facadeSource,{ecmaVersion:'latest',sourceType:'module'}));assert.equal(facades.length,1);
    const facadeMoon={clientProgramRowSourceAcceptChargedPage(original,charge,bytes) {
      assert.equal(original,run);assert.equal(charge,nativeTicket);assert.equal(charge,tickets.at(-1));
      assert.equal(charge.body,raw.at(-1));assert.equal(bytes,wireBuffers.at(-1).bytes);
      assert(Buffer.isBuffer(bytes));consumed=bytes.toString('utf8');nativeTicket=undefined;
      facadeAdmissions++;events.push('admit-rows');return ok();
    },clientProgramRowSourceAcceptPage(){assert.fail('original physical charge cannot be replaced');}};
    const facadeBuffer={from(wire,encoding){
      assert.equal(encoding,'utf8');const bytes=Buffer.from(wire,encoding);
      wireBuffers.push({wire,bytes});return bytes;
    }};
    facadeConsumer=Function('checked','fail','moon','run','Buffer',
      'return ('+facadeSource.slice(facades[0].start,facades[0].end)+');')
      (checked,fail,facadeMoon,run,facadeBuffer);
  }
  const options=Object.freeze({rowRun:Object.freeze({run}),resource:'rows',columns:['name','zero','nullable'],signal:new AbortController().signal,
    authorizationFor(index){assert.equal(this,options);events.push(`authorize-${index}`);},
    chargePage(){assert.fail('projected rows cannot be charged as another received body');},
    consumeObservation(ticket){assert.equal(this,options);assert.equal(ticket,nativeTicket);nativeTicket=undefined;events.push('consume-observation');},
    consumePageWire(wire,{charge}){if(actualFacade)return facadeConsumer(wire,{charge});
      assert.equal(charge,nativeTicket);assert.equal(charge,tickets.at(-1));
      assert.equal(charge.body,raw.at(-1));nativeTicket=undefined;consumed=wire;events.push('admit-rows');}});
  const ports={fail,Buffer:actualFacade?{from(){assert.fail('Table provider must not duplicate facade wire encoding');}}:Buffer,
    identifier:value=>/^sha256:[0-9a-f]{64}$/u.test(value??''),
    byResource:new Map([['rows',{selector,schemaWire}]]),declared:{views:[{resource:'rows',fields:['name','zero','nullable']}]},bridge,
    closedReply(value){if(!value.ok)fail(value.code);return value.result;},JSON:{stringify(value){encoded++;return JSON.stringify(value);}}};
  const readPages=Function(...Object.keys(ports),'return ('+source.slice(found[0].start,found[0].end)+');')(...Object.values(ports));
  const factory=Function('checked','fail',body(source,'createInstalledTableSourceReader')+'\nreturn createInstalledTableSourceReader;')
    (checked,fail)({moon,initialCapacity:initial,readPages,frameLimits:Object.freeze({maxBytes:4194304,maxNodes:100000,maxDepth:32})});
  let retained;
  const reader=factory.prepare(options,original=>{
    assert.equal(retained,undefined);retained=original;
  },reserve);
  assert.equal(retained,reader);
  return{factory,reader,events,raw,tickets,reserveCalls,bodyQuotes,serializeQuotes,options,
    stats:()=>({chargedBytes,encoded,consumed,resolving,readCalls,nativeTicket}),
    facadeStats:()=>({wireBuffers,facadeAdmissions})};
}

test('Table managed reader retains same actual raw tickets and reserves before metadata copy and row serialization',async()=>{
  const f=tableManagedReaderFixture({actualFacade:true});await f.reader.read();
  assert.equal(f.raw.length,4);assert.equal(f.tickets.length,4);
  assert.equal(f.stats().chargedBytes,f.raw.reduce((sum,body)=>sum+body.length,0));
  assert.equal(f.events.filter(v=>v==='consume-observation').length,3);
  assert.equal(f.stats().encoded,1);assert.equal(f.stats().consumed,'[{"name":"é\\r\\n","zero":0,"nullable":null},{}]');
  assert.equal(f.facadeStats().wireBuffers.length,1,'the actual Source facade encodes the generated row wire once');
  assert.equal(f.facadeStats().wireBuffers[0].wire,f.stats().consumed);
  assert.equal(f.facadeStats().facadeAdmissions,1,'the same Buffer and final physical ticket enter the existing charged Core port');
  assert.equal(f.stats().nativeTicket,undefined);
  assert.equal(f.bodyQuotes.length,7,'four original bodies plus three actual metadata outbound stages');
  assert.equal(f.serializeQuotes.length,2,'metadata request and final row output constructed under same original');
  assert.equal(f.reserveCalls.at(-1).phase,undefined,'final raw response ticket stays unconsumed for checked row admission');
  assert.equal(f.reader.observe().cleanupConfirmed,false);f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
  await assert.rejects(f.reader.read(),{code:'InstalledTableSourceReaderAlreadyStarted'});
});

test('Table managed reader capacity refusal and invalid generation precede body allocation or row encoding',async()=>{
  const cause=Object.freeze(new Error('original-resource-refusal')),f=tableManagedReaderFixture({growthFailure:cause});
  await assert.rejects(f.reader.read(),error=>error===cause);
  assert.equal(f.events.includes('allocate'),false);assert.equal(f.raw.length,1);assert.equal(f.stats().chargedBytes,0);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
  const mismatch=tableManagedReaderFixture({metadataRows:99});
  await assert.rejects(mismatch.reader.read(),{code:'InvalidTableReadReply'});
  assert.equal(mismatch.stats().encoded,0);assert.equal(mismatch.stats().consumed,undefined);
  mismatch.reader.requestStop();assert.equal(mismatch.factory.retire(),true);
});

test('Table managed reader typed empty input and original pending cleanup keep their separate duties',async()=>{
  const empty=tableManagedReaderFixture({rows:[]});await empty.reader.read();
  assert.equal(empty.stats().consumed,'[]');assert.equal(empty.stats().encoded,1);empty.reader.requestStop();assert.equal(empty.factory.retire(),true);
  let pending=true,retries=0;
  const cleanup=Object.freeze({status:()=>({pending}),async retry(){retries++;}});
  const cause=Object.freeze(Object.assign(new Error('original-process-unknown'),{cleanupHandle:cleanup}));
  const f=tableManagedReaderFixture({returnedFailure:cause});await assert.rejects(f.reader.read(),error=>error===cause);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,false);assert.equal(f.factory.retire(),false);
  await f.reader.retry();assert.equal(retries,1);assert.equal(f.reader.observe().cleanupConfirmed,false);
  pending=false;await f.reader.retry();assert.equal(retries,2);assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
  assert.equal(f.stats().encoded,0);assert.equal(f.stats().consumed,undefined);
});

// Exact authored normal bound constructor and exact Table factory; only the
// Core capacity/Source association/Account ports are explicit. This connects
// the actual registration sequence, not physical authority or a normal ABI.
function tableBoundConstructionFixture({refuseInitial=false}={}) {
  const host=text('./installed-host-services.mjs'),table=text('./installed-table-source.mjs');
  const services={},context={},installation={registration:'local',revision:'local/0.1'},sourceContexts=new WeakMap(),installations=new WeakMap(),boundConstructions=new WeakMap();
  const events=[],profile={},profileCapacity={},capacity={},declaration={},environment={wire:'original-environment'},account={authorize(){assert.fail('no read authorization during installation');}};
  const selector={catalog_identity_cid:'catalog',table_uuid:'table',schema_cid:'schema'},targets=[{resource:'rows',selector,schemaWire:'original-schema'}];
  const declared={catalog_cid:'catalog',views:[{resource:'rows',fields:['name','zero','nullable']}],manifest_entry:'original'};
  const prepared={declaration,declared,environment};
  const scope={active:true,role:'source',installation,baseEnvironmentWire:'original-base',connectorId:'table'};
  const material={phase:'working',inputs:[],providers:[]};
  const frames=Object.freeze({maxBytes:4194304,maxNodes:100000,maxDepth:32});
  const bridge=Object.freeze({frameLimits:frames,checkReadSelector(value){assert.equal(value,selector);return value;},
    async resolveGeneration(){assert.fail('no metadata during installation');},async read(){assert.fail('no Table read during installation');}});
  const moon={clientProgramInstalledTableSourceReaderCapacity(columns,original){assert.equal(this,moon);assert.equal(columns,3);assert.equal(original,profileCapacity);events.push('reader-quote');return refuseInitial?undefined:capacity;},
    clientProgramInstalledTableSourceBodyCapacity(){assert.fail('no body quote during installation');},
    clientProgramInstalledTableSourceSerializationCapacity(){assert.fail('no output quote during installation');},
    clientProgramRowSourceChargeResponseBody(){assert.fail('no received-byte charge during installation');}};
  const original={moon,root:'/UNOPENED',principalId:'original',current(){},selected:new Map([[installation,'original-runtime']])};
  sourceContexts.set(context,{original,material,scope});installations.set(services,original);
  context.prepareDeclaration=views=>{assert.equal(views[0].schema_cid,selector.schema_cid);scope.prepared=prepared;events.push('declare');return prepared;};
  let source;
  const row=options=>{
    assert.equal(scope.reader,options.providerReader,'original reader association must precede Common row Source construction');
    assert.equal(options.providerReader.capacity,capacity);assert.equal(options.readPages,undefined,'normal has no legacy fallback');
    assert.equal(options.declaration,declaration);assert.equal(options.environment,environment);assert.equal(options.sourceInitialization,context);
    assert.deepEqual(scope.readerDemand,{nested:false,responses:4,queryPages:3,maxResponseBytes:65536,maxNodes:400000,maxDepth:32,maxRows:16,maxTotalRows:16,transferBytes:16777216n});
    events.push('row-source');source=Object.freeze({tableReadTargets:options.tableReadTargets,reader:options.providerReader});scope.source=source;return source;
  };
  const tablePorts={fail,text:value=>typeof value==='string'&&value.length>0,
    keys:(value,names)=>value&&Object.keys(value).sort().join(',')===[...names].sort().join(','),
    dataCid:()=> 'sha256:'+'a'.repeat(64),checked,createInstalledRowSource:row};
  const factory=Function(...Object.keys(tablePorts),body(table,'createInstalledTableSourceReader')+'\n'+body(table,'createInstalledTableSource')+'\nreturn createInstalledTableSource;')(...Object.values(tablePorts));
  const hostPorts={sourceContexts,installations,boundConstructions,fail,nodeTypes,
    runtimeUnboxedReferenceOption:value=>value,
    captureConfigurationReaders:value=>value,installedSourceConfigurationReader:()=>({}),
    reserveInstalledTableConstruction(a,b,c){assert.equal(a,original);assert.equal(b,material);assert.equal(c,profile);events.push('profile-reserve');return profileCapacity;},
    requireSynchronousSourceConstruction:(_m,value)=>value,
    async installRowSourceAuthorization(){events.push('account');return account;},
    installedTableReadSite({authorization,ownAuthorization}){assert.equal(authorization,account);assert.equal(ownAuthorization,true);return {connection:'table-original',issueReadGrant(){assert.fail('no grant during construction');}};},
    reserveSource(a,b){assert.equal(a,original);assert.equal(b,material);assert.equal(material.providers.at(-1),capacity);events.push('reserve-reader');},
    createInstalledTableSource:factory};
  const bind=Function(...Object.keys(hostPorts),body(host,'bindInstalledSourceConstruction')+'\nreturn bindInstalledSourceConstruction;')(...Object.values(hostPorts));
  const bound=bind(services,context,profile);
  const options={connection:'table-original',targets,limits:{maxPages:3,maxPageBytes:65536,maxPageRows:16,maxCaptureRows:16},accountConfiguration:'original-account',
    createBridge(){events.push('bridge');return bridge;}};
  return{create:()=>bound.createTableSource(options),events,scope,material,owned:()=>boundConstructions.get(context),source:()=>source};
}

test('normal Table bound construction reserves and registers its SAME managed reader before original row Source',async()=>{
  const f=tableBoundConstructionFixture();const source=await f.create();
  assert.equal(source,f.source());assert.equal(f.scope.reader,source.reader);assert.equal(f.owned().reader,source.reader);
  assert.deepEqual(f.events,['profile-reserve','bridge','declare','account','reader-quote','reserve-reader','row-source']);
  assert.equal(f.owned().adapter,source);assert.equal(source.reader.retire(),true);
});

test('normal Table missing original reader capacity refuses before reader constructor with partial originals retained',async()=>{
  const f=tableBoundConstructionFixture({refuseInitial:true});
  await assert.rejects(f.create(),{code:'InstalledTableSourceReaderUnavailable'});
  assert.equal(f.events.includes('row-source'),false);assert.equal(f.events.includes('reserve-reader'),false);
  assert.equal(f.owned().reader,undefined);assert.notEqual(f.owned().site,undefined);assert.notEqual(f.owned().authorization,undefined);
  assert.equal(f.owned().constructing,false);assert.equal(f.source(),undefined);
});

// Exact authored Table reader entered by the actual shared RowRun Host. Core
// reservation/charge ports are explicit; this is not a Native process, Account,
// funding profile or ordinary Table/Result proof. No Common image is imported.
function tableOriginalPreparationFixture({rowRunFailure, readPages, beforeCharge, prepareReentry}={}) {
  const run=Object.freeze({}),borrow=Object.freeze({}),acquisition=Object.freeze({}),ledger=Object.freeze({});
  const initial=Object.freeze({}),events=[],closeState={};
  let observe,session,readCalls=0,closes=0,charges=0;
  let controllers=0,signalJoins=0,signalReads=0;
  const externalSignal=new AbortController().signal;
  const moon={
    clientProgramRowSourceStartProviderAccounted(original,capacity,_nonce,_verify,owner) {
      assert.equal(original,acquisition);assert.equal(capacity,initial);assert.equal(owner,ledger);return ok(run);
    },
    clientProgramRowSourceBorrowResponses(original,selected) {
      assert.equal(original,run);assert.equal(selected,acquisition);return ok(borrow);
    },
    clientProgramRowSourceBindResponseCleanup(original,callback) {
      assert.equal(original,borrow);observe=callback;events.push('bind');return ok();
    },
    clientProgramRowSourceGrowResponseCapacity(original) {assert.equal(original,borrow);return ok();},
    clientProgramRowSourceGrowResponseConstructionCapacity(original) {assert.equal(original,borrow);return ok();},
    clientProgramRowSourceRetireResponseWorkspace(original) {assert.equal(original,borrow);return ok();},
    clientProgramRowSourceCloseAccounted(original) {
      assert.equal(original,run);if(!observe())return {$tag:0,_0:'same reader pending'};
      closes++;return ok();
    },
    clientProgramRowSourceCaptureCleanup:()=>ok(true),
    clientProgramRowSourceCaptureCleanupAdvance:()=>ok(true),
    clientProgramInstalledTableSourceBodyCapacity(previous,bytes) {
      assert.equal(this,moon);assert(bytes>0);return ok(Object.freeze({previous}));
    },
    clientProgramInstalledTableSourceSerializationCapacity(previous,bytes) {
      assert.equal(this,moon);assert(bytes>0);return ok(Object.freeze({previous}));
    },
    clientProgramRowSourceChargeResponseBody(original,bytes) {
      assert.equal(this,moon);assert.equal(original,run);assert(Buffer.isBuffer(bytes));
      charges++;beforeCharge?.(session,closeState,bytes);return ok(Object.freeze({bytes}));
    },
  };
  const frameLimits=Object.freeze({maxBytes:256,maxNodes:64,maxDepth:8});
  const factory=Function('checked','fail','AbortController','AbortSignal',
    body(text('./installed-table-source.mjs'),'createInstalledTableSourceReader')+
    '\nreturn createInstalledTableSourceReader;')(checked,fail,
    class extends AbortController {constructor(){super();controllers++;}},
    {any(signals){signalJoins++;return AbortSignal.any(signals);}})({moon,initialCapacity:initial,frameLimits,
    async readPages(options,physical) {
      readCalls++;events.push('read');
      return readPages===undefined?'same original result':await readPages(options,physical,frameLimits);
    }});
  session=startInstalledRowRun({moon,acquisition,ledger,nonce:'same-table-original',
    capacity:{provider:initial,transferBytes:1024n,executionBytes:1024n}});
  const reenter=field=>{if(prepareReentry===field)session.close();};
  const options={get rowRun(){if(rowRunFailure!==undefined)throw rowRunFailure;reenter('rowRun');return Object.freeze({run});},
    get consumeObservation(){reenter('consumeObservation');return()=>{};},
    get signal(){if(++signalReads===2)reenter('signal');return externalSignal;},
    verifyRead(){assert.equal(this,options);events.push('current');}};
  Object.freeze(options);
  return {factory,session,events,closeState,
    read:()=>session.readProvider({receiver:factory,prepare:factory.prepare,options}),
    counts:()=>({readCalls,closes,charges}),
    preparationCounts:()=>({controllers,signalJoins,signalReads})};
}

test('Table original preparation enters the actual shared Host and retires only its same reader',async()=>{
  const f=tableOriginalPreparationFixture();
  assert.equal(await f.read(),'same original result');
  assert.deepEqual(f.events,['bind','current','read']);
  assert.deepEqual(f.counts(),{readCalls:1,closes:0,charges:0});
  f.session.close();
  assert.deepEqual(f.counts(),{readCalls:1,closes:1,charges:0});
  assert.equal(f.factory.retire(),true);
});

test('Table original partial preparation keeps the same failure and is retired by its original Host',async()=>{
  const primary=Object.freeze(new Error('same original rowRun getter'));
  const f=tableOriginalPreparationFixture({rowRunFailure:primary});
  await assert.rejects(f.read(),error=>error===primary);
  assert.deepEqual(f.events,['bind']);assert.equal(f.counts().readCalls,0);
  f.session.close();
  assert.equal(f.counts().closes,1);assert.equal(f.factory.retire(),true);
});

test('Table original received body rechecks the same stopped reader before actual frame decoding',async()=>{
  let accepted=0,received;
  const f=tableOriginalPreparationFixture({
    beforeCharge(session,state,bytes){received=bytes;session.closeAfterFailure(state);},
    readPages(_options,physical,limits){
      const parser=createProcessFrameReader(limits,()=>{accepted++;},
        physical.beforeBodyAllocation,physical.bodyReceived);
      // Actual complete received body is charged. Its invalid JSON makes a
      // continued decoder observable; stop must refuse BEFORE that decoder.
      const wire=Buffer.from([0,0,0,1,0x7b]);
      parser.feed(wire);
      assert.fail('stopped reader continued into its result');
    },
  });
  await assert.rejects(f.read(),{code:'InstalledTableSourceReaderClosed'});
  assert.equal(received.toString('utf8'),'{');assert.equal(accepted,0);
  assert.deepEqual(f.counts(),{readCalls:1,closes:0,charges:1});
  assert.equal(f.closeState.closeFailed,true);
  assert.equal(f.closeState.recovery.cleanupPending(),true);
  // This is managed reader retirement only. No parent close ACK is inferred.
  assert.equal(f.factory.retire(),true);
});

test('Table original settled reader cannot create another pending retry while its same Host retires',async()=>{
  for(const ending of ['resolved','rejected']) {
    let start,resolve,reject;
    const began=new Promise(yes=>{start=yes;});
    const pending=new Promise((yes,no)=>{resolve=yes;reject=no;});
    const primary=Object.freeze(new Error('same original stopped read'));
    const f=tableOriginalPreparationFixture({readPages(){start();return pending;}});
    const reading=f.read();await began;
    f.session.closeAfterFailure(f.closeState);
    assert.equal(f.closeState.recovery.cleanupPending(),true);
    assert.equal(await f.closeState.recovery.cleanup(),false);
    assert.equal(f.counts().closes,0);
    if(ending==='resolved'){resolve('original settled');assert.equal(await reading,'original settled');}
    else{reject(primary);await assert.rejects(reading,error=>error===primary);}
    // The original read settled and its SAME reader retired. Retrying that
    // spent reader must now be synchronous; a fresh Promise would manufacture
    // pending work every time before the Host can observe the original stop.
    assert.equal(await f.closeState.recovery.cleanup(),true);
    assert.equal(f.closeState.recovery.cleanupPending(),false);
    assert.deepEqual(f.counts(),{readCalls:1,closes:1,charges:0});
    f.session.close();assert.equal(f.counts().closes,1);
    assert.equal(f.factory.retire(),true);
  }
});

test('Table original preparation getter retirement forbids the next constructor on the same closed Host',async()=>{
  for(const field of ['rowRun','consumeObservation','signal']) {
    const f=tableOriginalPreparationFixture({prepareReentry:field});
    await assert.rejects(f.read(),{code:'InstalledTableSourceReaderClosed'});
    assert.deepEqual(f.counts(),{readCalls:0,closes:1,charges:0});
    assert.equal(f.preparationCounts().controllers,field==='signal'?1:0,
      `${field}: a returned original cannot enter the next constructor after retirement`);
    assert.equal(f.preparationCounts().signalJoins,0,
      `${field}: the retired signal cannot be rebound into a new composite`);
    assert.equal(f.factory.retire(),true);
    f.session.close();assert.equal(f.counts().closes,1);
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {createInstalledCredentialSourceReader, installedJsonSourceReaderLimitNames,
  installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';

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

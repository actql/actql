// Real Local driver composition with explicit Run/Content/native ports.
// No Account grant, actual FD, Common Reference or physical STORE is supplied.
// The outcome-shape case also consumes actual Common protocol admission;
// its receipt identifiers and response are fixture DATA, not a physical ACK.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import test from 'node:test';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createLocalFileStoreDriver,LOCAL_STORE_LIMITS} from './installed-project-file-effects.mjs';

const cid=digit=>'sha256:'+digit.repeat(64);
const wire=value=>canonicalJson(value,{dataKeys:true});
function fixture(){
  const run=Object.freeze({}),binding=Object.freeze({});
  const resource=Object.freeze({$actql_ref:'resource',version:'actql-resource-ref/0.1',
    provider_namespace:'local',resource_kind:'file_collection',provider_identity_cid:cid('a'),
    authority_scope_cid:cid('b'),boundary_cid:cid('c'),identity_cid:cid('d')});
  const content=Object.freeze({$actql_ref:'content',identity_cid:cid('e')});
  const value={path:'out.jsonl',content:{...content}};
  const command={command_id:'command:local.local.files.store.v1',contract_cid:cid('f')};
  const member={kind:'command',resource:'files',command:{commandRef:command.command_id,
    commandCid:command.contract_cid}};
  const limits={...LOCAL_STORE_LIMITS,maxFileBytes:1024};
  let live=true,nativeCalls=0;
  const nativeFilesystem=Object.freeze(Object.fromEntries(['openFileRoot','openFileDirectory',
    'openRootFileWriter','fileRootCurrent','fileRootWrite','fileRootPublish','fileRootClose']
    .map(name=>[name,()=>{nativeCalls++;assert.fail('No native use before approved send');}])));
  const borrowed=Object.freeze({binding,current:()=>live,wire:()=>wire(content)});
  const contentOwner=Object.freeze({consumeContent(){assert.fail('No byte read before approved send');}});
  const {driver,site}=createLocalFileStoreDriver({entry:{connection:'local',rootPath:'/original/root',
    limits:{maxPathBytes:1024}},target:{resourceWire:wire(resource)},command,bindingCid:cid('1'),
    principalId:'reader',authorization:{configurationCid:cid('2')},assertCurrent(){},
    resources:{assertCurrent(original){assert.strictEqual(original,run);},limits(original){
      assert.strictEqual(original,run);return limits;}},limits,nativeFilesystem});
  const selected=driver.describe({member,runOriginal:run,runInvocationCid:cid('3'),dispatchRequestCid:cid('4')});
  const prepare=(changes={})=>driver.prepareRequestChild({member,runOriginal:run,value,
    selector:resource,current:selected,content:name=>{assert.equal(name,'content');return borrowed;},
    contentOwner,...changes});
  return{driver,site,run,member,selected,resource,value,prepare,contentOwner,
    retire(){live=false;},nativeCalls:()=>nativeCalls};
}

test('Local STORE retains original Content borrower and exact input before approval without I/O',async()=>{
  const f=fixture(),child=f.prepare(),prepared=child.prepare();
  f.value.path='changed';f.value.content.identity_cid=cid('9');
  const facts=f.driver.requestFacts(prepared.request);
  assert.equal(facts.value.path,'out.jsonl');assert.equal(facts.value.content.identity_cid,cid('e'));
  assert.deepEqual(facts.target,f.resource);
  f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:f.run});
  assert.equal(f.nativeCalls(),0);
  f.retire();
  assert.throws(()=>f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:f.run}),
    {code:'OriginalEffectContentUnavailable'});
  assert.equal(await child.release(),true);assert.equal(child.status().pending,false);
  assert.throws(()=>f.driver.requestFacts(prepared.request),{code:'ForeignLocalStoreRequest'});
  await f.site.close();assert.equal(f.nativeCalls(),0);
});

test('Local STORE rejects changed, missing and foreign originals before native acquisition',async()=>{
  const f=fixture();
  for(const changes of [
    {content:()=>({current:()=>false,wire:()=>''})},
    {content:()=>({current:()=>true,wire:()=>'{"foreign":true}'})},
    {value:{path:'../escape',content:f.value.content}},
    {selector:{...f.resource,identity_cid:cid('9')}},
  ]){
    const child=f.prepare(changes);
    assert.throws(()=>child.prepare());
    assert.equal(await child.release(),true);
  }
  const missing=f.prepare({contentOwner:undefined}),prepared=missing.prepare();
  assert.throws(()=>f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:f.run}),
    {code:'OriginalEffectContentUnavailable'});
  assert.throws(()=>f.driver.requestFacts({...prepared.request}),{code:'ForeignLocalStoreRequest'});
  assert.throws(()=>f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:{}}));
  await missing.release();await f.site.close();assert.equal(f.nativeCalls(),0);
});

test('Local STORE accepts no structural Account or approval substitute',async()=>{
  const f=fixture();
  assert.throws(()=>f.site.issueEffectGrant({operation:'files.write',resource:'files',
    runInvocationCid:cid('3'),dispatchRequestCid:cid('4'),subjectCid:cid('5'),
    decision:{action:'dispatch',boundary:'effect_commit',subjectCid:cid('5'),basis:'resumed',
      checkpointCid:cid('6'),resolutionCid:cid('7'),
      tuple:{connection:'local',resource:'files',operation:'effect'}}}),{code:'LocalStoreNotAuthorized'});
  assert.equal(f.nativeCalls(),0);await f.site.close();
});

test('Local STORE recovered request connects the retained original Content child before any send',async()=>{
  const f=fixture(),capture=f.prepare(),initial=capture.prepare();
  const saved=f.driver.recoveryEntry({entries:[initial]});
  const member={...f.member,memberIndex:0};
  const restored=f.driver.recoverRequests({
    durable:{connectorRecovery:[{memberIndex:0,...saved}]},
    body:{effects:[{changes:[{}]}]},runOriginal:f.run,members:[member],
    runInvocationCid:cid('3'),dispatches:[cid('4')]});
  const request=restored.requests[0][0],entries=[[{request,requestCid:f.driver.requestCid(request)}]];
  const prepared={},allowed={},definition={},source={},events=[];
  let pending=true;
  const borrowed={binding:{},current:()=>pending};
  const contentOwner={consumeContent(){assert.fail('No bytes are sent during recovery preparation');}};
  const recovered={prepared,allowed,runDefinition:definition,computation:{
    effectSources:[{memberIndex:0,source}],preview:{},invocation:{},computation:{capturedRun:{}}}};
  const child=f.driver.prepareRecoveredContentChild({recovered,members:[member],entries,memberIndexes:[0],
    control:{adoptCheckedClientEffectSerializationRun(value,run){
      assert.strictEqual(value,allowed);assert.strictEqual(run,definition);return{};}},
    store:{},principalId:'reader',runOriginal:f.run,limits:{maxFields:10,maxWork:1000,
      body:{maxBytes:10000,maxNodes:1000,maxDepth:64}},
    contentRun:{prepareRecoveredCommandContent(options){
      assert.strictEqual(options.prepared,prepared);assert.strictEqual(options.source,source);
      assert.equal(options.row,0);assert.equal(options.inputName,'content');
      assert.equal(options.referenceWire,wire(f.value.content));
      events.push('construct');return{
        async prepare(){events.push('prepare');return{borrow:borrowed,contentOwner};},
        async release(){events.push('release');pending=false;return true;},status:()=>({pending})};}}});
  assert.deepEqual(events,[]);assert.equal(child.status().pending,true);
  await child.prepare();assert.deepEqual(events,['construct','prepare']);
  f.driver.recheckRequests({member,entries:entries[0],runOriginal:f.run});
  assert.equal(f.nativeCalls(),0);
  assert.equal(await child.release(),true);assert.equal(child.status().pending,false);
  assert.throws(()=>f.driver.requestFacts(request),{code:'ForeignLocalStoreRequest'});
  assert.throws(()=>child.prepare(),{code:'LocalStoreRecoveryAlreadyAttempted'});
  await capture.release();await f.site.close();assert.equal(f.nativeCalls(),0);
});

test('Local STORE projects a Command outcome admitted by actual Common without a provider action',async()=>{
  const url=process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME
    ?pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME)
    :new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url);
  const moon=await import(url),hash=bytes=>createHash('sha256').update(bytes).digest('hex');
  const contentCid=value=>'sha256:'+hash(wire(value));
  const f=fixture(),child=f.prepare(),prepared=child.prepare();
  const response={request_cid:prepared.requestCid,path:'out.jsonl',bytes:9,action:'stored'};
  const body=Buffer.from(wire(response));
  const observation={useCid:cid('8'),statusCode:200,body};
  const admitShape=outcome=>{
    // Only protocol/self-CID admission is selected here. No Preview binding,
    // dispatch claim, Ledger commit or external outcome is issued by this DATA.
    const receipt={version:'actql-effect-row-outcome-receipt/0.1',
      effect_preview_cid:cid('2'),effect_member_preview_cid:cid('3'),row_preview_cid:cid('4'),
      dispatch_entry_cid:cid('5'),credential_use_cid:observation.useCid,
      response_physical_sha256:hash(body),response_byte_count:body.length,http_status_code:200,
      typed_outcome:outcome,typed_outcome_cid:contentCid(outcome)};
    return checked(moon.strategyPublicationAdmit('effect_row_outcome_receipt',
      wire({...receipt,receipt_cid:contentCid(receipt)}),131072,10000,64));
  };
  try{
    const expected={state:'applied',result:{}};
    assert(admitShape(expected),'Independent original Command outcome baseline is valid');
    const projected=f.driver.project({request:prepared.request,observation});
    assert.equal(projected.kind,'typed-success-response');
    assert(admitShape(projected.outcome),'The actual adapter outcome must satisfy the unchanged Common schema');
    assert.deepEqual(projected.outcome,expected);
    assert.equal(JSON.parse(body.toString('utf8')).action,'stored',
      'The private physical response marker is distinct from the generic outcome');
    for(const changed of [
      {...response,request_cid:cid('9')},{...response,path:'other.jsonl'},
      {...response,bytes:1025},{...response,extra:true},
    ])assert.deepEqual(f.driver.project({request:prepared.request,
      observation:{...observation,body:Buffer.from(wire(changed))}}),{kind:'unknown'});
    assert.deepEqual(f.driver.project({request:prepared.request,
      observation:{...observation,statusCode:500}}),{kind:'unknown'});
    assert.throws(()=>f.driver.project({request:{...prepared.request},observation}),
      {code:'ForeignLocalStoreRequest'});
    assert.equal(f.nativeCalls(),0);
  }finally{await child.release();await f.site.close();}
});


test('Local STORE recovery bounds each original row before whole-frame concatenation and encodes it once', () => {
  const source=readFileSync(new URL('./installed-project-file-effects.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'}),found=[];
  const visit=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='recoveryEntry')found.push(node.value);
    for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(visit);else if(value&&typeof value==='object')visit(value);}};
  visit(tree);assert.equal(found.length,1);
  const fn=Function('wire','cid','createHash','own','bindingCid','limits','fail',
    'return (function '+source.slice(found[0].start,found[0].end)+');');
  const records=[{path:'é\n"',content:{identity_cid:cid('1')}},
    {path:'😀',content:{identity_cid:cid('2')}}];
  const entries=records.map(record=>({request:record}));
  let encodes=0,whole=0,reads=0;
  const actualWire=value=>{if(value?.requests?.length)whole++;if(records.includes(value))encodes++;return wire(value);};
  const bind=cid('3'),expected=wire({binding:bind,requests:records});
  const emit=fn(actualWire,value=>'sha256:'+createHash('sha256').update(wire(value)).digest('hex'),createHash,
    request=>{reads++;return {record:request};},bind,{maxRequestBytes:100000},code=>{throw Object.assign(new Error(code),{code});});
  const actual=emit({entries});
  assert.equal(actual.wire,expected);
  assert.equal(actual.observationCid,'sha256:'+createHash('sha256').update(expected).digest('hex'));
  assert.equal(reads,2);assert.equal(encodes,2);assert.equal(whole,0);
});


test('Local STORE recovery preserves original admission order and rejects before encoding an over-limit tail', () => {
  const source=readFileSync(new URL('./installed-project-file-effects.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'}),found=[];
  const visit=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='recoveryEntry')found.push(node.value);
    for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(visit);else if(value&&typeof value==='object')visit(value);}};
  visit(tree);assert.equal(found.length,1);
  const fn=Function('wire','cid','createHash','own','bindingCid','limits','fail',
    'return (function '+source.slice(found[0].start,found[0].end)+');');
  const bind=cid('3'),records=[{path:'é\n',content:{identity_cid:cid('1')}},
    {path:'😀',content:{identity_cid:cid('2')}},{path:'tail',content:{identity_cid:cid('4')}}];
  const entries=records.map(record=>({request:record}));let reads=0,encoded=[];
  const encode=value=>{if(records.includes(value))encoded.push(records.indexOf(value));return wire(value);};
  const fail=code=>{throw Object.assign(new Error(code),{code});};
  const exact=Buffer.byteLength(wire({binding:bind,requests:records.slice(0,2)}));
  const emit=fn(encode,value=>cid('5'),createHash,request=>{reads++;return {record:request};},bind,
    {maxRequestBytes:exact-1},fail);
  assert.throws(()=>emit({entries}),{code:'LocalStoreRecoveryLimit'});
  assert.equal(reads,3,'every original is admitted before any encoding refusal');
  assert.deepEqual(encoded,[0,1],'never concatenate the frame or encode its tail after refusal');
  reads=0;encoded=[];
  const foreign=fn(encode,value=>cid('5'),createHash,request=>{
    reads++;if(request===records[2])throw undefined;return {record:request};
  },bind,{maxRequestBytes:1},fail);
  let caught=false;try{foreign({entries});}catch(error){caught=true;assert.strictEqual(error,undefined);}
  assert.equal(caught,true);assert.equal(reads,3);assert.deepEqual(encoded,[]);
  const accepted=fn(encode,value=>cid('5'),createHash,request=>({record:request}),bind,
    {maxRequestBytes:exact},fail)({entries:entries.slice(0,2)});
  assert.equal(Buffer.byteLength(accepted.wire),exact);
});

test('Local STORE approved send preserves an original undefined failure after confirmed writer close', async () => {
  const source=readFileSync(new URL('./installed-project-file-effects.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'}),found=[];
  const visit=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='send')found.push(node.value);
    for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(visit);else if(value&&typeof value==='object')visit(value);}};
  visit(tree);assert.equal(found.length,1);
  const proof={},run={},request={},selected={},authorization={proof,useId:'original'};
  const observed={runInvocationCid:cid('1'),dispatchRequestCid:cid('2')};
  const grant={...observed,subjectCid:cid('3'),used:false,decision:{}};
  const original={cid:cid('4'),record:{value:{path:'out',overwrite:false}},borrow:{},contentOwner:{}};
  let closes=0,executions=0;
  const writer={async execute(){executions++;throw undefined;},async close(){closes++;return {pending:false};},
    status:()=>({pending:false}),retry(){assert.fail('no retry');}};
  const send=Function('memberCurrent','description','own','grants','decisionCurrent','prepareLocalStoredContentWrite',
    'nativeFilesystem','entry','randomUUID','limits','runCurrent','cid','wire','fail','writerProfile',
    'return (async function '+source.slice(found[0].start,found[0].end)+');')(
    ()=>{},()=>observed,()=>original,new WeakMap([[proof,grant]]),()=>{},()=>writer,{},
    {rootPath:'/original'},()=> 'temporary',{maxFileBytes:1024,maxResponseBytes:65536},()=>{},
    value=>cid('5'),wire,code=>{throw Object.assign(new Error(code),{code});});
  let caught=false;try{await send({member:{},request,current:selected,authorization,runOriginal:run});}
  catch(error){caught=true;assert.strictEqual(error,undefined);}
  assert.equal(caught,true);assert.equal(executions,1);assert.equal(closes,1);
  assert.strictEqual(original.writeChild,writer);assert.equal(grant.used,true);
});


test('Local STORE keeps cleanup pending for an undefined close failure without replacing its original primary', async () => {
  const source=readFileSync(new URL('./installed-project-file-effects.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'}),found=[];
  const visit=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='send')found.push(node.value);
    for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(visit);else if(value&&typeof value==='object')visit(value);}};
  visit(tree);assert.equal(found.length,1);
  const construct=Function('memberCurrent','description','own','grants','decisionCurrent','prepareLocalStoredContentWrite',
    'nativeFilesystem','entry','randomUUID','limits','runCurrent','cid','wire','fail','writerProfile',
    'return (async function '+source.slice(found[0].start,found[0].end)+');');
  for(const primaryFailed of [false,true]){
    const proof={},observed={runInvocationCid:cid('1'),dispatchRequestCid:cid('2')};
    const grant={...observed,subjectCid:cid('3'),used:false,decision:{}};
    const original={cid:cid('4'),record:{value:{path:'out'}},borrow:{},contentOwner:{}};
    let executions=0,closes=0;
    const writer={async execute(){executions++;if(primaryFailed)throw null;return {path:'out',bytes:0};},
      async close(){closes++;throw undefined;},status:()=>({pending:true}),retry(){}};
    const send=construct(()=>{},()=>observed,()=>original,new WeakMap([[proof,grant]]),()=>{},()=>writer,{},
      {rootPath:'/original'},()=> 'temporary',{maxFileBytes:1024,maxResponseBytes:65536},()=>{},
      value=>cid('5'),wire,code=>{throw Object.assign(new Error(code),{code});});
    await assert.rejects(send({member:{},request:{},current:{},authorization:{proof,useId:'original'},runOriginal:{}}),
      error=>{
        assert.equal(error.code,'LocalStoreCleanupPending');assert.equal(error.cleanupPending,true);
        assert.strictEqual(error.cause,primaryFailed?null:undefined);
        assert.strictEqual(error.cleanupHandle.status,writer.status);
        assert.strictEqual(error.cleanupHandle.retry,writer.retry);return true;
      });
    assert.equal(executions,1);assert.equal(closes,1);assert.strictEqual(original.writeChild,writer);
    assert.equal(grant.used,true);
  }
});

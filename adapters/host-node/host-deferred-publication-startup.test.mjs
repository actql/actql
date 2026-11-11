import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {inspect} from 'node:util';
import {compileFunction} from 'node:vm';
import nodeTest from 'node:test';
import {parse} from 'acorn';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {issueNodeClientSubmissionEpoch} from './client-submission.mjs';
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {submissionEpoch} from '../../packages/sdk/submission-fixture.mjs';

const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const installedHost=ast.body.find(node=>node.type==='FunctionDeclaration'&&
  node.id.name==='openInstalledHost');
const installedEntryGuard=installedHost.body.body[0];
assert.equal(installedEntryGuard.type,'IfStatement');
assert.match(source.slice(installedEntryGuard.start,installedEntryGuard.end),
  /InstalledRequestPreparationUnavailable/u);
const declaration=name=>{
  const found=nodes.filter(node=>node.type==='VariableDeclarator'&&node.id.name===name);
  assert.equal(found.length,1,name);return source.slice(found[0].start,found[0].end);
};
const returned=nodes.filter(node=>node.type==='ReturnStatement'&&
  source.slice(node.start,node.end).startsWith('return Object.assign(host, {port:bootstrapPort'));
assert.equal(returned.length,1);
const activationChoice=nodes.filter(node=>node.type==='IfStatement'&&
  node.consequent.type==='ReturnStatement'&&
  source.slice(node.consequent.start,node.consequent.end)==='return await activate();');
assert.equal(activationChoice.length,1);
const make=compileFunction(`return async function(input){
  const createNodeInProcessClientHost=options=>{
    input.observeIngress(options);return baseCreateNodeInProcessClientHost(options);
  };
  const host={},principalId='original',mode='local',namespaceId='original';
  const authorityScopeCid=input.scope,workspaceId=undefined,moon=input.moon,journal=input.journal;
  const closeHostRequestJournal=()=>journal.close();
  const sourceProfile=input.source,installedEffect=undefined,diagnostic=undefined,observation=undefined;
  const fixtureRequestPreparation=Object.freeze(Object.fromEntries(
    ['beforeSourceSnapshot','bindSourceSnapshot','bindSourceRequest','finishSourceProducer','intentCid',
      'captureSourceSnapshot','assertSourceSnapshotCurrent','publishSourceSnapshot']
      .map(name=>[name,()=>{throw Error('No business Source in this fixture');}])));
  const preparation=input.selected===false?undefined:{initialControl:input.initialControl,
    fundedPreparation(){throw Error('No business funding in this fixture');},
    requestPreparation(){return fixtureRequestPreparation;},
    beforeResultPublicationOperation(operation){if(operation!=='attach')throw Error('Unexpected component operation');},
    assertResultPublicationCurrent(){},
    bindSourceRequest(){throw Error('No business Source in this fixture');}};
  ${source.slice(installedEntryGuard.start,installedEntryGuard.end)}
  const originalSourcePreparation=input.withSource===false?undefined:fixtureRequestPreparation;
  const ${declaration('originalRequestPreparation')};
  const ${declaration('localSigningRecoveries')};
  let modelRuntimeClosing=false,activationFlight,activationFailure,store;
  const retireModelRuntime=input.retire;
  const initializePublicationServices=()=>input.initialize(host,value=>{store=value;});
  const ${declaration('hostConnection')};
  const ${declaration('authorizedScope')};
  const ${declaration('resultReadLimits')};
  const ${declaration('negotiate')};
  const ${declaration('activate')};
  ${source.slice(activationChoice[0].start,activationChoice[0].end)}
  const ${declaration('bootstrapIngress')};
  const ${declaration('bootstrapPort')};
  ${source.slice(returned[0].start,returned[0].end)};};`,
  ['baseCreateNodeInProcessClientHost','issueNodeClientSubmissionEpoch',
    'sourcePreparationPort','clientOperationError'])(createNodeInProcessClientHost,
      issueNodeClientSubmissionEpoch,sourcePreparationPort,
      code=>Object.assign(new Error(code),{code}));
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};};
const ref={namespaceId:'original',authorityScopeCid:submissionEpoch.authorityScopeCid,
  runDefinitionCid:'sha256:'+'d'.repeat(64)};

// Exact same-Host startup/activation statements, real SDK ingress/registry and
// explicit physical/Journal stopping ports. These counters do not issue a
// startup/Source/Store supplier or qualify the literal installed README entry.
async function createFixture({initialize,withSource=true,selected=true}={}){
  const calls=[],moon={},journal={
    issueSubmissionEpoch(fields,runtime){assert.strictEqual(this,journal);
      assert.strictEqual(runtime,moon);assert.equal(fields.currentAuthorization,true);
      calls.push('epoch');return submissionEpoch;},close(){calls.push('journal');}};
  let constructions=0;
  const host=await make({scope:ref.authorityScopeCid,moon,journal,withSource,selected,
    observeIngress(options){assert.equal(typeof options.bindOwnedRequest,
      'function');},
    source:{close(){calls.push('source');}},initialControl:{close(){calls.push('control');return {pending:false};}},
    retire(){calls.push('retire-runtime');},async initialize(same,setStore){
      constructions++;if(initialize)return initialize(same,setStore,calls);
      setStore({close(){calls.push('store');}});
      return Object.assign(same,{port:{async perform(operation){
        assert.equal(operation,'attach');calls.push('attach');return {ref,durability:'durable',revision:1};}},
        dispatchOwner:{drain(){calls.push('drain');}},retireTerminalEffects(){calls.push('retire');}});
    }});
  const registry=createEmbeddedHostRegistry(()=>true);
  return {host,calls,constructions:()=>constructions,
    connect:()=>registry.connect('/original','same',async()=>host,{mode:'local',owner:'local'})};
}

nodeTest('installed Host fixture requires its actual preparation owner before activation',async()=>{
  let initialized=0;
  await assert.rejects(createFixture({selected:false,withSource:false,
    initialize(){initialized++;}}),{name:'TypeError',message:'InstalledRequestPreparationUnavailable'});
  assert.equal(initialized,0);
});

nodeTest('selected ordinary Host cannot borrow Journal coverage for Publication activation',async()=>{
  const initializer=nodes.find(node=>node.type==='VariableDeclarator'&&
    node.id.name==='initializePublicationServices');
  const guard=initializer.init.body.body[0].block.body[0];
  assert.equal(guard.type,'IfStatement');
  const check=compileFunction(`return async preparation=>{${source.slice(guard.start,guard.end)}};`)();
  let journalCalls=0;
  for(const preparation of [{},{prepareHostJournal(){journalCalls++;}}]){
    await assert.rejects(check(preparation),TypeError);
  }
  assert.equal(journalCalls,0);
  const original=new Error('OriginalPublicationPreparationFailure');
  await assert.rejects(check({prepareResultPublication(){throw original;}}),error=>error===original);
  const waiting=deferred();let returned=false,calls=0;
  const pending=check({prepareResultPublication(){calls++;return waiting.promise;}})
    .then(()=>{returned=true;});
  await Promise.resolve();assert.equal(calls,1);assert.equal(returned,false);
  waiting.resolve();await pending;assert.equal(returned,true);
});

for(const withSource of [true,false]){
const fixture=options=>createFixture({...options,withSource});
const test=(name,body)=>nodeTest(`${withSource?'Source-selected':'ordinary selected'}: ${name}`,body);

test('SDK connect and unused close require no Publication Store key or service construction',async()=>{
  const f=await fixture(),client=await f.connect();
  assert.equal(Object.hasOwn(f.host.port,sourcePreparationPort),true);
  assert.equal(Object.hasOwn(f.host.port,'answerCheckpoint'),withSource);
  assert.equal(f.constructions(),0);assert.equal(f.host.store,undefined);
  assert.deepEqual(f.calls,['epoch']);
  await client.close();
  assert.equal(f.constructions(),0);
  assert.deepEqual(f.calls,['epoch','journal','source','control','retire-runtime']);
});

test('same Host activation is single flight and final lease waits its original terminal state',async()=>{
  const entered=deferred(),released=deferred();
  const f=await fixture({async initialize(host,setStore,calls){
    entered.resolve();await released.promise;
    setStore({close(){calls.push('store');}});
    return Object.assign(host,{port:{async perform(){calls.push('attach');return {ref,durability:'durable',revision:1};}},
      dispatchOwner:{drain(){calls.push('drain');}},retireTerminalEffects(){calls.push('retire');}});
  }});
  const client=await f.connect(),first=client.attach(ref).catch(error=>error),second=client.attach(ref).catch(error=>error);
  await entered.promise;assert.equal(f.constructions(),1);
  let closed=false;const closing=client.close().then(()=>{closed=true;});
  await Promise.resolve();await Promise.resolve();assert.equal(closed,false);
  assert.equal(f.calls.includes('journal'),false);
  released.resolve();await Promise.all([first,second]);await closing;
  assert.equal(f.constructions(),1);assert.equal(f.calls.filter(name=>name==='store').length,1);
  assert.ok(f.calls.indexOf('store')<f.calls.indexOf('control'));
});

test('invalid or foreign connection requests refuse before optional construction',async()=>{
  const f=await fixture(),client=await f.connect();
  await assert.rejects(f.host.port.perform('unknown',{}),{code:'InvalidClientRequest'});
  await assert.rejects(f.host.port.perform('attach',{connection:{mode:'remote',owner:'local',
    durability:'durable',consentRefs:[],runners:[]},ref}),error=>
    ['InvalidClientRequest','ClientConnectionDenied'].includes(error.code));
  assert.equal(f.constructions(),0);await client.close();
});

test('failed activation retains its original cleanup callbacks and cannot be ACKed by later replacement',async()=>{
  let ready=false,retries=0,replacements=0;
  const cleanup={status(){return {pending:!ready};},async retry(){retries++;return {pending:!ready};}};
  const failure=Object.assign(new Error('private physical initialization'),{cleanupHandle:cleanup});
  const f=await fixture({initialize(){throw failure;}}),client=await f.connect();
  const refused=await client.attach(ref).catch(error=>error);
  assert.doesNotMatch(inspect(refused,{showHidden:true,depth:5}),/private physical initialization/);
  await assert.rejects(f.host.prepareShutdown(),error=>error===failure);
  cleanup.status=()=>{replacements++;return {pending:false};};
  cleanup.retry=async()=>{replacements++;return {pending:false};};
  await assert.rejects(f.host.prepareShutdown(),error=>error===failure);
  assert.equal(replacements,0);assert.equal(retries,2);assert.equal(f.constructions(),1);
  ready=true;await f.host.prepareShutdown();await client.close();
  assert.equal(replacements,0);assert.equal(f.calls.includes('store'),false);
});

test('Promise settlement and absent pending observation cannot retire failed construction',async()=>{
  let observation;
  const cleanup={status:()=>observation,retry:async()=>({pending:false})};
  const failure=Object.assign(new Error('OriginalUnknown'),{cleanupHandle:cleanup});
  const f=await fixture({initialize(){throw failure;}}),client=await f.connect();
  await client.attach(ref).catch(()=>{});
  await assert.rejects(f.host.prepareShutdown(),error=>error===failure);
  assert.equal(f.calls.includes('control'),false);
  observation={pending:false};await f.host.prepareShutdown();await client.close();
});

test('failed activation captures original cleanup before the first shutdown can observe a replacement',async()=>{
  let ready=false,retries=0,replacements=0;
  const cleanup={status(){return {pending:!ready};},async retry(){retries++;}};
  const failure=Object.assign(new Error('OriginalPartialActivation'),{cleanupHandle:cleanup});
  const f=await fixture({initialize(){throw failure;}}),client=await f.connect();
  await client.attach(ref).catch(()=>{});
  failure.cleanupHandle={status(){replacements++;return {pending:false};},
    async retry(){replacements++;}};
  cleanup.status=()=>{replacements++;return {pending:false};};
  cleanup.retry=async()=>{replacements++;};
  await assert.rejects(f.host.prepareShutdown(),error=>error===failure);
  assert.equal(retries,1);assert.equal(replacements,0);
  assert.equal(f.calls.includes('control'),false);
  ready=true;await client.close();assert.equal(replacements,0);
});

test('an unobserved cleanup getter failure retains its same acquired receiver for later shutdown',async()=>{
  let reads=0,ready=false,retries=0,replacements=0;
  const cleanup={get status(){if(++reads===1)throw Error('OriginalStatusGetter');
    return ()=>({pending:!ready});},async retry(){retries++;}};
  const failure=Object.assign(new Error('OriginalPartialActivation'),{cleanupHandle:cleanup});
  const f=await fixture({initialize(){throw failure;}}),client=await f.connect();
  await client.attach(ref).catch(()=>{});
  failure.cleanupHandle={status(){replacements++;return {pending:false};},
    async retry(){replacements++;}};
  await assert.rejects(f.host.prepareShutdown(),error=>error===failure);
  assert.equal(reads,2);assert.equal(retries,1);assert.equal(replacements,0);
  ready=true;await client.close();assert.equal(replacements,0);
});
}

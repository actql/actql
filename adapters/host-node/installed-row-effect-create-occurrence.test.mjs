import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {maxHeaderSize} from 'node:http';
import {parse} from 'acorn';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {prepareInstalledRowCaptureChild, retainInstalledRowCaptureChild, releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectRequestChild, prepareInstalledEffectCredentialChild, captureInstalledEffectPlanRecipe, selectInstalledEffectCredentialOperation, prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';

// Actual enclosing row-stage loop/callees. Core inventory, checked Preview,
// driver request/claim, Resource and physical ports are explicit here.
const source=await readFile(new URL('./installed-row-effect.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function walk(node,parents=[]){
  if(!node||typeof node!=='object')return;
  if(typeof node.type==='string')nodes.push({node,parents});
  for(const value of Object.values(node))if(Array.isArray(value))value.forEach(n=>walk(n,[...parents,node]));else if(value&&typeof value==='object')walk(value,[...parents,node]);
}
walk(ast);
const variable=name=>{
  const found=nodes.filter(({node})=>node.type==='VariableDeclarator'&&node.id.name===name);
  assert.equal(found.length,1,name);return found[0].node.init;
};
const recipePort = ownerOf => expression('recipeOf', {ownerOf,
  // Existing single-recipe fixtures have no codec-size substitution. Keep
  // that explicit port while executing the actual shared kind selection.
  controlRecipes: {get: original => original}});
const readPorts = (ownerOf, resourceFields = () => ({})) => {
  const recipeOf = recipePort(ownerOf);
  const managedReadChild = expression('managedReadChild', {ownerOf, recipeOf, fail, selectInstalledEffectCredentialOperation});
  const describeMember = expression('describeMember', {ownerOf, managedReadChild, resourceFields});
  return {recipeOf, managedReadChild, describeMember};
};
const expression=(name,ports)=>{
  if(name==='recoveredEntries'&&ports.validateRecoveredEntries===undefined) ports={...ports,validateRecoveredEntries:expression('validateRecoveredEntries',ports)};
  if (['footprintOf', 'checkRows', 'prepareCredentialOperation', 'physicalRoute', 'decideTargetRead'].includes(name) &&
      ports.recipeOf === undefined) ports = {...ports, recipeOf: recipePort(ports.ownerOf)};
  if (name === 'physicalRoute' && ports.describeMember === undefined) {
    ports = {...readPorts(ports.ownerOf, ports.resourceFields), ...ports};
  }
  return Function(...Object.keys(ports),`return (${source.slice(variable(name).start,variable(name).end)});`)(...Object.values(ports));
};
const capture=nodes.find(({node})=>node.type==='FunctionDeclaration'&&node.id.name==='captureStage').node;
const loops=capture.body.body.filter(n=>n.type==='ForOfStatement'&&n.body.body.some(statement=>statement.type==='VariableDeclaration'&&statement.declarations.some(d=>d.id.name==='description')));
assert.equal(loops.length,1);
const loop=loops[0];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const checked=value=>{if(value.error)throw value.error;return value.ok;};
const cid=character=>`sha256:${character.repeat(64)}`;
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);

test('managed capability uses the same original control frame before any provider constructor', () => {
  const member = {}, entries = [], current = {}, receiver = {}, events = [];
  let active = false, calls = 0;
  receiver.issueCapability = function(facts) {
    assert.strictEqual(this, receiver);
    assert(active, 'constructor must be inside the original funded frame');
    assert.strictEqual(facts.member, member);
    assert.strictEqual(facts.entries, entries);
    assert.strictEqual(facts.current, current);
    calls++;
    return {identity: cid('1'), route: 'single_serial', binding: {
      connector_registration: 'original', connector_revision: '0.1', runtime_bundle_cid: cid('2')}};
  };
  const actual = expression('admitCapability', {ownerOf: original => {
    assert.strictEqual(original, member);
    return {owned: receiver, connectorRegistration: 'original', connectorRevision: '0.1', runtimeBundleCid: cid('2')};
  }, commonCapability: () => assert.fail('existing provider capability must be used'),
  cidPattern: /^sha256:[0-9a-f]{64}$/, fail});
  const frame = (original, method, args) => {
    assert.strictEqual(original, receiver);
    assert.strictEqual(method, receiver.issueCapability);
    events.push('begin');active = true;
    try { return Reflect.apply(method, original, args); }
    finally { active = false;events.push('end'); }
  };
  assert.deepEqual(actual(member, entries, current, cid('3'), cid('4'), frame),
    {identity: cid('1'), route: 'single_serial'});
  assert.deepEqual(events, ['begin', 'end']);
  const refusal = new Error('same original control reservation refused');
  assert.throws(() => actual(member, entries, current, cid('3'), cid('4'),
    () => {throw refusal;}), error => error === refusal);
  assert.equal(calls, 1, 'a refused frame invokes no provider constructor');
});

test('managed footprint uses the same original control frame and original request inventory', () => {
  const member = {}, entries = [{request: {}}], receiver = {};
  let active = false, calls = 0;
  receiver.footprint = function(facts) {
    assert.strictEqual(this, receiver);assert(active);
    assert.strictEqual(facts.member, member);assert.strictEqual(facts.entries, entries);calls++;
    return {kind: 'exact_targets', provider_boundary_cid: cid('1'), provider_namespace: 'original',
      resource_kind: 'Account', resource_identity_scheme_cid: cid('2'), provider_object_identity_cids: [cid('3')]};
  };
  const actual = expression('footprintOf', {ownerOf: () => ({owned: receiver}),
    footprintKinds: ['exact_targets'], cidPattern: /^sha256:[0-9a-f]{64}$/,
    text: value => typeof value === 'string' && value.length > 0, fail});
  const result = actual(member, entries, (original, method, args) => {
    assert.strictEqual(original, receiver);assert.strictEqual(method, receiver.footprint);
    active = true;try {return Reflect.apply(method, original, args);} finally {active = false;}
  });
  assert.equal(result.provider_object_identity_cids[0], cid('3'));
  assert.equal(calls, 1);assert.equal(active, false);
});

test('actual capture failure input callback retires only its pins after the shared child drain', async () => {
  const marker = new Error('stop after original cleanup retention'), children = [];
  const input = {}, events = [];
  let releaseInputs, finishCapture, observations = 0;
  const moon = {clientProgramPinEffectSources: () => ({ok: input}),
    clientProgramReleaseEffectInputs(original) {assert.strictEqual(original, input); events.push('pins');}};
  const actual = Function('moon', 'checked', 'runLimits', 'fail', 'releaseInstalledRowCapture',
    `return (${source.slice(capture.start, capture.end)});`)(moon, checked, () => ({maxPinnedResults: 1}), fail,
    releaseInstalledRowCapture);
  await assert.rejects(actual({members:[],ownChildren(original) {
    original.push({prepared: {status() {observations++; return {pending: false};},
      release() {assert.fail('already retired');}, retry() {assert.fail('already retired');}}});
    children.push(...original);
  }, ownInputs(release, finish) {releaseInputs = release; finishCapture = finish; throw marker;}}),
  error => error === marker);
  finishCapture();
  const control = {
    publicationPreparedReleaseAction(index, count, inspected, pending, attempted) {
      return index < 0 ? 'finished' : !inspected ? 'inspect' : pending && !attempted ? 'release' : 'advance';
    },
  };
  const primary = new Error('original capture failure');
  await assert.rejects(releaseInstalledRowCapture({children, releaseInputs, control}, primary), error => error === primary);
  assert.deepEqual(events, ['pins']);
  assert.equal(observations, 3, 'the actual input callback does not run another child cleanup owner');
});

const member=Object.freeze({kind:'create',effectId:'create',memberIndex:0});
const input=[{label:'b'},{label:'a'},{label:'a'}];
const issued=[{content_cid:cid('a'),occurrence:0},{content_cid:cid('a'),occurrence:1},{content_cid:cid('b'),occurrence:0}];
function fixture({child=false,inventoryError,managed=false,constructorFailureAt,controlFrame=false,requestProjection=false}={}){
  const events=[],contexts=[],requests=[],requestChildren=[],workspaceEvents=[],runOriginal=Object.freeze({}),description=Object.freeze({original:true});
  let activeConstructor;
  let projecting = false, projections = 0;
  let inventoryCalls=0;
  const moon={clientProgramEffectCreateRowInventory(wires,count,bytes,nodes,depth){
    inventoryCalls++;events.push('inventory');
    assert.deepEqual(wires,input.map(value=>JSON.stringify({state:'present',value})));
    assert.deepEqual([count,bytes,nodes,depth],[3,10000,100,10]);
    if(inventoryError)throw inventoryError;
    return {ok:[1,2,0].map((index,i)=>runtimeTupleFromFields({0:index,1:JSON.stringify(issued[i])}))};
  }};
  const prepare=context=>{
    assert.equal(inventoryCalls,1,'Common original identity must exist before provider preparation');
    assert.strictEqual(context.runOriginal,runOriginal);
    assert.strictEqual(context.current,description);
    assert.deepEqual(context.createRowIdentity,issued[contexts.length]);
    assert(Object.isFrozen(context.createRowIdentity));
    if(managed)assert.equal(activeConstructor?.rowIndex,contexts.length,'the same original workspace precedes provider allocation');
    contexts.push(context);events.push('prepare');
    if(contexts.length===constructorFailureAt)throw undefined;
    const request=Object.freeze({value:context.value}),requestCid=cid(String(contexts.length));
    requests.push(request);return {request,requestCid};
  };
  const owned={describe(){return description;},requestFacts:request=>{
    if (controlFrame) {
      assert(projecting, 'post-return JSON projection has its original control frame');
      assert.equal(activeConstructor, undefined, 'the Native request constructor already completed');
      projections++;
    }
    return {value:request.value,target:undefined};
  },
    prepareRequest:prepare,
    ...(child?{prepareRequestChild(context){
      const result=prepare(context);let pending=true;
      return {async prepare(){events.push('child prepare');assert.equal(requestChildren.length,contexts.length);return result;},
        release(){pending=false;},retry(){pending=false;},status(){return {pending};}};
    }}:{})};
  let aliasesRetired=false;
  const debits=[],settlements=[];
  const managedRecipe=managed?captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations:Object.freeze([]),rowOperations:Object.freeze([
      Object.freeze({operation:'other original occurrence',extent:{}}),
      Object.freeze({operation:'construct',extent:{}})]),
    requestConstruction:Object.freeze({operationIndex:1})}),2):undefined;
  const nativePlan={},parent={},prepared={},identity={};
  const runtime={clientProgramInstalledEffectManagedOperationPlan:()=>({$tag:1,_0:nativePlan}),
    clientProgramInstalledEffectOperationConstructionBegin(token){assert.equal(activeConstructor,undefined);activeConstructor=token;workspaceEvents.push(['begin',token.rowIndex]);return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationConstructionComplete(token){assert.equal(activeConstructor,token);workspaceEvents.push(['complete',token.rowIndex]);activeConstructor=undefined;return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationConstructionRetain(owner,p,r,plan,memberIndex,perRow,operationIndex,rowIndex,operation){
      assert.equal(owner,parent);assert.equal(p,prepared);assert.equal(r,identity);assert.equal(plan,nativePlan);
      assert.deepEqual([memberIndex,perRow,operationIndex,operation],[0,true,1,'construct']);
      assert.equal(inventoryCalls,1);assert.equal(contexts.length,rowIndex);
      const token={rowIndex};debits.push(token);events.push('debit');return {$tag:1,_0:token};
    },clientProgramInstalledEffectOperationRetire(token,ack){assert(aliasesRetired);assert.equal(ack,true);settlements.push(token);return {$tag:1,_0:true};}};
  Object.assign(moon,runtime);
  const managedEffect={controlConstruction:(receiver,method,args)=>Reflect.apply(method,receiver,args),runtime:moon,value:parent,prepared,request:identity,operationPlan:nativePlan,
    readPlan:runtime.clientProgramInstalledEffectManagedOperationPlan};
  const ownerOf=value=>{assert.strictEqual(value,member);return {owned,managedPlanRecipe:managedRecipe};};
  const limits={preview:{maxWireBytes:10000,maxNodes:100,maxDepth:10},maxRows:3,maxRowsPerMember:3};
  const createRows=nodes.find(({node})=>node.type==='FunctionDeclaration'&&node.id.name==='prepareInstalledCreateRows').node;
  const prepareInstalledCreateRows=Function('checked','runtimeField','fail','parseExactJson',
    `return (${source.slice(createRows.start,createRows.end)});`)(checked,runtimeField,fail,
      expression('parseExactJson',{fail}));
  const entryOf=expression('entryOf',{ownerOf,cidPattern:/^sha256:[0-9a-f]{64}$/,targeted:()=>false,fail});
  const requestEntry=expression('requestEntry',{entryOf,sameEffectValue:(_kind,a,b)=>same(a,b),targeted:()=>false,fail});
  const resourceFields=value=>{assert.strictEqual(value,member);return {runOriginal};};
  const commandContentRow=()=>undefined;
  const requestsOf=expression('requestsOf',{ownerOf,requestEntry,resourceFields,commandContentRow});
  const ports={...readPorts(ownerOf, resourceFields),controlConstruction:controlFrame ? (receiver, method, args) => {
    assert.equal(projecting, false);projecting = true;
    try {return Reflect.apply(method, receiver, args);} finally {projecting = false;}
  } : undefined,physicalOperations:()=>assert.fail('No physical call in constructor-only fixture'),
    moon,members:[member],ownerOf,assertCurrent(){events.push('current');},
    proposals:[input.map(value=>({changesWire:JSON.stringify({state:'present',value})}))],
    runInvocationCid:cid('c'),dispatches:[cid('d')],reads:[undefined],signal:undefined,
    resourceFields,currents:[],rowsOf:[],observations:[],commandContentBorrower:()=>assert.fail('No Command borrow'),
    control:{},prepared,identity,inputs:{},sourceSet:{members:[{payload:{}}]},limits,
    contentBorrowers:[],targeted:()=>false,guarded:()=>false,contentOwner:undefined,
    requestChildren,prepareInstalledRowCaptureChild,commandContentRow,requestEntry,requestsOf,prepareInstalledCreateRows,fail,
    managedEffect,prepareInstalledEffectRequestChild,prepareInstalledEffectOwnedRequestChild,retireRequestAliases(){aliasesRetired=true;ports.rowsOf.length=0;ports.currents.length=0;return true;}};
  if (requestProjection) ports.controlConstruction.requestProjection = (actualMember, operation, row, receiver, method, args) => {
    assert.deepEqual([actualMember, operation, row], [0, 1, projections]);
    assert.equal(activeConstructor, undefined);
    assert.strictEqual(args[0], member);assert.strictEqual(args[2].request, requests[row]);
    workspaceEvents.push(['project', row]);
    return ports.controlConstruction(receiver, method, args);
  };
  const run=()=>Function(...Object.keys(ports),`return (async()=>{${source.slice(loop.start,loop.end)};return {rowsOf,observations,currents};})();`)(...Object.values(ports));
  return {run,contexts,events,requestChildren,workspaceEvents,activeConstructor:()=>activeConstructor,projections:()=>projections,inventoryCalls:()=>inventoryCalls,entryOf,ownerOf,owned,runOriginal,debits,settlements,managedEffect};
}

test('managed request JSON export uses the same control frame after Native constructor completion', async () => {
  const original = fixture({managed: true, controlFrame: true});
  const result = await original.run();
  assert.equal(original.projections(), 3);
  assert.equal(result.rowsOf[0].length, 3);
  assert.equal(original.activeConstructor(), undefined);
  assert.deepEqual(original.workspaceEvents, [
    ['begin', 0], ['complete', 0], ['begin', 1], ['complete', 1], ['begin', 2], ['complete', 2],
  ]);
});

test('create original occurrence reaches synchronous provider before request and stays in canonical Preview frame',async()=>{
  const f=fixture();const result=await f.run();
  assert.equal(f.inventoryCalls(),1);assert.deepEqual(f.contexts.map(value=>value.value),[input[1],input[2],input[0]]);
  assert.equal(result.rowsOf[0].length,3);assert(Object.isFrozen(result.rowsOf[0]));
  result.rowsOf[0].forEach((row,index)=>{assert(Object.isFrozen(row));assert.strictEqual(row.identity,f.contexts[index].createRowIdentity);assert.strictEqual(row.entry.value,f.contexts[index].value);});
  assert(f.events.indexOf('inventory')<f.events.indexOf('prepare'));
});

test('create original occurrence reaches retained request child before its first await',async()=>{
  const f=fixture({child:true});const result=await f.run();
  assert.equal(f.inventoryCalls(),1);assert.equal(f.requestChildren.length,3);
  assert.deepEqual(result.rowsOf[0].map(row=>row.identity),issued);
  for(const child of f.requestChildren){assert.equal(child.prepared.status().pending,true);await child.prepared.release();assert.equal(child.prepared.status().pending,false);}
});

test('create original inventory failure retains exact cause before sync or child provider construction',async()=>{
  const primary=Object.assign(new Error('original inventory refusal'),{cleanupHandle:Object.freeze({original:true})});
  for(const child of [false,true]){
    const f=fixture({child,inventoryError:primary});await assert.rejects(f.run(),error=>error===primary);
    assert.equal(f.inventoryCalls(),1);assert.equal(f.contexts.length,0);assert.equal(f.requestChildren.length,0);
  }
});

test('create cold request preparation receives same admitted Preview identities without issuing another inventory',()=>{
  const identities=issued.map(value=>Object.freeze({...value})),seen=[],claims=identities.map((_,i)=>({canonicalRequestCid:cid(String(i+1))}));
  const changes=identities.map((identity,i)=>({target_row_identity:identity,after:{value:input[[1,2,0][i]]}}));
  const owned={prepareRequest(context){assert.strictEqual(context.createRowIdentity,identities[seen.length]);seen.push(context);
    return {request:{value:context.value},requestCid:claims[seen.length-1].canonicalRequestCid};},requestFacts:request=>({value:request.value,target:undefined})};
  const ownerOf=()=>({owned});
  const entryOf=expression('entryOf',{ownerOf,cidPattern:/^sha256:[0-9a-f]{64}$/,targeted:()=>false,fail});
  const recover=expression('recoveredEntries',{singular:{owned},members:[member],ownerOf,resourceFields:()=>({runOriginal:{}}),
    orderedSourceIndexes:()=>[0,1,2],entryOf,sameEffectValue:(_kind,a,b)=>same(a,b),approvedValue:(_kind,change)=>change.after.value,targeted:()=>false,fail});
  const result=recover({members:[member],body:{effects:[{changes}]},durable:{},recorded:{members:[{claims}]},previewWire:'original approved Preview',runInvocationCid:cid('c'),dispatches:[cid('d')]});
  assert.equal(seen.length,3);assert.equal(result.entries[0].length,3);
});

test('non-create request preparation retains its original context without a create occurrence field',()=>{
  for(const kind of ['update','delete','upsert','command']){
    const selected=Object.freeze({kind}),current=Object.freeze({}),runOriginal=Object.freeze({}),seen=[];
    const rows=[{value:{n:1},selector:'first'},{value:{n:2},selector:'second'}];
    const owned={prepareRequest(context){seen.push(context);return context.value;}};
    const requestsOf=expression('requestsOf',{ownerOf:value=>{assert.strictEqual(value,selected);return {owned};},
      resourceFields:()=>({runOriginal}),commandContentRow:()=>assert.fail('No Content lookup without original borrower'),
      requestEntry:(member,row,prepared)=>{assert.strictEqual(member,selected);assert.strictEqual(row.value,prepared);return prepared;}});
    assert.deepEqual(requestsOf(selected,rows,current,undefined,undefined),rows.map(row=>row.value));
    seen.forEach((context,index)=>{assert.deepEqual(context,{member:selected,value:rows[index].value,selector:rows[index].selector,current,runOriginal});assert.equal(Object.hasOwn(context,'createRowIdentity'),false);});
  }
});


test('selected original constructor occurrence reaches the actual row loop before provider work',async()=>{
  const f=fixture({managed:true}),result=await f.run();
  assert.equal(f.debits.length,3);assert.equal(f.settlements.length,0);
  assert.equal(f.requestChildren.length,3);
  assert.deepEqual(result.rowsOf[0].map(row=>row.identity),issued);
  assert.deepEqual(f.events.filter(value=>['inventory','debit','prepare'].includes(value)),
    ['inventory','debit','prepare','debit','prepare','debit','prepare']);
  for(const retained of f.requestChildren)await retained.prepared.release();
  assert.equal(result.rowsOf.length,0);assert.equal(result.currents.length,0);
  assert.deepEqual(f.settlements,f.debits);
});

test('actual route retirement waits for its active refresh before severing request aliases',async()=>{
  let proceed,entered;
  const observed=new Promise(resolve=>{entered=resolve;});
  const gate=new Promise(resolve=>{proceed=resolve;});
  // All admission/grant/provider ports are explicit. No member or physical
  // operation is fabricated to exercise the real enclosing async borrow fence.
  const route=expression('physicalRoute',{fail,guarded:()=>false,
    checkRows:async()=>{entered();await gate;},ownerOf:()=>assert.fail('No member'),
    admitCapability:()=>assert.fail('No capability'),routeOf:()=>assert.fail('No route')})({
      members:[],entries:[[{}]],previewRows:[],dispatches:[],subjectCid:'subject'});
  const currents=[{}],rowsOf=[{}],observations=[{}],proposals=[{}];
  const declarations=nodes.filter(({node,parents})=>node.type==='VariableDeclarator'&&
    node.id.name==='retireRequestAliases'&&parents.includes(capture));
  assert.equal(declarations.length,1,'capture owner retirement');
  const node=declarations[0].node.init;
  const scope=Function('route','currents','rowsOf','observations','proposals',`
    let captureOpen=true,entries=Object.freeze([[{}]]),memberCaptures=[];
    const retire=${source.slice(node.start,node.end)};
    return {retire,finish(){captureOpen=false;},entries:()=>entries};
  `)(route,currents,rowsOf,observations,proposals);
  assert.equal(scope.retire(),false,'capture is still active');
  scope.finish();
  const refresh=route.current({preflight:{observedRows:[]}});
  await observed;
  assert.equal(scope.retire(),false,'refresh still owns request/current locals');
  assert.notEqual(scope.entries(),undefined);assert.equal(currents.length,1);
  await assert.rejects(route.current({preflight:{observedRows:[]}}),{code:'InstalledRowEffectRouteRetired'});
  proceed();await refresh;
  assert.equal(scope.retire(),true);
  assert.equal(scope.entries(),undefined);
  for(const original of [currents,rowsOf,observations,proposals])assert.equal(original.length,0);
  assert.throws(()=>route.bindDispatch({members:[],subjectCid:'subject'}),{code:'InstalledRowEffectRouteRetired'});
});


test('a constructor Plan from another captured preparation refuses before native debit or provider work',async()=>{
  for(const field of ['prepared','request','runtime']){
    const f=fixture({managed:true});f.managedEffect[field]={};
    await assert.rejects(f.run(),{code:'ForeignInstalledEffectManagedRun'});
    assert.equal(f.debits.length,0);assert.equal(f.contexts.length,0);assert.equal(f.requestChildren.length,0);
  }
});

test('actual claimed dispatch keeps the request borrowed until send and projection finish',async()=>{
  let proceed,entered,sends=0,projects=0;
  const observed=new Promise(resolve=>{entered=resolve;}),gate=new Promise(resolve=>{proceed=resolve;});
  const selected={kind:'create',resource:'rows'},request={},entry={request,requestCid:cid('e')},description={};
  const claim=Object.fromEntries(['scope','locator','key','basis','intentFingerprintCid','canonicalRequestCid'].map(name=>[name,name]));
  const owned={writeOperation:()=> 'create',send({request:actual}){assert.equal(actual,request);sends++;return {};},
    project({request:actual,current}){assert.equal(actual,request);assert.equal(current,description);projects++;return {kind:'provider-response'};},
    describe:()=>description};
  const owner={installed:[{}],owned,site:{credential:{},callResource(){},issueEffectGrant(){return {original:true};}}};
  selected.mapping=owner.installed[0];
  const route=expression('physicalRoute',{fail,guarded:()=>false,ownerOf:()=>owner,
    checkRows:async()=>{},resourceFields:()=>({}),admitCapability:()=>({identity:'capability'}),routeOf:()=>({}),
    commitDecisions:()=>new Map(),requireApproval:()=>{},scopeKey:()=> 'scope',admitRow:()=>claim,
    async captureClaimedEffectResponse({execute}){execute();entered();await gate;return {claimed:true,physical:{observation:{original:true}}};},
    settle:()=>undefined})({members:[selected],entries:[[entry]],previewRows:[[]],
      dispatches:['dispatch'],dispatchIndexes:[[0]],subjectCid:'subject',ledger:{},applyPreview:{}});
  const preflight=await route.current({preflight:{observedRows:[]}});
  const dispatch=route.bindDispatch({members:[{claims:[claim]}],subjectCid:'subject'});
  const sent=dispatch({memberIndex:0,rowIndex:0,claim,currentPreflight:preflight});
  await observed;
  assert.equal(route.retire(),false);
  assert.equal(sends,1);assert.equal(projects,0);
  await assert.rejects(dispatch({memberIndex:0,rowIndex:0,claim,currentPreflight:preflight}),{code:'InstalledRowEffectRouteRetired'});
  proceed();assert.equal((await sent).claimed,true);
  assert.equal(projects,1);assert.equal(route.retire(),true);assert.equal(sends,1);
});

test('actual create check forwards the same issued authorization into its selected managed physical occurrence',async()=>{
  const selected={kind:'create',memberIndex:3},request={},raw=Object.freeze({grant:{original:true},scope:{}});
  const decision={},events=[],selectedRecipe={credentialOperations:[{phase:'capture-check'}]};
  const originalCredential={},originalResource=()=>{},boundCredential={},boundResource=()=>{};
  const site={credential:originalCredential,callResource:originalResource,
    issueReadGrant(facts){assert.equal(facts.decision,decision);events.push('grant');return raw;}};
  const owned={check:{operation:'form-read',resource:'rows'},checkRequest(context){
    assert.equal(context.request,request);assert.equal(context.authorization.grant,raw.grant);
    assert.equal(context.credential,boundCredential);assert.equal(context.callResource,boundResource);
    events.push('provider');return {checked:true};}};
  const checkRows=expression('checkRows',{ownerOf:()=>({owned,site,managedPlanRecipe:selectedRecipe}),
    readDecision:async()=>decision,fail});
  let forwarded;
  await checkRows({members:[selected],entries:[[{request}]],runInvocationCid:'run',dispatches:['dispatch'],
    subjectOf:()=> 'subject',assertCurrent(){},operationPhase:'capture',
    physicalOperations:async facts=>{
      forwarded=facts;events.push('managed');assert.equal(facts.originalAuthorization,raw);
      assert.equal(facts.site,site);assert.equal(facts.phase,'capture-check');
      return facts.invoke({authorization:Object.freeze({...raw,useId:facts.useId}),
        credential:boundCredential,callResource:boundResource});
    }});
  assert.deepEqual(events,['grant','managed','provider']);
  assert.equal(forwarded.member,selected);assert.equal(forwarded.rowIndex,0);
  assert.equal(forwarded.operation,'form-read');assert.equal(forwarded.purpose,'read');
  assert.equal(forwarded.useId,'dispatch-check-subject-0');
});

test('actual capture operation retains the original bound child before invoking its separately selected read',async()=>{
  const selected={memberIndex:2},credential={},binding={},control={},journal={},resolveSecret=()=>{},token={},extent={};
  const parent={},prepared={},identity={},plan={},grant={},children=[],events=[];
  const scope=Object.freeze({runtimeBundleCid:'runtime',connectorRegistration:'connector',connectorRevision:'revision',
    runInvocationCid:'run',dispatchRequestCid:'dispatch',operation:'form-read'});
  const raw=Object.freeze({grant,scope});let retired=false;
  const moon={clientProgramInstalledEffectManagedPlanCaptureChildren:original=>{assert.equal(original,plan);return 1;},
    clientProgramInstalledEffectManagedOperationPlan:()=>({$tag:1,_0:plan}),
    clientProgramInstalledEffectManagedPlanOperation:(original,memberIndex,perRow,index,operation)=>{
      assert.equal(original,plan);assert.deepEqual([memberIndex,perRow,index,operation],[2,true,3,'form-read']);return {$tag:1,_0:extent};},
    clientProgramInstalledEffectOperationExtentPhysical:()=>true,
    clientProgramInstalledEffectOperationExtentTransfer:()=>129n,
    clientProgramInstalledEffectOperationResponseBackingFits(original,bytes,headers){
      assert.equal(original,extent);assert.equal(bytes,64);assert.equal(headers,maxHeaderSize);return true;},
    clientProgramInstalledEffectOperationBorrow(){events.push('borrow');return {$tag:1,_0:token};},
    clientProgramInstalledEffectOperationStart:()=>({$tag:1,_0:undefined}),
    clientProgramInstalledEffectOperationCharge:()=>({$tag:1,_0:undefined}),
    clientProgramInstalledEffectOperationRetire:()=>({$tag:1,_0:true})};
  const managedEffect={controlConstruction:(receiver,method,args)=>Reflect.apply(method,receiver,args),runtime:moon,value:parent,prepared,request:identity,operationPlan:plan,
    readPlan:moon.clientProgramInstalledEffectManagedOperationPlan};
  const originalSite=Object.freeze({runtimeBundleCid:'runtime',connectorRegistration:'connector',connectorRevision:'revision',
    referenceCurrent:()=>true,authorizationPurpose(original){assert.equal(original,raw);return {kind:'read',resource:'rows'};},
    bindRunAcquisition(original){assert.equal(original,raw);assert.equal(children.length,1);events.push('bind');
      return {credential:{binding,control,journal,resolveSecret},close:()=> 'closed'};},
    callResource(){events.push('read');return Promise.resolve({originalResponse:true});}});
  const recipe={rowOperations:[{},{},{},{operation:'form-read'}],credentialOperations:[
    {phase:'capture-check',operationIndex:3,maxRequestBytes:64,maxResponseBytes:64}]};
  const actual=expression('prepareCredentialOperation',{moon,ownerOf:()=>({managedPlanRecipe:recipe}),fail,
    selectInstalledEffectCredentialOperation,
    installedRowCredentialOperationSite:original=>{assert.equal(original,credential);return originalSite;},
    prepareInstalledRowCaptureChild,prepareInstalledEffectCredentialChild});
  const input={member:selected,rowIndex:0,phase:'capture-check',operation:'form-read',site:{credential},originalAuthorization:raw,
    useId:'use',resource:'rows',purpose:'read',managedEffect,requestChildren:children,retireRequestAliases:()=>retired,
    runInvocationCid:'run',dispatchRequestCid:'dispatch',assertCurrent(){},
    invoke:({authorization,credential:bound,callResource})=>{
      assert.equal(children.length,1);assert.equal(authorization.grant,grant);assert.equal(authorization.useId,'use');
      return callResource({grant,scope,useId:'use',...bound,operations:new Map([['form-read',Object.freeze({method:'GET',path:'/form'})]]),
        maxRequestBytes:64,maxResponseBytes:64});}};
  assert.deepEqual(await actual(input),{originalResponse:true});
  assert.deepEqual(events,['borrow','bind','read']);
  await children[0].prepared.release();assert.equal(children[0].prepared.status().pending,true);
  retired=true;await children[0].prepared.retry();assert.equal(children[0].prepared.status().pending,false);
  await assert.rejects(actual(input),{code:'InstalledEffectPhysicalChildLimit'});
});

test('managed create checks and cold routes refuse missing original parent retention before grant or provider entry',async()=>{
  let entered=0;
  const selected={kind:'create'},owner={managedPlanRecipe:{credentialOperations:[]},
    owned:{check:{resource:'rows',operation:'form-read'}},site:{issueReadGrant:()=>{entered++;}}};
  const checkRows=expression('checkRows',{ownerOf:()=>owner,readDecision:async()=>{entered++;},fail});
  await assert.rejects(checkRows({members:[selected],entries:[[]],dispatches:[],subjectOf:()=> 'subject'}),
    {code:'InstalledEffectPhysicalPlanUnavailable'});
  const physicalRoute=expression('physicalRoute',{ownerOf:()=>owner,fail});
  assert.throws(()=>physicalRoute({members:[selected],operationPhase:'resume'}),{code:'InstalledEffectPhysicalPlanUnavailable'});
  assert.equal(entered,0);
});

test('actual claimed managed write enters its separate occurrence only inside the original durable dispatch',async()=>{
  for(const claimed of [true,false]){
    const events=[],selected={kind:'create',resource:'rows',memberIndex:4},request={},raw=Object.freeze({grant:{},scope:{}});
    const claim=Object.fromEntries(['scope','locator','key','basis','intentFingerprintCid'].map(name=>[name,name]));
    claim.canonicalRequestCid=cid('e');
    const entry={request,requestCid:claim.canonicalRequestCid},description={},dispatching={},bytes=Buffer.from('{}');
    const owned={describe:()=>description,writeOperation:()=> 'create',
      send(context){events.push('send');assert.equal(context.request,request);assert.equal(context.authorization.grant,raw.grant);
        return {observation:{useCid:'use',statusCode:200,body:bytes}};},
      project(){events.push('project');return {kind:'provider-response'};}};
    const owner={installed:[{}],owned,managedPlanRecipe:{credentialOperations:[{phase:'write'}]},
      site:{issueEffectGrant(){events.push('grant');return raw;}}};selected.mapping=owner.installed[0];
    const ledger={claimDispatch(original){assert.equal(original.canonicalRequestCid,claim.canonicalRequestCid);events.push('claim');return {claimed,dispatching};},
      beginPhysicalFlight(original){assert.equal(original,dispatching);events.push('flight');return ()=>events.push('end');},
      recordResponse(original){assert.equal(original.dispatching,dispatching);assert.equal(original.responseBytes,bytes);events.push('store');return {response:{}};}};
    const route=expression('physicalRoute',{ownerOf:()=>owner,fail,guarded:()=>false,checkRows:async()=>{},resourceFields:()=>({}),
      admitCapability:()=>({identity:'capability'}),routeOf:()=>({}),commitDecisions:()=>new Map(),requireApproval:()=>{},
      scopeKey:()=> 'scope',admitRow:()=>claim,captureClaimedEffectResponse,settle:()=>undefined})({
        members:[selected],entries:[[entry]],previewRows:[[]],dispatches:['dispatch'],dispatchIndexes:[[0]],
        subjectCid:'subject',applyPreview:{},ledger,runInvocationCid:'run',assertCurrent(){},
        physicalOperations(facts){events.push('managed');assert.equal(facts.originalAuthorization,raw);
          assert.equal(facts.phase,'write');assert.equal(facts.rowIndex,0);assert.equal(facts.purpose,'effect');
          assert.equal(facts.runInvocationCid,'run');assert.equal(facts.dispatchRequestCid,'dispatch');
          return facts.invoke({authorization:{...raw,useId:facts.useId},credential:{},callResource(){}});}});
    const current=await route.current({preflight:{observedRows:[]}});
    const dispatch=route.bindDispatch({members:[{claims:[claim]}],subjectCid:'subject'});
    const result=await dispatch({memberIndex:0,rowIndex:0,claim,currentPreflight:current});
    assert.equal(result.claimed,claimed);
    assert.deepEqual(events,claimed?['grant','claim','flight','managed','send','end','store','project']:['grant','claim']);
    assert.equal(route.retire(),true);
  }
});

test('actual claimed CREATE runs its separately authorized original Form check before the write occurrence',async()=>{
  const events=[],selected={kind:'create',resource:'rows',memberIndex:2},request={},description={};
  const controlConstruction=(receiver,method,args)=>Reflect.apply(method,receiver,args);
  const claim={scope:'scope',locator:'locator',key:'key',basis:'basis',intentFingerprintCid:'row',canonicalRequestCid:cid('e')};
  const writeGrant=Object.freeze({grant:{write:true},scope:{}}),readGrant=Object.freeze({grant:{read:true},scope:{}}),decision={};
  let checked=false;
  const owned={describe:()=>description,writeOperation:()=> 'create',
    checkRequest(context){assert.equal(this,owned);assert.equal(context.request,request);assert.equal(context.authorization.grant,readGrant.grant);assert.equal(context.controlConstruction,controlConstruction);
      events.push('form');checked=true;},
    send(context){assert(checked);assert.equal(context.authorization.grant,writeGrant.grant);events.push('send');
      return {observation:{useCid:'write-use',statusCode:200,body:Buffer.from('{}')}};},
    project(){events.push('project');return {kind:'provider-response'};}};
  const owner={installed:[{}],owned,managedPlanRecipe:{credentialOperations:[{phase:'write-check'},{phase:'write'}]},
    beforeSendCheck:Object.freeze({resource:'forms',operation:'form-read',request:owned.checkRequest,receiver:owned}),
    site:{issueEffectGrant(){events.push('effect-grant');return writeGrant;},
      issueReadGrant(facts){assert.equal(facts.decision,decision);assert.equal(facts.resource,'forms');assert.equal(facts.operation,'form-read');
        assert.equal(facts.runInvocationCid,'run');assert.equal(facts.dispatchRequestCid,'dispatch');assert.equal(facts.maxUses,1);
        events.push('read-grant');return readGrant;}}};selected.mapping=owner.installed[0];
  const ledger={claimDispatch(){events.push('claim');return {claimed:true,dispatching:{}};},
    beginPhysicalFlight(){events.push('flight');return ()=>events.push('end');},recordResponse(){events.push('store');return {response:{}};}};
  const route=expression('physicalRoute',{ownerOf:()=>owner,fail,guarded:()=>false,checkRows:async()=>{},resourceFields:()=>({}),
    admitCapability:()=>({identity:'capability'}),routeOf:()=>({}),commitDecisions:()=>new Map(),requireApproval:()=>{},scopeKey:()=> 'scope',
    admitRow:()=>claim,captureClaimedEffectResponse,settle:()=>undefined,
    readDecision:async(member,resource,subject)=>{assert.equal(member,selected);assert.equal(resource,'forms');assert.equal(subject,'subject');events.push('authorize-read');return decision;}})({
      members:[selected],entries:[[{request,requestCid:claim.canonicalRequestCid}]],previewRows:[[]],dispatches:['dispatch'],dispatchIndexes:[[0]],
      subjectCid:'subject',runInvocationCid:'run',applyPreview:{},ledger,assertCurrent(){},controlConstruction,
      physicalOperations(facts){
        assert.equal(facts.member,selected);assert.equal(facts.rowIndex,0);
        if(facts.phase==='write-check'){
          assert.equal(facts.originalAuthorization,readGrant);assert.equal(facts.purpose,'read');events.push('managed-read');
          return facts.invoke({authorization:{...readGrant,useId:facts.useId},credential:{},callResource(){}});
        }
        assert.equal(facts.phase,'write');assert(checked,'Form read must finish before selecting the write child');
        assert.equal(facts.originalAuthorization,writeGrant);assert.equal(facts.purpose,'effect');events.push('managed-write');
        return facts.invoke({authorization:{...writeGrant,useId:facts.useId},credential:{},callResource(){}});
      }});
  const current=await route.current({preflight:{observedRows:[]}}),dispatch=route.bindDispatch({members:[{claims:[claim]}],subjectCid:'subject'});
  assert.equal((await dispatch({memberIndex:0,rowIndex:0,claim,currentPreflight:current})).claimed,true);
  assert.deepEqual(events,['effect-grant','claim','flight','authorize-read','read-grant','managed-read','form','managed-write','send','end','store','project']);
  assert.equal(route.retire(),true);
});

test('pre-write check selection captures original callback and refuses unfunded or accessor flags before use',()=>{
  const node=nodes.find(({node})=>node.type==='FunctionDeclaration'&&node.id.name==='captureBeforeSendCheck').node;
  const capture=Function('nodeTypes','fail','text',`return (${source.slice(node.start,node.end)});`)(nodeTypes,fail,value=>typeof value==='string'&&value.length>0);
  const recipe={rowOperations:[{operation:'form-read'}],credentialOperations:[{phase:'write-check',operationIndex:0}]};
  let called=0;
  const original=function(){called++;},driver={kinds:['create'],check:Object.freeze({resource:'forms',operation:'form-read',beforeSend:true}),checkRequest:original};
  const selected=capture(driver,recipe);assert.equal(called,0);assert.equal(selected.request,original);assert.equal(selected.receiver,driver);assert(Object.isFrozen(selected));
  driver.checkRequest=()=>assert.fail('later replacement');assert.equal(selected.request,original);
  assert.throws(()=>capture(driver,undefined),{code:'InvalidInstalledEffectWriteCheck'});
  assert.throws(()=>capture({kinds:['create']},recipe),{code:'InstalledEffectWriteCheckUnavailable'});
  const accessor={kinds:['create'],check:Object.freeze({resource:'forms',operation:'form-read',get beforeSend(){called++;return true;}}),checkRequest:original};
  assert.throws(()=>capture(accessor,recipe),{code:'InvalidInstalledEffectWriteCheck'});assert.equal(called,0);
  assert.equal(capture({kinds:['create'],check:Object.freeze({resource:'forms',operation:'form-read'}),checkRequest:original},undefined),undefined);
});

test('a failed original pre-write Form check retains the claim without entering send store or settlement',async()=>{
  const selected={kind:'create',resource:'rows'},request={},entry={request,requestCid:cid('e')},primary=new Error('original Form changed'),events=[];
  const claim={scope:'scope',locator:'locator',key:'key',basis:'basis',intentFingerprintCid:'row',canonicalRequestCid:entry.requestCid};
  const owned={writeOperation:()=> 'create',checkRequest(){throw primary;},send(){assert.fail('Form drift cannot send');}};
  const owner={installed:[{}],owned,managedPlanRecipe:{credentialOperations:[{phase:'write-check'},{phase:'write'}]},
    beforeSendCheck:{resource:'forms',operation:'form-read',request:owned.checkRequest,receiver:owned},
    site:{issueEffectGrant:()=>({grant:'write'}),issueReadGrant:()=>({grant:'read'})}};selected.mapping=owner.installed[0];
  let retainedClaim;
  const ledger={claimDispatch(original){retainedClaim=original;events.push('claim');return {claimed:true,dispatching:{}};},
    beginPhysicalFlight(){events.push('flight');return ()=>events.push('end');},recordResponse(){assert.fail('No mutation response exists');}};
  const route=expression('physicalRoute',{ownerOf:()=>owner,fail,guarded:()=>false,checkRows:async()=>{},resourceFields:()=>({}),
    admitCapability:()=>({identity:'capability'}),routeOf:()=>({}),commitDecisions:()=>new Map(),requireApproval:()=>{},scopeKey:()=> 'scope',
    admitRow:()=>claim,captureClaimedEffectResponse,readDecision:async()=>({action:'dispatch'}),settle:()=>assert.fail('No typed mutation outcome')})({
      members:[selected],entries:[[entry]],previewRows:[[]],dispatches:['dispatch'],dispatchIndexes:[[0]],subjectCid:'subject',runInvocationCid:'run',
      applyPreview:{},ledger,assertCurrent(){},physicalOperations(facts){assert.equal(facts.phase,'write-check');events.push('check');return facts.invoke({});}});
  const current=await route.current({preflight:{observedRows:[]}}),dispatch=route.bindDispatch({members:[{claims:[claim]}],subjectCid:'subject'});
  await assert.rejects(dispatch({memberIndex:0,rowIndex:0,claim,currentPreflight:current}),error=>error===primary);
  assert.deepEqual(events,['claim','flight','check','end']);assert.equal(retainedClaim.canonicalRequestCid,entry.requestCid);assert.equal(route.retire(),true);
});

// Execute the complete original capture prelude through Source export. The
// checked pin/export and native Plan/borrow are explicit ports; this proves
// ordering/lifetime, not complete constructor quantities or ordinary authority.
function prefixFixture({failBorrowAt, exportFailure}={}) {
  const events=[],children=[],input=Object.freeze({}),nativePlan={},parent={},prepared={},identity={};
  let releaseInputs,finish,borrowCount=0,exportCalls=0;
  const moon={clientProgramPinEffectSources(){events.push('pin');return {ok:input};},
    clientProgramReleaseEffectInputs(value){assert.equal(value,input);events.push('unpin');},
    clientProgramEffectInputExportLimits(){return {};},
    clientProgramInstalledEffectManagedOperationPlan(){return {$tag:1,_0:nativePlan};},
    clientProgramInstalledEffectOperationConstructionBegin(){return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationConstructionComplete(){return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationConstructionRetain(owner,p,r,plan,memberIndex,perRow,operationIndex,rowIndex,operation){
      assert.equal(owner,parent);assert.equal(p,prepared);assert.equal(r,identity);assert.equal(plan,nativePlan);
      assert.deepEqual([perRow,operationIndex,rowIndex,operation],[false,0,0,'capture-prefix']);
      events.push(`borrow-${memberIndex}`);borrowCount++;
      if(borrowCount===failBorrowAt)throw primary;
      return {$tag:1,_0:{memberIndex}};
    },
    clientProgramInstalledEffectOperationRetire(token,ack){assert.equal(ack,true);events.push(`retire-${token.memberIndex}`);return {$tag:1,_0:true};}};
  const primary=new Error('same original capture-prefix failure');
  const members=Array.from({length:failBorrowAt??1},(_,memberIndex)=>Object.freeze({kind:'create',memberIndex}));
  const recipe=Object.freeze({memberOperations:Object.freeze([Object.freeze({operation:'capture-prefix',extent:{}})]),
    rowOperations:Object.freeze([]),captureConstruction:Object.freeze({operationIndex:0})});
  const owned=Object.freeze({managedPlanRecipe:recipe,profile:{source:'fixture-source'},
    owned:Object.freeze({recoveryEntry(){assert.fail('No recovery work before Source finishes');}})});
  const managedEffect={controlConstruction:(receiver,method,args)=>Reflect.apply(method,receiver,args),runtime:moon,value:parent,prepared,request:identity,operationPlan:nativePlan,
    readPlan:moon.clientProgramInstalledEffectManagedOperationPlan};
  const control={publicationPreparedReleaseAction(index,_count,checked,pending,attempted){
    return index<0?'finished':!checked?'inspect':pending&&!attempted?'release':'advance';},
    publicationCleanupOwnerAction(index,count,checked,pending,available,attempted){
      return index>=count?'finished':!checked?'inspect':pending&&available&&!attempted?'retry':'advance';
    }};
  const ports={...readPorts(()=>owned),moon,prepared,identity,managedEffect,members,checkedHost:{},checked,fail,
    runLimits:()=>ports.limits,
    limits:{maxPinnedResults:2,maxRows:2,maxRowsPerMember:2,maxWork:100,maxFields:4,body:{maxBytes:100,maxNodes:20,maxDepth:5}},
    ownerOf:()=>owned,assertCurrent(){},own(){},ownChildren(value){assert.equal(children.length,0);children.push(value);},
    ownInputs(release,complete){releaseInputs=release;finish=complete;},control,
    prepareInstalledRowCaptureChild,retainInstalledRowCaptureChild,prepareInstalledEffectRequestChild,releaseInstalledRowCapture,
    prepareCredentialOperation:()=>assert.fail('No physical child in capture prelude'),
    plan:{outputLimits:{maxWireBytes:100}},exportLimits:()=>[],singular:undefined,cid:()=>cid('e'),
    store:{storeAuthorityCid:cid('f')},runInvocationCid:cid('c'),execution:{},signal:undefined,
    preparePinnedEffectSourceSet:async options=>{
      exportCalls++;events.push('export');
      assert.equal(borrowCount,members.length,'all original member prefix reservations precede exported rows');
      assert.equal(children[0].length,members.length,'all same children retained before export');
      members.forEach((_,index)=>options.onProposalRow(index,0,{changesWire:'{"value":{"label":"same"}}'}));
      if(exportFailure)throw primary;
      return {payloads:[]};
    }};
  let retainedInputs;
  Object.assign(managedEffect.controlConstruction, {retainInputs(value) {
    assert.equal(retainedInputs, undefined, 'retain the original capture input once');
    assert.ok(value && typeof value === 'object');
    retainedInputs = value;
  }});
  const end=capture.body.body.find(node=>node.type==='ExpressionStatement'&&node.expression.type==='CallExpression'&&node.expression.callee.name==='own'&&node.expression.arguments[0]?.name==='sourceSet').end;
  const code=source.slice(capture.body.start+1,end);
  const run=()=>Function(...Object.keys(ports),`return (async()=>{${code};return {proposals,requestChildren};})();`)(...Object.values(ports));
  return {run,events,children,primary,exportCalls:()=>exportCalls,cleanup:async()=>{
    finish();
    const marker=Object.freeze(new Error('same original prefix cleanup'));
    try{await releaseInstalledRowCapture({children:children[0],releaseInputs,control},marker);}
    catch(cause){if(cause!==marker)throw cause;}
  }};
}

test('original member capture reservation precedes exported proposal rows and retains their prefix until release',async()=>{
  const f=prefixFixture(),result=await f.run();
  assert.deepEqual(f.events,['pin','borrow-0','export']);
  assert.equal(result.proposals[0][0].changesWire,'{"value":{"label":"same"}}');
  assert.equal(result.requestChildren.length,1);
  assert.equal(result.requestChildren[0].prepared.status().pending,true);
  await f.cleanup();
  assert.equal(result.proposals.length,0);
  assert.deepEqual(f.events,['pin','borrow-0','export','retire-0','unpin']);
});

test('partial member prefix refusal retains original sibling and releases pin without a fabricated Source set',async()=>{
  const f=prefixFixture({failBorrowAt:2});
  await assert.rejects(f.run(),error=>error===f.primary);
  assert.deepEqual(f.events,['pin','borrow-0','borrow-1']);
  assert.equal(f.exportCalls(),0);
  assert.equal(f.children[0].length,1);
  await f.cleanup();
  assert.deepEqual(f.events,['pin','borrow-0','borrow-1','retire-0','unpin']);
});

test('failed Source export keeps original capture prefix child pending until enclosing capture ends',async()=>{
  const f=prefixFixture({exportFailure:true});
  await assert.rejects(f.run(),error=>error===f.primary);
  assert.deepEqual(f.events,['pin','borrow-0','export']);
  const child=f.children[0][0].prepared;
  await child.release();
  assert.equal(child.status().pending,true);
  assert.deepEqual(f.events,['pin','borrow-0','export']);
  await f.cleanup();
  assert.deepEqual(f.events,['pin','borrow-0','export','retire-0','unpin']);
});

test('member capture control does not consume a row constructor from the original row bound',async()=>{
  const f=fixture({managed:true});
  // Explicit pre-retained control port, no native capacity or permission
  // claimed. The actual member borrow is covered by the separate prefix case.
  const control=Object.freeze({prepared:Object.freeze({status:()=>({pending:false})})});
  f.requestChildren.push(control);
  const result=await f.run();
  assert.equal(result.rowsOf[0].length,3);
  assert.equal(f.requestChildren.length,4);
  assert.equal(f.requestChildren[0],control);
  assert.equal(f.debits.length,3);
});

test('CREATE inventory consumes the original checked proposal wire before any lossy JS number encoding',()=>{
  const wire='{"state":"present","value":{"wide":9007199254740993}}';
  const value=JSON.parse(wire).value;
  assert.equal(value.wide,9007199254740992);
  const originalIdentity=Object.freeze({content_cid:cid('a'),occurrence:0});
  const moon={clientProgramEffectCreateRowInventory(wires,count){
    assert.deepEqual(wires,[wire]);assert.equal(count,1);
    return {ok:[runtimeTupleFromFields({0:0,1:JSON.stringify(originalIdentity)})]};}};
  const declaration=nodes.find(({node})=>node.type==='FunctionDeclaration'&&
    node.id.name==='prepareInstalledCreateRows').node;
  const prepare=Function('checked','runtimeField','fail','parseExactJson',
    `return (${source.slice(declaration.start,declaration.end)});`)(checked,runtimeField,fail,JSON.parse);
  const result=prepare(moon,[Object.freeze({changesWire:wire})],
    {maxWireBytes:10000,maxNodes:100,maxDepth:10});
  assert.strictEqual(result.rows[0],result.createRows[0].entry);
  assert.equal(result.rows[0].proposalWire,wire);
  assert.deepEqual(result.rows[0].value,value);
  assert.deepEqual(result.createRows[0].identity,originalIdentity);
});

test('actual managed row loop completes each original workspace before the next constructor while retaining all outputs', async () => {
  const f=fixture({managed:true});
  const result=await f.run();
  assert.deepEqual(f.workspaceEvents,[['begin',0],['complete',0],['begin',1],['complete',1],['begin',2],['complete',2]]);
  assert.equal(f.activeConstructor(),undefined);
  assert.equal(result.rowsOf[0].length,3);
  assert.equal(f.requestChildren.length,3);
  assert.equal(f.settlements.length,0,'workspace completion is not output/child retirement');
  for(const retained of f.requestChildren)await retained.prepared.release();
  assert.deepEqual(f.settlements,f.debits);
});

test('actual managed row loop stops on the same failed constructor and retains its unfinished workspace', async () => {
  const f=fixture({managed:true,constructorFailureAt:2});
  await assert.rejects(f.run(),cause=>cause===undefined);
  assert.deepEqual(f.workspaceEvents,[['begin',0],['complete',0],['begin',1]]);
  assert.equal(f.activeConstructor(),f.debits[1]);
  assert.equal(f.contexts.length,2,'the third constructor must not start after failure');
  assert.equal(f.requestChildren.length,2);
  assert.equal(f.settlements.length,0,'failed original is still owned by original cleanup');
  for(const retained of f.requestChildren)await retained.prepared.release();
  assert.deepEqual(f.settlements,f.debits);
});


function sameControlFrame() {
  const events=[],parent={},prepared={},request={},plan={};let active=false;
  const runtime={clientProgramInstalledEffectManagedOperationPlan:()=>({$tag:1,_0:plan}),
    clientProgramInstalledEffectOperationControlConstructionBegin(p,v,r,selected){assert.deepEqual([p,v,r,selected],[parent,prepared,request,plan]);assert(!active);active=true;events.push('begin');return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlConstructionComplete(){assert(active);active=false;events.push('complete');return {$tag:1,_0:undefined};}};
  const run={runtime,value:parent,prepared,request,operationPlan:plan,readPlan:runtime.clientProgramInstalledEffectManagedOperationPlan,closed:false,selecting:false};
  const work=prepareInstalledEffectControlConstruction(run);run.controlConstruction=work;run.retireControlConstruction=work.retire;
  return {work,events,active:()=>active};
}

test('actual CREATE read grant uses its original control frame and returns workspace before physical dispatch', async () => {
  const f=sameControlFrame(),selected={kind:'create',resource:'rows'},entry={request:{}},decision={},grant={grant:{},scope:{}};
  const site={issueReadGrant(facts){assert.equal(this,site);assert(f.active());assert.equal(facts.decision,decision);f.events.push('grant');return grant;}};
  const owned={check:{operation:'read',resource:'form'},checkRequest(context){assert.equal(context.authorization,grant);assert.equal(context.controlConstruction,f.work);f.events.push('physical');}};
  const check=expression('checkRows',{ownerOf:()=>({owned,site,managedPlanRecipe:{credentialOperations:[]}}),
    readDecision:async()=>decision,fail});
  await check({members:[selected],entries:[[entry]],runInvocationCid:'run',dispatches:['dispatch'],subjectOf:()=> 'subject',
    controlConstruction:f.work,physicalOperations(facts){assert.equal(f.active(),false);assert.equal(facts.originalAuthorization,grant);return facts.invoke({authorization:grant});}});
  assert.deepEqual(f.events,['begin','grant','complete','physical']);assert.equal(f.work.retire(),true);
});

test('ordinary CREATE retains the original Run continuation current fence without a Mapping selection', () => {
  const selected={kind:'create',effectId:'append'},owner={resources:undefined};let reads=0;
  const facts={prepared:{},assertContinuationCurrent(){assert.equal(this,facts);reads++;}};
  const select=expression('selectionFence',{owners:[],validateOwnerSelections:()=>undefined,ownerOf:member=>{
    assert.equal(member,selected);return owner;},resourceFields:()=>assert.fail('no legacy Resource original'),
    selectionChanged:()=>assert.fail('no Mapping selection is being supplied'),
    assertUpdateTargetSelectionMembersCurrent:()=>assert.fail('no Mapping proof from Run current'),
    requireSynchronousEffectResource:value=>value,fail});
  const current=select(facts,[selected],0);
  assert.equal(typeof current,'function');assert.equal(reads,1);
  current();assert.equal(reads,2);
});

test('CREATE continuation namespace follows its original Mapping selection rather than Run current presence', () => {
  const calls=nodes.filter(({node})=>node.type==='CallExpression'&&node.callee.name==='continuationOf');
  assert.equal(calls.length,1);
  const selected=calls[0].node.arguments.at(-1);
  const choose=Function('assertCurrent','updateTargetSelections',`return (${source.slice(selected.start,selected.end)});`);
  const owner={},installation={binding:'original'};
  const wire=expression('continuationOf',{canonicalJson:JSON.stringify,
    singular:{profile:{continuation:'legacy',continuationBinding:'binding'},continuationBinding:'original'},
    contractCidOf:()=>cid('a'),ownerOf:()=>owner,installationFacts:actual=>{assert.equal(actual,owner);return installation;}});
  const serialize=selections=>JSON.parse(wire({request:'request',attempt:'attempt'},
    {programId:'program',stageId:'stage',stageIndex:0},[{kind:'create',effectId:'append'}],['dispatch'],choose(()=>{},selections)));
  const ordinary=serialize(undefined);
  assert.equal(Object.hasOwn(ordinary,'stage_index'),false);
  assert.equal(Object.hasOwn(ordinary.members[0],'installation'),false);
  const mapped=serialize([{}]);assert.equal(mapped.stage_index,0);assert.deepEqual(mapped.members[0].installation,installation);
});

test('Run continuation current cannot replace an original Mapping selection current assertion', () => {
  const prepared={},selection={},selections=[selection];let asserted=0;
  const member={kind:'update',stageIndex:0,effectId:'edit',mapping:{target:'target',mappingRef:'mapping',mappingCid:'cid'}};
  const facts={prepared,updateTargetSelections:selections,assertContinuationCurrent(){assert.fail('Run current is not Mapping current');},
    assertUpdateSelectionCurrent(){assert.equal(this,facts);asserted++;}};
  const select=expression('selectionFence',{owners:[],validateOwnerSelections:(_owners,original,p)=>{
    assert.equal(original,selections);assert.equal(p,prepared);return original;},ownerOf:()=>({resources:undefined}),
    resourceFields:()=>assert.fail('no legacy Resource original'),requireSynchronousEffectResource:value=>value,
    assertUpdateTargetSelectionMembersCurrent:(original,members,p)=>{assert.equal(original,selections);assert.equal(p,prepared);
      assert.deepEqual(members,[{stage_index:0,effect_id:'edit',target_ref:'target',mapping_ref:'mapping',mapping_cid:'cid'}]);},
    selectionChanged:()=>fail('MissingOriginalMappingCurrent'),fail});
  const current=select(facts,[member],0,selections);current();assert.equal(asserted,2);
  assert.throws(()=>select({...facts,assertUpdateSelectionCurrent:undefined},[member],0,selections),{code:'MissingOriginalMappingCurrent'});
});

test('actual Effect execution retains its original cancellation read and avoids a duplicate resumed read', async () => {
  const text=await readFile(new URL('./embedded-local.mjs',import.meta.url),'utf8');
  const found=[];
  const walk=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&node.id.name==='executeEffectComputation')found.push(node.init);
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(walk);else walk(value);};
  walk(parse(text,{ecmaVersion:'latest',sourceType:'module'}));assert.equal(found.length,1);
  const body=found[0].body,cut=body.body.find(n=>n.type==='VariableDeclaration'&&n.declarations.some(d=>d.id.name==='readResume'));
  assert(cut);
  const prepare=Function('journal','moon','control','clientOperationError','facts','sourceResume','targetResume','modelResume',
    text.slice(body.start+1,cut.start)+'return {facts,assertContinuationCurrent};');
  const ref={},moon={},control={};let captures=0,reads=0,cancelled=false;
  const journal={observeRunCancellation(r,m,c){assert.equal(this,journal);assert.deepEqual([r,m,c],[ref,moon,control]);captures++;
    return ()=>{reads++;return {cancellationRequested:cancelled};};}};
  const error=code=>Object.assign(new Error(code),{code});
  const warm=prepare(journal,moon,control,error,{ref});assert.equal(captures,1);
  warm.assertContinuationCurrent();assert.equal(reads,1);
  cancelled=true;assert.throws(()=>warm.assertContinuationCurrent(),{code:'ClientRunCancellationRequested'});
  assert.equal(reads,2);
  let resumed=0;const originalResume={assertCurrent(){assert.equal(this,originalResume);resumed++;}};
  const active=prepare(journal,moon,control,error,{ref},originalResume);
  active.assertContinuationCurrent();assert.equal(resumed,1);assert.equal(reads,2);
});

test('actual target authorization retains same original grant receiver in its selected control frame', async () => {
  const f=sameControlFrame(),member={resource:'rows'},decision={action:'dispatch'},grant={grant:{},scope:{}};
  const site={issueReadGrant(facts){assert.equal(this,site);assert(f.active());assert.equal(facts.decision,decision);f.events.push('grant');return grant;}};
  const decide=expression('decideTargetRead',{ownerOf:()=>({connection:'connection',authorization:{authorize:async()=>decision},owned:{targetRead:{operation:'read'}},site}),fail});
  const read=await decide({member,runInvocationCid:'run',dispatchRequestCid:'dispatch',subjectCid:'subject',controlConstruction:f.work});
  const result=await read.authorizationForRow(0);assert.equal(result.grant,grant.grant);
  assert.deepEqual(f.events,['begin','grant','complete']);assert.equal(f.work.retire(),true);
});

test('actual claimed write and projection use their original control frame around the existing durable dispatch', async () => {
  const f=sameControlFrame(),selected={kind:'create',resource:'rows',memberIndex:0},request={},raw={grant:{},scope:{}};
  const claim=Object.fromEntries(['scope','locator','key','basis','intentFingerprintCid'].map(name=>[name,name]));claim.canonicalRequestCid=cid('e');
  const entry={request,requestCid:claim.canonicalRequestCid},description={},dispatching={},bytes=Buffer.from('{}');
  const owned={describe:()=>description,writeOperation:()=> 'create',send(){assert(!f.active());f.events.push('send');return {observation:{useCid:'use',statusCode:200,body:bytes}};},
    project(context){assert.equal(this,owned);assert(f.active());assert.equal(context.request,request);f.events.push('project');return {kind:'provider-response'};}};
  const site={issueEffectGrant(){assert.equal(this,site);assert(f.active());f.events.push('grant');return raw;}};
  const owner={installed:[{}],owned,site,managedPlanRecipe:{credentialOperations:[{phase:'write'}]}};selected.mapping=owner.installed[0];
  const ledger={claimDispatch(){f.events.push('claim');return {claimed:true,dispatching};},beginPhysicalFlight(){return ()=>{};},recordResponse(){f.events.push('store');return {response:{}};}};
  const route=expression('physicalRoute',{ownerOf:()=>owner,fail,guarded:()=>false,checkRows:async()=>{},resourceFields:()=>({}),
    admitCapability:()=>({identity:'capability'}),routeOf:()=>({}),commitDecisions:()=>new Map(),requireApproval:()=>{},scopeKey:()=> 'scope',admitRow:()=>claim,captureClaimedEffectResponse,settle:()=>undefined})({
      members:[selected],entries:[[entry]],previewRows:[[]],dispatches:['dispatch'],dispatchIndexes:[[0]],subjectCid:'subject',applyPreview:{},ledger,runInvocationCid:'run',assertCurrent(){},controlConstruction:f.work,
      physicalOperations(facts){assert(!f.active());return facts.invoke({authorization:raw,credential:{},callResource(){}});}});
  const current=await route.current({preflight:{observedRows:[]}}),dispatch=route.bindDispatch({members:[{claims:[claim]}],subjectCid:'subject'});
  await dispatch({memberIndex:0,rowIndex:0,claim,currentPreflight:current});
  assert.deepEqual(f.events,['begin','grant','complete','claim','send','store','begin','project','complete']);
  assert.equal(route.retire(),true);assert.equal(f.work.retire(),true);
});


test('actual managed row loop composes the original owned request child without replacing its factory', async () => {
  const f = fixture({managed: true}); let cleanup = false, factories = 0, prepares = 0;
  f.owned.prepareRequestChild = context => {
    factories++;
    const result = f.owned.prepareRequest(context);
    return {prepare() {prepares++; return result;}, release: () => cleanup,
      retry: () => cleanup, status: () => ({pending: !cleanup})};
  };
  await f.run();
  assert.equal(factories, 3); assert.equal(prepares, 3);
  assert.deepEqual(f.workspaceEvents, [['begin',0],['complete',0],['begin',1],['complete',1],['begin',2],['complete',2]]);
  for (const retained of f.requestChildren) await retained.prepared.release();
  assert.equal(f.settlements.length, 0);
  cleanup = true;
  for (const retained of f.requestChildren) await retained.prepared.retry();
  assert.deepEqual(f.settlements, f.debits);
  assert.equal(factories, 3, 'cleanup never invokes another request factory');
});

// Actual original dispatcher/target-read constructors; permission, Core
// reservation and provider IO remain explicit ports in this source component.
test('managed Salesforce read handoff retains exact issuer originals across member metadata and row target phases', async () => {
  const member = {kind: 'update', memberIndex: 0, effectId: 'save', resource: 'Account'};
  const grant = Object.freeze({grant: {}, scope: {operation: 'salesforce:record:observe'}});
  const decision = {action: 'dispatch'}, approval = {}, credential = {}, calls = [];
  const target = {id: 'original'}, versionCid = cid('a'), current = {};
  const selectedRecipe = captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze([Object.freeze({operation: 'describe', extent: {}})]),
    rowOperations: Object.freeze([Object.freeze({operation: 'observe', extent: {}}),
      Object.freeze({operation: 'write', extent: {}})]),
    credentialOperations: Object.freeze([
      Object.freeze({phase: 'capture-describe', perRow: false, operationIndex: 0, maxRequestBytes: 128, maxResponseBytes: 64}),
      Object.freeze({phase: 'capture-target', perRow: true, operationIndex: 0, maxRequestBytes: 128, maxResponseBytes: 64}),
      Object.freeze({phase: 'write', operationIndex: 1, maxRequestBytes: 128, maxResponseBytes: 64}),
    ])}), 3);
  const site = {credential, issueReadGrant(facts) {
    assert.equal(facts.operation, 'observe'); assert.strictEqual(facts.decision, approval);
    return grant;
  }};
  let consumed, originalEnvelope;
  const owned = {targetRead: {operation: 'observe'}, admitTargetReadApproval: () => approval,
    describe: options => options.readChild(grant, {grant: grant.grant, useId: 'metadata-use',
      maxResponseBytes: 32, operations: new Map()}),
    async observeTargets(options) {
      originalEnvelope = await options.authorizationForRow(0);
      consumed = options.readChild;
      await options.readChild(originalEnvelope, {grant: grant.grant, useId: originalEnvelope.useId,
        maxResponseBytes: 16, operations: new Map()}, 0);
      return [{identity: target, versionCid, before: {Name: 'before'}}];
    }};
  const owner = {connection: 'crm', site, owned, managedPlanRecipe: selectedRecipe};
  const ownerOf = original => {assert.strictEqual(original, member); return owner;};
  const recipeOf = expression('recipeOf', {ownerOf, controlRecipes: new Map([[selectedRecipe, selectedRecipe]])});
  const physicalOperations = facts => {
    assert.strictEqual(facts.originalAuthorization, grant);
    assert.strictEqual(facts.site, site);
    assert.strictEqual(facts.member, member);
    assert.equal(facts.rowIndex, 0);
    assert.equal(facts.runInvocationCid, 'run');
    assert.equal(facts.dispatchRequestCid, 'dispatch');
    calls.push([facts.phase, facts.purpose, facts.maxResponseBytes]);
    return facts.invoke({authorization: {...grant, useId: facts.useId}, credential: {binding: credential},
      callResource(input) {
        assert.strictEqual(input.grant, grant.grant);
        assert.strictEqual(input.binding, credential);
        assert.equal(input.maxRequestBytes, 128);
        return current;
      }});
  };
  const managedReadChild = expression('managedReadChild', {recipeOf, ownerOf, fail, selectInstalledEffectCredentialOperation});
  const describe = expression('describeMember', {ownerOf, managedReadChild, resourceFields: () => ({})});
  assert.strictEqual(await describe({member, runInvocationCid: 'run', dispatchRequestCid: 'dispatch',
    physicalOperations, operationPhase: 'capture', label: 'original', assertCurrent() {}}), current);
  const decide = expression('decideTargetRead', {ownerOf, recipeOf, fail});
  const read = await decide({member, runInvocationCid: 'run', dispatchRequestCid: 'dispatch', subjectCid: 'subject',
    targetReads: {authorize: () => decision}});
  const observe = expression('observeRows', {ownerOf, managedReadChild, resourceFields: () => ({}),
    fail, sameValue: same, cidPattern: /^sha256:[0-9a-f]{64}$/});
  const observed = await observe({member, entries: [{target}], current, read, physicalOperations,
    operationPhase: 'capture', runInvocationCid: 'run', dispatchRequestCid: 'dispatch'});
  assert.deepEqual(observed, [{identity: target, state: 'present', versionCid, before: {Name: 'before'}}]);
  assert.deepEqual(calls, [['capture-describe', 'read', 32], ['capture-target', 'target-read', 16]]);
  assert.throws(() => consumed(originalEnvelope, {}, 0), {code: 'ForeignInstalledEffectReadChild'});
  assert.equal(calls.length, 2, 'consumed original never grants another operation');
});

function recoveredConstructorFixture({refuseSecond = false, failure = false, capturedAlready = false, pendingRetire = false, input = false} = {}) {
  const parent = {}, prepared = {}, request = {}, plan = {}, events = [], children = [];
  const members = [{memberIndex: 0}, {memberIndex: 1}], active = new Set(), tokens = [];
  let aliasesRetired = false, constructions = 0, retirePending = pendingRetire;
  const owners = [{}, {}], inputExtents = [{}, {}];
  const original = Object.freeze({entries: Object.freeze([[], []]), currents: Object.freeze([{}, {}])});
  const runtime = {
    clientProgramInstalledEffectManagedOperationPlan: () => ({$tag: 1, _0: plan}),
    clientProgramInstalledEffectOperationConstructionRetain(p, v, r, selected, member, perRow, slot, row, operation) {
      assert.deepEqual([p, v, r, selected], [parent, prepared, request, plan]);
      if (capturedAlready && slot === 0) fail('AlreadyBound');
      assert.deepEqual([perRow, slot, row, operation], [false, 1, 0, 'capture']);
      events.push(`retain-${member}`);
      if (refuseSecond && member === 1) throw undefined;
      const token = {member};tokens.push(token);return {$tag: 1, _0: token};
    },
    clientProgramInstalledEffectOperationConstructionBegin(token) {
      assert.equal(tokens.length, 2, 'every original member is retained before any constructor');
      active.add(token.member);events.push(`begin-${token.member}`);return {$tag: 1, _0: undefined};
    },
    clientProgramInstalledEffectOperationInputBegin(token, selected) {
      assert.equal(tokens.length, 2, 'all original members precede selecting any input');
      assert.strictEqual(selected, inputExtents[token.member]);
      active.add(token.member);events.push(`input-${token.member}`);
      return {$tag: 1, _0: undefined};
    },
    clientProgramInstalledEffectOperationConstructionComplete(token) {
      assert(active.has(token.member));active.delete(token.member);events.push(`complete-${token.member}`);
      return {$tag: 1, _0: undefined};
    },
    clientProgramInstalledEffectOperationRetire(token, acknowledgement) {
      assert.equal(acknowledgement, true);assert(aliasesRetired);
      events.push(`retire-${token.member}`);return {$tag: 1, _0: !retirePending};
    },
  };
  const run = {runtime, value: parent, prepared, request, operationPlan: plan,
    controlConstruction: (receiver, method, args) => Reflect.apply(method, receiver, args),
    readPlan: runtime.clientProgramInstalledEffectManagedOperationPlan};
  const recipe = {captureConstruction: {operationIndex: 0}, recoveryConstruction: {operationIndex: 1,
    ...(input ? {inputExtent(wire, recovery, memberIndex) {
      assert.equal(wire, facts.previewWire); assert.strictEqual(recovery, facts.durable.connectorRecovery);
      assert.strictEqual(members[memberIndex].memberIndex, memberIndex);
      events.push(`select-${memberIndex}`); return inputExtents[memberIndex];
    }} : {})}, memberOperations: [{operation: 'capture'}, {operation: 'capture'}]};
  const facts = {members, body: {}, durable: {connectorRecovery: []}, recorded: {}, previewWire: 'unchanged', runInvocationCid: 'run', dispatches: ['a', 'b']};
  const actual = expression('prepareRecoveredEntries', {moon: runtime, recipeOf: () => recipe, fail,
    ownerOf: member => owners[member.memberIndex], sameValue: same,
    validateRecoveredEntries(input, entries) {assert.strictEqual(input.body, facts.body);assert.strictEqual(entries, original.entries);events.push('recheck');},
    retainInstalledRowCaptureChild, prepareInstalledEffectRequestChild,
    recoveredEntries(input) {
      assert.strictEqual(input.body, facts.body);assert.strictEqual(input.members, members);
      assert.deepEqual([...active], [0, 1]);constructions++;events.push('rebuild');
      if (failure) throw undefined;
      return original;
    }});
  const invoke = () => actual({...facts, managedEffect: run, requestChildren: children,
    retireRequestAliases: () => aliasesRetired, assertCurrent() {}});
  return {invoke, original, events, children, run, facts, constructions: () => constructions,
    retire() {aliasesRetired = true;}, finalRetire() {return run.recoveredRequestInput.retire();},
    allowRetire() {retirePending = false;}};
}

test('cold request rebuilding enters every same-Plan member workspace before the single original provider constructor', async () => {
  const f = recoveredConstructorFixture();
  assert.strictEqual(f.invoke(), f.original);
  assert.equal(f.constructions(), 1);
  assert.deepEqual(f.events, ['retain-0', 'retain-1', 'begin-0', 'begin-1', 'rebuild', 'complete-1', 'complete-0']);
  for (const child of f.children) {await child.prepared.release();assert.equal(child.prepared.status().pending, true);}
  f.retire();
  for (const child of f.children) {await child.prepared.retry();assert.equal(child.prepared.status().pending, false);}
  assert.equal(f.finalRetire(), true);
  assert.deepEqual(f.events.slice(-2), ['retire-0', 'retire-1']);
});

test('cold member reservation refusal preserves the exact undefined cause before any provider reconstruction', async () => {
  const f = recoveredConstructorFixture({refuseSecond: true});
  let caught = false;
  try {f.invoke();} catch (error) {caught = true;assert.strictEqual(error, undefined);}
  assert(caught);assert.equal(f.constructions(), 0);
  assert.deepEqual(f.events, ['retain-0', 'retain-1']);assert.equal(f.children.length, 0);
  assert.equal(f.run.recoveredRequestInput.children.length, 1);
  f.retire();assert.equal(f.finalRetire(), true);
  assert.equal(f.run.recoveredRequestInput.children.length, 0);
});

test('cold provider constructor failure retains every original member prefix until the same alias retirement', async () => {
  const f = recoveredConstructorFixture({failure: true});
  let caught = false;
  try {f.invoke();} catch (error) {caught = true;assert.strictEqual(error, undefined);}
  assert(caught);assert.equal(f.constructions(), 1);
  assert.deepEqual(f.events, ['retain-0', 'retain-1', 'begin-0', 'begin-1', 'rebuild']);
  for (const child of f.children) {await child.prepared.release();assert.equal(child.prepared.status().pending, true);}
  f.retire();
  for (const child of f.children) {await child.prepared.retry();assert.equal(child.prepared.status().pending, false);}
  assert.equal(f.finalRetire(), true);
  assert.deepEqual(f.events.slice(-2), ['retire-0', 'retire-1']);
});


test('hot continuation preserves spent capture slots and uses its original distinct recovery construction', async () => {
  const f = recoveredConstructorFixture({capturedAlready: true});
  assert.strictEqual(f.invoke(), f.original);
  assert.equal(f.constructions(), 1);
  assert.deepEqual(f.events, ['retain-0', 'retain-1', 'begin-0', 'begin-1', 'rebuild', 'complete-1', 'complete-0']);
  for (const child of f.children) {await child.prepared.release();assert.equal(child.prepared.status().pending, true);}
  f.retire();
  for (const child of f.children) {await child.prepared.retry();assert.equal(child.prepared.status().pending, false);}
  assert.equal(f.finalRetire(), true);
});

test('hot reconciliation borrows the same still-backed recovery requests without spending another constructor', async () => {
  const f = recoveredConstructorFixture();
  assert.strictEqual(f.invoke(), f.original);
  assert.equal(f.finalRetire(), false, 'active stage still borrows the request body');
  f.retire();await f.children[0].prepared.release();
  assert.equal(f.run.recoveredRequestInput.borrowers, 0);
  assert(!f.events.some(value => value.startsWith('retire-')), 'stage close keeps actual body backing');
  assert.strictEqual(f.invoke(), f.original);
  assert.equal(f.constructions(), 1);
  assert.equal(f.events.filter(value => value.startsWith('retain-')).length, 2);
  assert.equal(f.events.filter(value => value === 'recheck').length, 1);
  assert.equal(f.finalRetire(), false);
  await f.children[1].prepared.release();
  assert.equal(f.finalRetire(), true);
  assert.equal(f.run.recoveredRequestInput.result, undefined);
  assert.equal(f.run.recoveredRequestInput.children.length, 0);
  assert.throws(f.invoke, {code: 'InstalledEffectRecoveryInputRetired'});
});

test('hot recovery input refuses copied Preview and retains a pending original child without another constructor', async () => {
  const f = recoveredConstructorFixture({pendingRetire: true});
  f.invoke();f.retire();await f.children[0].prepared.release();
  f.facts.body = {};
  assert.throws(f.invoke, {code: 'ForeignInstalledRowEffectRequest'});
  assert.equal(f.constructions(), 1);
  assert.equal(f.finalRetire(), false);
  assert.equal(f.run.recoveredRequestInput.result, undefined, 'aliases are cut before the first child settlement');
  assert.throws(f.invoke, {code: 'InstalledEffectRecoveryInputRetired'});
  f.allowRetire();assert.equal(f.finalRetire(), true);
  assert.equal(f.events.filter(value => value.startsWith('retain-')).length, 2);
});

test('failed recovery constructor keeps its exact primary and cannot rebuild on hot observation', () => {
  const f = recoveredConstructorFixture({failure: true});
  let caught = 0;
  for(let i=0;i<2;i++)try{f.invoke();}catch(error){caught++;assert.strictEqual(error,undefined);}
  assert.equal(caught, 2);assert.equal(f.constructions(), 1);
  f.retire();assert.equal(f.finalRetire(), true);
});

test('hot recovery refuses an overlapping stage borrow without granting another constructor or lease', () => {
  const f=recoveredConstructorFixture();f.invoke();
  assert.throws(f.invoke,{code:'InstalledEffectRecoveryInputBorrowed'});
  assert.equal(f.run.recoveredRequestInput.borrowers,1);
  assert.equal(f.constructions(),1);
  assert.equal(f.children.length,1);
});

test('hot recovery checks the original live parent after closed or replaced Request custody', async () => {
  for(const changed of ['closed','request']) {
    const f=recoveredConstructorFixture();f.invoke();f.retire();await f.children[0].prepared.release();
    if(changed==='closed')f.run.closed=true;else f.run.request={};
    assert.throws(f.invoke,{code:'ForeignInstalledEffectManagedRun'});
    assert.equal(f.run.recoveredRequestInput.borrowers,0);assert.equal(f.constructions(),1);
  }
});


test('cold reconstruction selects each actual saved member input before that same constructor starts', async () => {
  const f = recoveredConstructorFixture({input: true});
  assert.strictEqual(f.invoke(), f.original);
  assert.equal(f.constructions(), 1);
  assert.deepEqual(f.events, ['retain-0', 'retain-1', 'select-0', 'input-0',
    'select-1', 'input-1', 'rebuild', 'complete-1', 'complete-0']);
  f.retire();
  for (const child of f.children) await child.prepared.release();
  assert.equal(f.finalRetire(), true);
  assert.deepEqual(f.events.slice(-2), ['retire-0', 'retire-1']);
});


test('managed request projection forwards the same completed original row and constructor coordinates', async () => {
  const f = fixture({managed: true, controlFrame: true, requestProjection: true});
  const result = await f.run();
  assert.equal(f.projections(), 3);assert.equal(f.debits.length, 3);
  assert.deepEqual(f.workspaceEvents, [
    ['begin', 0], ['complete', 0], ['project', 0],
    ['begin', 1], ['complete', 1], ['project', 1],
    ['begin', 2], ['complete', 2], ['project', 2],
  ]);
  result.rowsOf[0].forEach((row, index) => assert.strictEqual(row.entry.value, f.contexts[index].value));
  for (const retained of f.requestChildren) await retained.prepared.release();
  assert.deepEqual(f.settlements, f.debits);
});

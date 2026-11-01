import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {maxHeaderSize} from 'node:http';
import {parse} from 'acorn';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {prepareInstalledRowCaptureChild, retainInstalledRowCaptureChild, releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {prepareInstalledEffectRequestChild, prepareInstalledEffectCredentialChild, captureInstalledEffectPlanRecipe} from './installed-effect-plan.mjs';

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
const expression=(name,ports)=>Function(...Object.keys(ports),`return (${source.slice(variable(name).start,variable(name).end)});`)(...Object.values(ports));
const capture=nodes.find(({node})=>node.type==='FunctionDeclaration'&&node.id.name==='captureStage').node;
const loops=capture.body.body.filter(n=>n.type==='ForOfStatement'&&n.body.body.some(statement=>statement.type==='VariableDeclaration'&&statement.declarations.some(d=>d.id.name==='description')));
assert.equal(loops.length,1);
const loop=loops[0];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const checked=value=>{if(value.error)throw value.error;return value.ok;};
const cid=character=>`sha256:${character.repeat(64)}`;
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);

test('actual capture failure input callback retires only its pins after the shared child drain', async () => {
  const marker = new Error('stop after original cleanup retention'), children = [];
  const input = {}, events = [];
  let releaseInputs, finishCapture, observations = 0;
  const moon = {clientProgramPinEffectSources: () => ({ok: input}),
    clientProgramReleaseEffectInputs(original) {assert.strictEqual(original, input); events.push('pins');}};
  const actual = Function('moon', 'checked', 'limits', 'fail', 'releaseInstalledRowCapture',
    `return (${source.slice(capture.start, capture.end)});`)(moon, checked, {maxPinnedResults: 1}, fail,
    releaseInstalledRowCapture);
  await assert.rejects(actual({ownChildren(original) {
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
function fixture({child=false,inventoryError,managed=false}={}){
  const events=[],contexts=[],requests=[],requestChildren=[],runOriginal=Object.freeze({}),description=Object.freeze({original:true});
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
    contexts.push(context);events.push('prepare');
    const request=Object.freeze({value:context.value}),requestCid=cid(String(contexts.length));
    requests.push(request);return {request,requestCid};
  };
  const owned={describe(){return description;},requestFacts:request=>({value:request.value,target:undefined}),
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
    clientProgramInstalledEffectOperationConstructionBegin(){return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationConstructionComplete(){return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationConstructionRetain(owner,p,r,plan,memberIndex,perRow,operationIndex,rowIndex,operation){
      assert.equal(owner,parent);assert.equal(p,prepared);assert.equal(r,identity);assert.equal(plan,nativePlan);
      assert.deepEqual([memberIndex,perRow,operationIndex,operation],[0,true,1,'construct']);
      assert.equal(inventoryCalls,1);assert.equal(contexts.length,rowIndex);
      const token={rowIndex};debits.push(token);events.push('debit');return {$tag:1,_0:token};
    },clientProgramInstalledEffectOperationRetire(token,ack){assert(aliasesRetired);assert.equal(ack,true);settlements.push(token);return {$tag:1,_0:true};}};
  Object.assign(moon,runtime);
  const managedEffect={runtime:moon,value:parent,prepared,request:identity,operationPlan:nativePlan,
    readPlan:runtime.clientProgramInstalledEffectManagedOperationPlan};
  const ownerOf=value=>{assert.strictEqual(value,member);return {owned,managedPlanRecipe:managedRecipe};};
  const limits={preview:{maxWireBytes:10000,maxNodes:100,maxDepth:10},maxRows:3};
  const createRows=nodes.find(({node})=>node.type==='FunctionDeclaration'&&node.id.name==='prepareInstalledCreateRows').node;
  const prepareInstalledCreateRows=Function('checked','runtimeField','fail','parseExactJson',
    `return (${source.slice(createRows.start,createRows.end)});`)(checked,runtimeField,fail,
      expression('parseExactJson',{fail}));
  const entryOf=expression('entryOf',{ownerOf,cidPattern:/^sha256:[0-9a-f]{64}$/,targeted:()=>false,fail});
  const requestEntry=expression('requestEntry',{entryOf,sameEffectValue:(_kind,a,b)=>same(a,b),targeted:()=>false,fail});
  const resourceFields=value=>{assert.strictEqual(value,member);return {runOriginal};};
  const commandContentRow=()=>undefined;
  const requestsOf=expression('requestsOf',{ownerOf,requestEntry,resourceFields,commandContentRow});
  const ports={moon,members:[member],ownerOf,assertCurrent(){events.push('current');},
    proposals:[input.map(value=>({changesWire:JSON.stringify({state:'present',value})}))],
    runInvocationCid:cid('c'),dispatches:[cid('d')],reads:[undefined],signal:undefined,
    resourceFields,currents:[],rowsOf:[],observations:[],commandContentBorrower:()=>assert.fail('No Command borrow'),
    control:{},prepared,identity,inputs:{},sourceSet:{members:[{payload:{}}]},limits,
    contentBorrowers:[],targeted:()=>false,guarded:()=>false,contentOwner:undefined,
    requestChildren,prepareInstalledRowCaptureChild,commandContentRow,requestEntry,requestsOf,prepareInstalledCreateRows,fail,
    managedEffect,prepareInstalledEffectRequestChild,retireRequestAliases(){aliasesRetired=true;ports.rowsOf.length=0;ports.currents.length=0;return true;}};
  const run=()=>Function(...Object.keys(ports),`return (async()=>{${source.slice(loop.start,loop.end)};return {rowsOf,observations,currents};})();`)(...Object.values(ports));
  return {run,contexts,events,requestChildren,inventoryCalls:()=>inventoryCalls,entryOf,ownerOf,owned,runOriginal,debits,settlements,managedEffect};
}

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
  const node=variable('retireRequestAliases');
  const scope=Function('route','currents','rowsOf','observations','proposals',`
    let captureOpen=true,entries=Object.freeze([[{}]]);
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
  const managedEffect={runtime:moon,value:parent,prepared,request:identity,operationPlan:plan,
    readPlan:moon.clientProgramInstalledEffectManagedOperationPlan};
  const originalSite=Object.freeze({runtimeBundleCid:'runtime',connectorRegistration:'connector',connectorRevision:'revision',
    referenceCurrent:()=>true,authorizationPurpose(original){assert.equal(original,raw);return {kind:'read',resource:'rows'};},
    bindRunAcquisition(original){assert.equal(original,raw);assert.equal(children.length,1);events.push('bind');
      return {credential:{binding,control,journal,resolveSecret},close:()=> 'closed'};},
    callResource(){events.push('read');return Promise.resolve({originalResponse:true});}});
  const recipe={rowOperations:[{},{},{},{operation:'form-read'}],credentialOperations:[
    {phase:'capture-check',operationIndex:3,maxRequestBytes:64,maxResponseBytes:64}]};
  const actual=expression('prepareCredentialOperation',{moon,ownerOf:()=>({managedPlanRecipe:recipe}),fail,
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
  const claim={scope:'scope',locator:'locator',key:'key',basis:'basis',intentFingerprintCid:'row',canonicalRequestCid:cid('e')};
  const writeGrant=Object.freeze({grant:{write:true},scope:{}}),readGrant=Object.freeze({grant:{read:true},scope:{}}),decision={};
  let checked=false;
  const owned={describe:()=>description,writeOperation:()=> 'create',
    checkRequest(context){assert.equal(this,owned);assert.equal(context.request,request);assert.equal(context.authorization.grant,readGrant.grant);
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
      subjectCid:'subject',runInvocationCid:'run',applyPreview:{},ledger,assertCurrent(){},
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
  const managedEffect={runtime:moon,value:parent,prepared,request:identity,operationPlan:nativePlan,
    readPlan:moon.clientProgramInstalledEffectManagedOperationPlan};
  const control={publicationPreparedReleaseAction(index,_count,checked,pending,attempted){
    return index<0?'finished':!checked?'inspect':pending&&!attempted?'release':'advance';},
    publicationCleanupOwnerAction(index,count,checked,pending,available,attempted){
      return index>=count?'finished':!checked?'inspect':pending&&available&&!attempted?'retry':'advance';
    }};
  const ports={moon,prepared,identity,managedEffect,members,checkedHost:{},checked,fail,
    limits:{maxPinnedResults:2,maxRows:2,maxWork:100,maxFields:4,body:{maxBytes:100,maxNodes:20,maxDepth:5}},
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
  const canonicalRows=expression('canonicalRows',{moon,checked,fail,runtimeField,parseExactJson:JSON.parse,
    limits:{preview:{maxWireBytes:10000,maxNodes:100,maxDepth:10}}});
  const row=Object.freeze({value,proposalWire:wire});
  const result=canonicalRows([row]);
  assert.equal(result[0].entry,row);
  assert.deepEqual(result[0].identity,originalIdentity);
});

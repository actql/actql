import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import {prepareInstalledEffectRequestChild, captureInstalledEffectPlanRecipe} from './installed-effect-plan.mjs';

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
    clientProgramInstalledEffectOperationBorrow(owner,p,r,plan,memberIndex,perRow,operationIndex,rowIndex,operation){
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
  const canonicalRows=expression('canonicalRows',{limits,moon,checked,runtimeField,fail,parseExactJson:JSON.parse});
  const entryOf=expression('entryOf',{ownerOf,cidPattern:/^sha256:[0-9a-f]{64}$/,targeted:()=>false,fail});
  const requestEntry=expression('requestEntry',{entryOf,sameEffectValue:(_kind,a,b)=>same(a,b),targeted:()=>false,fail});
  const resourceFields=value=>{assert.strictEqual(value,member);return {runOriginal};};
  const commandContentRow=()=>undefined;
  const requestsOf=expression('requestsOf',{ownerOf,requestEntry,resourceFields,commandContentRow});
  const ports={moon,members:[member],ownerOf,assertCurrent(){events.push('current');},
    proposals:[input.map(value=>({changesWire:JSON.stringify({value})}))],
    runInvocationCid:cid('c'),dispatches:[cid('d')],reads:[undefined],signal:undefined,
    resourceFields,currents:[],rowsOf:[],observations:[],commandContentBorrower:()=>assert.fail('No Command borrow'),
    control:{},prepared,identity,inputs:{},sourceSet:{members:[{payload:{}}]},limits,
    contentBorrowers:[],targeted:()=>false,guarded:()=>false,contentOwner:undefined,
    requestChildren,prepareInstalledRowCaptureChild,commandContentRow,requestEntry,requestsOf,canonicalRows,fail,
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

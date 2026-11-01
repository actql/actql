import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {AcquisitionOpenError} from '../host-common/acquisition-outcome.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {finishInstalledEffectModelScope} from './installed-effect-managed-run.mjs';

// Actual Local constructor -> Host bag -> Request manager -> runtime port.
// Core nominal/Resource/current interfaces are explicit fixture ports. This is
// neither a compiled Common ABI nor physical backing, Source IO or a public Run.
function method(file, name, ports) {
  const s=readFileSync(new URL(file,import.meta.url),'utf8');let selected;
  const walk=n=>{if(!n||typeof n!=='object')return;
    if(n.type==='Property'&&n.key?.name===name){assert(!selected);selected=n;}
    for(const value of Object.values(n)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);}};
  walk(parse(s,{ecmaVersion:'latest',sourceType:'module'}));assert(selected,name);
  return Function(...Object.keys(ports),`return ({${s.slice(selected.start,selected.end)}}).${name};`)(...Object.values(ports));
}
const fail=code=>{throw Object.assign(new Error(code),{code});},ok=value=>({$tag:1,_0:value});
async function fixture({failurePhase,failure,failKeyedRead,hostRetirement=false}={}) {
  const prepared={},request={},sdkRequest={},parent={},input={},holder={},original={},value={},selected={},compilation={};
  const graph=Object.freeze({task:0,step:1}),rawGraph={},keyed={},declaration={},calls=[];
  const plan={kind:'serialization',serializationGraph:graph,compiled:{},runDefinition:{}};
  const record={},originalInstallation={releaseRequestDomainAliases(){}},originals={},runs=new WeakMap(),liveRuns=new Set(),view={};
  let profile,localOptions,currentFailure;
  const state={parent,prepared,holder,compilationFamily:'content',context:undefined,original};
  const producer={receipt:input,preparation:state,liveRuns:0};
  const moon={
    clientProgramPreparationBorrowRead:h=>{assert.equal(h,holder);return prepared;},
    clientProgramPreparationBorrowRetirementStarted:h=>{assert.equal(h,holder);return true;},
    clientProgramCompleteRequestContentPreparation(p,i,r,s){assert.deepEqual([p,i,r,s],[parent,input,request,selected]);
      assert.equal(record.computeRuns.get(prepared).selectedKeyed,selected);assert.equal(state.contentCompilation,compilation);
      calls.push('complete');if(failurePhase==='complete')throw failure;return ok();},
    clientProgramAdoptRequestContentPreparation(p,r){assert.deepEqual([p,r],[parent,request]);calls.push('adopt');if(failurePhase==='adopt')throw failure;return ok(value);},
    clientProgramPrepareRequestKeyedSerializationCompilation(p,i,s,g){assert.equal(this,moon);assert.deepEqual([p,i,s,g],[parent,input,selected,rawGraph]);
      assert.equal(state.contentPlan,selected);calls.push('compile');if(failurePhase==='compile')throw failure;return ok(compilation);},
    clientProgramInstalledManagedRunCheck(v,p,r){assert.deepEqual([v,p,r],[value,prepared,request]);return ok();},
    clientProgramInstalledManagedRunRetire(v){assert.equal(v,value);if(!hostRetirement)assert.fail('Local child cannot retire its Host parent');return ok();},
    clientProgramInstalledManagedKeyedSourceRead(v,k,r,d){
      assert.deepEqual([v,k,d],[value,keyed,declaration]);calls.push('keyed-read');
      if(failKeyedRead)throw failKeyedRead;return ok({originalRequest:r});
    },
    clientProgramInstalledKeyedSourceReadRetire(){calls.push('keyed-retire');return ok();},
    clientProgramNodeLocalContentRunPrepare(){assert.fail('No independent Content admission');},
    clientProgramInstalledManagedKeyedContentRunBegin(){assert.fail('No standalone Content begin');},
    clientProgramLocalFileTimestamp(){},clientProgramResourceReferenceIssuer:()=>({}),
    clientProgramKeyedAcquisitionMatchesProgram:(k,p)=>k===keyed&&p===prepared,
    clientProgramKeyedDirectAcquisitionCoordinates:()=>({_0:0,_1:0}),
    clientProgramPrepareLocalQueryRequirement:()=>ok({}),clientProgramQueryRequirementSourceRef:()=> 'local:files',
    clientProgramKeyedAcquisitionSourceEvidenceFacts:()=>ok(['local:contents']),
    clientProgramRowSourcePrepareAcquisition:d=>{assert.equal(d,declaration);return ok({});},
    clientProgramInstalledRowCaptureCapacity:()=>({}),
    clientProgramInstalledManagedKeyedContentPrepare(...args){assert.equal(args[0],prepared);assert.equal(args[2],keyed);calls.push('selected');return ok(selected);},
  };
  state.context={runtime:moon};
  const current=()=>{if(currentFailure)throw currentFailure;};
  const managerPorts={current,producerForRequest:r=>{assert.equal(r,sdkRequest);return producer;},fail,
    callbacks:{request:()=>sdkRequest,contentRequirements(o,p,s){assert.deepEqual([o,p,s],[originals,prepared,selected]);return{attempts:2};}},
    originals,runs,liveRuns,view,checked};
  for(const name of ['retainContentPreparation','prepareKeyedContentRun','adoptContentPreparation'])view[name]=method('./ordinary-source-managed.mjs',name,managerPorts);
  view.assertCurrent=current;view.prepareRead=()=>assert.fail('No physical read selected');
  const managerSource=readFileSync(new URL('./ordinary-source-managed.mjs',import.meta.url),'utf8');
  const privateNames=new Set(['runFor','captureReader','closeChild']);
  let privateFunctions=[];
  const walk=n=>{if(!n||typeof n!=='object')return;
    if(n.type==='FunctionDeclaration'&&privateNames.has(n.id?.name))privateFunctions.push(managerSource.slice(n.start,n.end));
    for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};
  walk(parse(managerSource,{ecmaVersion:'latest',sourceType:'module'}));assert.equal(privateFunctions.length,3);
  const privatePorts={current,runs,fail,pending:v=>v?.pending===true,resourceRuntime:{assertOrdinaryManagedRunCurrent(o,i){assert.equal(o,original);assert.equal(i,input);}}};
  const helpers=Function(...Object.keys(privatePorts),privateFunctions.join('\n')+'\nreturn{runFor,captureReader,closeChild};')(...Object.values(privatePorts));
  view.prepareKeyedRead=method('./ordinary-source-managed.mjs','prepareKeyedRead',{
    ...helpers,project:true,bundle:{sources:[{declaration}]},fail});
  const tokens=new WeakMap([[graph,rawGraph]]),control={};
  control.prepareCheckedClientRequestKeyedSerializationCompilation=method('../host-common/runtime-core.mjs',
    'prepareCheckedClientRequestKeyedSerializationCompilation',{serializationPlanTokens:tokens,moon,compiledRunResult:checked});
  const host=method('./embedded-local.mjs','prepareManagedKeyedContentRun',{
    sourceManaged:view,moon,record,originalInstallation,originals,checked,
    clientOperationError:code=>Object.assign(new Error(code),{code}),assertSourceManagedInstallationCurrent(){},
    originalSourceManagedHostRequest:()=>sdkRequest,runtimeCore:()=>({publicationControl:control})});
  const retainContent=method('./embedded-local.mjs','retainManagedContentPreparation',{
    sourceManaged:view,computeManaged:undefined,moon,originalInstallation,originals,
    assertSourceManagedInstallationCurrent(){},originalSourceManagedHostRequest:()=>sdkRequest,
    clientOperationError:code=>Object.assign(new Error(code),{code})});
  const path=new URL('../connectors/local/host/installed-project-files.mjs',import.meta.url),s=readFileSync(path,'utf8');
  const names=new Set(['fail','canonical','cid','positive','text','acknowledged','physicalReadChild','installPreparedProjectLocalFiles']);
  const parts=parse(s,{ecmaVersion:'latest',sourceType:'module'}).body.flatMap(n=>{
    const v=n.type==='ExportNamedDeclaration'?n.declaration:n;
    const selectedNames=v?.type==='VariableDeclaration'?v.declarations.map(d=>d.id.name):[v?.id?.name];
    if(!selectedNames.some(n=>names.has(n)))return[];selectedNames.forEach(n=>assert(names.delete(n)));return[s.slice(v.start,v.end)];});assert.equal(names.size,0);
  const install=Function('createHash','canonicalJson','checked','runtimeOptionalField','readFile','moduleUrl',
    'createInstalledRowSource','rowSourceCheckEnvironment','composeInstalledCheckEnvironment','retainInstalledHostInitializationFailure','AcquisitionOpenError','mime',
    parts.join('\n').replaceAll('import.meta.url','moduleUrl')+'\nreturn installPreparedProjectLocalFiles;')(
      createHash,canonicalJson,checked,runtimeOptionalField,readFile,path,
      async options=>{localOptions=options;return{connectorBindings:[],admitsSource:()=>true};},()=>({wire:'{}'}),()=> '{}',
      async cause=>cause,AcquisitionOpenError,()=>assert.fail('No MIME/physical read'));
  const entry={connection:'local',rootPath:'/not-opened',declaration,scopeCid:'sha256:'+'a'.repeat(64),
    queryAliases:[{name:'local',resource:'files'},{name:'local.contents',resource:'contents'}],
    limits:{maxReadBytes:100,maxPages:2,maxPageBytes:8,maxFileBytes:32},wire:JSON.stringify({views:[
      {resource:'files',source_ref:'local:files'},{resource:'contents',source_ref:'local:contents'}]})};
  const bundle={sources:[entry]};profile=await install({moon,preparation:{originalsForRuntime:()=>bundle},sourceManaged:view,
    baseEnvironmentWire:'{}',authorizationFor:async()=>({context:{contextCid:'context'},assertAccountCurrent(){}}),
    prepareManagedContentRun(p,r,g,recipe,construct,preparation){assert.equal(profile,record.managedSourceProfile);return host(moon,p,r,g,recipe,construct,preparation);}});
  record.managedSourceProfile=profile;
  const content=installNodeContentRun({moon,core:{contentGenerationControl:{workspaceCapacity:()=>({retainedBytes:1n,executionBytes:1n}),
    prefixCapacity(p,t,s){assert.deepEqual([p,t,s],[prepared,0,1]);calls.push('prefix');return{retainedBytes:5n,executionBytes:7n};}},
    publicationControl:{checkClientCompiledRunOwner(c,p){assert.equal(c,plan.compiled);assert.equal(p,prepared);}}},
    preparedRunRequired:true,assertRunCurrent(){},registry:'{}',values:'{}',ownerPrincipal:'fixture',
    retainPreparation:(p,original)=>retainContent(moon,p,original),
    prepareKeyedManagedRun:(p,r,g,recipe,original)=>profile.prepareManagedContentRun(p,r,recipe,g,original),borrowKeyedManagedLedger:()=>assert.fail('No physical Ledger borrowed')});
  return{calls,content,profile,prepared,request,plan,graph,keyed,compilation,record,state,control,selected,localOptions,declaration,moon,view,original,
    child:(r={})=>view.prepareKeyedRead(prepared,declaration,original,r),failCurrent:e=>{currentFailure=e;},
    compile:(changes={})=>content.prepareManagedKeyedCompilation({preparedProgram:prepared,request,serializationGraph:graph,keyedAcquisition:keyed,...changes}),
    bind:()=>content.prepareManagedKeyedRun({preparedProgram:prepared,request,plan,keyedAcquisition:keyed})};
}

test('Request keyed Content selects then compiles once before completing and adopting its same Host parent',async()=>{
  const f=await fixture();assert.equal(f.compile(),f.compilation);assert.equal(f.compile(),f.compilation);
  assert.deepEqual(f.calls,['prefix','selected','compile','complete','adopt']);
  const run=f.record.computeRuns.get(f.prepared);assert.equal(run.selectedKeyed,f.selected);assert.equal(run.contentCompilation,f.compilation);
  f.bind();f.bind();await f.profile.close();assert.equal(f.calls.filter(x=>x==='compile').length,1);
});

test('Request keyed Content preserves its exact failed constructor without reissuing after undefined or typed refusal',async()=>{
  for(const [failurePhase,failure]of[['compile',undefined],['complete',new Error('same completion')],['adopt',new Error('same adoption')]]){
    const f=await fixture({failurePhase,failure});for(let i=0;i<2;i++){
      let thrown=false;try{f.compile();}catch(e){thrown=true;assert.equal(e,failure);}assert(thrown);
    }
    assert.equal(f.calls.filter(x=>x==='selected').length,1);assert.equal(f.calls.filter(x=>x==='compile').length,1);
    assert.equal(f.record.computeRuns.get(f.prepared).selectedKeyed,f.selected);await f.profile.close();
  }
});

test('Request keyed Content refuses missing compiler preparation and foreign graph or keyed originals',async()=>{
  const f=await fixture();assert.throws(f.bind,{message:'InstalledContentRunPreparationUnavailable'});assert.deepEqual(f.calls,[]);
  assert.throws(()=>f.compile({keyedAcquisition:{}}),{message:'ForeignInstalledContentRun'});
  assert.throws(()=>f.control.prepareCheckedClientRequestKeyedSerializationCompilation({}, {}, f.selected, {...f.graph}),{message:'Foreign Content compilation graph'});
  f.compile();assert.throws(()=>f.compile({serializationGraph:{...f.graph}}),{message:'ForeignInstalledContentRun'});await f.profile.close();
});


test('Request keyed child keeps its original physical close through current refusal',async()=>{
  const f=await fixture();f.compile();const child=f.child(),primary=new Error('same current refusal');
  let pending=true,calls=0;const physical={close(){assert.equal(this,physical);calls++;return{pending};},status:()=>({pending})};
  child.retainChild(physical);physical.close=()=>assert.fail('No replacement close');f.failCurrent(primary);
  assert.throws(()=>f.child(),e=>e===primary);assert.equal((await child.close()).pending,true);
  pending=false;assert.equal((await child.close()).pending,false);assert.equal(calls,2);await f.profile.close();
});

test('Request keyed child history and original request are not refilled by physical close',async()=>{
  const f=await fixture();f.compile();const request={},child=f.child(request);
  assert.throws(()=>f.child(request),{code:'InstalledSourcePreparationMismatch'});
  assert.equal((await child.close()).pending,false);assert.equal((await f.child().close()).pending,false);
  assert.throws(()=>f.child(),{code:'InstalledSourcePreparationMismatch'});await f.profile.close();
});

test('actual planFor forwards its original keyed selection through adoption before the Task issuer',async()=>{
  const f=await fixture(),source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');let selected;
  const walk=n=>{if(!n||typeof n!=='object')return;
    if(n.type==='VariableDeclarator'&&n.id?.name==='planFor')selected=n.init;
    for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};
  walk(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(selected);
  const ports={prepareSubmit:{assertOwned:p=>assert.equal(p,f.prepared),originalInferRun:()=>undefined},
    earlyMockInferPlans:new WeakMap(),earlyContentPlans:new WeakMap(),inferSelections:new WeakMap(),
    preparation:{},moon:{clientProgramSerializationOccurrences:()=>[{}],clientProgramAcquisitionCount:()=>2},
    control:{},authorityScopeCid:'authority',namespaceId:'namespace',storeAuthorityCid:'store',now:()=> '2026-10-31T00:00:00.000Z',
    installedResultDataPolicy:{},runContent:f.content,
    selectInstalledSerializationGraph:options=>{assert.equal(options.preparedProgram,f.prepared);return f.graph;},
    serializationTaskRunAdmission:options=>{assert.equal(options.compilationOriginal,f.compilation);assert.equal(options.serializationGraph,f.graph);
      assert.equal(options.requestIdentity,f.request);f.calls.push('task-run');return f.plan;},
    diagnostic:()=>assert.fail('No successful-path diagnostic'),clientOperationError:code=>Object.assign(new Error(code),{code})};
  const planFor=Function(...Object.keys(ports),`return (${source.slice(selected.start,selected.end)});`)(...Object.values(ports));
  assert.equal(planFor({preparedProgram:f.prepared,requestId:'original-request'},undefined,f.request,f.keyed),f.plan);
  assert.deepEqual(f.calls,['prefix','selected','compile','complete','adopt','task-run']);await f.profile.close();
});


test('Local keyed reader closes its exact Core tuple once and leaves only a weak close tombstone',async()=>{
  const f=await fixture();f.compile();
  const original=f.localOptions.prepareKeyedSourceRead({checkedOwner:f.prepared,keyedAcquisition:f.keyed,request:{},declaration:f.declaration});
  assert.deepEqual(await f.localOptions.closeKeyedSourceRead(original),{pending:false});
  assert.deepEqual(await f.localOptions.closeKeyedSourceRead(original),{pending:false});
  await assert.rejects(f.localOptions.closeSourceRead(original),{code:'ForeignLocalFilesSourcePreparation'});
  await f.localOptions.site.close();await f.profile.close();
  assert.equal(f.calls.filter(x=>x==='keyed-retire').length,1);
});

test('Local partial keyed reader keeps its original child without inventing a Core tuple or parent ACK',async()=>{
  const primary=new Error('same original keyed read refusal'),f=await fixture({failKeyedRead:primary});f.compile();
  const request={};assert.throws(()=>f.localOptions.prepareKeyedSourceRead({checkedOwner:f.prepared,keyedAcquisition:f.keyed,request,declaration:f.declaration}),e=>e===primary);
  assert.throws(()=>f.localOptions.prepareKeyedSourceRead({checkedOwner:f.prepared,keyedAcquisition:f.keyed,request,declaration:f.declaration}),{code:'LocalFilesSourcePreparationMismatch'});
  await f.localOptions.site.close();await f.profile.close();
  assert.equal(f.calls.filter(x=>x==='keyed-read').length,1);assert.equal(f.calls.includes('keyed-retire'),false);
});


test('Request keyed Host cuts raw compiler aliases before its consumed parent return can fail',async()=>{
  const f=await fixture({hostRetirement:true});f.compile();const run=f.record.computeRuns.get(f.prepared);
  const primary=new Error('same consumed preparation return');let returns=0;
  f.view.severPreparation=(p,o)=>{assert.equal(p,f.prepared);assert.equal(o,f.original);
    for(const name of['contentCompilation','contentGraph','contentRecipe','selectedKeyed'])assert.equal(run[name],undefined);
    if(++returns===1)throw primary;};
  const retire=method('./embedded-local.mjs','retireManagedComputeRun',{
    moon:f.moon,record:f.record,checked,finishInstalledEffectModelScope,
    clientOperationError:code=>Object.assign(new Error(code),{code}),
    managedPreparationRetirementContinuation:original=>{assert.equal(original,run);assert.equal(run.closed,true);return()=>{};}});
  assert.throws(()=>retire(f.prepared),e=>e===primary);const finish=retire(f.prepared);finish();
  assert.equal(returns,2);assert.equal(run.closed,true);await f.profile.close();
});


test('Local keyed Content cuts all original and dynamic aliases while its Prepared key stays held',async()=>{
  const f=await fixture({hostRetirement:true});f.compile();f.bind();
  const original=f.state.contentPreparation,local=original.localPreparation;
  for(const key of ['recipe','graph','selected','keyed','contentEntry','hostRun'])assert.notEqual(local[key],undefined,key);
  f.view.severPreparation=()=>{assert.equal(original.retired,true);assert.equal(local.retired,true);
    for(const key of Object.keys(original))if(key!=='retired')assert.equal(original[key],undefined,key);
    for(const key of Object.keys(local))if(key!=='retired')assert.equal(local[key],undefined,key);};
  const retire=method('./embedded-local.mjs','retireManagedComputeRun',{
    moon:f.moon,record:f.record,checked,finishInstalledEffectModelScope,
    clientOperationError:code=>Object.assign(new Error(code),{code}),managedPreparationRetirementContinuation:()=>()=>{}});
  retire(f.prepared)();
  assert.throws(f.compile,{message:'ForeignInstalledContentRun'});
  assert.throws(f.bind,{message:'InstalledContentRunPreparationUnavailable'});
  await f.profile.close();
});

test('Local Content alias retirement retains a pending original read and retries that same release',async()=>{
  const f=await fixture({hostRetirement:true});f.compile();
  const original=f.state.contentPreparation,local=original.localPreparation;
  const read=f.localOptions.prepareKeyedSourceRead({checkedOwner:f.prepared,keyedAcquisition:f.keyed,request:{},declaration:f.declaration});
  let cuts=0;f.view.severPreparation=()=>{cuts++;};
  const retire=method('./embedded-local.mjs','retireManagedComputeRun',{
    moon:f.moon,record:f.record,checked,finishInstalledEffectModelScope,
    clientOperationError:code=>Object.assign(new Error(code),{code}),managedPreparationRetirementContinuation:()=>()=>{}});
  assert.throws(()=>retire(f.prepared),{code:'LocalFileCleanupPending'});
  assert.equal(original.retired,false);assert.equal(local.retired,false);assert.equal(cuts,0);
  await f.localOptions.closeKeyedSourceRead(read);retire(f.prepared)();
  assert.equal(original.retired,true);assert.equal(local.retired,true);assert.equal(cuts,1);
  await f.profile.close();
});

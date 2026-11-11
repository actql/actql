import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

// Execute the original private group and enclosing custody with explicit
// Model/Core/Store ports. No Runtime, physical stop or public-close ACK is
// issued by these controls; ordinary matching-package acceptance is separate.
const source=readFileSync(new URL('./acquired-effect-computation.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const functions=ast.body.map(node=>node.declaration??node);
const groupFunction=functions.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='acquiredEffectModelGroup');
const outer=functions.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='openAcquiredEffectComputation');
const declaration=name=>{
  const node=outer.body.body.find(node=>node.type==='VariableDeclaration'&&node.declarations.some(d=>d.id.name===name));
  assert(node,`original ${name}`);return source.slice(node.start,node.end);
};
function fixture({publicationSuccess=false,deferPublication=false}={}){
  const events=[],contexts=[],binding={},issuance={},primary=new Error('OriginalModelEffectEvidenceRejected');
  let entered,release;const preparationEntered=new Promise(resolve=>{entered=resolve;}),preparationPending=new Promise(resolve=>{release=resolve;});
  const flags={binding:true,issuer:true,stop:true,capture:true,capacity:true};
  const stopped=[false,false],retired=[false,false];let borrowed=true,closeStarted=false,physicalClosed=false,persistCalls=0;
  const selections=Object.freeze([0,1].map(index=>Object.freeze({graph:{index},occurrence:{},observeAccount:()=>({})})));
  const components=selections.map((selection,index)=>({bindOriginal(context){contexts[index]=context;},hasFailure:()=>false,failure:()=>undefined}));
  const preparations=selections.map((selection,index)=>({selection,component:components[index]}));
  const plan={compiled:{},runDefinition:{}};
  const checked=value=>{assert.equal(value.$tag,1);return value._0;};
  const ok=_0=>({$tag:1,_0});
  const moon={
    clientProgramEffectComposedModelKeyedAcquisition:()=>ok(undefined),
    clientProgramAdvanceInferObservationIssuance(original){assert.strictEqual(original,issuance);return ok({_0:true});},
    clientProgramReleaseInferInvocationBinding(original){assert.strictEqual(original,binding);events.push('binding');return flags.binding;},
    clientProgramCancelInferObservationIssuance(original){assert.strictEqual(original,issuance);return false;},
    clientProgramCleanupInferObservationIssuance(original){assert.strictEqual(original,issuance);events.push('issuer');return ok(flags.issuer);},
    clientProgramRefreshAcquiredEffectCleanup(){events.push('refresh');return true;},
  };
  const ports={checked,runtimeField:(value,index)=>value[`_${index}`],canonicalJson:JSON.stringify,
    openNodeInferCaptureCustody({operation}){const index=operation.index;return {
      retainCompleted(){return true;},completedCallCount:()=>1,
      async persist(){persistCalls++;},modelEvidence:()=>[],
      custody:{async retirePublication(){assert(stopped[index]);events.push(`capture-${index}`);if(flags.capture)retired[index]=true;return flags.capture;},
        async close(){assert(!borrowed);events.push(`child-${index}`);return true;},
        async cleanup(){assert(!borrowed);return true;},cleanupPending:()=>borrowed},
    };},
    startCompleteInferObservation(){return issuance;},
    async acquiredInferEffectPublicationPlan(options){options.retainBinding(binding);entered();if(deferPublication)await preparationPending;if(!publicationSuccess)throw primary;return {plan:{original:true},observation:{name:'run_observation',wire:'{}',identity:'observation'},invocation:{name:'run_invocation',wire:'{}',identity:'invocation'}};},
    preparePrivatePublicationHolding(){assert(publicationSuccess);return {async commit(){events.push('commit');}};},
  };
  const group=Function(...Object.keys(ports),'return ('+source.slice(groupFunction.start,groupFunction.end)+');')(...Object.values(ports))({
    moon,acquired:{control:{runDefinitionRunId:()=> 'fixture',modelPrivateHoldingCid:(_definition,_authority,name)=>name}},infer:{components:selections},
    originalModelComponents:components,originalModelSelection:{components:selections},
    originalPreparation:{components:preparations},plan,modelController:{},current(){},
  });
  group.bind({captures:[],evidence:[]});
  for(const [index,context] of contexts.entries())context.retainOperation({index,physicalStopped:()=>stopped[index],
    async stop(){events.push(`stop-${index}`);if(!flags.stop)throw primary;stopped[index]=true;},
    releaseOriginalPublicationCapacity(){assert(retired.every(Boolean));events.push('capacity');if(flags.capacity)borrowed=false;return flags.capacity;}});
  const execution={async close(){events.push('parent-close');closeStarted=true;assert.equal(borrowed,false,'original publication borrow must retire before parent Model cleanup');physicalClosed=true;},
    async cleanup(){events.push('parent-cleanup');physicalClosed=closeStarted&&!borrowed;return physicalClosed;},cleanupPending:()=>!physicalClosed||borrowed};
  const outerPorts={modelGroup:group,execution,moon,checked,
    captures:[{async close(){events.push('source');}}],async cleanupInfer(){return group.cleanup(true);},observeUsage(){}};
  const custody=Function(...Object.keys(outerPorts),`
    let closed=false,pending=true,settled=true,unresolved=false;
    let recovery,restoredModelOutput,contentFamilyCleanup,contentFamily,contentRecovery,keyedCleanup,originalPreparation,sourceContinuation,modelToken,checkedHost;
    let originalPreparationRetained=false,restoredModelHostAttempted=false,hostOpenAttempted=false,computeEntered=true;
    ${declaration('retireUnenteredCompute')}
    ${declaration('custody')}
    return custody;
  `)(...Object.values(outerPorts));
  return {group,custody,flags,events,primary,preparationEntered,releasePreparation:()=>release(),persistCalls:()=>persistCalls,
    async succeed(){for(const context of contexts)context.retainCompleted();return group.persist();},
    async fail(){for(const context of contexts)context.retainCompleted();await assert.rejects(group.persist(),e=>e===primary);assert.equal(group.hasOutputPins(),true);}};
}

test('failed plural publication returns original bindings and capacity before enclosing first close',async()=>{
  const f=fixture();await f.fail();
  await f.custody.close();assert.equal(await f.custody.cleanup(),true);
  assert.equal(f.custody.cleanupPending(),false);
  assert(f.events.indexOf('binding')<f.events.indexOf('issuer'));
  assert(f.events.indexOf('capacity')<f.events.indexOf('parent-close'));
  assert(f.events.indexOf('parent-close')<f.events.indexOf('source'));
  assert.equal(f.persistCalls(),2,'same failed publication is never reissued during cleanup');
});

for(const phase of ['binding','issuer','capture','capacity']) test(`failed publication ${phase} refusal retains the same cleanup and Source until original recovery`,async()=>{
  const f=fixture();await f.fail();f.flags[phase]=false;
  await assert.rejects(f.custody.close(),{code:'ERR_ASSERTION'});assert.equal(f.custody.cleanupPending(),true);
  assert.equal(await f.custody.cleanup(),false);
  assert.equal(f.events.filter(event=>event==='parent-close').length,1);assert(!f.events.includes('source'));
  f.flags[phase]=true;
  // Retry only the same internal cleanup, never another public close, Model,
  // preparation or publication. The first parent close already owns its stop.
  assert.equal(await f.custody.cleanup(),true);
  assert.equal(f.events.filter(event=>event==='parent-close').length,1);
  assert.equal(f.custody.cleanupPending(),false);assert.equal(f.persistCalls(),2);
});

test('failed publication stop throw preserves its exact failure and all downstream cleanup duties',async()=>{
  const f=fixture();await f.fail();f.flags.stop=false;
  await assert.rejects(f.custody.close(),e=>e===f.primary);
  assert.equal(f.custody.cleanupPending(),true);
  assert(!f.events.includes('capacity'));assert(!f.events.includes('source'));
  await assert.rejects(f.custody.cleanup(),e=>e===f.primary);
  assert.equal(f.persistCalls(),2);
});

test('successful plural preparation keeps original evidence until enclosing close after downstream consumer failure',async()=>{
  const f=fixture({publicationSuccess:true});
  const plan=await f.succeed();assert.equal(plan.original,true);
  assert.equal(f.group.hasOutputPins(),true);
  assert(!f.events.includes('binding'),'final dependency consumption still owns the original before close');
  // The outer caller failed after accepting this prepared plan. It invokes
  // its original cleanup owner; no repeated preparation or public call follows.
  await f.custody.close();assert.equal(await f.custody.cleanup(),true);
  assert.equal(f.custody.cleanupPending(),false);
  assert(f.events.indexOf('capacity')<f.events.indexOf('parent-close'));
  assert.equal(f.persistCalls(),2);
});


test('enclosing close awaits the same unfinished publication before retiring its original borrow',async()=>{
  const f=fixture({publicationSuccess:true,deferPublication:true});
  const preparing=f.succeed().then(value=>({value}),error=>({error}));
  await f.preparationEntered;
  const closing=f.custody.close();
  await new Promise(resolve=>setImmediate(resolve));
  assert(!f.events.includes('binding'));assert(!f.events.includes('parent-close'));assert(!f.events.includes('source'));
  f.releasePreparation();
  const result=await preparing;assert.equal(result.error?.message,'InstalledEffectModelPublicationRetired');
  await closing;assert.equal(await f.custody.cleanup(),true);
  assert.equal(f.persistCalls(),2);assert(!f.events.includes('commit'),'close cannot start another private write');
  assert.equal(f.events.filter(event=>event==='parent-close').length,1);
});

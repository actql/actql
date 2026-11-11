import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {withOriginalInferModelObservation} from './infer-effect-observation.mjs';

// Actual publication functions with explicit typed Core/Store-plan ports.
// No runtime source overlay, installed package, real Model or authority claim.
const text=readFileSync(new URL('./local-values-plan.mjs',import.meta.url),'utf8');
const declarations=parse(text,{ecmaVersion:'latest',sourceType:'module'}).body;
const body=name=>{
  const node=declarations.find(node=>node.declaration?.id?.name===name)?.declaration;
  assert.ok(node);return text.slice(node.start,node.end);
};
const limits={maxWireBytes:16384,maxNodes:1024,maxDepth:20};
function fixture({inline=true,projectionFailure,sourceCount=2,upstreamWhole=false,unitFailure}={}) {
  const events=[],issued={binding:{}},modelOriginal={unit:inline?0:sourceCount},scan={},receipt={};
  const retention={wire:'{"effective_retention_policy_cid":"retention","effective_data_policy_cid":"combined"}'};
  const sourceObjects=Array.from({length:sourceCount},()=>({}));
  const sources=sourceObjects.map((original,index)=>({sourceEvidence:{original},captured:{
    ...(inline||upstreamWhole?{inputKind:'whole-input',wholeCapacity:{}}:{requirement:{}}),
    occurrence:{stage:inline?0:index,input:index,task:index},
    identity:{index},logicalInput:{},checkedSource:{sourceDataPolicyCid:'source-policy-'+index},
    capture:{source:()=>original},
  }}));
  const ok=_0=>({$tag:1,_0});
  const moon={
    clientProgramEffectPublicationDataPolicyCid:()=> 'combined',
    clientProgramEffectDefinitionCid:()=> 'program',
    clientProgramEffectCompilationResultNames:()=>['updates'],
    clientProgramCapturedSourceLogicalCid:identity=>'logical-'+identity.index,
    clientProgramCapturedSourceSchemaCid:identity=>'schema-'+identity.index,
    clientProgramCapturedSourceDependencyBodies:()=>({_0:'{"rows":[]}',_1:'{"fields":[]}'}),
    clientProgramEffectPublicationPolicyBodies:()=>ok([]),
    clientProgramReleaseInferInvocationBinding:binding=>{
      assert.strictEqual(binding,issued.binding);events.push('release-binding');
    },
    clientProgramInferModelIdentityStartCapacity:()=>({_0:3n,_1:4n}),
    clientProgramInferModelIdentityStart:()=>{events.push('scan-start');return ok(scan);},
    clientProgramInferModelIdentityNextCapacity:()=>({_0:3n,_1:4n}),
    clientProgramInferModelIdentityAdvance:()=>ok({_0:true,_1:1}),
    clientProgramInferModelIdentityFinish:()=>ok(receipt),
    clientProgramInferModelIdentityCancel:original=>{
      assert.strictEqual(original,scan);events.push('cancel-scan');return true;
    },
    clientProgramInferModelIdentityReceiptCancel:original=>{
      assert.strictEqual(original,receipt);events.push('cancel-receipt');
    },
    clientProgramInferModelObservationCapacity:()=>({_0:5n,_1:6n}),
  };
  const control={
    checkedClientEffectInferInvocation(prepared,compilation,definition,actual) {
      assert.strictEqual(actual,issued);events.push('same-invocation');
      return {invocation:{},observation:{},owner:{}};
    },
    captureCheckedClientInferModelObservation(actual,originalScan,originalReceipt) {
      assert.strictEqual(actual,issued);assert.strictEqual(originalScan,scan);
      assert.strictEqual(originalReceipt,receipt);events.push('original-model');
      if(projectionFailure!==undefined)throw projectionFailure;
      return modelOriginal;
    },
    admitRunEvidence(){assert.fail('Transferred Source evidence is not readmitted');},
    seal(name,wire) {
      assert.equal(inline||upstreamWhole,false,'Whole input retention is issued by its typed Core owner');
      assert.equal(name,'result_retention_policy');events.push('source-retention');return {wire};
    },
    issueCheckedAcquiredEffectEvidence(...args) {
      assert.equal(inline,false,'Whole Model contributions never enter Query-only evidence');
      const unit=args[10];events.push('source-unit-'+unit);
      return {invocation:{},catalogBodies:[]};
    },
    issueCheckedWholeEffectSourceUnit(plan,prepared,request,slot,captured,identity,capacity,input,observation,scope,actualRetention,actualLimits) {
      assert.strictEqual(plan,sourcePlan);assert.strictEqual(prepared,acquired.prepared);
      assert.strictEqual(request,acquired.requestIdentity);
      const source=sources[slot];
      assert.strictEqual(captured,sourceObjects[slot]);assert.strictEqual(identity,source.captured.identity);
      assert.strictEqual(capacity,source.captured.wholeCapacity);assert.strictEqual(input,source.captured.logicalInput);
      assert.strictEqual(observation,source.sourceEvidence);assert.equal(scope,'authority');
      assert.strictEqual(actualRetention,retention);assert.strictEqual(actualLimits,limits);
      events.push('whole-unit-'+slot);
      if(unitFailure!==undefined)throw unitFailure;
      return {invocation:{},catalogBodies:[]};
    },
  };
  const sourcePlan={};
  const acquired={moon,control,prepared:{},requestIdentity:{},compilation:{},admission:{},
    definition:{},runDefinition:{wire:'{"created_at":"2026-11-11T00:00:00Z","valid_until":"2026-11-12T00:00:00Z"}'},
    compiledPlan:{identity:'compiled-plan'},authorityScopeCid:'authority',namespaceId:'namespace',
    storeAuthorityCid:'store',now:()=> '2026-11-11T00:00:00Z'};
  const operation={
    bindIssuedInvocation(){events.push('bind');return issued;},
    growOriginalPublicationCapacity(){events.push('grow');},
  };
  const buildLocalPublicationPlan=()=>{
    events.push('plan');return {plan:{},retention,retentionDependencies:[]};
  };
  const create=new Function('runtimeField','runtimeOptionalField','checked','limits',
    'withOriginalInferModelObservation','buildLocalPublicationPlan',
    body('acquiredMultiEffectPublicationPlan')+'\n'+body('acquiredInferEffectPublicationPlan')+
      '\nreturn {acquiredMultiEffectPublicationPlan,acquiredInferEffectPublicationPlan};');
  const functions=create(runtimeField,runtimeOptionalField,checked,limits,
    withOriginalInferModelObservation,buildLocalPublicationPlan);
  const invoke=()=>functions.acquiredInferEffectPublicationPlan({acquired,sources,
    compiled:{},operation,issuance:{},modelEvidence:[],sourcePlan});
  return {events,issued,modelOriginal,functions,acquired,sources,invoke,sourcePlan,operation};
}

test('upstream Whole Units use the same Plan and original capture tuple without Query conversion',async()=>{
  const f=fixture({inline:false,upstreamWhole:true}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[2],f.modelOriginal);
  assert.equal(context.acquiredEvidenceByUnit.length,2);
  assert.deepEqual(f.events.filter(value=>value.startsWith('whole-unit-')),['whole-unit-0','whole-unit-1']);
  assert.equal(f.events.filter(value=>value==='source-retention').length,0);
  assert.equal(f.events.filter(value=>value.startsWith('source-unit-')).length,0);
  assert.equal(f.events.includes('release-binding'),false);
});

test('a missing original Whole Plan cannot fall back to the Query-only issuer',async()=>{
  const f=fixture({inline:false,upstreamWhole:true});
  await assert.rejects(f.functions.acquiredInferEffectPublicationPlan({acquired:f.acquired,sources:f.sources,
    compiled:{},operation:f.operation,issuance:{},modelEvidence:[]}),/WholeEffectProducerUnitOriginalRequired/);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
  assert.equal(f.events.filter(value=>value.startsWith('whole-unit-')||value.startsWith('source-unit-')).length,0);
});

test('Whole producer refusal preserves the exact checked cause and releases only its Model binding',async()=>{
  const failure=new Error('OriginalWholeCaptureForeign'),f=fixture({inline:false,upstreamWhole:true,unitFailure:failure});
  await assert.rejects(f.invoke(),error=>error===failure);
  assert.deepEqual(f.events.filter(value=>value.startsWith('whole-unit-')),['whole-unit-0']);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
  assert.equal(f.events.filter(value=>value.startsWith('source-unit-')).length,0);
});

test('two Whole contributions cannot be relabeled as separate complete evidence for one upstream Unit',async()=>{
  const f=fixture({inline:false,upstreamWhole:true});f.sources[1].captured.occurrence.stage=0;
  await assert.rejects(f.invoke(),/DuplicateEffectProducerUnitEvidence/);
  assert.deepEqual(f.events.filter(value=>value.startsWith('whole-unit-')),['whole-unit-0']);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
});

test('inline Whole sources retain same issued Model and bypass Query-only evidence or duplicate retention issuance',async()=>{
  const f=fixture(),publication=await f.invoke();
  assert.strictEqual(publication.binding,f.issued.binding);
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[0],f.modelOriginal);
  assert.deepEqual(context.acquiredEvidenceByUnit,[]);
  assert.equal(context.acquisitionDependencies.length,4);
  assert.equal(f.events.filter(value=>value==='bind').length,1);
  assert.equal(f.events.filter(value=>value==='original-model').length,1);
  assert.equal(f.events.includes('release-binding'),false,'capture custody retains successful binding');
});

test('upstream Query Units remain distinct while original Model Unit waits for its checked import closure',async()=>{
  const f=fixture({inline:false}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[2],f.modelOriginal);
  assert.equal(context.acquiredEvidenceByUnit.length,2);
  assert.deepEqual(f.events.filter(value=>value.startsWith('source-unit-')),['source-unit-0','source-unit-1']);
  assert.equal(f.events.filter(value=>value==='source-retention').length,2);
});

test('three inline Whole occurrences retain the same original Model context without Query conversion',async()=>{
  const f=fixture({sourceCount:3}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[0],f.modelOriginal);
  assert.deepEqual(context.acquiredEvidenceByUnit,[]);
  assert.equal(context.acquisitionDependencies.length,6);
  assert.equal(f.events.filter(value=>value==='original-model').length,1);
  assert.equal(f.events.filter(value=>value==='same-invocation').length,1);
});

test('three Query producer Units preserve their exact coordinates before Model Unit three',async()=>{
  const f=fixture({inline:false,sourceCount:3}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[3],f.modelOriginal);
  assert.equal(context.acquiredEvidenceByUnit.length,3);
  assert.deepEqual(f.events.filter(value=>value.startsWith('source-unit-')),
    ['source-unit-0','source-unit-1','source-unit-2']);
  assert.equal(f.events.filter(value=>value==='source-retention').length,3);
});

test('Model projection refusal keeps original cause and releases same binding after original scan cleanup',async()=>{
  const failure=Object.freeze(new Error('OriginalProjectionRefused'));
  const f=fixture({projectionFailure:failure});
  await assert.rejects(f.invoke(),error=>error===failure);
  assert.deepEqual(f.events.slice(-3),['cancel-receipt','cancel-scan','release-binding']);
  assert.equal(f.events.includes('plan'),false);
});

test('Whole Source Unit runtime facade forwards the original typed tuple and registers only the issued dependency',()=>{
  const text=readFileSync(new URL('../host-common/runtime-core.mjs',import.meta.url),'utf8');
  let method;
  (function walk(node){
    if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.key?.name==='issueCheckedWholeEffectSourceUnit'){
      assert.equal(method,undefined);method=node;
    }
    for(const value of Object.values(node))for(const child of Array.isArray(value)?value:[value])walk(child);
  })(parse(text,{ecmaVersion:'latest',sourceType:'module'}));
  assert(method);
  const plan={},prepared={},request={},captured={},identity={},capacity={},input={},observation={},retention={};
  const rawObservation={},rawRetention={},issued={},projected={},tokens=new WeakMap(),calls=[];
  const ports={issuanceLimits(actual,label){assert.strictEqual(actual,limits);assert.equal(label,'Whole Effect Source Unit');},
    checked,evidenceToken(actual){assert.strictEqual(actual,observation);return rawObservation;},
    token(actual){assert.strictEqual(actual,retention);return rawRetention;},
    inspectAcquiredEffectEvidence(actual,original,bounds){
      assert.strictEqual(actual,issued);assert.strictEqual(original,retention);assert.strictEqual(bounds,limits);return projected;
    },localEffectDependencyTokens:tokens,
    moon:{clientProgramIssueInstalledWholeEffectSourceUnit(...args){calls.push(args);return {$tag:1,_0:issued};}}};
  const invoke=new Function(...Object.keys(ports),`return ({${text.slice(method.start,method.end)}}).issueCheckedWholeEffectSourceUnit;`)(...Object.values(ports));
  assert.strictEqual(invoke(plan,prepared,request,2,captured,identity,capacity,input,observation,'authority',retention,limits),projected);
  assert.deepEqual(calls,[[plan,prepared,request,2,captured,identity,capacity,input,rawObservation,'authority',rawRetention,16384,1024,20]]);
  assert.deepEqual(tokens.get(projected),{kind:'acquired',issued});
  assert.throws(()=>invoke(plan,prepared,request,-1,captured,identity,capacity,input,observation,'authority',retention,limits),/Invalid acquired Effect Source slot/);
  assert.equal(calls.length,1);
});

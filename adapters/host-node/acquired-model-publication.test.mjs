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
function fixture({inline=true,projectionFailure,sourceCount=2}={}) {
  const events=[],issued={binding:{}},modelOriginal={unit:inline?0:sourceCount},scan={},receipt={};
  const retention={wire:'{"effective_retention_policy_cid":"retention","effective_data_policy_cid":"combined"}'};
  const sourceObjects=Array.from({length:sourceCount},()=>({}));
  const sources=sourceObjects.map((original,index)=>({sourceEvidence:{original},captured:{
    ...(inline?{inputKind:'whole-input',wholeCapacity:{}}:{requirement:{}}),
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
      assert.equal(inline,false,'inline Model retention is issued once by its typed Core owner');
      assert.equal(name,'result_retention_policy');events.push('source-retention');return {wire};
    },
    issueCheckedAcquiredEffectEvidence(...args) {
      assert.equal(inline,false,'Whole Model contributions never enter Query-only evidence');
      const unit=args[10];events.push('source-unit-'+unit);
      return {invocation:{},catalogBodies:[]};
    },
  };
  const acquired={moon,control,prepared:{},compilation:{},admission:{},
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
    compiled:{},operation,issuance:{},modelEvidence:[]});
  return {events,issued,modelOriginal,functions,acquired,sources,invoke};
}

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

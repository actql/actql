// Actual private scheduling/projection code with explicit Core ports. Genuine
// 4097-member numeric construction is executed separately by the Core cases.
import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from './runtime-core.mjs';
import {preparePinnedEffectSourceSet} from '../host-node/effect-input-export.mjs';
const ok=value=>({$tag:1,_0:value});
function fixture() {
  const issued={},source={},calls=[];
  let refusal;
  const moon={
    strategyRemoteManagedOutputEvidenceKind:()=> 'fixture metadata',
    strategyPublicationAdmit:(name,wire)=>ok({name,wire,identity:'sha256:'+'1'.repeat(64)}),
    strategyPublicationContractName:v=>v.name,strategyPublicationContractIdentityField:()=> 'cid',
    strategyPublicationContractIdentity:v=>v.identity,strategyPublicationContractJson:v=>v.wire,
    strategyRunEvidenceAdmit:(name,wire)=>ok({name,wire,identity:'sha256:'+'2'.repeat(64)}),
    strategyRunEvidenceName:v=>v.name,strategyRunEvidenceIdentity:v=>v.identity,strategyRunEvidenceJson:v=>v.wire,
    clientProgramIssueAcquiredEffectEvidence(){calls.push('issuer');return refusal===undefined?ok(issued):{$tag:0,_0:refusal};},
    clientProgramIssueInstalledWholeEffectSourceUnit(){calls.push('whole-issuer');return refusal===undefined?ok(issued):{$tag:0,_0:refusal};},
    clientProgramAcquiredEffectInvocation:()=>({}),clientProgramAcquiredEffectDependencyBodies:()=>[],
    clientProgramAcquiredEffectCatalogBodies(){calls.push('legacy-catalog');return ok([]);},
  };
  const control=runtimeCore(moon).publicationControl;
  const limits={maxWireBytes:1000000,maxNodes:100000,maxDepth:64};
  const retention=control.admit('result_retention_policy','{}',limits);
  const observation=control.admitRunEvidence('source_evidence','{}',limits);
  return {calls,refuse(value){refusal=value;},
    query(defer=false){return control.issueCheckedAcquiredEffectEvidence({},source,{},{},{},observation,'scope','policy',retention,limits,0,retention,defer);},
    whole(defer=false){return control.issueCheckedWholeEffectSourceUnit({}, {}, {}, 0, source, {}, {}, {}, observation,'scope',retention,limits,defer);}};
}

test('registered Query and Whole scheduling preserves typed issuers and defers only Catalog wires',()=>{
  const f=fixture();
  for(const value of [f.query(true),f.whole(true)]) {
    assert.equal(value.catalogDeferred,true);assert.deepEqual(value.catalogBodies,[]);
  }
  assert.deepEqual(f.calls,['issuer','whole-issuer']);
  const primary=new Error('OriginalSourceRefused');f.refuse(primary);
  assert.throws(()=>f.query(true),error=>error.code==='MoonBitHostFailure'&&error.cause===primary);
  assert.deepEqual(f.calls,['issuer','whole-issuer','issuer']);
});

test('unmanaged default still performs eager legacy Catalog lookup',()=>{
  const f=fixture();
  assert.equal(f.query().catalogDeferred,undefined);
  assert.deepEqual(f.calls,['issuer','legacy-catalog']);
});

test('deferred Catalog without an actual late provider refuses before inputs or export',async()=>{
  let inspected=0;
  await assert.rejects(preparePinnedEffectSourceSet({moon:{clientProgramEffectInputCount(){inspected++;}},
    localEvidenceContext:{catalogDeferred:true}}),/MissingOriginalCatalogConstruction/);
  assert.equal(inspected,0);
});

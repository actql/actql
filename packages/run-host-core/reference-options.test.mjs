import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {admitEnvironment,prepare,sourceEvidenceFacts,prepareEffect,compileEffect,
  effectSourceEvidenceFacts} from './index.mjs';
import {createJournal,prepareDispatch,prepareIntent,admissionDurableJson,
  admitDurableJson,acceptedSiteOutput,acceptedSourceObservation} from '../coordinator-core/index.mjs';
import {residentSourceEnvironment,sourceProgram,sourceRef,sourceContractCid} from
  '../../scripts/fixtures/resident-source.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const cid=digit=>'sha256:'+digit.repeat(64);
function emptyDurable() {
  const request=prepareDispatch({coordinatorAuthority:'coordinator-a',
    runDefinitionCid:cid('0'),taskKey:'task-a',taskAttempt:1,
    dispatchId:'option-dispatch',siteKey:'site-a',siteGeneration:1,
    runtimeBundleCid:cid('a'),connectorRegistration:'local',connectorRevision:'local/1',
    strategyRevision:'strategy/1',inputBindingCid:cid('1'),obligationsCid:cid('2'),
    budgetCid:cid('3'),evidenceIssuerCapabilityCid:cid('b'),grantCid:cid('4')});
  return admitDurableJson(admissionDurableJson(prepareIntent(createJournal('coordinator-a'),request)));
}

test('actual Run Host reference Option preserves Source fields and absence',async()=>{
  const fixture=await residentSourceEnvironment(root);
  const environment=admitEnvironment(fixture.wire,fixture.cid,{rela:true});
  const prepared=prepare(sourceProgram,'json',environment);
  const facts=sourceEvidenceFacts(prepared,0,0);
  assert.equal(facts.sourceRef,sourceRef);
  assert.equal(facts.sourceContractCid,sourceContractCid);
  assert.equal(facts.sourceDataPolicyCid,'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf');
  assert.equal(sourceEvidenceFacts(prepared,1,0),undefined);
  assert(Object.isFrozen(facts));
  assert.throws(()=>sourceEvidenceFacts({...prepared},0,0),/ForeignRunHostHandle/u);
});

test('actual Effect reference Option keeps its original compilation binding',()=>{
  const read=name=>readFileSync(new URL('./fixtures/'+name,import.meta.url),'utf8').trimEnd();
  const wire=read('source-compute-effect.environment.json');
  const environment=admitEnvironment(wire,JSON.parse(wire).evidence_bundle_cid,{rela:true});
  const prepared=prepareEffect(read('source-compute-effect.program.json'),'json',environment);
  const compilation=compileEffect(prepared);
  const view=JSON.parse(wire).connector_catalogs[0].source_views[0];
  assert.deepEqual(effectSourceEvidenceFacts(prepared,compilation,0,0),{
    sourceRef:'connector://crm/main/r#v',sourceContractCid:view.contract_cid,
    sourceViewContractCid:view.contract_cid,carrierSchemaContractCid:view.output.schema.cid,
    sourceDataPolicyCid:view.output.data_policy.cid,dataClassification:'unknown'});
  assert.equal(effectSourceEvidenceFacts(prepared,compilation,1,0),undefined);
  assert.throws(()=>effectSourceEvidenceFacts({...prepared},compilation,0,0),/ForeignRunHostHandle/u);
});

test('actual Coordinator Result of reference Option keeps absent Site output absent',()=>{
  assert.equal(acceptedSiteOutput(emptyDurable()),undefined);
});

test('actual Coordinator direct reference Option keeps absent Source observation absent',()=>{
  assert.equal(acceptedSourceObservation(emptyDurable()),undefined);
});

import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import * as coordinator from './index.mjs';
import {runtimeCore} from '../../adapters/host-common/runtime-core.mjs';
import {durableOutputRecordFixture} from '../../scripts/fixtures/remote-output-record-fixture.mjs';

// The caller must prepare this exact real target or supply a qualified retained
// artifact. No mock, fallback runtime or skipped-success path is available.
const path=process.env.ACTQL_BINDING_TEST_BRIDGE;
if(!path)throw new Error('Prepare the actual connectors_builtin_node JS target and set ACTQL_BINDING_TEST_BRIDGE');
const expected=process.env.ACTQL_BINDING_TEST_BRIDGE_SHA256;
if(!expected||createHash('sha256').update(readFileSync(path)).digest('hex')!==expected){
  throw new Error('Actual binding test artifact digest mismatch');
}
const bridge=await import(pathToFileURL(path).href);

test('actual Coordinator boxed Some preserves the original admitted output and request',()=>{
  const original=durableOutputRecordFixture(coordinator,runtimeCore(bridge));
  const facts=coordinator.acceptedSiteOutput(original.durable);
  assert.equal(facts.dispatchRequestCid,original.requestCid);
  assert.equal(facts.rowCount,'2');
  assert.equal(facts.retainedBytes,'12');
  assert(Object.isFrozen(facts));
  assert.deepEqual(coordinator.acceptedSiteOutput(original.outputDurable),facts);
  const foreign=coordinator.prepareDispatch({coordinatorAuthority:'coordinator-a',
    runDefinitionCid:'sha256:'+'0'.repeat(64),taskKey:'task-a',taskAttempt:1,
    dispatchId:'different-original-dispatch',siteKey:'site-a',siteGeneration:1,
    runtimeBundleCid:'sha256:'+'a'.repeat(64),connectorRegistration:'local',connectorRevision:'local/1',
    strategyRevision:'strategy/1',inputBindingCid:'sha256:'+'1'.repeat(64),
    obligationsCid:'sha256:'+'2'.repeat(64),budgetCid:'sha256:'+'3'.repeat(64),
    evidenceIssuerCapabilityCid:'sha256:'+'b'.repeat(64),grantCid:'sha256:'+'4'.repeat(64)});
  assert.throws(()=>coordinator.admitResponseJson(original.reply,foreign,true),
    {code:'CoordinatorOwnerRejected'});
  assert.deepEqual(coordinator.acceptedSiteOutput(original.durable),facts);
});

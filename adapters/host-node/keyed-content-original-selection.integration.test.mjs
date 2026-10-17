// Actual Common original matcher, encrypted Store and installed consumer Host.
// The producer Run/candidate/funding ports below are explicit control fixtures;
// they are not genuine keyed Source admission, a byte loan or a normal profile.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture, generatedContentFixtureControl}
  from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';

async function fixture(t, {matcher = moon.clientProgramEffectCommandContentMatchesIssued} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'keyed-original-selection-', label: 'Original keyed Content reference selection'});
  const generated = await createGeneratedContentFixture(t);
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  const compiled = {}, preparedProgram = {}, acquisition = {}, ledger = {}, reservation = {};
  let execution, issued, releases = 0, matcherCalls = 0;
  const counters = {matches: () => matcherCalls, releases: () => releases};
  const control = {...generatedContentFixtureControl,
    reserveWorkspace(original) { assert.equal(original, ledger); return reservation; },
    releaseWorkspace(original, value) {
      assert.equal(original, ledger); assert.equal(value, reservation); releases++;
    },
    recoveryCandidateForRun(original, definition, originalAcquisition, wire) {
      assert.equal(original, compiled); assert.equal(originalAcquisition, acquisition);
      assert.equal(definition, plan.runDefinition);
      assert.equal(wire, generated.description.wire);
      return generated.candidate;
    },
    holdingCid(value) { assert.equal(value, generated.candidate); return generated.holding.holding_cid; },
    reissuer(resolve) { return moon.clientProgramCapturedContentReissuer(resolve); },
    issue(...args) {
      issued = generatedContentFixtureControl.issue(...args);
      return issued;
    },
  };
  const plan = {compiled, runDefinition: {identity: generated.description.identity,
    wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'}};
  const fixtureMoon = {...moon,
    clientProgramKeyedAcquisitionMatchesProgram: () => true,
    clientProgramKeyedAcquisitionSourceEvidenceFacts: () => ({$tag: 1,
      _0: ['explicit producer fixture', generated.description.identity, generated.description.identity,
        generated.description.effectiveDataPolicyCid, 'internal', generated.description.identity]}),
    clientProgramKeyedLookupCapacity: () => ({_1: 1}),
    clientProgramEffectCommandContentMatchesIssued: matcher === undefined ? undefined : (...args) => {
      matcherCalls++; return matcher(...args);
    },
  };
  const owner = installRunKeyedContentCapture({moon: fixtureMoon,
    publications: {checkClientCompiledRunOwner() {}, checkClientCompiledRunDefinition() {}},
    control, preparedProgram, plan, acquisition, ledger, maxBytes: 4096, maxWork: 1000,
    store: generated.store, namespaceId: 'fixture',
    authorityScopeCid: generated.description.workspaceScopeCid,
    storeAuthorityCid: generated.description.storeCid,
    principalId: 'fixture', ownerPrincipal: 'fixture', now: () => '2026-10-17T00:00:00.000Z',
    authorize: () => true, retainExecution(value) { execution = value; }});
  t.after(async () => { assert.equal(await execution.cleanup(), true); });
  const recover = () => owner.recover({keyedAcquisition: acquisition,
    verifyRead: async () => {}, referenceWire: generated.description.wire,
    captureAuthorityCid: generated.binding.capture_authority_cid});
  assert.equal(owner.issuedForContent(undefined), undefined);
  await recover();
  return {scratch, generated, owner, issued: () => issued, recover, counters,
    execution: () => execution};
}

async function runAtPreparation(t, f, value, inspect) {
  let failure, preparations = 0;
  const host = await openContentCommandHost({scratch: f.scratch, generated: f.generated,
    originalContentValue: value, keys: generateKeyPairSync('ed25519'), entrance: 'Local',
    onPrepareContent({originalContent}) {
      preparations++;
      try { inspect(originalContent('content')); } catch (error) { failure = error; throw error; }
    }});
  t.after(host.close);
  const run = await host.client.start(host.fixture.program);
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  if (failure !== undefined) throw failure;
  assert.equal(state.status, 'waiting_checkpoint');
  assert.equal(preparations, 1);
  assert.equal(host.reads(), 1);
  assert.equal(host.sends(), 0, 'original selection issues no dispatch or read permission');
  await host.close();
}

test('keyed inventory selects only the same actual issued Command Content original', async t => {
  const f = await fixture(t);
  const issued = f.issued();
  let borrowed;
  await runAtPreparation(t, f, issued, view => {
    borrowed = view;
    assert.strictEqual(f.owner.issuedForContent(view.binding), issued);
    assert.strictEqual(f.owner.issuedForContent(view.binding), issued);
    assert.equal(f.owner.issuedForContent({...view.binding}), undefined,
      'copied opaque fields do not recreate the original consumer view');
    assert.equal(f.owner.issuedForContent({binding: view.binding,
      matchesIssued: () => true}), undefined, 'caller matching callbacks are not consulted');
    assert.equal(view.current(), true);
  });
  assert.equal(f.owner.issuedForContent(borrowed.binding), undefined, 'consumer retirement refuses');
  assert.ok(f.counters.matches() >= 3);
  assert.equal(f.generated.store.status().storedBytes, 3);
  await f.execution().cleanup();
  assert.equal(f.counters.releases(), 1);
  await f.generated.store.retirePhysicalHolding(f.generated.holding.holding_cid);
  f.scratch.passed();
});

test('keyed inventory refuses an equal-wire reference from another actual issuance', async t => {
  const f = await fixture(t);
  const equalWire = await f.generated.issue();
  assert.notStrictEqual(equalWire, f.issued());
  await runAtPreparation(t, f, equalWire, view => {
    assert.equal(view.matchesIssued(equalWire), true);
    assert.equal(view.matchesIssued(f.issued()), false);
    assert.equal(f.owner.issuedForContent(view.binding), undefined);
  });
  assert.equal(f.generated.store.status().storedBytes, 3);
  await f.execution().cleanup();
  await f.generated.store.retirePhysicalHolding(f.generated.holding.holding_cid);
  f.scratch.passed();
});

test('keyed inventory refences original custody after an explicit matcher-return cleanup control', async t => {
  let cleanup, cleanupFlight, observed = 0;
  const f = await fixture(t, {matcher(binding, issued) {
    const matched = moon.clientProgramEffectCommandContentMatchesIssued(binding, issued);
    if (matched && cleanup !== undefined) {
      observed++;
      cleanupFlight = cleanup();
    }
    return matched;
  }});
  cleanup = () => f.execution().cleanup();
  await runAtPreparation(t, f, f.issued(), view => {
    assert.equal(view.matchesIssued(f.issued()), true);
    assert.equal(f.owner.issuedForContent(view.binding), undefined,
      'a prior real Core match cannot export a Source whose cleanup has started');
    assert.equal(f.execution().cleanupPending(), true);
  });
  assert.equal(observed, 1);
  assert.equal(await cleanupFlight, true);
  assert.equal(f.counters.releases(), 1);
  assert.equal(f.generated.store.status().storedBytes, 3,
    'Source alias retirement neither retires bytes nor acknowledges a physical loan');
  await f.generated.store.retirePhysicalHolding(f.generated.holding.holding_cid);
  f.scratch.passed();
});

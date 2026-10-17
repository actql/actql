// Actual Common candidate/Reference/consumer and encrypted Store. Family
// scheduling, evidence and admission are explicit controls, not a genuine
// SERIALIZE Effect preparation, selected physical allocation or installed loan.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture, generatedContentFixtureControl}
  from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {installEffectContentFamily} from './installed-content-family.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

async function fixture(t, {restored = false, omitRestoredOriginal = false, afterMatch, failCompletion} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'generated-original-selection-', label: 'Generated Content original selection'});
  const generatedCleanups = [];
  let owner, holdingCid;
  const generated = await createGeneratedContentFixture({after: fn => generatedCleanups.push(fn)});
  t.after(async () => {
    // Drain this same family's temporary duties before the fixture Store closes.
    if (owner !== undefined) assert.equal(await owner.cleanup(), true);
    if (holdingCid !== undefined) await generated.store.retirePhysicalHolding(holdingCid);
    for (const close of generatedCleanups) await close();
  });
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  const prepared = {}, compiled = {}, step = {}, input = {}, receipt = {};
  const generation = {}, completion = {}, evidence = {};
  let port, issued, original;
  holdingCid = restored ? generated.holding.holding_cid : cid('family original byte holding');
  if (restored) {
    issued = await generated.issue({retainOriginal: value => { original = value; }});
  }
  const plan = {compiled, serializationGraph: {}, runDefinition: {
    identity: cid('controlled family Run'), wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'}};
  const control = {...generatedContentFixtureControl,
    effectFamily(originalPrepared, graph, _bodies, _limits, value, activate, retainedCompletion) {
      assert.equal(originalPrepared, prepared);
      assert.equal(graph, plan.serializationGraph);
      assert.equal(retainedCompletion, restored ? completion : undefined);
      port = value;
      if (!restored) assert.equal(activate(step), true);
      return {};
    },
    familyPendingPiece(value) { assert.equal(value, step); return {piece: 'id\n', revision: 1}; },
    familyAcknowledgePiece(value, revision) { assert.equal(value, step); assert.equal(revision, 1); return true; },
    familyInput(value) { assert.equal(value, step); return {input, receipt, encoder: generated.encoder}; },
    familyByteCompletion(value) {
      assert.equal(value, step);
      return {contentCid: generated.description.contentCid};
    },
    issue(...args) {
      issued = generatedContentFixtureControl.issue(...args);
      return issued;
    },
    familyComplete(originalCompiled, definition, value, inputEvidence, candidate, content) {
      assert.equal(originalCompiled, compiled); assert.equal(definition, plan.runDefinition);
      assert.equal(value, step); assert.equal(inputEvidence, evidence);
      assert.equal(candidate, generated.candidate); assert.equal(content, issued);
      if (failCompletion !== undefined) throw failCompletion;
      return generation;
    },
    candidate(encoder, binding) {
      assert.equal(encoder, generated.encoder); assert.deepEqual(binding, generated.binding);
      return generated.candidate;
    },
  };
  owner = installEffectContentFamily({
    moon: {...moon, clientProgramEffectCommandContentMatchesIssued(binding, value) {
      const result = moon.clientProgramEffectCommandContentMatchesIssued(binding, value);
      afterMatch?.({result, owner, port});
      return result;
    }}, control, publications: {
      bindCheckedClientSerializationCapture() { return {}; },
      bindCheckedClientSerializationInputIdentity() { return evidence; },
      checkedClientSerializationByteHoldingCid() { return holdingCid; },
      exportCheckedClientContentGenerationOutput() { return completion; },
      checkedClientSerializationRecoveryBindings() { return []; },
    }, bodies: {}, prepared, plan, store: generated.store,
    principalId: 'fixture', ownerPrincipal: 'fixture', now: () => '2026-10-17T00:00:00.000Z',
    authorize: () => true, namespaceId: 'fixture',
    authorityScopeCid: generated.description.workspaceScopeCid,
    storeAuthorityCid: generated.description.storeCid,
    installedBinding: () => ({graphPolicy: {cid: generated.description.effectiveDataPolicyCid},
      binding: generated.binding}),
    referenceLimits: {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxTextUnits: 4096},
    completionLimits: {}, outputLimits: {maxColumns: 2},
    ...(restored ? {restored: {generation, completion, recovery: {},
      ...(omitRestoredOriginal ? {} : {storedOriginal: original})}} : {}),
  });
  owner.bindCapture({}, {});
  assert.equal(owner.storageForContent(undefined), undefined);
  const generate = async () => {
    await owner.handlePause({status: 'settling', slot: 0});
    await owner.handlePause({status: 'settling', slot: 1});
  };
  return {scratch, generated, owner, generate, issued: () => issued, holdingCid, generation};
}

async function withConsumer(t, f, issued, inspect, expectedStatus = 'waiting_checkpoint') {
  let failure;
  const host = await openContentCommandHost({scratch: f.scratch, generated: f.generated,
    originalContentValue: issued, keys: generateKeyPairSync('ed25519'), entrance: 'Local',
    onPrepareContent({originalContent}) {
      try { inspect(originalContent('content')); } catch (error) { failure = error; throw error; }
    }});
  t.after(host.close);
  const run = await host.client.start(host.fixture.program);
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  if (failure !== undefined) throw failure;
  assert.equal(state.status, expectedStatus);
  assert.equal(host.reads(), 1);
  assert.equal(host.sends(), 0);
  await host.close();
}

for (const restored of [false, true]) {
  test(`generated family selects the same confirmed original after ${restored ? 'original restoration' : 'temporary generation cleanup'}`, async t => {
    const f = await fixture(t, {restored});
    if (!restored) {
      assert.equal(f.owner.generation(), undefined);
      await f.generate();
      assert.equal(f.owner.cleanupPending(), false, 'temporary cleanup is not durable Content retirement');
    }
    assert.equal(f.owner.generation(), f.generation);
    let stored, view;
    await withConsumer(t, f, f.issued(), value => {
      view = value;
      assert.strictEqual(f.owner.issuedForContent(value.binding), f.issued());
      stored = f.owner.storageForContent(value.binding);
      assert.ok(Object.isFrozen(stored));
      assert.strictEqual(stored.issued, f.issued());
      assert.strictEqual(stored.candidate, f.generated.candidate);
      assert.equal(stored.holding.holding_cid, f.holdingCid);
      assert.equal(stored.holding.objects[0].cid, f.generated.description.contentCid);
      assert.equal(f.owner.storageCurrentForContent(stored, value.binding), true);
      assert.equal(f.owner.storageCurrentForContent({...stored}, value.binding), false);
      assert.equal(f.owner.storageForContent({...value.binding}), undefined);
      assert.equal(f.owner.storageForContent({matchesIssued: () => true}), undefined);
    });
    assert.equal(f.owner.storageForContent(view.binding), undefined, 'original consumer retirement refuses');
    assert.equal(f.owner.storageCurrentForContent(stored, view.binding), false);
    assert.equal(f.generated.store.status().storedBytes, 3);
    f.scratch.passed();
  });
}

test('generated family refuses an equal-wire Content from another issuance', async t => {
  const f = await fixture(t);
  await f.generate();
  const other = await f.generated.issue();
  assert.notStrictEqual(other, f.issued());
  await withConsumer(t, f, other, view => {
    assert.equal(view.matchesIssued(other), true);
    assert.equal(view.matchesIssued(f.issued()), false);
    assert.equal(f.owner.issuedForContent(view.binding), undefined);
    assert.equal(f.owner.storageForContent(view.binding), undefined);
  });
  f.scratch.passed();
});

test('restored family without the original holding receiver does not reconstruct it from recovery DATA', async t => {
  const f = await fixture(t, {restored: true, omitRestoredOriginal: true});
  await withConsumer(t, f, f.issued(), view => {
    assert.equal(f.owner.issuedForContent(view.binding), undefined);
    assert.equal(f.owner.storageForContent(view.binding), undefined);
    assert.equal(f.owner.storageCurrentForContent({}, view.binding), false);
  });
  f.scratch.passed();
});

test('generated family refences cancellation begun during the original matcher callback', async t => {
  const f = await fixture(t, {afterMatch({result, port}) { if (result) port.cancel(); }});
  await f.generate();
  await withConsumer(t, f, f.issued(), view => {
    assert.equal(f.owner.storageForContent(view.binding), undefined);
    assert.equal(f.owner.issuedForContent(view.binding), undefined);
  }, 'needs_reconciliation');
  assert.equal(f.generated.store.status().storedBytes, 3, 'cancel is not physical holding retirement');
  f.scratch.passed();
});

test('failed generation retains its original cleanup and exports no durable stored binding', async t => {
  const primary = new Error('ControlledFamilyCompletionFailure');
  const f = await fixture(t, {failCompletion: primary});
  await assert.rejects(f.generate(), error => error === primary);
  assert.equal(f.owner.generation(), undefined);
  assert.equal(f.owner.cleanupPending(), true);
  await withConsumer(t, f, f.issued(), view => {
    assert.equal(f.owner.storageForContent(view.binding), undefined);
  });
  assert.equal(await f.owner.cleanup(), true);
  assert.equal(await f.generated.store.inspectPhysicalHolding(f.holdingCid), undefined);
  assert.equal(f.generated.store.status().storedBytes, 3, 'unrelated original holding remains');
  f.scratch.passed();
});

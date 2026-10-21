// Actual Common candidate/Reference/consumer and encrypted Store. Family
// scheduling, evidence and admission are explicit controls, not a genuine
// SERIALIZE Effect preparation, selected physical allocation or installed loan.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdir, mkdtemp, stat, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture, generatedContentFixtureControl}
  from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {installEffectContentFamily} from './installed-content-family.mjs';
import {issueStoredGeneratedContent, retainGeneratedContentEvidence} from './generated-content-holding.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

async function fixture(t, {restored = false, omitRestoredOriginal = false, afterMatch,
  failCompletion, maxObjectBytes = 10000, retainCustody = false,
  familyFactory = installEffectContentFamily, afterRetained} = {}) {
  const parent = new URL('../../_build/', import.meta.url).pathname;
  await mkdir(parent, {recursive: true});
  // An intentionally unresolved custody counter must not use the ordinary
  // remove-on-passed scratch. Match the existing explicit Unknown test route.
  const scratch = retainCustody
    ? Object.freeze({path: await mkdtemp(join(parent, 'generated-original-unknown-'))})
    : await createOwnedScratch({parent, prefix: 'generated-original-selection-',
      label: 'Generated Content original selection'});
  if (retainCustody) {
    assert.equal((await stat(scratch.path)).mode & 0o777, 0o700);
    t.diagnostic(`Fresh original custody root retained on failure or Unknown: ${scratch.path}`);
  }
  const generatedCleanups = [];
  let owner, holdingCid;
  const generated = await createGeneratedContentFixture({after: fn => generatedCleanups.push(fn)},
    {directory: join(scratch.path, 'original-publication'), maxObjectBytes});
  assert.equal(generated.configuration.maxObjectBytes, maxObjectBytes);
  t.after(async () => {
    // Drain this same family's temporary duties before the fixture Store closes.
    if (owner !== undefined) assert.equal(await owner.cleanup(), true);
    if (!retainCustody && holdingCid !== undefined) await generated.store.retirePhysicalHolding(holdingCid);
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
  owner = familyFactory({
    moon: {...moon, clientProgramEffectCommandContentMatchesIssued(binding, value) {
      const result = moon.clientProgramEffectCommandContentMatchesIssued(binding, value);
      afterMatch?.({result, owner, port});
      return result;
    }}, control, publications: {
      checkedClientSerializationGenerationLimits(value, graph) {
        assert.strictEqual(value, compiled); assert.strictEqual(graph, plan.serializationGraph);
        return {maxRows: 100, maxBytes: 10000};
      },
      bindCheckedClientEffectSerializationCapture() { return {}; },
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
    ...(afterRetained === undefined ? {} : {faultInjection(name) {
      if (name === 'effect_content_generation_retained') afterRetained({owner});
    }}),
    ...(restored ? {restored: {generation, completion, recovery: {},
      ...(omitRestoredOriginal ? {} : {storedOriginal: original})}} : {}),
  });
  owner.bindCapture({}, {});
  assert.equal(owner.storageForContent(undefined), undefined);
  const generate = async () => {
    await owner.handlePause({status: 'settling', slot: 0});
    await owner.handlePause({status: 'settling', slot: 1});
  };
  return {scratch, generated, owner, generate, issued: () => issued, holdingCid, generation, retainCustody};
}

// An explicit source probe observes only whether this private alias is absent
// at cleanup's true return. It neither exposes a production getter nor treats
// GC as retirement. The original family body is otherwise unchanged; actual
// Common issuance and Store operations still execute under the fixture controls.
function cleanupAliasSourceProbe(observe) {
  const source = readFileSync(new URL('./installed-content-family.mjs', import.meta.url), 'utf8');
  const first = source.indexOf('export function installEffectContentFamily(');
  const start = source.indexOf('  const cleanup = async () => {', first);
  const end = source.indexOf('  return Object.freeze({provider,', start);
  assert.ok(first >= 0 && start > first && end > start);
  const cleanup = source.slice(start, end);
  assert.equal(cleanup.match(/\breturn true;/gu)?.length, 3);
  assert.ok(cleanup.includes('await flight.catch(() => {})'));
  const instrumented = source.slice(first, start).replace(/^export /u, '') +
    cleanup.replace(/\breturn true;/gu,
      'return (cleanupAliasObserved(storedOriginal === undefined), true);') + source.slice(end);
  return new Function('issueStoredGeneratedContent', 'retainGeneratedContentEvidence',
    'cleanupAliasObserved', `'use strict';\n${instrumented}\nreturn installEffectContentFamily;`)(
    issueStoredGeneratedContent, retainGeneratedContentEvidence, observe);
}

async function withConsumer(t, f, issued, inspect, expectedStatus = 'waiting_checkpoint') {
  let failure;
  const keys = generateKeyPairSync('ed25519');
  if (f.retainCustody) {
    // Preserve this fresh counter's original synthetic signer with its Run/DB
    // and Content holdings. No secret is logged and no old state is touched.
    await writeFile(join(f.scratch.path, 'original-test-signing-key.pem'),
      keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600, flag: 'wx'});
  }
  const host = await openContentCommandHost({scratch: f.scratch, generated: f.generated,
    originalContentValue: issued, keys, entrance: 'Local',
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
  const f = await fixture(t, {retainCustody: true,
    afterMatch({result, port}) { if (result) port.cancel(); }});
  await f.generate();
  await withConsumer(t, f, f.issued(), view => {
    assert.equal(f.owner.storageForContent(view.binding), undefined);
    assert.equal(f.owner.issuedForContent(view.binding), undefined);
  }, 'needs_reconciliation');
  assert.equal(f.generated.store.status().storedBytes, 3, 'cancel is not physical holding retirement');
  t.diagnostic(`Fresh needs-reconciliation Run/DB/key/holding retained: ${f.scratch.path}`);
});

test('explicit family close refuses new original handoffs after temporary generation cleanup', async t => {
  const f = await fixture(t, {retainCustody: true});
  await f.generate();
  assert.equal(f.owner.cleanupPending(), false);
  let closing;
  await withConsumer(t, f, f.issued(), view => {
    const original = f.owner.storageForContent(view.binding);
    assert.ok(original);
    closing = f.owner.close();
    // Temporary encoder cleanup was already acknowledged, but explicit parent
    // close must still forbid new borrowers of this original occurrence.
    assert.equal(f.owner.storageForContent(view.binding), undefined);
    assert.equal(f.owner.issuedForContent(view.binding), undefined);
    assert.equal(f.owner.storageCurrentForContent(original, view.binding), false);
  }, 'needs_reconciliation');
  assert.equal(await closing, true);
  assert.equal(await f.owner.cleanup(), true);
  assert.equal(f.generated.store.status().storedBytes, 3);
  assert.ok(await f.generated.store.inspectPhysicalHolding(f.holdingCid),
    'family close is not retirement of the original durable holding');
  t.diagnostic(`Fresh close-refused Run/DB/key/holding retained: ${f.scratch.path}`);
});

test('source probe retires the family alias when explicit close awaited the same completing flight', async t => {
  const returns = [];
  let closing;
  const f = await fixture(t, {
    familyFactory: cleanupAliasSourceProbe(absent => returns.push(absent)),
    afterRetained({owner}) { closing = owner.close(); },
  });
  await f.generate();
  assert.equal(await closing, true);
  assert.deepEqual(returns.slice(), [true], 'the post-flight cleaned return drops its own selection alias');
  assert.equal(f.owner.cleanupPending(), false);
  assert.equal(f.generated.store.status().storedBytes, 3);
  assert.ok(await f.generated.store.inspectPhysicalHolding(f.holdingCid));
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

test('the original smaller Store ceiling still refuses the family writer before acquisition', async t => {
  // The installed family declares its existing10000-byte writer before I/O.
  // The prior fixture8192 ceiling correctly refused it, even for a3-byte body.
  // Keep that real counter beside the explicitly compatible positive Store.
  const f = await fixture(t, {maxObjectBytes: 8192});
  await assert.rejects(f.generate(), {code: 'PublicationObjectLimit'});
  assert.equal(f.owner.generation(), undefined);
  assert.equal(f.generated.store.status().storedBytes, 3);
  assert.equal(await f.generated.store.inspectPhysicalHolding(f.holdingCid), undefined);
  assert.equal(await f.owner.cleanup(), true);
  f.scratch.passed();
});

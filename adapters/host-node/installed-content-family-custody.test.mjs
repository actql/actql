import assert from 'node:assert/strict';
import test from 'node:test';
import {installEffectContentFamily} from './installed-content-family.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';

// Actual family constructor and cleanup; Common, Store and authority ports
// remain explicit. This does not prove physical funding or a generated Run.
function fixture({constructorFailure, append} = {}) {
  const active = {}, compiled = {}, graph = {}, calls = [];
  let retained;
  const options = {
    moon: {clientProgramEffectAcquisitionCount: () => 0},
    control: {
      effectFamily(_prepared, selected, _bodies, _limits, port, activate) {
        assert.equal(selected, graph);
        calls.push('provider');
        assert.notEqual(retained, undefined, 'cleanup must transfer before the provider constructor');
        assert.equal(retained.cleanupPending(), true);
        assert.equal(port.cleanup(), false);
        if (constructorFailure !== undefined) throw constructorFailure;
        assert.equal(activate(active), true);
        return {};
      },
      familyPendingPiece(value) {
        assert.equal(value, active); return {revision: 1, piece: Buffer.from('original')};
      },
      familyAcknowledgePiece() {return true;},
    },
    publications: {checkedClientSerializationGenerationLimits(value, selected) {
      assert.equal(value, compiled); assert.equal(selected, graph);
      return {maxRows: 1, maxBytes: 32};
    }},
    bodies: {}, prepared: {}, plan: {compiled, serializationGraph: graph,
      runDefinition: {wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'}},
    principalId: 'principal', ownerPrincipal: 'principal',
    storeAuthorityCid: 'store', now: () => '2026-10-27T00:00:00.000Z', authorize: () => true,
    store: {storeAuthorityCid: 'store', status: () => ({closed: false}),
      createPreparedObjectWriter() {
        return {append: append ?? (() => {}), cancel() {calls.push('writer-cancel');},
          status: () => ({reservationHeld: false, custodyPending: false, cleanupPending: false})};
      }},
    outputLimits: {},
    retainCleanup(value) {calls.push('retain'); retained = value;},
  };
  return {options, calls, retained: () => retained};
}

test('Content provider constructor failure retains its original cleanup before throwing', async () => {
  const original = new Error('original provider constructor failure');
  const f = fixture({constructorFailure: original});
  assert.throws(() => installEffectContentFamily(f.options), error => error === original);
  assert.deepEqual(f.calls, ['retain', 'provider']);
  const cleanup = f.retained();
  assert.equal(Object.isFrozen(cleanup), true);
  assert.equal(cleanup.cleanupPending(), true);
  assert.equal(await cleanup.cleanup(), true);
  assert.equal(cleanup.cleanupPending(), false);
});

test('actual acquired Effect custody receives the Content failure cleanup through its installed owner', async () => {
  const original = new Error('same original Content provider failure');
  const f = fixture({constructorFailure: original}), parent = {}, plan = {};
  const ok = value => ({$tag: 1, _0: value});
  const moon = {...f.options.moon,
    clientProgramEffectSerializationOccurrences: () => [{}],
    clientProgramInstalledEffectManagedRunCheck: () => ok(),
    clientProgramInstalledEffectManagedOperationPlan(value, prepared, request) {
      assert.equal(this, moon); assert.equal(value, parent);
      assert.equal(prepared, acquired.prepared); assert.equal(request, acquired.requestIdentity); return ok(plan);
    },
    clientProgramInstalledEffectManagedHostOpen() {assert.fail('no Compute after constructor failure');},
  };
  const selected = {provider: f.options.control.effectFamily};
  const core = {publicationControl: f.options.publications,
    contentGenerationControl: {...f.options.control, workspaceCapacity: () => ({}),
      effectFamily(...args) {
        // The actual installed owner must forward the parent callback before
        // this provider is reached. The caller test observes its real custody.
        selected.provider = args[4];
        throw original;
      }}};
  const contentRun = installNodeContentRun({moon, core,
    ownerPrincipal: f.options.ownerPrincipal, storeAuthorityCid: f.options.storeAuthorityCid,
    now: f.options.now, authorize: f.options.authorize});
  const acquired = {prepared: f.options.prepared, allowed: {},
    requestIdentity: {}, runDefinition: f.options.plan.runDefinition,
    control: {
      adoptCheckedClientEffectSerializationRun: () => f.options.plan.compiled,
      compiledSerializationGraph: () => f.options.plan.serializationGraph,
    }};
  let custody;
  await assert.rejects(openAcquiredEffectComputation({moon, acquired, managedRun: parent,
    contentRun, store: f.options.store, principalId: f.options.principalId, now: f.options.now,
    retainComputationOwner(value) {custody = value;}}), error => error === original);
  assert.equal(selected.provider.cleanup(), false);
  assert.equal(custody.cleanupPending(), true);
  await custody.close();
  assert.equal(selected.provider.cleanup(), true);
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
});

test('retained Content cleanup joins the same pending append before reporting completion', async () => {
  let entered, release;
  const started = new Promise(resolve => {entered = resolve;});
  const pending = new Promise(resolve => {release = resolve;});
  const f = fixture({append() {entered(); return pending;}});
  const owner = installEffectContentFamily(f.options), cleanup = f.retained();
  assert.equal(owner.cleanup, cleanup.cleanup);
  assert.equal(owner.close, cleanup.close);
  assert.equal(owner.cleanupPending, cleanup.cleanupPending);
  const work = assert.rejects(owner.handlePause({status: 'settling', slot: 0}),
    {message: 'ContentPieceAcknowledgementRejected'});
  await started;
  let finished = false;
  const closing = cleanup.cleanup().then(value => {finished = true; return value;});
  await Promise.resolve();
  assert.equal(finished, false);
  assert.equal(cleanup.cleanupPending(), true);
  release();
  await work;
  assert.equal(await closing, true);
  assert.equal(cleanup.cleanupPending(), false);
  assert.deepEqual(f.calls, ['retain', 'provider', 'writer-cancel']);
});

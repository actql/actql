import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {Worker} from 'node:worker_threads';
import {loadCheckpointRuntime} from './sqlite-checkpoint-journal.mjs';
import {C, input, open, identity, seedApproval, replaceClaim, reference, saved, runtime as fixtureRuntime} from './model-resume-state.fixture.mjs';

// Public claim regressions use the retained compiled Core decision ports.
// Model admission, input custody and Store outcomes remain explicit doubles.
const claimRuntime = await loadCheckpointRuntime();
const claimPorts = {resumeClaimDecide: claimRuntime.resumeClaimDecide,
  revalidationFailedState: claimRuntime.revalidationFailedState,
  runStateAdmit: claimRuntime.runStateAdmit};

function fixture(t, options = {}, count = 3, maxAttempts = 1) {
  const root = mkdtempSync(join(tmpdir(), 'model-resume-state-'));
  const opened = open(root, options);
  t.after(() => {opened.journal.close(); rmSync(root, {recursive: true, force: true});});
  const registration = input(count, maxAttempts);
  return {...opened, root, registration, start() {
    opened.journal.registerResumeCallSet(registration);
    return seedApproval(opened.journal.path);
  }};
}
const throwsCode = (fn, code) => assert.throws(fn, error => error.code === code);
const mutate = (path, fn) => {const db = new DatabaseSync(path); try {fn(db);} finally {db.close();}};
const storedResume = path => {
  const db = new DatabaseSync(path);
  try {
    return Object.fromEntries(['runs', 'resume_intents', 'resume_model_scopes',
      'resume_model_slots', 'resume_model_attempts', 'resume_admissions'].map(table =>
      [table, db.prepare(`SELECT * FROM ${table}`).all()]));
  } finally {db.close();}
};

test('public unsent cancellation and invalidating claims preserve an entered Model scope', t => {
  const f = fixture(t, {runtimeOverrides: claimPorts}); const claim = f.start();
  f.journal.renewResume(claim, 10);
  assert.equal(f.journal.hasStartedResume(identity.checkpointCid), false);
  f.journal.enterResumedCall(claim, reference(0));
  assert.equal(f.journal.hasStartedResume(identity.checkpointCid), true);
  f.clock.value += 11;
  const before = storedResume(f.journal.path);
  assert.equal(before.resume_admissions.length, 0);
  const options = {claimant: 'replacement', leaseMs: 1000,
    binding: {...f.registration.binding, environmentBindingCid: C('changed')}};
  assert.equal(f.journal.claimResume(identity.runId, {...options,
    preserveStarted: true, expectedCheckpointCid: C('other')}).action, 'changed');
  for (const preserveStarted of [false, true]) {
    assert.deepEqual(f.journal.claimResume(identity.runId, {...options, preserveStarted}),
      {action: 'admitted'});
  }
  assert.deepEqual(f.journal.cancelUnsentResume(identity.checkpointCid), {outcome: 'admitted'});
  assert.equal(f.journal.getRunState(identity.runId).status, 'resuming');
  assert.deepEqual(storedResume(f.journal.path), before);
});

test('a public same-binding replacement claim can enter only later proven-unsent Model slots', async t => {
  const f = fixture(t, {runtimeOverrides: claimPorts}); const claim = f.start();
  f.journal.renewResume(claim, 10);
  const first = f.journal.enterResumedCall(claim, reference(0));
  f.settlements.set(first.attemptCid, saved(first));
  await f.journal.observeResumedCall(first);
  const unknown = f.journal.enterResumedCall(claim, reference(1));
  f.clock.value += 11;
  const options = {claimant: 'replacement', leaseMs: 1000, binding: f.registration.binding};
  assert.deepEqual(f.journal.claimResume(identity.runId, {...options, preserveStarted: true}),
    {action: 'admitted'});
  const next = f.journal.claimResume(identity.runId, options);
  assert.equal(next.action, 'claimed');
  assert.equal(next.claim.generation, claim.generation + 1);
  throwsCode(() => f.journal.enterResumedCall(next.claim, reference(0)), 'ModelResumeCallSettled');
  throwsCode(() => f.journal.enterResumedCall(next.claim, reference(1)), 'ModelResumeAttemptUnknown');
  assert.equal(f.journal.enterResumedCall(next.claim, reference(2)).generation, next.claim.generation);
  f.settlements.set(unknown.attemptCid, saved(unknown));
  assert.equal((await f.journal.observeResumedCall(unknown)).state, 'SavedSuccess');
});

test('settled Model starts remain protected after reopen and grant expiry', async t => {
  for (const state of ['SavedSuccess', 'SavedFailure']) {
    const f = fixture(t, {runtimeOverrides: claimPorts}); const claim = f.start();
    const entry = f.journal.enterResumedCall(claim, reference(0));
    f.settlements.set(entry.attemptCid, saved(entry, state));
    await f.journal.observeResumedCall(entry);
    f.journal.close(); f.clock.value = 1000010;
    const reopened = open(f.root, {clock: f.clock, runtimeOverrides: claimPorts}).journal;
    t.after(() => reopened.close());
    const before = storedResume(reopened.path);
    assert.equal(reopened.hasStartedResume(identity.checkpointCid), true);
    assert.deepEqual(reopened.cancelUnsentResume(identity.checkpointCid), {outcome: 'admitted'});
    assert.deepEqual(reopened.claimResume(identity.runId, {claimant: 'replacement', leaseMs: 1000,
      binding: {...f.registration.binding, authorizationContextCid: C('changed')}}), {action: 'admitted'});
    assert.equal(reopened.readResumeCalls(identity).slots[0].state, state);
    assert.deepEqual(storedResume(reopened.path), before);
  }
});

test('generic Model start guards reject missing, substituted or incoherent retained inventory', t => {
  const corruptions = [
    db => {
      // Deliberately simulate a damaged inventory; normal SQL FK enforcement
      // prevents deleting this parent while its durable attempts exist.
      db.exec('PRAGMA foreign_keys = OFF');
      db.prepare('DELETE FROM resume_model_scopes').run();
    },
    db => db.prepare('DELETE FROM resume_model_slots WHERE ordinal = 2').run(),
    db => db.prepare("UPDATE resume_model_scopes SET inventory_json = '{}'").run(),
    db => db.prepare(`UPDATE resume_model_scopes SET originals_json = json_set(originals_json,
      '$.preparedInvocationWire', ?)`)
      .run(JSON.stringify({cid: C('foreign-prepared')})),
    db => db.prepare(`UPDATE resume_model_attempts SET entry_json = json_set(entry_json,
      '$.intentId', 'foreign-intent', '$.admission.intentId', 'foreign-intent')`).run(),
    db => db.prepare(`UPDATE resume_model_attempts SET entry_json = json_set(entry_json,
      '$.resolutionCid', ?, '$.admission.resolutionCid', ?)`)
      .run(C('foreign-resolution'), C('foreign-resolution')),
  ];
  for (const corrupt of corruptions) {
    const f = fixture(t, {runtimeOverrides: claimPorts}); const claim = f.start();
    f.journal.renewResume(claim, 10);
    f.journal.enterResumedCall(claim, reference(0));
    f.clock.value += 11;
    mutate(f.journal.path, corrupt);
    const before = storedResume(f.journal.path);
    throwsCode(() => f.journal.hasStartedResume(identity.checkpointCid), 'ModelResumeInventoryCorrupt');
    throwsCode(() => f.journal.cancelUnsentResume(identity.checkpointCid), 'ModelResumeInventoryCorrupt');
    for (const preserveStarted of [false, true]) {
      throwsCode(() => f.journal.claimResume(identity.runId, {claimant: 'replacement', leaseMs: 1000,
        binding: {...f.registration.binding, environmentBindingCid: C('changed')}, preserveStarted}),
      'ModelResumeInventoryCorrupt');
    }
    assert.deepEqual(storedResume(f.journal.path), before);
  }
});

test('cancellation committed before Model entry prevents any attempt row', t => {
  for (const fenceFirst of [false, true]) {
    const f = fixture(t); const claim = f.start();
    if (fenceFirst) f.journal.fenceRunCancellation({originalRunWire: f.registration.modelCallSet.originalRunWire});
    assert.equal(f.journal.cancelUnsentResume(identity.checkpointCid).outcome, 'cancelled');
    assert.equal(f.journal.getRunState(identity.runId).status, 'cancelled');
    const before = storedResume(f.journal.path);
    throwsCode(() => f.journal.enterResumedCall(claim, reference(0)),
      fenceFirst ? 'ModelRunCancelled' : 'ResumeClaimStale');
    assert.equal(before.resume_model_attempts.length, 0);
    assert.deepEqual(storedResume(f.journal.path), before);
  }
});

test('Model entry committed before cancellation preserves observation and fences the next call', async t => {
  const f = fixture(t); const claim = f.start();
  const entry = f.journal.enterResumedCall(claim, reference(0));
  f.journal.fenceRunCancellation({originalRunWire: f.registration.modelCallSet.originalRunWire});
  const before = storedResume(f.journal.path);
  assert.deepEqual(f.journal.cancelUnsentResume(identity.checkpointCid), {outcome: 'admitted'});
  throwsCode(() => f.journal.enterResumedCall(claim, reference(1)), 'ModelRunCancelled');
  assert.deepEqual(storedResume(f.journal.path), before);
  f.settlements.set(entry.attemptCid, saved(entry));
  assert.equal((await f.journal.observeResumedCall(entry)).state, 'SavedSuccess');
  assert.equal(f.journal.hasStartedResume(identity.checkpointCid), true);
});

test('legacy starts retain their existing optional-preservation and invalidation behavior', t => {
  for (const kind of ['read_access', 'effect_set']) {
    const f = fixture(t, {runtimeOverrides: claimPorts});
    f.registration.body.kind = kind; delete f.registration.modelCallSet;
    f.journal.persistCheckpoint(f.registration); const claim = seedApproval(f.journal.path);
    f.journal.renewResume(claim, 10);
    assert.equal(f.journal.hasStartedResume(identity.checkpointCid), false);
    f.journal.enterResumedDispatch(claim, {checkpointCid: identity.checkpointCid});
    f.clock.value += 11;
    assert.equal(f.journal.hasStartedResume(identity.checkpointCid), true);
    assert.deepEqual(f.journal.cancelUnsentResume(identity.checkpointCid), {outcome: 'admitted'});
    const options = {claimant: 'replacement', leaseMs: 1000,
      binding: {...f.registration.binding, environmentBindingCid: C('changed')}};
    assert.deepEqual(f.journal.claimResume(identity.runId, {...options, preserveStarted: true}),
      {action: 'admitted'});
    assert.equal(f.journal.claimResume(identity.runId, options).action, 'invalidated');
    assert.equal(f.journal.getRunState(identity.runId).status, 'failed');
    assert.equal(f.journal.hasStartedResume(identity.checkpointCid), false);
  }
});

test('three slots retain saved, unknown and unsent across a claim replacement', async t => {
  const f = fixture(t); const claim = f.start();
  const first = f.journal.enterResumedCall(claim, reference(0));
  assert.equal(typeof first.then, 'undefined');
  f.settlements.set(first.attemptCid, saved(first));
  await f.journal.observeResumedCall(first);
  f.journal.enterResumedCall(claim, reference(1));
  assert.deepEqual(f.journal.readResumeCalls(identity).slots.map(s => s.state), ['SavedSuccess', 'EnteredUnknown', 'Unsent']);
  const next = replaceClaim(f.journal.path);
  throwsCode(() => f.journal.enterResumedCall(next, reference(0)), 'ModelResumeCallSettled');
  throwsCode(() => f.journal.enterResumedCall(next, reference(1)), 'ModelResumeAttemptUnknown');
  assert.equal(f.journal.enterResumedCall(next, reference(2)).generation, 2);
});

test('same-slot entry races across independent SQLite connections admit once', async t => {
  const f = fixture(t); const claim = f.start();
  const barrier = new SharedArrayBuffer(4);
  const workerSource = `import {parentPort,workerData} from 'node:worker_threads';
    import {open} from ${JSON.stringify(new URL('./model-resume-state.fixture.mjs', import.meta.url).href)};
    const {journal}=open(workerData.root); parentPort.postMessage('ready');
    Atomics.wait(new Int32Array(workerData.barrier),0,0);
    try {journal.enterResumedCall(workerData.claim,workerData.reference); parentPort.postMessage('entered');}
    catch(error){parentPort.postMessage(error.code ?? error.message);} finally{journal.close();}`;
  const workers = [0, 1].map(() => new Worker(workerSource, {eval: true, type: 'module',
    workerData: {root: f.root, barrier, claim, reference: reference(0)}}));
  const exits = workers.map(worker => new Promise(resolve => worker.once('exit', resolve)));
  t.after(async () => {await Promise.all(workers.map(worker => worker.terminate()));});
  const results = workers.map(worker => new Promise((resolve, reject) => {
    worker.on('error', reject); worker.on('message', value => {if (value !== 'ready') resolve(value);});
  }));
  await Promise.all(workers.map(worker => new Promise((resolve, reject) => {
    worker.once('message', resolve); worker.once('error', reject);
  })));
  Atomics.store(new Int32Array(barrier), 0, 1); Atomics.notify(new Int32Array(barrier), 0);
  assert.deepEqual((await Promise.all(results)).sort(), ['ModelResumeAttemptUnknown', 'entered']);
  await Promise.all(exits);
});

test('approval expiry during Store await permits settlement but fences the next call', async t => {
  let release;
  const f = fixture(t, {verifySettlement: ({entry}) => new Promise(resolve => {release = () => resolve(saved(entry));})});
  const claim = f.start(); const entered = f.journal.enterResumedCall(claim, reference(0));
  const observation = f.journal.observeResumedCall(entered);
  f.clock.value = 100000; release();
  assert.equal((await observation).state, 'SavedSuccess');
  throwsCode(() => f.journal.enterResumedCall(claim, reference(1)), 'ApprovalExpired');
});

test('cancellation tombstone precedes inventory and rejects later registration atomically', t => {
  const f = fixture(t); const originalRunWire = f.registration.modelCallSet.originalRunWire;
  assert.equal(f.journal.fenceRunCancellation({originalRunWire}).outcome, 'accepted');
  assert.equal(f.journal.fenceRunCancellation({originalRunWire}).outcome, 'already_requested');
  throwsCode(() => f.journal.registerResumeCallSet(f.registration), 'ModelRunCancelled');
  mutate(f.journal.path, db => {
    for (const table of ['runs', 'checkpoints', 'resume_model_scopes', 'resume_model_slots']) {
      assert.equal(db.prepare(`SELECT count(*) AS n FROM ${table}`).get().n, 0);
    }
  });
});

test('cancellation between calls is sticky; the original owner can settle after replacement', async t => {
  const f = fixture(t); const claim = f.start();
  const entered = f.journal.enterResumedCall(claim, reference(0));
  f.journal.fenceRunCancellation({originalRunWire: f.registration.modelCallSet.originalRunWire});
  const next = replaceClaim(f.journal.path);
  throwsCode(() => f.journal.enterResumedCall(next, reference(1)), 'ModelRunCancelled');
  f.settlements.set(entered.attemptCid, saved(entered));
  assert.equal((await f.journal.observeResumedCall(entered)).state, 'SavedSuccess');
  throwsCode(() => f.journal.enterResumedCall(claim, reference(2)), 'ModelRunCancelled');
});

test('Store commit before marker repairs by re-observing exact immutable entry without resend', async t => {
  let crash = true;
  const f = fixture(t, {faults: {beforeCommit(step) {if (step === 'observeResumedCall' && crash) throw Error('crash');}}});
  const claim = f.start(); const entered = f.journal.enterResumedCall(claim, reference(0));
  f.settlements.set(entered.attemptCid, saved(entered));
  await assert.rejects(f.journal.observeResumedCall(entered), /crash/);
  assert.equal(f.journal.readResumeCalls(identity).slots[0].state, 'EnteredUnknown');
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0)), 'ModelResumeAttemptUnknown');
  crash = false;
  f.journal.close();
  const restarted = open(f.root, {clock: f.clock, settlements: f.settlements}).journal;
  t.after(() => restarted.close());
  replaceClaim(restarted.path);
  f.clock.value = 100000;
  assert.equal((await restarted.observeResumedCall(entered)).state, 'SavedSuccess');
  assert.equal(restarted.readResumeCalls(identity).slots[0].attempts[0].attemptCid, entered.attemptCid);
  restarted.close();
});

test('absence or corruption is never interpreted as unsent and duplicate registration cannot repair it', t => {
  const f = fixture(t); f.start();
  mutate(f.journal.path, db => db.prepare('DELETE FROM resume_model_slots WHERE ordinal = 1').run());
  throwsCode(() => f.journal.readResumeCalls(identity), 'ModelResumeInventoryCorrupt');
  throwsCode(() => f.journal.registerResumeCallSet(f.registration), 'ModelResumeInventoryCorrupt');
  throwsCode(() => f.journal.readResumeCalls({...identity, checkpointCid: C('absent')}), 'ModelResumeInventoryCorrupt');
});

test('scope, slot, prepared invocation, input custody, ordering and inventory bindings fail closed', t => {
  const f = fixture(t); const claim = f.start();
  throwsCode(() => f.journal.enterResumedCall(claim, {...reference(0), scopeCid: C('other')}), 'ModelResumeIdentityMismatch');
  throwsCode(() => f.journal.enterResumedCall(claim, {...reference(0), slotCid: C('other')}), 'ModelResumeSlotMismatch');
  throwsCode(() => f.journal.readResumeCalls({...identity, preparedInvocationCid: C('other')}), 'ModelResumeIdentityMismatch');
  mutate(f.journal.path, db => db.prepare("UPDATE resume_model_slots SET binding_json = '{}' WHERE ordinal = 1").run());
  throwsCode(() => f.journal.readResumeCalls(identity), 'ModelResumeInventoryCorrupt');
});

test('invalid or partially inserted inventory rolls the entire Checkpoint registration back', t => {
  let inserted = 0;
  const f = fixture(t, {faults: {beforeCommit(step) {if (step === 'registerResumeCallSlot' && ++inserted === 2) throw Error('crash');}}});
  assert.throws(() => f.journal.registerResumeCallSet(f.registration), /crash/);
  mutate(f.journal.path, db => {
    for (const table of ['runs', 'checkpoints', 'resume_model_scopes', 'resume_model_slots'])
      assert.equal(db.prepare(`SELECT count(*) AS n FROM ${table}`).get().n, 0);
  });
  const bad = fixture(t, {mutateInventory: inventory => ({...inventory, slots: [inventory.slots[1], inventory.slots[0], inventory.slots[2]]})});
  throwsCode(() => bad.journal.registerResumeCallSet(bad.registration), 'InvalidModelCallInventory');
});

test('bounded retry appends immutable attempts only after a verified classified failure', async t => {
  const f = fixture(t, {}, 1, 2); const claim = f.start();
  const first = f.journal.enterResumedCall(claim, reference(0));
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0, 2)), 'ModelResumeAttemptUnknown');
  f.settlements.set(first.attemptCid, saved(first, 'SavedFailure', true));
  await f.journal.observeResumedCall(first);
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0, 1)), 'ModelResumeAttemptMismatch');
  const second = f.journal.enterResumedCall(claim, reference(0, 2));
  f.settlements.set(second.attemptCid, saved(second, 'SavedFailure', true));
  await f.journal.observeResumedCall(second);
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0, 3)), 'ModelResumeAttemptMismatch');
  const slot = f.journal.readResumeCalls(identity).slots[0];
  assert.deepEqual(slot.attempts.map(a => [a.attemptIndex, a.attemptCid, a.state]),
    [[1, first.attemptCid, 'SavedFailure'], [2, second.attemptCid, 'SavedFailure']]);
});

test('arbitrary or foreign settlement references cannot record success; unknown stays attempt-unknown', async t => {
  const f = fixture(t); const claim = f.start(); const entry = f.journal.enterResumedCall(claim, reference(0));
  assert.equal((await f.journal.observeResumedCall(entry)).state, 'EnteredUnknown');
  f.settlements.set(entry.attemptCid, {state: 'SavedSuccess', captureCid: C('arbitrary')});
  await assert.rejects(f.journal.observeResumedCall(entry), {code: 'ModelResumeSettlementUnverified'});
  await assert.rejects(f.journal.observeResumedCall({...entry, claimant: 'foreign'}), {code: 'ModelResumeAttemptMismatch'});
  const foreign = saved(entry); foreign.entry.slotCid = C('foreign'); f.settlements.set(entry.attemptCid, foreign);
  await assert.rejects(f.journal.observeResumedCall(entry), {code: 'ModelResumeSettlementUnverified'});
  assert.equal(f.journal.readResumeCalls(identity).slots[0].state, 'EnteredUnknown');
});

test('empty inventory is explicit and duplicate exact registration is idempotent', t => {
  const f = fixture(t, {}, 0); f.journal.registerResumeCallSet(f.registration);
  f.journal.registerResumeCallSet(f.registration);
  assert.deepEqual(f.journal.readResumeCalls(identity).slots, []);
  const missing = {...f.registration}; delete missing.modelCallSet;
  throwsCode(() => f.journal.persistCheckpoint(missing), 'ModelCallInventoryRequired');
});

test('a changed scope or strategy cannot reset an existing Run INFER occurrence', t => {
  const f = fixture(t); const claim = f.start();
  const entered = f.journal.enterResumedCall(claim, reference(0));
  const changed = structuredClone(f.registration);
  changed.body.checkpoint_cid = C('second-checkpoint');
  changed.body.checkpoint_id = 'second-checkpoint';
  changed.body.required_artifact.artifact_cid = C('second-scope');
  const scope = JSON.parse(changed.modelCallSet.scopeWire);
  scope.checkpointCid = changed.body.checkpoint_cid;
  scope.scopeCid = changed.body.required_artifact.artifact_cid;
  scope.strategyRevision++;
  changed.modelCallSet.scopeWire = JSON.stringify(scope);
  mutate(f.journal.path, db => db.prepare("UPDATE runs SET status = 'running' WHERE run_id = ?").run(identity.runId));
  throwsCode(() => f.journal.registerResumeCallSet(changed), 'ModelResumeOccurrenceConflict');
  const original = f.journal.readResumeCalls(identity);
  assert.equal(original.slots[0].state, 'EnteredUnknown');
  assert.equal(original.slots[0].attempts[0].attemptCid, entered.attemptCid);
  mutate(f.journal.path, db => assert.equal(db.prepare('SELECT count(*) AS n FROM checkpoints').get().n, 1));
});

test('independent occurrences register without weakening the Run-wide cancellation fence', t => {
  const f = fixture(t); f.journal.registerResumeCallSet(f.registration);
  const second = structuredClone(f.registration);
  second.body.checkpoint_cid = C('second-checkpoint'); second.body.checkpoint_id = 'second-checkpoint';
  second.body.required_artifact.artifact_cid = C('second-scope');
  const scope = JSON.parse(second.modelCallSet.scopeWire);
  scope.checkpointCid = second.body.checkpoint_cid; scope.scopeCid = second.body.required_artifact.artifact_cid;
  scope.taskIndex = 1; second.modelCallSet.scopeWire = JSON.stringify(scope);
  mutate(f.journal.path, db => db.prepare("UPDATE runs SET status = 'running' WHERE run_id = ?").run(identity.runId));
  f.journal.registerResumeCallSet(second);
  f.journal.fenceRunCancellation({originalRunWire: second.modelCallSet.originalRunWire});
  throwsCode(() => f.journal.registerResumeCallSet(f.registration), 'ModelRunCancelled');
  throwsCode(() => f.journal.registerResumeCallSet(second), 'ModelRunCancelled');
});

test('missing, asynchronous or substituted verifier admission cannot register inventory', t => {
  const absent = fixture(t, {verifierOverrides: {admitCallSet: undefined}});
  throwsCode(() => absent.journal.registerResumeCallSet(absent.registration), 'ModelResumeVerifierUnavailable');
  const asyncPort = fixture(t, {verifierOverrides: {admitCallSet: async () => ({})}});
  throwsCode(() => asyncPort.journal.registerResumeCallSet(asyncPort.registration), 'AsyncModelResumeAdmission');
  const swapped = fixture(t);
  swapped.registration.modelCallSet.slotWires.reverse();
  assert.throws(() => swapped.journal.registerResumeCallSet(swapped.registration));
  const noCustody = fixture(t);
  noCustody.registration.modelCallSet.fixedInputReceiptWire = JSON.stringify({cid: identity.inputArtifactCid, durable: false});
  assert.throws(() => noCustody.journal.registerResumeCallSet(noCustody.registration));
  for (const f of [absent, asyncPort, swapped, noCustody]) mutate(f.journal.path, db =>
    assert.equal(db.prepare('SELECT count(*) AS n FROM checkpoints').get().n, 0));
});

test('uncommitted approval, stale claim and substituted resolution cannot enter a call', t => {
  const f = fixture(t); const claim = f.start();
  throwsCode(() => f.journal.enterResumedCall({...claim, claimant: 'foreign'}, reference(0)), 'ResumeClaimStale');
  throwsCode(() => f.journal.enterResumedCall(claim, {...reference(0), resolutionCid: C('foreign')}), 'ModelResumeIdentityMismatch');
  mutate(f.journal.path, db => db.prepare("UPDATE checkpoints SET closure = 'open'").run());
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0)), 'ResolutionNotCommitted');
  assert.deepEqual(f.journal.readResumeCalls(identity).slots.map(s => s.state), ['Unsent', 'Unsent', 'Unsent']);
});

test('settlement is idempotent, immutable, and remains saved on a concurrent unknown observation', async t => {
  const f = fixture(t); const claim = f.start(); const entry = f.journal.enterResumedCall(claim, reference(0));
  f.settlements.set(entry.attemptCid, saved(entry));
  const first = await f.journal.observeResumedCall(entry);
  assert.deepEqual(await f.journal.observeResumedCall(entry), first);
  f.settlements.delete(entry.attemptCid);
  assert.equal((await f.journal.observeResumedCall(entry)).state, 'SavedSuccess');
  f.settlements.set(entry.attemptCid, saved(entry, 'SavedFailure', true));
  await assert.rejects(f.journal.observeResumedCall(entry), {code: 'ModelResumeSettlementConflict'});
});

test('unknown Model evidence never unlocks a retry as an ordinary saved failure', async t => {
  const f = fixture(t, {}, 1, 2); const claim = f.start(); const entry = f.journal.enterResumedCall(claim, reference(0));
  f.settlements.set(entry.attemptCid, {...saved(entry), state: 'EnteredUnknown'});
  await assert.rejects(f.journal.observeResumedCall(entry), {code: 'ModelResumeSettlementUnverified'});
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0, 2)), 'ModelResumeAttemptUnknown');
});

test('the legacy dispatch lane retains one-entry and earlier-generation unknown fencing', t => {
  const f = fixture(t);
  f.registration.body.kind = 'read_access'; delete f.registration.modelCallSet;
  f.journal.persistCheckpoint(f.registration); const claim = seedApproval(f.journal.path);
  f.journal.enterResumedDispatch(claim, {checkpointCid: identity.checkpointCid, resolutionCid: C('resolution')});
  // Same-generation uniqueness remains the existing SQLite primary-key fence.
  assert.throws(() => f.journal.enterResumedDispatch(claim, {checkpointCid: identity.checkpointCid}));
  const next = replaceClaim(f.journal.path);
  throwsCode(() => f.journal.enterResumedDispatch(next, {checkpointCid: identity.checkpointCid}), 'PriorAdmissionUnresolved');
  mutate(f.journal.path, db => assert.equal(db.prepare('SELECT count(*) AS n FROM resume_model_scopes').get().n, 0));
});

test('non-retryable saved failures remain settled and entered originals are checked on reopen', async t => {
  const f = fixture(t, {}, 2, 2); const claim = f.start();
  const entered = f.journal.enterResumedCall(claim, reference(0));
  f.settlements.set(entered.attemptCid, saved(entered, 'SavedFailure', false));
  await f.journal.observeResumedCall(entered);
  throwsCode(() => f.journal.enterResumedCall(claim, reference(0, 2)), 'ModelResumeCallSettled');
  assert.equal(f.journal.enterResumedCall(claim, reference(1)).state, 'EnteredUnknown');
  mutate(f.journal.path, db => db.prepare("UPDATE resume_model_attempts SET attempt_wire = '{}' WHERE ordinal = 1").run());
  const reopened = open(f.root).journal;
  try { throwsCode(() => reopened.readResumeCalls(identity), 'ModelResumeInventoryCorrupt'); }
  finally { reopened.close(); }
});

test('an interrupted entry transaction never leaves a partial attempt or consumes its slot', t => {
  let crash = true;
  const f = fixture(t, {faults: {beforeCommit(step) {if (step === 'enterResumedCall' && crash) throw Error('entry crash');}}});
  const claim = f.start();
  assert.throws(() => f.journal.enterResumedCall(claim, reference(0)), /entry crash/);
  const slot = f.journal.readResumeCalls(identity).slots[0];
  assert.equal(slot.state, 'Unsent'); assert.deepEqual(slot.attempts, []);
  crash = false;
  assert.equal(f.journal.enterResumedCall(claim, reference(0)).attemptIndex, 1);
});

// These port spies establish routing and transaction boundaries only. The
// compiled Core separately proves canonical Model/Run binding; neither fixture
// establishes actual execution-owner call completeness or physical Store custody.
function resolutionPorts(calls) {
  const approval = {checkpoint_cid: identity.checkpointCid, resolution_cid: C('resolution'),
    verified_resolution_cid: C('verified'), expires: 100000, claims: [], reviewer_id: 'reviewer',
    expires_at: new Date(100000).toISOString()};
  const admit = (...args) => {calls.push({method: 'admit', args}); return JSON.stringify({ok: true, attestation_preimage: 'attestation'});};
  const decide = (...args) => {calls.push({method: 'decide', args}); return JSON.stringify({ok: true,
    action: 'commit', decision: 'approved', effect: 'move_run', run_status: 'resuming',
    resolution_cid: C('resolution'), verified_resolution_cid: C('verified'),
    verified_resolution_wire: JSON.stringify(approval), resume_intent_id: 'intent'});};
  const immediate = (...args) => {calls.push({method: 'immediate', args}); return JSON.stringify({ok: true, attestation_preimage: 'attestation'});};
  const seal = (...args) => {calls.push({method: 'seal', args}); return JSON.stringify({ok: true,
    checkpoint_cid: identity.checkpointCid, decision: 'approved', resolution_cid: C('resolution'),
    verified_resolution_cid: C('verified'), verified_resolution_wire: JSON.stringify(approval)});};
  return {resolutionProofPreimage: () => JSON.stringify({ok: true, preimage: 'proof'}),
    checkpointExpiredAt: () => JSON.stringify({ok: true, expired: false}),
    modelResolutionAdmit: admit, modelResolutionDecide: decide,
    modelResolutionAdmitImmediate: immediate, modelResolutionSealImmediate: seal,
    resolutionAdmit() {throw Error('generic Model admission forbidden');},
    resolutionDecide() {throw Error('generic Model decision forbidden');},
    resolutionAdmitImmediate() {throw Error('generic Model immediate forbidden');},
    resolutionSealImmediate() {throw Error('generic Model immediate seal forbidden');},
  };
}

test('Model Resolution dispatch uses retained exact originals and dedicated Core exports', async t => {
  const calls = []; const f = fixture(t, {runtimeOverrides: resolutionPorts(calls)});
  f.journal.registerResumeCallSet(f.registration);
  const result = await f.journal.submitResolution({checkpointCid: identity.checkpointCid, resolutionWire: 'resolution'});
  assert.equal(result.outcome, 'committed'); assert.equal(result.resumeIntentId, 'intent');
  assert.deepEqual(calls.map(c => [c.method, c.args.length]), [['admit', 7], ['decide', 12]]);
  for (const call of calls) {
    const originals = JSON.parse(call.args[0]);
    assert.deepEqual(originals, {...f.registration.modelCallSet, checkpointWire: JSON.stringify(f.registration.body)});
    assert.equal(call.args[1], originals.checkpointWire);
    assert.equal(call.args[2], 'resolution');
  }
});

test('Model Resolution commit rechecks inventory and cancellation after async attestation', async t => {
  const calls = []; let release;
  const f = fixture(t, {runtimeOverrides: resolutionPorts(calls),
    attestResolution: () => new Promise(resolve => {release = () => resolve({hostKeyId: 'host-key', signature: 'signature'});})});
  f.journal.registerResumeCallSet(f.registration);
  const pending = f.journal.submitResolution({checkpointCid: identity.checkpointCid, resolutionWire: 'resolution'});
  // Authentication yields before the attestation port; wait for that exact call.
  await new Promise((resolve, reject) => {
    let ended = false;
    const timer = setTimeout(() => {ended = true; reject(Error('attestation was not reached'));}, 1000);
    const check = () => {if (release) {clearTimeout(timer); resolve();} else if (!ended) setImmediate(check);};
    check();
  });
  f.journal.fenceRunCancellation({originalRunWire: f.registration.modelCallSet.originalRunWire}); release();
  await assert.rejects(pending, {code: 'ModelRunCancelled'});
  assert.deepEqual(calls.map(c => c.method), ['admit']);
  mutate(f.journal.path, db => assert.equal(db.prepare('SELECT count(*) AS n FROM resolutions').get().n, 0));
});

test('missing dedicated Model Resolution export refuses without generic fallback', async t => {
  const calls = []; const ports = resolutionPorts(calls); delete ports.modelResolutionAdmit;
  const f = fixture(t, {runtimeOverrides: ports}); f.journal.registerResumeCallSet(f.registration);
  await assert.rejects(f.journal.submitResolution({checkpointCid: identity.checkpointCid, resolutionWire: 'resolution'}),
    {code: 'ModelResolutionRuntimeUnavailable'});
  assert.deepEqual(calls, []);
});

test('immediate Model resolutions use the dedicated pair and require checked owner originals', async t => {
  const calls = []; const f = fixture(t, {runtimeOverrides: resolutionPorts(calls)});
  const args = {body: f.registration.body, authorities: f.registration.authorities,
    modelCallSet: f.registration.modelCallSet, resolutionWire: 'resolution'};
  assert.equal((await f.journal.admitImmediateResolution(args)).decision, 'approved');
  assert.deepEqual(calls.map(c => [c.method, c.args.length]), [['immediate', 7], ['seal', 9]]);
  mutate(f.journal.path, db => assert.equal(db.prepare('SELECT count(*) AS n FROM checkpoints').get().n, 0));
  await assert.rejects(f.journal.admitImmediateResolution({...args, modelCallSet: undefined}),
    {code: 'ModelCallInventoryRequired'});
});

test('immediate Model sealing rechecks cancellation and never falls back when its export is absent', async t => {
  const calls = []; const f = fixture(t, {runtimeOverrides: resolutionPorts(calls),
    attestResolution: () => {
      f.journal.fenceRunCancellation({originalRunWire: f.registration.modelCallSet.originalRunWire});
      return {hostKeyId: 'host-key', signature: 'signature'};
    }});
  const args = {body: f.registration.body, authorities: f.registration.authorities,
    modelCallSet: f.registration.modelCallSet, resolutionWire: 'resolution'};
  await assert.rejects(f.journal.admitImmediateResolution(args), {code: 'ModelRunCancelled'});
  assert.deepEqual(calls.map(c => c.method), ['immediate']);
  const ports = resolutionPorts([]); delete ports.modelResolutionSealImmediate;
  const absent = fixture(t, {runtimeOverrides: ports});
  await assert.rejects(absent.journal.admitImmediateResolution(args), {code: 'ModelResolutionRuntimeUnavailable'});
});

test('legacy Resolution and immediate routes preserve original exports and argument arity', async t => {
  const calls = []; const model = resolutionPorts(calls);
  const f = fixture(t, {runtimeOverrides: {...model,
    resolutionAdmit: model.modelResolutionAdmit, resolutionDecide: model.modelResolutionDecide,
    resolutionAdmitImmediate: model.modelResolutionAdmitImmediate, resolutionSealImmediate: model.modelResolutionSealImmediate}});
  f.registration.body.kind = 'read_access'; delete f.registration.modelCallSet;
  f.journal.persistCheckpoint(f.registration);
  await f.journal.submitResolution({checkpointCid: identity.checkpointCid, resolutionWire: 'resolution'});
  await f.journal.admitImmediateResolution({body: f.registration.body,
    authorities: f.registration.authorities, resolutionWire: 'resolution'});
  assert.deepEqual(calls.map(c => [c.method, c.args.length]), [['admit', 6], ['decide', 11], ['immediate', 6], ['seal', 8]]);
  assert.equal(JSON.parse(calls[0].args[0]).kind, 'read_access');
});

test('active Run Checkpoint projects exact waiting or resuming metadata without inferring current authority', t => {
  const f = fixture(t); assert.equal(f.journal.activeRunCheckpoint(identity.runId), undefined);
  f.journal.registerResumeCallSet(f.registration);
  const waiting = f.journal.activeRunCheckpoint(identity.runId);
  assert.equal(waiting.checkpointCid, identity.checkpointCid); assert.equal(waiting.kind, 'model_invocation');
  assert.equal(waiting.runDefinitionCid, identity.runDefinitionCid); assert.equal(waiting.closure, 'open');
  assert.equal(waiting.continuationStateCid, C('continuation')); assert.equal(waiting.prepareAttemptId, null);
  assert.ok(Object.isFrozen(waiting)); assert.ok(Object.isFrozen(waiting.subject));
  seedApproval(f.journal.path); f.clock.value = 10000000;
  const resuming = f.journal.activeRunCheckpoint(identity.runId);
  assert.equal(resuming.checkpointCid, waiting.checkpointCid); assert.equal(resuming.closure, 'resolved');
  assert.equal(resuming.claimant, undefined); assert.equal(resuming.observedClaims, undefined);
  mutate(f.journal.path, db => {db.exec("UPDATE resume_intents SET state = 'completed'; UPDATE runs SET status = 'succeeded'");});
  assert.equal(f.journal.activeRunCheckpoint(identity.runId), undefined);
  throwsCode(() => f.journal.activeRunCheckpoint(''), 'InvalidRunId');
});

test('active Run Checkpoint rejects mismatched owner links, missing rows and ambiguous active intents', t => {
  const mismatch = fixture(t); mismatch.journal.registerResumeCallSet(mismatch.registration);
  mutate(mismatch.journal.path, db => db.prepare('UPDATE runs SET checkpoint_cid = ?').run(C('missing')));
  throwsCode(() => mismatch.journal.activeRunCheckpoint(identity.runId), 'CheckpointJournalCorrupt');
  const ambiguous = fixture(t); ambiguous.start();
  mutate(ambiguous.journal.path, db => {
    db.exec('PRAGMA foreign_keys = OFF');
    db.prepare(`INSERT INTO resume_intents VALUES (?, ?, ?, ?, NULL, 'pending', 0, '', 0, '', '')`)
      .run('other-intent', C('other-checkpoint'), C('other-resolution'), identity.runId);
  });
  throwsCode(() => ambiguous.journal.activeRunCheckpoint(identity.runId), 'CheckpointJournalCorrupt');
  const foreign = fixture(t); foreign.journal.registerResumeCallSet(foreign.registration);
  mutate(foreign.journal.path, db => {
    const cp = JSON.parse(db.prepare('SELECT checkpoint_wire FROM checkpoints').get().checkpoint_wire);
    cp.run_id = 'foreign-run'; db.prepare('UPDATE checkpoints SET checkpoint_wire = ?').run(JSON.stringify(cp));
  });
  throwsCode(() => foreign.journal.activeRunCheckpoint(identity.runId), 'CheckpointJournalCorrupt');
});

test('Model public summary re-admits exact stored originals and exposes only bound identities', t => {
  const f = fixture(t); f.journal.registerResumeCallSet(f.registration);
  const summary = f.journal.modelCheckpointSummary(identity.checkpointCid);
  assert.deepEqual(summary, {checkpointCid: identity.checkpointCid, runId: identity.runId,
    runDefinitionCid: identity.runDefinitionCid, scopeCid: identity.scopeCid,
    reviewProjectionCid: C('review'), preparedInvocationCid: identity.preparedInvocationCid});
  assert.ok(Object.isFrozen(summary));
  throwsCode(() => f.journal.modelCheckpointSummary(C('absent')), 'CheckpointNotFound');
  mutate(f.journal.path, db => {
    const row = db.prepare('SELECT originals_json FROM resume_model_scopes').get();
    const originals = JSON.parse(row.originals_json);
    originals.preparedInvocationWire = JSON.stringify({cid: C('substituted-prepared')});
    db.prepare('UPDATE resume_model_scopes SET originals_json = ?').run(JSON.stringify(originals));
  });
  throwsCode(() => f.journal.modelCheckpointSummary(identity.checkpointCid), 'ModelResumeInventoryCorrupt');
  const legacy = fixture(t); legacy.registration.body.kind = 'read_access'; delete legacy.registration.modelCallSet;
  legacy.journal.persistCheckpoint(legacy.registration);
  throwsCode(() => legacy.journal.modelCheckpointSummary(identity.checkpointCid), 'ModelCheckpointKindMismatch');
});

test('Model entry fails closed when the live grant export is missing, expired or substituted', t => {
  const cases = [
    {port: undefined, code: 'ModelInvocationGrantRuntimeUnavailable'},
    {port: () => JSON.stringify({ok: false, issue: 'DecisionOutsideWindow'}), code: 'ModelInvocationGrantRejected'},
    {port: (...args) => JSON.stringify({...JSON.parse(fixtureRuntime.modelInvocationGrantAt(...args)), scopeCid: C('foreign')}),
      code: 'ModelInvocationGrantMismatch'},
  ];
  for (const {port, code} of cases) {
    const f = fixture(t, {runtimeOverrides: {modelInvocationGrantAt: port}}); const claim = f.start();
    throwsCode(() => f.journal.enterResumedCall(claim, reference(0)), code);
    assert.deepEqual(f.journal.readResumeCalls(identity).slots.map(slot => [slot.state, slot.attempts.length]),
      [['Unsent', 0], ['Unsent', 0], ['Unsent', 0]]);
  }
});

test('immediate Model permission fails closed without its dedicated live grant export', async t => {
  const f = fixture(t, {runtimeOverrides: {...resolutionPorts([]), modelImmediateInvocationGrantAt: undefined}});
  await assert.rejects(f.journal.admitImmediateResolution({body: f.registration.body,
    authorities: f.registration.authorities, modelCallSet: f.registration.modelCallSet,
    resolutionWire: 'resolution'}), {code: 'ModelInvocationGrantRuntimeUnavailable'});
});

test('name-neutral read refusal preserves exact claim, kind and prior-start fencing', t => {
  const unsent = fixture(t); unsent.registration.body.kind = 'read_access'; delete unsent.registration.modelCallSet;
  unsent.journal.persistCheckpoint(unsent.registration); const claim = seedApproval(unsent.journal.path);
  throwsCode(() => unsent.journal.refuseUnsentReadResume(identity.checkpointCid, identity.runDefinitionCid), 'InvalidResumeClaim');
  throwsCode(() => unsent.journal.refuseUnsentReadResume(identity.checkpointCid, identity.runDefinitionCid,
    {...claim, generation: 99}), 'ResumeClaimStale');
  assert.equal(unsent.journal.refuseUnsentReadResume(identity.checkpointCid, identity.runDefinitionCid, claim).outcome, 'failed');
  const entered = fixture(t); entered.registration.body.kind = 'read_access'; delete entered.registration.modelCallSet;
  entered.journal.persistCheckpoint(entered.registration); const live = seedApproval(entered.journal.path);
  entered.journal.enterResumedDispatch(live, {checkpointCid: identity.checkpointCid});
  assert.equal(entered.journal.refuseUnsentReadResume(identity.checkpointCid, identity.runDefinitionCid, live).outcome, 'admitted');
  const model = fixture(t); const modelClaim = model.start();
  throwsCode(() => model.journal.refuseUnsentReadResume(identity.checkpointCid, identity.runDefinitionCid, modelClaim),
    'CheckpointRunMismatch');
});

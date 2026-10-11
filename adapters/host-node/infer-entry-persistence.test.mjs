import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setImmediate as turn} from 'node:timers/promises';
import {createNodeInferEntryPersistence} from './infer-entry-persistence.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {C, input, open, immediateReference, reference,
  immediateIdentity, identity, seedApproval} from './model-resume-state.fixture.mjs';

// Real SQLite commit/read/reopen, with explicit Model admission/Core port
// doubles. This is not public execution or a production Core ACK proof.
function fixture(t, {deferred = false} = {}) {
  const root = mkdtempSync(join(tmpdir(), 'infer-entry-persistence-'));
  let physical;
  t.after(() => { try { physical?.journal.close(); }
    finally { rmSync(root, {recursive: true, force: true}); } });
  physical = open(root);
  const registration = input(1);
  let claim;
  const ref = deferred ? reference(0) : immediateReference(0);
  let tokens;
  if (deferred) {
    physical.journal.registerResumeCallSet(registration);
    claim = seedApproval(physical.journal.path);
    physical.journal.renewResume(claim, 1000);
    tokens = {preparedCallSet: {}};
  } else {
    physical.journal.registerImmediateModelCallSet({modelCallSet: registration.modelCallSet,
      declaredResults: registration.declaredResults});
    tokens = physical.issueImmediate(ref);
  }
  const entry = {}, views = new WeakMap();
  const original = {entry, slot: 0, attemptWire: ref.attemptWire,
    authorityWire: ref.authorityWire};
  let acks = 0, writes = 0, wakes = 0, owned = true;
  const acknowledgement = {entry};
  const moon = {
    clientProgramCreateInferCallEntryPersistence(actual, prepared, poll) {
      assert.equal(actual, entry); assert.equal(prepared, tokens.preparedCallSet);
      if (!owned) return undefined;
      if (!views.has(entry)) views.set(entry, {poll});
      return views.get(entry);
    },
    clientProgramAcknowledgeSavedInferCallEntry(actual, prepared) {
      assert.equal(actual, entry); assert.equal(prepared, tokens.preparedCallSet);
      acks++;
      return owned ? acknowledgement : undefined;
    },
    clientProgramInferCallEntryPersistencePending: () => ({kind: 'pending'}),
    clientProgramInferCallEntryPersistenceUnknown: () => ({kind: 'unknown'}),
    clientProgramInferCallEntryPersistenceSaved: ack => ({kind: 'saved', ack}),
  };
  const enter = (method, args) => {
    writes++;
    return physical.journal[method](...args);
  };
  let saveBehavior = enter => enter();
  // Explicit fault-injection Store ports, delegating unchanged to the actual
  // journal. Production callers cannot supply a per-entry save callback.
  const store = {
    readModelAttemptOriginals: receipt => physical.journal.readModelAttemptOriginals(receipt),
    enterImmediateModelCall: (...args) => saveBehavior(() => enter('enterImmediateModelCall', args)),
    enterResumedCall: (...args) => saveBehavior(() => enter('enterResumedCall', args)),
  };
  const adapter = createNodeInferEntryPersistence({moon, preparedCallSet: tokens.preparedCallSet,
    journal: store, ioNotification: {notify() { wakes++; }} });
  const begin = (behavior = enter => enter()) => {
    saveBehavior = behavior;
    return deferred ? adapter.beginResumed(original, ref, claim)
      : adapter.beginImmediate(original, ref, tokens);
  };
  return {adapter, original, ref, moon, physical, registration, tokens, root,
    revoke() { if (!deferred) physical.invalidateDecision(tokens.decision); },
    retire() { owned = false; }, counts: () => ({acks, writes, wakes}),
    inventory: () => physical.journal.readModelCalls(deferred ? identity : immediateIdentity),
    begin,
    reopen() { physical.journal.close(); physical = open(root); return physical; }};
}

for (const deferred of [false, true]) {
  test(`existing ${deferred ? 'deferred' : 'immediate'} journal entry becomes one original ACK`, async t => {
    const f = fixture(t, {deferred});
    const view = f.begin();
    assert.equal(view.poll().kind, 'pending', 'save observation crosses the async boundary');
    assert.equal(f.inventory().slots[0].state, 'EnteredUnknown', 'journal committed before acknowledgement');
    assert.equal(f.begin(() => { throw new Error('second save'); }), view);
    await turn();
    const observed = view.poll();
    assert.equal(observed.kind, 'saved');
    assert.equal(observed.ack.entry, f.original.entry);
    assert.equal(view.poll(), observed);
    assert.deepEqual(f.counts(), {acks: 1, writes: 1, wakes: 1});
    const before = f.inventory().slots[0].attempts;
    assert.equal(before.length, 1);
    const restarted = f.reopen();
    assert.deepEqual(restarted.journal.readModelCalls(deferred ? identity : immediateIdentity)
      .slots[0].attempts, before, 'reopening does not enter another attempt');
    assert.deepEqual(f.counts(), {acks: 1, writes: 1, wakes: 1});
  });
}

test('late save after cancellation and permission loss remains observation, not new authority', async t => {
  const f = fixture(t);
  let resolve;
  const pending = new Promise(done => { resolve = done; });
  let receipt;
  const view = f.begin(enter => { receipt = enter(); return pending; });
  f.physical.journal.fenceRunCancellation({originalRunWire:
    f.registration.modelCallSet.originalRunWire});
  f.revoke();
  await turn();
  assert.equal(view.poll().kind, 'pending');
  assert.deepEqual(f.counts(), {acks: 0, writes: 1, wakes: 0});
  resolve(receipt);
  await turn();
  assert.equal(view.poll().kind, 'saved', 'original held owner may retain a late ACK');
  assert.equal(f.physical.journal.modelCancellationFenced(identity.runId,
    identity.runDefinitionCid), true, 'ACK does not clear the cancellation fence');
  assert.deepEqual(f.counts(), {acks: 1, writes: 1, wakes: 1});
});

for (const asynchronous of [false, true]) {
  test(`saved entry with ${asynchronous ? 'async' : 'sync'} response loss stays unknown without re-entry`, async t => {
    const f = fixture(t);
    const view = f.begin(enter => {
      enter();
      if (asynchronous) return Promise.reject(new Error('LostCommitResponse'));
      throw new Error('LostCommitResponse');
    });
    await turn();
    assert.equal(view.poll().kind, 'unknown');
    assert.deepEqual(f.counts(), {acks: 0, writes: 1, wakes: 1});
    assert.equal(f.begin(), view, 'unknown never retries the durable entry');
    const restarted = f.reopen();
    assert.equal(restarted.journal.readModelCalls(immediateIdentity).slots[0].state, 'EnteredUnknown');
    assert.deepEqual(f.counts(), {acks: 0, writes: 1, wakes: 1});
  });
}

test('save exception before commit is not fabricated as confirmed absence', async t => {
  const f = fixture(t);
  const view = f.begin(() => { throw new Error('SaveUnavailable'); });
  await turn();
  assert.equal(view.poll().kind, 'unknown');
  assert.equal(f.inventory().slots[0].state, 'Unsent', 'this test can inspect absence; adapter cannot infer it');
  assert.deepEqual(f.counts(), {acks: 0, writes: 0, wakes: 1});
});

test('an old entered attempt cannot be substituted for a fresh journal entry', async t => {
  const f = fixture(t);
  const old = f.physical.journal.enterImmediateModelCall(f.ref, f.tokens);
  assert.equal(old.state, 'EnteredUnknown');
  assert.equal(f.adapter.begin, undefined, 'there is no caller-supplied receipt/save callback API');
  const view = f.begin();
  await turn();
  assert.equal(view.poll().kind, 'unknown', 'the actual journal rejects a duplicate Enter');
  assert.equal(f.inventory().slots[0].attempts.length, 1);
  assert.deepEqual(f.counts(), {acks: 0, writes: 1, wakes: 1});
});

test('async save observation keeps the original reference and raw bytes immutable', async t => {
  const f = fixture(t);
  let resolve, receipt;
  const pending = new Promise(done => { resolve = done; });
  const view = f.begin(enter => { receipt = enter(); return pending; });
  f.ref.attemptWire = 'foreign-wire';
  f.ref.authorityWire = 'foreign-authority';
  f.ref.runId = 'foreign-run';
  f.original.attemptWire = 'foreign-wire';
  resolve(receipt);
  await turn();
  assert.equal(view.poll().kind, 'saved', 'original saved snapshot is not rewritten by the caller');
  assert.equal(view.poll().ack.entry, f.original.entry);
  assert.deepEqual(f.counts(), {acks: 1, writes: 1, wakes: 1});
});

test('receipt binding mutations never issue an ACK for the original entry', async t => {
  for (const [field, replacement] of [['runId', 'foreign'], ['scopeCid', C('foreign')],
    ['slotCid', C('foreign-slot')], ['attemptCid', C('foreign-attempt')],
    ['attemptIndex', 2], ['state', 'SavedSuccess'], ['provenance', 'deferred']]) {
    const f = fixture(t);
    const view = f.begin(enter => ({...enter(), [field]: replacement}));
    await turn();
    assert.equal(view.poll().kind, 'unknown', field);
    assert.deepEqual(f.counts(), {acks: 0, writes: 1, wakes: 1}, field);
  }
});

test('wrong original bytes or port position are refused before the physical write', t => {
  const f = fixture(t);
  for (const changed of [{...f.ref, ordinal: 1}, {...f.ref, attemptWire: '{}'},
    {...f.ref, authorityWire: '{}'}]) {
    assert.throws(() => f.adapter.beginImmediate(f.original, changed, f.tokens),
      /InferEntryPersistenceBindingMismatch/);
  }
  assert.deepEqual(f.counts(), {acks: 0, writes: 0, wakes: 0});
});

test('a reclaimed owner cannot turn a completed save into an ACK', async t => {
  const f = fixture(t);
  let resolve;
  const pending = new Promise(done => { resolve = done; });
  let receipt;
  const view = f.begin(enter => { receipt = enter(); return pending; });
  f.retire();
  resolve(receipt);
  await turn();
  assert.equal(view.poll().kind, 'unknown');
  assert.equal(f.inventory().slots[0].state, 'EnteredUnknown');
  assert.deepEqual(f.counts(), {acks: 1, writes: 1, wakes: 1});
});

test('a foreign view or missing installed persistence ports starts no write', t => {
  const f = fixture(t);
  assert.throws(() => createNodeInferEntryPersistence({moon: {}, journal: f.physical.journal,
    ioNotification: {notify() {}}}), /InferEntryPersistenceUnavailable/);
  f.retire();
  assert.equal(f.begin(), undefined);
  assert.deepEqual(f.counts(), {acks: 0, writes: 0, wakes: 0});
});

test('installed persistence binder keeps the original compiled/definition/admission owners', () => {
  const compiledOwner = {}, definitionOwner = {}, admission = {}, prepared = {}, active = {};
  const scope = {}, account = {}, currentAccount = () => account, currentTime = () => 'now';
  let issues = 0, bindings = 0;
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture-only',
    strategyPublicationSeal: () => ok(definitionOwner),
    strategyPublicationContractName: () => 'run_definition',
    strategyPublicationContractIdentityField: () => 'self_cid',
    strategyPublicationContractIdentity: () => 'definition',
    strategyPublicationContractJson: () => '{}',
    strategyRunEvidenceName: () => 'evidence',
    strategyRunEvidenceIdentity: () => 'evidence',
    strategyRunEvidenceJson: () => '{}',
    clientProgramCompileLocalInfer: () => ok({}),
    clientProgramIssueTaskCompiledRun: () => ok(compiledOwner),
    clientProgramBindCompiledInferResultPolicy: value => ok(value),
    clientProgramCompiledRunTemplate: () => ({}),
    clientProgramCompiledRunPlan: () => ({}),
    clientProgramCompiledRunPrepared: () => ({}),
    clientProgramCompiledRunAuthorization: () => ({}),
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramIssueScopedInferDispatchAdmission(...args) {
      issues++;
      assert.deepEqual(args, [compiledOwner, definitionOwner, scope, account,
        'principal', 'now', false, currentAccount, currentTime]);
      return ok(admission);
    },
    clientProgramBindInferModelEntryPersistence(...args) {
      bindings++;
      assert.deepEqual(args, [active, prepared, admission, beginEntry]);
      return ok(undefined);
    },
  };
  const control = runtimeCore(moon).publicationControl;
  const limits = {maxWireBytes: 100, maxNodes: 10, maxDepth: 5};
  const definition = control.seal('run_definition', '{}', limits);
  const compiled = control.prepareCheckedClientCompiledRun({}, 'infer', {
    resultDataPolicy: {kind: 'data_policy', cid: 'policy', wire: '{}'}}, {});
  const beginEntry = () => undefined;
  const observation = {account, principalId: 'principal', at: 'now', delegated: false,
    observeAccount: currentAccount, observeAt: currentTime, beginEntry};
  const bind = (c = compiled, d = definition, o = observation) =>
    control.bindCheckedClientInferModelEntryPersistence(c, active, d, prepared, scope, o);
  assert.equal(bind(), admission);
  assert.deepEqual([issues, bindings], [1, 1]);
  for (const copy of [{...compiled}, {...compiled, kind: 'values'}]) {
    assert.throws(() => bind(copy), /Foreign Client compiled Infer dispatch/);
  }
  assert.throws(() => bind(compiled, {...definition}), /Foreign publication contract/);
  assert.throws(() => bind(compiled, definition, {...observation, observeAt: undefined}),
    /Foreign Client compiled Infer dispatch/);
  assert.deepEqual([issues, bindings], [1, 1], 'copies/missing current ports never issue admission');
});

test('Node operation forwards original entry bytes without rebuilding a Model entry', () => {
  const active = {}, entry = {}, prepared = {}, view = {};
  let begins = 0, originalsAvailable = true;
  const moon = {
    clientProgramStartScopedInferExecution: () => ({$tag: 1, _0: active}),
    clientProgramInferCallEntryOriginals(actual) {
      assert.equal(actual, entry);
      return originalsAvailable ? {_0: 0, _1: 'original-call', _2: 'original-attempt',
        _3: 'original-authority'} : undefined;
    },
  };
  const operation = openNodeInferOperation({moon, provider: {}, preparedProgram: {},
    step: 0, graph: {}, registry: '', values: '', fragment: '', ordered: ''});
  const plan = {compiled: {}, runDefinition: {}};
  const scope = {};
  const control = {bindCheckedClientInferModelEntryPersistence(c, e, d, p, s, observation) {
    assert.deepEqual([c, e, d, p, s], [plan.compiled, active, plan.runDefinition, prepared, scope]);
    return observation.beginEntry(entry);
  }};
  const observation = {beginEntry(original) {
    begins++;
    assert.equal(Object.isFrozen(original), true);
    assert.deepEqual(original, {entry, slot: 0, callWire: 'original-call',
      attemptWire: 'original-attempt', authorityWire: 'original-authority'});
    return view;
  }};
  assert.equal(operation.bindModelEntryPersistence(control, plan, prepared, scope, observation), view);
  originalsAvailable = false;
  assert.equal(operation.bindModelEntryPersistence(control, plan, prepared, scope, observation), undefined);
  assert.equal(begins, 1);
});

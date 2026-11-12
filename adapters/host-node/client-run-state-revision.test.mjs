import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issueInstalledUnpublishedRunState, issueInstalledRunControlObservation} from '../host-common/run-state-observation.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {configureInferEvidence} from './infer-evaluation-evidence.mjs';

const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = {maxWireBytes:65536, maxNodes:4096, maxDepth:64};
const at = '2026-10-16T00:00:00.000Z';
function definition(runId = 'observed-run') {
  return control.seal('run_definition', JSON.stringify({version:'actql-run-definition/0.1',
    scope_id:'original-scope', run_id:runId, compiled_plan_cid:cid('1'),
    invocation_template_cid:cid('2'), authorization_context_cid:cid('3'),
    input_artifact_set_cid:cid('4'), created_at:at, valid_until:'2098-01-01T00:00:00.000Z'}), limits);
}
function accept(journal) {
  const identity = moon.clientRequestAdmitRecord(cid('a'), 'saved-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    cid('b'), 'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  assert.ok(identity);
  return journal.acceptDefinition(identity, {namespaceId:'namespace-a', runDefinition:definition(),
    lookupExpiresAt:'2099-01-01T00:00:00.000Z'}, moon, control).ref;
}
function state(frame, observedAt = at) {
  return {...issueInstalledUnpublishedRunState(moon, {runId:'observed-run', observedAt,
    resultNames:['answer'], dispatchReserved:false, preDispatchFailureConfirmed:false,
    cancelledBeforeStart:false, observedTerminalOutcome:'none', executionUnknown:false}),
  control:issueInstalledRunControlObservation(moon, {revision:frame.revision,
    cancellationRequested:frame.cancellationRequested,
    physicallyUnstarted:frame.physicalStartReserved === false,
    preDispatchFailureConfirmed:frame.preDispatchFailureConfirmed,
    physicalCloseConfirmed:frame.physicalCloseConfirmed})};
}
async function fixture(t) {
  const path = await mkdtemp(join(tmpdir(), 'actql-a-state-revision-'));
  t.after(() => rm(path, {recursive:true, force:true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  return {path, journal, ref:accept(journal)};
}
const frame = (journal, ref) => journal.lookupRunDefinition(ref, moon, control);
const publish = (journal, ref, at) => {
  const original = frame(journal, ref);
  return JSON.parse(journal.publishRunState(original, state(original, at), moon, control));
};

test('accepted original Run definition is returned without a second raw admission', async t => {
  const path = await mkdtemp(join(tmpdir(), 'actql-a-accepted-definition-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const identity = moon.clientRequestAdmitRecord(cid('a'), 'saved-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    cid('b'), 'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  const options = {namespaceId: 'namespace-a', runDefinition: definition(),
    lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
  const admitted = [];
  const counted = Object.freeze({...control, admit(...args) {
    assert.equal(args[0], 'run_definition');
    const original = control.admit(...args);
    admitted.push(original);
    return original;
  }});
  const accepted = journal.acceptDefinition(identity, options, moon, counted);
  assert.equal(admitted.length, 1, 'The matching accepted bytes already have their original admitted definition');
  assert.strictEqual(accepted.runDefinition, admitted[0]);
  assert.equal(accepted.inserted, true);

  const same = journal.acceptDefinition(identity, options, moon, counted);
  assert.equal(admitted.length, 2, 'A new acceptance observation admits its own input once');
  assert.strictEqual(same.runDefinition, admitted[1]);
  assert.equal(same.inserted, false);
  assert.deepEqual(same.ref, accepted.ref);

  const copied = journal.acceptDefinition(identity,
    {...options, runDefinition: {...options.runDefinition}}, moon, counted);
  assert.equal(admitted.length, 3, 'A copied DATA input still follows full admission');
  assert.strictEqual(copied.runDefinition, admitted[2]);

  const winner = journal.acceptDefinition(identity,
    {...options, runDefinition: definition('different-proposed-run')}, moon, counted);
  assert.equal(admitted.length, 5, 'Distinct proposed and saved definitions each require admission');
  assert.deepEqual(winner.ref, accepted.ref);
  assert.equal(winner.runDefinition.identity, accepted.runDefinition.identity);
  assert.strictEqual(winner.runDefinition, admitted[4]);

  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  writer.prepare('UPDATE client_requests SET run_definition_wire = ?').run('{}');
  assert.throws(() => journal.acceptDefinition(identity, options, moon, counted),
    {code: 'ClientRequestJournalCorrupt'}, 'Matching saved CID cannot hide changed physical wire');
  journal.close();
  const beforeClosed = admitted.length;
  assert.throws(() => journal.acceptDefinition(identity, options, moon, counted),
    {code: 'ClientRequestJournalClosed'});
  assert.equal(admitted.length, beforeClosed, 'A closed Journal does no raw admission work');
});

test('Effect cancellation callers share one actual Journal admission for unchanged rows', async t => {
  let selectedReads = 0, admissions = 0;
  const prepare = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = prepare.call(this, sql);
    if (/SELECT[\s\S]*FROM client_requests\s+WHERE namespace_id = \? AND authority_scope_cid = \? AND\s+run_definition_cid = \?/u.test(sql)) {
      const get = statement.get;
      t.mock.method(statement, 'get', function(...args) {
        selectedReads++;
        return get.apply(this, args);
      });
    }
    return statement;
  });
  const {path, journal, ref} = await fixture(t);
  const counted = Object.freeze({...control, admit(...args) {
    admissions++;
    return control.admit(...args);
  }});
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declarations = new Map();
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        ['prepareMockModelInputs', 'openEffectTargetReads', 'executeEffectComputation'].includes(node.declarations[0].id.name)) {
      declarations.set(node.declarations[0].id.name, source.slice(node.start, node.end));
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child !== null && typeof child === 'object') visit(child);
    }
  }
  visit(ast);
  assert.equal(declarations.size, 3);
  const prepared = Object.freeze({}), requestIdentity = Object.freeze({});
  const managed = Object.freeze({value: Object.freeze({})}), plan = Object.freeze({});
  const evidenceConfiguration = configureInferEvidence(undefined);
  // Journal storage and contract admission are real; execution/compilation
  // ports isolate the actual Host cancellation consumers from provider work.
  const ports = {
    journal, control: counted, checked, moon: {...moon,
      clientProgramEffectCompilationResultNames: () => [],
      clientProgramEffectCompilationUnitId: () => 'explicit-unit',
      clientProgramInstalledEffectManagedOperationPlan(owner, actualPrepared, actualRequest) {
        assert.strictEqual(owner, managed.value); assert.strictEqual(actualPrepared, prepared);
        assert.strictEqual(actualRequest, requestIdentity); return {$tag:1,_0:plan};
      }},
    preparation: {effectManagedPlanRun(actualMoon, actualPrepared, actualRequest) {
      assert.strictEqual(actualMoon, ports.moon);
      assert.strictEqual(actualPrepared, prepared);
      assert.strictEqual(actualRequest, requestIdentity);
      return managed;
    }},
    mockModels: {prepareAnswersForRuntime() {assert.fail('This cancellation fixture has no physical Mock Model input');}},
    checkpoints: {}, installedEffect: undefined,
    dispatchOwner: {track(actual, options) {
      assert.strictEqual(actual, ref);
      return options.run({observePreEffectFailure() {}});
    }},
    effectInstallation: {execute: options => options.openComputation()},
    observation: undefined, store: {}, storeAuthorityCid: cid('b'), authorityScopeCid: ref.authorityScopeCid,
    principalId: 'fixture', sourceProfile: undefined, registry: undefined, values: undefined,
    fragment: undefined, ordered: undefined,
    inferSelections: new WeakMap([[prepared, Object.freeze({graph: {}})]]),
    selectAcquiredEffectSources(options) {assert.strictEqual(options.managedPlan,plan);return [];},
    acquiredEffectContinuation: options => options,
    openAcquiredEffectComputation: async options => options,
    earlyMockEffectPlans: new WeakMap(), localSnapshotConfiguration: undefined,
    runContent: undefined, authorization: undefined, diagnostic() {}, now: () => at,
    effectSubmissions: new WeakMap(), modelController: undefined, evidenceConfiguration,
    clientOperationError: code => Object.assign(new Error(code), {code}),
  };
  const execute = compileFunction(`${declarations.get('prepareMockModelInputs')}\n` +
    `${declarations.get('openEffectTargetReads')}\n` +
    `${declarations.get('executeEffectComputation')}\nreturn executeEffectComputation;`,
  Object.keys(ports))(...Object.values(ports));
  const facts = Object.freeze({ref, prepared, identity: requestIdentity, compilation: {}, preparedExecution: {},
    updateTargetSelections: Object.freeze([]), assertUpdateSelectionCurrent() {}});
  selectedReads = 0;
  const first = await execute(facts);
  assert.ok(Object.hasOwn(first, 'inferEvidence'));
  assert.strictEqual(first.inferEvidence, evidenceConfiguration);
  for (let index = 0; index < 4; index++) {
    first.assertUpdateSelectionCurrent();
    assert.equal(first.sourceContinuation.currentRun(), true);
  }
  assert.equal(admissions, 1, 'Unchanged target and Source probes share full Run admission');
  assert.ok(selectedReads > 1, 'Repeated probes still select current physical rows');
  const second = await execute(facts);
  second.assertUpdateSelectionCurrent();
  assert.equal(admissions, 2, 'A distinct execution lifetime acquires its own observation');

  journal.requestCancellation(ref, {currentAuthorization: true,
    publicationCommitted: false}, moon, control);
  assert.equal(first.sourceContinuation.currentRun(), false);
  assert.throws(first.assertUpdateSelectionCurrent, {code: 'ClientRunCancellationRequested'});
  assert.equal(second.sourceContinuation.currentRun(), false);

  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  writer.prepare('UPDATE client_requests SET run_definition_wire = ?').run('{}');
  assert.throws(first.sourceContinuation.currentRun, {code: 'ClientRequestJournalCorrupt'});
  journal.close();
  assert.throws(second.sourceContinuation.currentRun, {code: 'ClientRequestJournalClosed'});
});

test('same original Run observation seeds the complete-row probe without another admission', async t => {
  const {path, journal, ref} = await fixture(t);
  let admissions = 0;
  const counted = {...control, admit(...args) {
    admissions++;
    return control.admit(...args);
  }};
  const original = journal.lookupRunDefinition(ref, moon, counted);
  assert.equal(admissions, 1);
  const observe = journal.observeRunCancellation(ref, moon, counted, original);
  const first = observe();
  assert.deepEqual(first, {revision: original.revision,
    cancellationRequested: original.cancellationRequested});
  assert.equal(Object.isFrozen(first), true);
  for (let index = 0; index < 10; index++) assert.strictEqual(observe(), first);
  assert.equal(admissions, 1, 'The complete original row has already been admitted');

  journal.requestCancellation(ref, {currentAuthorization: true,
    publicationCommitted: false}, moon, control);
  const changed = observe();
  assert.equal(changed.cancellationRequested, true);
  assert.equal(changed.revision, original.revision + 1);
  assert.equal(admissions, 2);
  assert.strictEqual(observe(), changed);

  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  const wire = writer.prepare('SELECT run_definition_wire FROM client_requests').get().run_definition_wire;
  writer.prepare('UPDATE client_requests SET run_definition_wire = ?').run('{}');
  assert.throws(observe, {code: 'ClientRequestJournalCorrupt'},
    'A changed payload without a revision increment cannot reuse the frame');
  assert.throws(observe, {code: 'ClientRequestJournalCorrupt'});
  writer.prepare('UPDATE client_requests SET run_definition_wire = ?').run(wire);
  assert.equal(observe().cancellationRequested, true);
  writer.exec('DELETE FROM client_requests');
  assert.equal(observe(), undefined);
  journal.close();
  assert.throws(observe, {code: 'ClientRequestJournalClosed'});
});

test('Run observation seed requires the same Journal controls and complete selected key', async t => {
  const {path, journal, ref} = await fixture(t);
  const original = frame(journal, ref);
  const other = openClientRequestJournal(path);
  t.after(() => other.close());
  const seed = (owner = journal, selected = ref, requestControl = moon,
    publicationControl = control, candidate = original) =>
    owner.observeRunCancellation(selected, requestControl, publicationControl, candidate);
  for (const candidate of [{...original}, frame(other, ref), Object.freeze({})]) {
    assert.throws(() => seed(journal, ref, moon, control, candidate),
      {code: 'ForeignRunStateObservation'});
  }
  assert.throws(() => seed(other), {code: 'ForeignRunStateObservation'});
  assert.throws(() => seed(journal, ref, {...moon}), {code: 'ForeignRunStateObservation'});
  assert.throws(() => seed(journal, ref, moon, {...control}), {code: 'ForeignRunStateObservation'});
  for (const selected of [{...ref, namespaceId: 'other'},
    {...ref, authorityScopeCid: cid('b')}, {...ref, runDefinitionCid: cid('c')}]) {
    assert.throws(() => seed(journal, selected), {code: 'ForeignRunStateObservation'});
  }
});

test('state revision persists independently of control and unchanged rereads across reopen', async t => {
  const {path, journal, ref} = await fixture(t);
  const first = publish(journal, ref);
  assert.equal(first.revision, 0);
  assert.equal(first.control.revision, 0);
  assert.equal(publish(journal, ref, '2026-10-16T00:00:01.000Z').revision, 0);
  journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
  const cancelled = publish(journal, ref);
  assert.equal(cancelled.control.revision, 1);
  assert.equal(cancelled.revision, 1);
  const current = frame(journal, ref);
  const forgedControl = {...state(current), control:{revision:0,
    cancellation_requested:false, physical_stop:'confirmed'}};
  assert.deepEqual(JSON.parse(journal.publishRunState(current, forgedControl, moon, control)), cancelled,
    'Control facts come only from the admitted same original journal row');
  journal.close();
  const reopened = openClientRequestJournal(path);
  t.after(() => reopened.close());
  assert.deepEqual(publish(reopened, ref), cancelled);
  assert.equal(publish(reopened, ref, '2026-10-16T00:00:02.000Z').revision, 1);
});

test('unchanged state observation reuses its admitted row without a write transaction', async t => {
  const {journal, ref} = await fixture(t);
  publish(journal, ref);
  let admissions = 0;
  const originalControl = Object.freeze({...control, admit(...args) {
    admissions++;
    return control.admit(...args);
  }});
  const original = journal.lookupRunDefinition(ref, moon, originalControl);
  const before = admissions;
  assert.equal(before, 1);
  const transactions = [];
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (/^(BEGIN|COMMIT|ROLLBACK)/u.test(sql)) transactions.push(sql);
    return exec.call(this, sql);
  });
  const observed = JSON.parse(journal.publishRunState(original, state(original), moon, originalControl));
  assert.equal(observed.revision, 0);
  assert.equal(admissions, before, 'the exact unchanged row keeps its typed definition');
  assert.deepEqual(transactions, [], 'an unchanged read has no durable mutation');
});

test('state projection reentry cannot reuse a row changed during its callback', async t => {
  const {journal, ref} = await fixture(t);
  publish(journal, ref);
  const original = frame(journal, ref), previous = state(original);
  let changed = false;
  const reentrant = {...previous, get updated_at() {
    if (!changed) {
      changed = true;
      journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
    }
    return previous.updated_at;
  }};
  assert.throws(() => journal.publishRunState(original, reentrant, moon, control),
    {code:'RunStateObservationChanged'});
  assert.equal(changed, true);
  assert.equal(frame(journal, ref).cancellationRequested, true);
});

test('state revision rejects copied foreign stale and changed complete original row frames', async t => {
  const {path, journal, ref} = await fixture(t);
  const original = frame(journal, ref), initial = state(original);
  assert.throws(() => journal.publishRunState({...original}, initial, moon, control),
    {code:'ForeignRunStateObservation'});
  assert.throws(() => journal.publishRunState(original, initial, moon, {...control}),
    {code:'ForeignRunStateObservation'});
  const other = openClientRequestJournal(path);
  t.after(() => other.close());
  assert.throws(() => other.publishRunState(original, initial, moon, control),
    {code:'ForeignRunStateObservation'});
  assert.throws(() => journal.publishRunState(original, {...initial, run_id:'other-run'}, moon, control),
    {code:'MoonBitHostFailure'});
  publish(other, ref);
  assert.throws(() => journal.publishRunState(original, initial, moon, control),
    {code:'RunStateObservationChanged'});
  const beforeCancel = frame(journal, ref);
  other.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
  assert.throws(() => journal.publishRunState(beforeCancel, state(beforeCancel), moon, control),
    {code:'RunStateObservationChanged'});
  const current = frame(journal, ref);
  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  // A same-counter mutation must not bypass the complete original-row fence.
  writer.prepare('UPDATE client_requests SET lookup_expires_at = ?').run('2099-02-01T00:00:00.000Z');
  assert.throws(() => journal.publishRunState(current, state(current), moon, control),
    {code:'RunStateObservationChanged'});
});

test('state revision retains Unknown on COMMIT loss before or after durability', async t => {
  for (const committed of [false, true]) {
    const {path, journal, ref} = await fixture(t);
    publish(journal, ref);
    journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
    const original = frame(journal, ref);
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    const mock = t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && !injected) {
        injected = true;
        if (committed) exec.call(this, sql);
        throw new Error('STATE_COMMIT_REPLY_LOST');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => journal.publishRunState(original, state(original), moon, control), error => {
      assert.equal(error.code, 'ClientRunStateObservationUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.cause.message, 'STATE_COMMIT_REPLY_LOST');
      return true;
    });
    mock.mock.restore();
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    // A fresh original-row observation converges without repeating execution
    // or treating the lost COMMIT reply as a durable acknowledgement.
    assert.equal(publish(reopened, ref).revision, 1);
  }
});

test('state revision refuses exhaustion and missing noninitial history without reset', async t => {
  const {path, journal, ref} = await fixture(t);
  publish(journal, ref);
  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  writer.prepare('UPDATE client_requests SET state_revision = ?').run(Number.MAX_SAFE_INTEGER);
  assert.equal(publish(journal, ref).revision, Number.MAX_SAFE_INTEGER);
  journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
  assert.throws(() => publish(journal, ref), {code:'MoonBitHostFailure'});
  writer.exec('UPDATE client_requests SET state_observation_key = NULL');
  assert.throws(() => publish(journal, ref), {code:'MoonBitHostFailure'});
  assert.equal(writer.prepare('SELECT state_revision FROM client_requests').get().state_revision,
    Number.MAX_SAFE_INTEGER);
});

test('state revision old private row layout is refused before original database mutation', async t => {
  const {path, journal} = await fixture(t);
  journal.close();
  const file = join(path, 'client-requests.sqlite3');
  const old = new DatabaseSync(file);
  old.exec('ALTER TABLE client_requests DROP COLUMN state_revision');
  old.exec('ALTER TABLE client_requests DROP COLUMN state_observation_key');
  old.close();
  const before = await readFile(file);
  assert.throws(() => openClientRequestJournal(path), {code:'UnknownClientRequestJournalFormat'});
  assert.deepEqual(await readFile(file), before);
});

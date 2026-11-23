import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);

const cid = digit => `sha256:${digit.repeat(64)}`;
const hash = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const fields = Object.freeze({authorityScopeCid: cid('a'), namespaceId: 'original-content',
  currentAuthorization: true});
const publication = runtimeCore(moon).publicationControl;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const evidence = Object.freeze({prepared: 'original-prepared-wire', authorization: 'original-authorization-wire'});

async function fixture(t, {selected = true, readOnly = false, link = true, debug = false,
  journalOptions, shared, runName = 'same-original'} = {}) {
  const path = shared?.path ?? await mkdtemp(join(tmpdir(), 'actql-original-submitted-intent-'));
  let journal = shared?.journal ?? openClientRequestJournal(path, journalOptions);
  if (shared === undefined) {
    t.after(async () => {journal.close(); await rm(path, {recursive: true, force: true});});
  }
  const getJournal = () => shared?.journal ?? journal;
  const epoch = journal.issueSubmissionEpoch(fields, moon);
  const reference = {epoch, nonce: runName + '-content'};
  const intent = moon.clientSubmittedIntent(JSON.stringify({kind: 'program', input: {},
    parameters: null, ...(selected ? {stopBefore: 'commit'} : {}),
    ...(debug ? {executionProfile: 'debug'} : {}),
    ...(readOnly ? {readOnly: true} : {})}), 4096, 128, 16);
  assert.ok(intent);
  const recorded = journal.recordSubmittedIntent(reference, intent, fields, moon);
  const requestId = recorded.requestId;
  const request = (parameters = cid('2')) => moon.clientRequestAdmitRecord(
    fields.authorityScopeCid, requestId, cid('1'), parameters, cid('3'),
    hash({version: 'actql-logical-request/0.1', authority_scope_cid: fields.authorityScopeCid,
      caller_request_id: requestId}),
    hash({version: 'actql-logical-request-intent/0.1', program_definition_cid: cid('1'),
      parameter_values_cid: parameters, caller_input_intent_cid: cid('3')}));
  const identity = request();
  assert.ok(identity);
  const definition = publication.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: 'original-content-scope', run_id: runName + '-run',
    compiled_plan_cid: cid('4'), invocation_template_cid: cid('5'), authorization_context_cid: cid('6'),
    input_artifact_set_cid: cid('7'), created_at: '2026-09-25T00:00:00.000Z',
    valid_until: '2098-01-01T00:00:00.000Z',
  }), limits);
  const submission = {...reference, intentCid: moon.clientSubmittedIntentCid(intent), currentAuthorization: true};
  const accepted = journal.acceptDefinition(identity, {namespaceId: fields.namespaceId,
    runDefinition: definition, runAdmissionEvidence: evidence,
    lookupExpiresAt: '2099-01-01T00:00:00.000Z', ...(link ? {submission} : {})}, moon, publication);
  const readRow = () => {
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    try {return database.prepare('SELECT * FROM client_requests WHERE run_definition_cid = ?').get(definition.identity);}
    finally {database.close();}
  };
  const mutate = transform => {
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    try {
      const row = database.prepare('SELECT run_admission_evidence_json FROM client_requests WHERE run_definition_cid = ?')
        .get(definition.identity);
      const material = JSON.parse(row.run_admission_evidence_json);
      transform(material);
      database.prepare('UPDATE client_requests SET run_admission_evidence_json = ? WHERE run_definition_cid = ?')
        .run(JSON.stringify(material), definition.identity);
    } finally {database.close();}
  };
  return {path, reference, intent, request, identity, accepted, readRow, mutate,
    update(sql, ...parameters) {
      const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
      try {return database.prepare(sql).run(...parameters);}
      finally {database.close();}
    },
    get journal() {return getJournal();},
    read: (requestControl = moon, publicationControl = publication) =>
      getJournal().originalSubmittedIntent(identity, fields, requestControl, publicationControl),
    reopen() {
      if (shared !== undefined) shared.reopen();
      else {journal.close(); journal = openClientRequestJournal(path, journalOptions);}
    }};
}

test('original submitted content is bound in the same Run acceptance and survives reopen without dispatch', async t => {
  const f = await fixture(t);
  assert.equal(f.accepted.runAdmissionEvidence.submittedIntentCid, moon.clientSubmittedIntentCid(f.intent));
  const row = f.readRow();
  const original = f.read();
  assert.ok(original);
  assert.equal(moon.clientSubmittedIntentCid(original.intent), moon.clientSubmittedIntentCid(f.intent));
  assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), true);
  assert.deepEqual(JSON.parse(original.referenceWire), f.reference);
  original.assertCurrent();
  assert.equal(Object.isFrozen(original), true);
  assert.deepEqual(f.readRow(), row, 'projection and repeated checks do not change Run, revision or physical claims');
  f.reopen();
  assert.throws(() => original.assertCurrent(), {code: 'ClientRequestJournalClosed'});
  const restored = f.read();
  assert.ok(restored);
  assert.equal(restored.referenceWire, original.referenceWire);
  restored.assertCurrent();
  assert.deepEqual(f.readRow(), row);
});

test('one original submitted-content handle admits each unchanged row once', async t => {
  const f = await fixture(t);
  const counts = {identity: 0, intent: 0, definition: 0};
  const requestControl = {...moon,
    clientRequestAdmitRecord(...args) {
      counts.identity++;
      return Reflect.apply(moon.clientRequestAdmitRecord, moon, args);
    },
    clientSubmittedIntent(...args) {
      counts.intent++;
      return Reflect.apply(moon.clientSubmittedIntent, moon, args);
    },
  };
  const publicationControl = {...publication, admit(name, ...args) {
    if (name === 'run_definition') counts.definition++;
    return Reflect.apply(publication.admit, publication, [name, ...args]);
  }};
  const original = f.read(requestControl, publicationControl);
  assert.deepEqual(counts, {identity: 1, intent: 1, definition: 1});
  original.assertCurrent();
  original.assertCurrent();
  f.update('UPDATE client_submission_epoch_authority SET observed_at=observed_at+1');
  original.assertCurrent();
  assert.deepEqual(counts, {identity: 1, intent: 1, definition: 1},
    'same selected scalar rows reuse the actual admitted originals, not another decode/hash');
  f.read(requestControl, publicationControl).assertCurrent();
  assert.deepEqual(counts, {identity: 2, intent: 2, definition: 2},
    'a distinct original operation has its own initial admission');
  f.mutate(value => {value.authorization = 'changed-valid-authorization-wire';});
  original.assertCurrent();
  assert.deepEqual(counts, {identity: 2, intent: 2, definition: 3},
    'a changed Run row revalidates its Run facts without decoding the unchanged intent');
  assert.deepEqual(Object.keys(f.journal.lookupSubmittedIntent(f.reference, fields, moon)).sort(),
    ['intentCid', 'intentWire', 'outcome', 'phase', 'requestId', 'revision', 'submissionRef'],
    'public submission records do not expose the private admitted intent or row snapshots');
});

for (const entry of ['resolveDefinition', 'admitOrLookupDefinition']) {
  test(`${entry} admits one exact request once before returning its saved Run`, async t => {
    const f = await fixture(t);
    let admissions = 0, issuances = 0;
    const requestControl = {...moon, clientRequestAdmitRecord(...args) {
      admissions++;
      return Reflect.apply(moon.clientRequestAdmitRecord, moon, args);
    }};
    const resolve = original => f.journal[entry](original, {
      namespaceId: fields.namespaceId, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      issueDefinition() {issuances++; throw new Error('SavedRunMustNotBeReissued');},
    }, requestControl, publication);
    const before = f.readRow();
    const retained = await resolve(f.identity);
    assert.deepEqual(retained.ref, f.accepted.ref);
    assert.equal(admissions, 1, 'one exact request has one Common admission, not repeated stored copies');
    assert.equal(issuances, 0);
    await resolve(f.identity);
    assert.equal(admissions, 2, 'a new public resolution has its own admission');
    const foreign = f.request(cid('b'));
    admissions = 0;
    await assert.rejects(async () => resolve(foreign), {code: 'ClientRequestIntentConflict'});
    assert.equal(admissions, 2, 'distinct requested and saved identities are each admitted once');
    assert.equal(issuances, 0);
    assert.deepEqual(f.readRow(), before, 'resolution and conflict never mutate or reissue the saved Run');
  });
}

test('admit-or-lookup refuses an incomplete request control before issuer callback', async t => {
  const f = await fixture(t);
  let issuances = 0;
  const incomplete = {...moon, clientRequestRelation: undefined};
  await assert.rejects(f.journal.admitOrLookupDefinition(f.identity, {
    namespaceId: 'another-owner', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    issueDefinition() {issuances++; throw new Error('InvalidControlMustNotReachIssuer');},
  }, incomplete, publication), {code: 'InvalidClientRequestLookup'});
  assert.equal(issuances, 0);
});

for (const [label, sql, expected] of [
  ['intent wire', "UPDATE client_submitted_intents SET intent_wire='{}'", 'ClientSubmittedIntentCorrupt'],
  ['epoch key', "UPDATE client_submission_epoch_authority SET authentication_key='" + '1'.repeat(64) + "'", 'ClientSubmittedIntentCorrupt'],
  ['Run custody', 'UPDATE client_submission_custody SET issued_count=issued_count+1', 'ClientRequestSubmissionCustodyLost'],
  ['intent custody', 'UPDATE client_submitted_intent_custody SET issued_count=issued_count+1', 'ClientSubmittedIntentCustodyLost'],
  ['restart custody', 'UPDATE client_submission_restart_custody SET issued_count=issued_count+1', 'ClientSubmissionRestartCustodyLost'],
]) {
  test(`original submitted-content reuse still observes changed ${label}`, async t => {
    const f = await fixture(t), original = f.read();
    original.assertCurrent();
    f.update(sql);
    assert.throws(() => original.assertCurrent(), {code: expected});
    assert.throws(() => f.read(), {code: expected});
    assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), true);
  });
}

test('failed original-content observation discards its retained decoded facts', async t => {
  const f = await fixture(t);
  let admissions = 0;
  const requestControl = {...moon, clientSubmittedIntent(...args) {
    admissions++;
    return Reflect.apply(moon.clientSubmittedIntent, moon, args);
  }};
  const original = f.read(requestControl);
  assert.equal(admissions, 1);
  f.mutate(value => {value.submittedIntentCid = cid('f');});
  assert.throws(() => original.assertCurrent(), {code: 'ClientRequestSubmittedIntentMismatch'});
  f.mutate(value => {value.submittedIntentCid = moon.clientSubmittedIntentCid(f.intent);});
  original.assertCurrent();
  assert.equal(admissions, 2, 'after a failed observation the restored bytes require new admission');
});

for (const [label, selected, expected] of [
  ['selected', true, 'ClientRequestSubmittedIntentBindingMissing'],
  ['unselected legacy', false, undefined],
]) {
  test(`original submitted content does not retrofit a ${label} Run from a later intent lookup`, async t => {
    const f = await fixture(t, {selected, link: false});
    const before = f.readRow();
    if (expected === undefined) assert.equal(f.read(), undefined);
    else assert.throws(() => f.read(), {code: expected});
    assert.deepEqual(f.readRow(), before);
  });
}

for (const [label, change, code] of [
  ['missing link', value => {delete value.submittedIntentCid;}, 'ClientRequestSubmittedIntentBindingMissing'],
  ['foreign content', value => {value.submittedIntentCid = cid('f');}, 'ClientRequestSubmittedIntentMismatch'],
]) {
  test(`original submitted content current check refuses ${label} without replacing its original view`, async t => {
    const f = await fixture(t);
    const original = f.read();
    f.mutate(change);
    assert.throws(() => original.assertCurrent(), {code});
    assert.throws(() => f.read(), {code});
    assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), true);
  });
}

test('original submitted content refuses another namespace or logical request', async t => {
  const f = await fixture(t);
  const before = f.readRow();
  assert.throws(() => f.journal.originalSubmittedIntent(f.identity,
    {...fields, namespaceId: 'another-owner'}, moon, publication), {code: 'ClientRequestSubmittedIntentMismatch'});
  const other = f.request(cid('b'));
  assert.ok(other);
  assert.throws(() => f.journal.originalSubmittedIntent(other, fields, moon, publication),
    {code: 'ClientRequestSubmittedIntentMismatch'});
  assert.deepEqual(f.readRow(), before);
});

test('same-Run original read-only restriction survives material/journal reopen without a dispatch grant', async t => {
  const f = await fixture(t, {selected: false, readOnly: true});
  const before = f.readRow();
  const original = f.read();
  assert.equal(moon.clientSubmittedIntentRequestsReadOnly(original.intent), true);
  assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), false);
  original.assertCurrent();
  f.reopen();
  assert.throws(() => original.assertCurrent(), {code: 'ClientRequestJournalClosed'});
  const restored = f.read();
  assert.equal(moon.clientSubmittedIntentRequestsReadOnly(restored.intent), true);
  restored.assertCurrent();
  assert.deepEqual(f.readRow(), before);
  f.mutate(value => {delete value.submittedIntentCid;});
  assert.throws(() => restored.assertCurrent(), {code: 'ClientRequestSubmittedIntentBindingMissing'});
  assert.throws(() => f.read(), {code: 'ClientRequestSubmittedIntentBindingMissing'});
});

test('selected Sample reads only the authenticated Debug submission linked to the accepted Run', async t => {
  const f = await fixture(t, {selected: false, debug: true});
  let checks = 0, duringCheck;
  const run = Object.freeze({}), observation = Object.freeze({}), records = Object.freeze({});
  const checkedProfile = Object.freeze({});
  const checked = Object.freeze({profile: checkedProfile,
    controlAdmissionCid: cid('8'), resolvedProfileCid: cid('9'), matchesStart() {return false;}});
  const sampleControl = {...publication, checkClientRelationSampleProfile(...args) {
    checks++;
    assert.deepEqual(args, [run, f.identity, f.accepted.runDefinition, observation,
      canonicalJson(f.reference), records, limits]);
    return duringCheck === undefined ? checked : duringCheck();
  }};
  const sampleRef = (ref = f.accepted.ref) =>
    f.journal.originalSubmittedIntent(f.identity, {...fields, sampleRunRef: ref,
      reserveSampleRead(bytes) {assert.ok(bytes > 0);}}, moon, sampleControl);
  const before = f.readRow();
  assert.equal(f.journal.lookupSubmittedIntent(f.reference, fields, moon).phase, 'preparing',
    'the exact Run is accepted before the outer submission outcome is ready');
  assert.throws(() => sampleRef({...f.accepted.ref, runDefinitionCid: cid('f')}),
    {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.throws(() => sampleRef({...f.accepted.ref, authorityScopeCid: cid('b')}),
    {code: 'ClientRunSampleStartOriginalUnavailable'});
  const original = sampleRef();
  assert.equal(moon.clientSubmittedIntentRequestsDebug(original.intent), true);
  assert.deepEqual(JSON.parse(original.referenceWire), f.reference);
  original.assertCurrent();
  const check = () => original.checkSampleProfile(run, f.accepted.runDefinition, observation, records, limits);
  assert.equal(check().profile, checkedProfile);
  assert.equal(checks, 1);
  assert.deepEqual(f.readRow(), before);
  duringCheck = () => undefined;
  assert.throws(check, {code: 'InvalidClientRunSampleProfileCheck'});
  duringCheck = () => {
    assert.throws(check, {code: 'ClientRunSampleProfileCheckActive'});
    return checked;
  };
  assert.equal(check().profile, checkedProfile);
  duringCheck = () => Promise.reject(new Error('A profile checker must be synchronous'));
  assert.throws(check, {code: 'InvalidClientRunSampleProfileCheck'});
  const changed = {...f.reference.epoch,
    authenticator: `${f.reference.epoch.authenticator[0] === '0' ? '1' : '0'}${f.reference.epoch.authenticator.slice(1)}`};
  duringCheck = () => {
    f.update('UPDATE client_submitted_intents SET epoch_wire = ?', JSON.stringify(changed));
    return checked;
  };
  assert.throws(check, {code: 'ClientSubmittedIntentCorrupt'});
  assert.equal(checks, 5);
  assert.throws(check, {code: 'ClientSubmittedIntentCorrupt'});
  assert.equal(checks, 5, 'a lost original is refused before entering the checker');
  assert.throws(() => original.assertCurrent(), {code: 'ClientSubmittedIntentCorrupt'});
  assert.throws(() => sampleRef(), {code: 'ClientSubmittedIntentCorrupt'});
  assert.deepEqual(f.readRow(), before);
});

test('selected Sample refuses Normal and refuses to retrofit an unlinked Debug intent', async t => {
  const normal = await fixture(t, {selected: false});
  const unlinked = await fixture(t, {selected: false, debug: true, link: false});
  for (const [f, code] of [[normal, 'ClientRunSampleStartOriginalUnavailable'],
    [unlinked, 'ClientRequestSubmittedIntentBindingMissing']]) {
    const before = f.readRow();
    assert.throws(() => f.journal.originalSubmittedIntent(f.identity,
      {...fields, sampleRunRef: f.accepted.ref, reserveSampleRead() {}}, moon, publication), {code});
    assert.deepEqual(f.readRow(), before);
  }
  assert.equal(moon.clientSubmittedIntentRequestsDebug(normal.read().intent), false);
  assert.equal(unlinked.read(), undefined);
});

test('selected Sample funds stored UTF-8 before decoding and refuses growth within the original view', async t => {
  const f = await fixture(t, {selected: false, debug: true});
  f.mutate(value => {value.prepared = '多'.repeat(24);});
  const expected = (() => {
    const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {
      const {reconciliation_state_wire, ...run} = db.prepare('SELECT * FROM client_requests').get();
      const intent = db.prepare('SELECT * FROM client_submitted_intents').get();
      const {authentication_key, observed_at} =
        db.prepare('SELECT * FROM client_submission_epoch_authority').get();
      return [...Object.values(run), ...Object.values(intent), authentication_key, observed_at]
        .filter(value => value !== null).reduce((bytes, value) => bytes + Buffer.byteLength(String(value)), 0);
    } finally {db.close();}
  })();
  const declined = new Error('Original reservation refused');
  let decoded = 0, checked = 0, reservations = 0;
  const selectedControl = {...moon, clientSubmittedIntent(...args) {
    decoded++;
    return moon.clientSubmittedIntent(...args);
  }};
  const selectedPublication = {...publication, checkClientRelationSampleProfile() {
    checked++;
    f.mutate(value => {value.prepared += '多';});
    return Object.freeze({profile: Object.freeze({}),
      controlAdmissionCid: cid('8'), resolvedProfileCid: cid('9'), matchesStart() {return false;}});
  }};
  const read = reserveSampleRead => f.journal.originalSubmittedIntent(f.identity,
    {...fields, sampleRunRef: f.accepted.ref, reserveSampleRead}, selectedControl, selectedPublication);
  assert.throws(() => read(bytes => {
    assert.equal(bytes, expected);
    throw declined;
  }), error => error === declined);
  assert.equal(decoded, 0);
  assert.throws(() => read(bytes => {
    assert.equal(bytes, expected);
    f.mutate(value => {value.prepared += '多';});
  }), {code: 'ClientRunSampleOriginalCapacity'});
  assert.equal(decoded, 0, 'the changed row cannot reach its original decoder');
  const original = read(bytes => {
    reservations++;
    assert.equal(decoded, 0);
    assert.equal(bytes, expected + 3);
  });
  assert.equal(decoded, 1);
  const check = () => original.checkSampleProfile({}, f.accepted.runDefinition, {}, {}, limits);
  assert.throws(check, {code: 'ClientRunSampleOriginalCapacity'});
  assert.throws(check, {code: 'ClientRunSampleOriginalCapacity'});
  assert.equal(checked, 1, 'the oversized replacement was refused before another check');
  assert.equal(reservations, 1, 'freshness checks use the original reserved bound');
});

async function selectedSampleStart(t, journalOptions, {shared, runName, maxArtifacts = 1} = {}) {
  const f = await fixture(t, {selected: false, debug: true, journalOptions, shared, runName});
  const run = Object.freeze({}), observation = Object.freeze({}), records = Object.freeze({});
  const program = Object.freeze({}), compiled = Object.freeze({}), profile = Object.freeze({});
  // Only this component's native fixture knows which handles represent its
  // committed prefixes. Exercise the actual JS scoped port and SQLite owner.
  const prefixes = new WeakMap();
  const bridge = runtimeCore({...moon,
    clientProgramCheckRelationSampleProfile(owner) {
      assert.equal(owner, run);
      return {$tag: 1, _0: {_0: profile, _1: cid('8'), _2: cid('9'), _3: program, _4: compiled}};
    },
    clientProgramWithRelationSampleJournal(owner, checked, prefix, current, consume) {
      assert.equal(owner, run);
      assert.equal(checked, profile);
      const original = prefixes.get(prefix);
      if (original === undefined || current() !== true) return {$tag: 0, _0: 'RefusedOriginal'};
      const {wires, fundedBytes} = original;
      let active = true;
      try {
        const completed = consume(wires.generation, wires.capture, wires.emission, wires.reference,
          wires.relation, () => active && current(), fundedBytes);
        return completed ? {$tag: 1, _0: undefined} : {$tag: 0, _0: 'VisitorRefused'};
      } finally { active = false; }
    }}).publicationControl;
  const requestControl = {...moon, clientProgramMatchesRequestIdentity(value, request) {
    return value === program && request === f.identity;
  }};
  const publicationControl = {...publication, checkClientRelationSampleProfile(owner, identity, definition,
    actualObservation, referenceWire, actualRecords) {
    assert.equal(owner, run);
    assert.equal(identity, f.identity);
    assert.equal(definition.identity, f.accepted.runDefinition.identity);
    assert.equal(actualObservation, observation);
    assert.equal(referenceWire, canonicalJson(f.reference));
    assert.equal(actualRecords, records);
    const retained = bridge.admit('run_definition', definition.wire, limits);
    const checked = bridge.checkClientRelationSampleProfile(run, identity, retained,
      observation, referenceWire, records, limits);
    return Object.freeze({...checked,
      matchesStart(actualProgram, actualCompiled) {return actualProgram === program && actualCompiled === compiled;},
      matchesAdoption(source, capture) {
        return source.logical_map_cid === cid('5') && source.output_port_id === cid('7') &&
          capture.max_items === 1 && capture.max_bytes === '1024' && capture.max_artifacts === maxArtifacts &&
          capture.ttl_seconds === 60 && capture.required === false;
      }});
  },
  checkClientCompiledRunOwner(owner, original) {assert.equal(owner, compiled); assert.equal(original, program);},
  checkClientCompiledRunDefinition(owner, definition) {
    assert.equal(owner, compiled);
    assert.equal(definition.identity, f.accepted.runDefinition.identity);
  }};
  f.journal.reserveDispatch(f.identity, fields, requestControl, publicationControl);
  const prepare = () => f.journal.originalSubmittedIntent(f.identity, {...fields,
    sampleRunRef: f.accepted.ref, reserveSampleRead(bytes) {assert.ok(bytes > 0);}},
  requestControl, publicationControl).checkSampleProfile(
    run, f.accepted.runDefinition, observation, records, limits);
  const start = (selection, currentAuthorization = true) => f.journal.reservePhysicalStart(f.identity,
    {...fields, ref: f.accepted.ref, currentAuthorization, localExecutionOwner: {program, compiled},
      captureSampleStart: selection}, requestControl, publicationControl);
  const selection = (captureRevision, selected = prepare()) =>
    ({program, compiled, startTicket: selected.startTicket, captureRevision});
  const readStart = () => {
    const database = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {
      if (database.prepare("SELECT 1 FROM sqlite_master WHERE name = 'client_relation_sample_starts'").get() === undefined) {
        return undefined;
      }
      return database.prepare('SELECT * FROM client_relation_sample_starts WHERE run_definition_cid = ?')
        .get(f.accepted.ref.runDefinitionCid);
    } finally {database.close();}
  };
  return {f, start, selection, readStart, prepare, committedPrefix(wires, reduction = 0) {
    const prefix = Object.freeze({});
    const metadataLimit = 1024 + 6 * f.accepted.ref.namespaceId.length;
    const fundedBytes = Object.values(wires).reduce((n, wire) => n + Buffer.byteLength(wire, 'utf8'),
      metadataLimit) - reduction;
    prefixes.set(prefix, {wires, fundedBytes});
    return prefix;
  }};
}

test('the checked Debug start seals its original Run revision and profile in the same COMMIT', async t => {
  const {f, start, selection, readStart} = await selectedSampleStart(t);
  const revisions = [];
  const selected = selection(function captureRevision(revision) {
    assert.equal(this, selected);
    assert.equal(f.readRow().physical_start_reserved, 1);
    assert.equal(readStart().start_revision, revision);
    revisions.push(revision);
  });
  assert.throws(() => start({...selected, startTicket: {}}), {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.throws(() => start({...selected, program: {}}), {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.throws(() => start(selection(() => assert.fail('denial cannot hand off')), false),
    {code: 'ClientRunPhysicalStartDenied'});
  assert.equal(readStart(), undefined);
  assert.equal(start(selected), true);
  assert.deepEqual(revisions, [2]);
  assert.deepEqual({...readStart()}, {
    run_definition_cid: f.accepted.ref.runDefinitionCid,
    namespace_id: fields.namespaceId,
    authority_scope_cid: fields.authorityScopeCid,
    submitted_intent_cid: moon.clientSubmittedIntentCid(f.intent),
    control_admission_cid: cid('8'), resolved_profile_cid: cid('9'), start_revision: 2,
  });
  f.update('UPDATE client_requests SET revision = revision + 1');
  f.reopen();
  assert.equal(f.readRow().revision, 3);
  assert.equal(readStart().start_revision, 2);
  assert.throws(() => start(selected), {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.equal(start(selection(() => assert.fail('a start is never reissued'))), false);
  assert.deepEqual(revisions, [2]);
});

test('the Debug start rechecks a measured original after profile admission and refuses before writing', async t => {
  const {f, start, selection, readStart} = await selectedSampleStart(t);
  const selected = selection(() => assert.fail('stale original cannot hand off'));
  f.mutate(value => {value.prepared += '多';});
  assert.throws(() => start(selected), {code: 'ClientRunSampleOriginalCapacity'});
  assert.equal(f.readRow().physical_start_reserved, 0);
  assert.equal(readStart(), undefined);
});

test('the Debug start admits the final representable revision and refuses exhaustion atomically', async t => {
  for (const revision of [2147483646, 2147483647]) {
    const {f, start, selection, readStart} = await selectedSampleStart(t);
    f.update('UPDATE client_requests SET revision = ?', revision);
    const revisions = [];
    const selected = selection(value => revisions.push(value));
    if (revision === 2147483646) {
      assert.equal(start(selected), true);
      assert.deepEqual(revisions, [2147483647]);
      assert.equal(readStart().start_revision, 2147483647);
    } else {
      assert.throws(() => start(selected), {code: 'ClientRunSampleStartRevisionExhausted'});
      assert.equal(f.readRow().revision, revision);
      assert.equal(f.readRow().physical_start_reserved, 0);
      assert.equal(readStart(), undefined);
      assert.deepEqual(revisions, []);
    }
  }
});

test('the selected schema boundary rolls back a Debug claim when its optional start row is unsupported', async t => {
  const {default: support} = await import('./host-journal-schema-support.cjs');
  const journalOptions = {maxDatabaseBytes: 4194304,
    primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
      maxSchemaPages: 256, maxWalFrames: 8192},
    primarySchemaSqlSupport: support.sql.filter(sql =>
      !sql.startsWith('CREATE TABLE client_relation_sample_starts ('))};
  const {f, start, selection, readStart} = await selectedSampleStart(t, journalOptions);
  const before = f.readRow();
  assert.throws(() => start(selection(() => assert.fail('rolled back start cannot hand off'))),
    {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.deepEqual(f.readRow(), before);
  assert.equal(readStart(), undefined);
});

test('a lost Debug start COMMIT reply retains the immutable original without issuing a receiver', async t => {
  const {f, start, selection, readStart} = await selectedSampleStart(t);
  const selected = {...selection(() => assert.fail('unknown start cannot hand off')),
    captureAdoption() {assert.fail('unknown start cannot issue a Sample writer');}};
  const exec = DatabaseSync.prototype.exec;
  let injected = false;
  DatabaseSync.prototype.exec = function(sql) {
    const value = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('PhysicalStartCommitReplyLost');}
    return value;
  };
  try {
    assert.throws(() => start(selected), {code: 'ClientRunPhysicalStartUnknown', outcome: 'unknown'});
  } finally { DatabaseSync.prototype.exec = exec; }
  assert.equal(injected, true);
  f.reopen();
  assert.equal(f.readRow().physical_start_reserved, 1);
  assert.equal(readStart().start_revision, 2);
  assert.equal(start(selection(() => assert.fail('a reopened start cannot hand off'))), false);
});

function committedRelationSample(ref, {revision = 2, attempt = '1', maxArtifacts = 1} = {}) {
  const seal = (name, body) => publication.sealRunEvidence(name, JSON.stringify({
    ...body, version: `actql-${name.replaceAll('_', '-')}/0.1`,
  }), limits);
  const generation = seal('sample_source_generation', {
    run_ref: ref, compiled_plan_cid: cid('4'), logical_map_cid: cid('5'),
    step_id: cid('6'), output_port_id: cid('7'), carrier: 'relation', carrier_contract_cid: cid('a'),
    producer_occurrence: {kind: 'first_physical_start', start_revision: String(revision), attempt_sequence: attempt},
    committed_generation: attempt,
  });
  const capture = seal('sample_original_capture', {
    source_generation_cid: generation.identity, control_admission_cid: cid('8'), resolved_profile_cid: cid('9'),
    strategy: 'execution_prefix', max_items: 1, max_bytes: '1024', max_artifacts: maxArtifacts,
    ttl_seconds: 60, required: false,
  });
  const relation = {version: 'actql-sample-relation/0.1', kind: 'relation', schema_cid: cid('b'),
    ordering_evidence_cid: null, columns: [{position: 0, name: 'n', value_contract_cid: cid('c'), required: true}],
    rows: [[{presence: 'present', value_contract_cid: cid('c'), value: 7}]]};
  const emission = seal('sample_emission_provenance', {
    original_capture_cid: capture.identity, source_generation_cid: generation.identity,
    relation_prefix_cid: hash(relation), ordering_evidence_cid: null, sampled_items: '1',
    total: {kind: 'exact', value: '1', unit: 'rows', scope_cid: cid('7'), basis_cid: generation.identity},
    completeness: 'complete', truncation: 'not_truncated',
  });
  const reference = seal('sample_reference', {
    run_ref: ref, output_port_id: cid('7'), original_capture_cid: capture.identity,
    emission_provenance_cid: emission.identity,
  });
  return {cid: reference.identity, wires: {generation: generation.wire, capture: capture.wire,
    emission: emission.wire, reference: reference.wire, relation: canonicalJson(relation)}};
}

async function relationSampleWriter(t, journalOptions, options) {
  const {f, start, selection, prepare, committedPrefix} = await selectedSampleStart(t, journalOptions, options);
  const selected = prepare();
  let writer;
  assert.equal(start({...selection(revision => assert.equal(revision, 2), selected),
    captureAdoption(original) {writer = original;}}), true);
  const ref = f.accepted.ref;
  return {f, writer, ref, committedPrefix, withAdoption: selected.withAdoption, prepare,
    adopt(wires, custody, reduction = 0) {
      let result;
      selected.withAdoption(committedPrefix(wires, reduction), custody.current, ticket => {
        result = writer(ticket);
      });
      return result;
    }, lookup(sampleRefCid, custody) {
    return f.journal.lookupRelationSampleAdoption(ref, sampleRefCid, custody, publication);
    }, retire(sampleRefCid, custody) {
      return f.journal.retireRelationSamplePayload(ref, sampleRefCid, custody, publication);
  }};
}

test('Relation Sample adoption retains one exact prefix and stable receipt under its original start', async t => {
  const {default: support} = await import('./host-journal-schema-support.cjs');
  let now = Date.now();
  const {f, adopt, ref, lookup} = await relationSampleWriter(t, {submissionEpochNow: () => now,
    maxDatabaseBytes: 4194304,
    primarySqlLimits: {maxPreparedStatements: 256, maxSqlBytes: 8192, maxTotalSqlBytes: 262144},
    primaryExecutionLimits: {maxParameters: 32, maxParameterBytes: 262144, maxResultRows: 128},
    primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
      maxSchemaPages: 256, maxWalFrames: 8192},
    primarySchemaSqlSupport: support.sql});
  const sample = committedRelationSample(ref);
  const custody = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  assert.throws(() => adopt(sample.wires, {...custody, current: () => false}),
    {code: 'RunHostRelationSampleJournalRejected'});
  assert.throws(() => adopt(sample.wires, {...custody, current: () => Promise.resolve(true)}),
    {code: 'RunHostRelationSampleJournalRejected'});
  assert.throws(() => adopt(sample.wires, custody, 1), {code: 'ClientRelationSampleCapacity'});
  assert.deepEqual(lookup(sample.cid, custody), {kind: 'unobserved'});
  assert.throws(() => adopt(committedRelationSample(ref, {revision: 3}).wires, custody),
    {code: 'ClientRelationSampleOriginalChanged'});
  assert.throws(() => adopt({...sample.wires, relation: sample.wires.relation.replace('"value":7', '"value":8')}, custody),
    {code: 'ClientRelationSampleOriginalChanged'});
  let currentChecks = 0;
  assert.throws(() => adopt(sample.wires, {...custody, current: () => ++currentChecks < 5}),
    {code: 'ClientRelationSampleDenied'});
  assert.deepEqual(lookup(sample.cid, custody), {kind: 'unobserved'}, 'last authority check rolled the insert back');
  const receipt = adopt(sample.wires, custody);
  assert.equal(receipt.kind, 'adopted');
  assert.equal(receipt.sampleRefCid, sample.cid);
  assert.equal(receipt.expiresAt, now + 60_000);
  const database = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    const rows = database.prepare('SELECT * FROM client_relation_sample_adoptions').all();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].relation_wire, sample.wires.relation);
    assert.equal(JSON.parse(rows[0].receipt_wire).self_cid, receipt.receiptCid);
  } finally { database.close(); }
  now += 120_000;
  assert.deepEqual(adopt(sample.wires, custody), receipt, 'an exact retry never refreshes TTL');
  assert.throws(() => adopt(committedRelationSample(ref, {attempt: '2'}).wires, custody),
    {code: 'ClientRelationSampleCapacity'});
  assert.throws(() => adopt(committedRelationSample(ref, {maxArtifacts: 2}).wires, custody),
    {code: 'ClientRelationSampleOriginalChanged'});
  f.reopen();
  assert.deepEqual(lookup(sample.cid, custody), receipt, 'the private reconciliation receipt survives expiry');
  let reserved = false;
  assert.throws(() => lookup(sample.cid, {current: () => false, reserve() {reserved = true;}}),
    {code: 'ClientRelationSampleDenied'});
  assert.equal(reserved, false);
  let readChecks = 0;
  assert.throws(() => lookup(sample.cid, {...custody, current: () => ++readChecks < 4}),
    {code: 'ClientRelationSampleDenied'});
  assert.equal(readChecks, 4);
  assert.deepEqual(f.journal.lookupRelationSampleAdoption({...ref, namespaceId: 'foreign-scope'},
    sample.cid, custody, publication), {kind: 'unobserved'});
});

test('cold Relation Sample read checks current access, bound evidence and the original receipt', async t => {
  let now = Date.now();
  const {f, ref, adopt, retire} = await relationSampleWriter(t, {submissionEpochNow: () => now});
  const sample = committedRelationSample(ref);
  const access = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  const receipt = adopt(sample.wires, access);
  f.reopen();

  const selection = {sampleRefCid: sample.cid, compiledPlanCid: cid('4'), logicalMapCid: cid('5'),
    stepId: cid('6'), outputPortId: cid('7'), carrierContractCid: cid('a'), maxBytes: 1024};
  const read = (selected = selection, custody = access, run = ref, control = publication) =>
    f.journal.readRetainedRelationSample(run, selected, custody, control);
  const update = (set, ...arguments_) => f.update(
    `UPDATE client_relation_sample_adoptions SET ${set} WHERE sample_ref_cid = ?`, ...arguments_, sample.cid);

  const byPort = {...selection, sampleRefCid: undefined};
  for (const sampleRefCid of [sample.cid, cid('d'), undefined]) {
    assert.throws(() => read({...selection, sampleRefCid}, {
      current: () => false, reserve() {assert.fail('denied access may not reserve an extent');},
    }), {code: 'ClientRelationSampleDenied'});
  }
  assert.deepEqual(read(selection, access, {...ref, namespaceId: 'foreign-scope'}), {kind: 'unobserved'});

  let live = true;
  assert.throws(() => read(selection, {
    current: () => live, reserve() {live = false;},
  }), {code: 'ClientRelationSampleDenied'});
  let funded = 0;
  const {kind, source, relation, receipt: originalReceipt} = read(selection, {
    current: () => true, reserve(bytes) {funded += bytes;},
  });
  assert.equal(kind, 'available');
  assert.deepEqual(source.run_ref, ref);
  assert.equal(source.output_port_id, selection.outputPortId);
  assert.deepEqual(relation, JSON.parse(sample.wires.relation));
  assert.deepEqual(originalReceipt, receipt);
  assert.deepEqual(read(byPort).receipt, receipt, 'the exact port selects its original receipt after reopening');
  const writer = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    writer.exec('BEGIN IMMEDIATE');
    writer.prepare('UPDATE client_relation_sample_adoptions SET relation_wire = ? WHERE sample_ref_cid = ?')
      .run(sample.wires.relation.replace('"value":7', '"value":8'), sample.cid);
    const observed = read(byPort);
    assert.deepEqual(observed.receipt, receipt, 'another writer cannot hide this committed receipt');
    assert.deepEqual(observed.relation, JSON.parse(sample.wires.relation));
    writer.exec('ROLLBACK');
  } finally {writer.close();}
  assert.deepEqual(read({...byPort, outputPortId: cid('e')}), {kind: 'unobserved'});
  assert.deepEqual(read(byPort, access, {...ref, namespaceId: 'foreign-scope'}), {kind: 'unobserved'});
  let reserves = 0;
  assert.throws(() => read(byPort, {...access, reserve(bytes) {
    assert.ok(bytes > 0);
    if (++reserves === 2) update('original_capture_cid = ?', cid('e'));
  }}), {code: 'ClientRelationSampleOriginalChanged'},
  'the second original proof catches a changed association after funding');
  update('original_capture_cid = ?', JSON.parse(sample.wires.capture).self_cid);
  let storedReceiptBytes;
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    storedReceiptBytes = db.prepare('SELECT length(CAST(receipt_wire AS BLOB)) AS bytes FROM client_relation_sample_adoptions WHERE sample_ref_cid = ?')
      .get(sample.cid).bytes;
  } finally {db.close();}
  assert.equal(funded, storedReceiptBytes + Object.values(sample.wires).reduce((sum, wire) => sum + Buffer.byteLength(wire), 0));
  assert.throws(() => read({...selection, outputPortId: cid('e')}), {code: 'ClientRelationSampleOriginalChanged'});
  update('relation_wire = ?', sample.wires.relation.replace('"value":7', '"value":8'));
  assert.throws(() => read(), {code: 'ClientRelationSampleOriginalChanged'});
  update('source_generation_wire = NULL, capture_wire = NULL, emission_wire = NULL, reference_wire = NULL, relation_wire = NULL');
  assert.throws(() => read(), {code: 'ClientRelationSampleInvalidOriginal'});
  assert.throws(() => read(byPort), {code: 'ClientRelationSampleInvalidOriginal'},
    'the same future-expiry row without payload is corrupt even with a proven output association');
  update('source_generation_wire = ?, capture_wire = ?, emission_wire = ?, reference_wire = ?, relation_wire = ?',
    sample.wires.generation, sample.wires.capture, sample.wires.emission, sample.wires.reference, sample.wires.relation);

  // The clock can reach expiry while the read tariff is admitted. Only the
  // unchanged original receipt is materialized in the subsequent transaction.
  const admittedAfterQuote = [];
  const trackAdmission = (name, ...arguments_) => {
    admittedAfterQuote.push(name);
    return publication.admitRunEvidence(name, ...arguments_);
  };
  assert.deepEqual(read(selection, {current: () => true, reserve() {now = receipt.expiresAt;}},
    ref, {admitRunEvidence: trackAdmission}), {kind: 'expired', sampleRefCid: sample.cid});
  assert.deepEqual(admittedAfterQuote, ['sample_adoption_receipt']);

  // Even before retirement, expiry only loads the receipt, with no step or
  // port status inferred from it. The one-byte payload limit cannot admit
  // the actual retained Relation.
  now = receipt.expiresAt;
  const admitted = [];
  const admitRunEvidence = (...arguments_) => {
    admitted.push(arguments_[0]);
    return publication.admitRunEvidence(...arguments_);
  };
  assert.deepEqual(read({...selection, maxBytes: 1}, {current: () => true,
    reserve(bytes) {assert.equal(bytes, storedReceiptBytes);}}, ref, {admitRunEvidence}),
  {kind: 'expired', sampleRefCid: sample.cid});
  assert.deepEqual(admitted, ['sample_adoption_receipt']);
  assert.equal(retire(sample.cid, access), true);
  f.reopen();
  assert.deepEqual(read(), {kind: 'expired', sampleRefCid: sample.cid});
  const selectedEvidence = [];
  const sealRunEvidence = (name, ...arguments_) => {
    selectedEvidence.push(name);
    return publication.sealRunEvidence(name, ...arguments_);
  };
  assert.deepEqual(read({...byPort, maxBytes: 1}, access, ref, {admitRunEvidence, sealRunEvidence}),
    {kind: 'expired', sampleRefCid: sample.cid});
  assert.deepEqual(selectedEvidence, ['sample_reference', 'sample_reference']);
  assert.deepEqual(admitted, ['sample_adoption_receipt', 'sample_adoption_receipt']);
  update('emission_provenance_cid = ?', cid('e'));
  assert.throws(() => read(byPort), {code: 'ClientRelationSampleOriginalChanged'},
    'an expired receipt alone cannot authenticate a damaged port association');
});

test('Relation Sample adoption with an uncertain COMMIT resolves only the original durable key', async t => {
  for (const committed of [true, false]) {
    const {f, adopt, ref, lookup} = await relationSampleWriter(t);
    const sample = committedRelationSample(ref);
    const custody = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    DatabaseSync.prototype.exec = function(sql) {
      if (sql === 'COMMIT' && !injected) {
        injected = true;
        if (committed) Reflect.apply(exec, this, [sql]);
        throw new Error('SampleAdoptionCommitReplyLost');
      }
      return Reflect.apply(exec, this, [sql]);
    };
    try {
      assert.throws(() => adopt(sample.wires, custody), {
        code: 'ClientRelationSampleAdoptionUnknown', outcome: 'unknown',
      });
    } finally { DatabaseSync.prototype.exec = exec; }
    assert.equal(injected, true);
    f.reopen();
    assert.throws(() => adopt(sample.wires, custody), {code: 'ClientRequestJournalClosed'});
    const retained = lookup(sample.cid, custody);
    assert.equal(retained.kind, committed ? 'adopted' : 'unobserved');
    if (committed) assert.equal(retained.sampleRefCid, sample.cid);
    assert.deepEqual(lookup(cid('f'), custody), {kind: 'unobserved'});
  }
});

test('Relation Sample adoption refuses equal payloads from another scope and asynchronous loans', async t => {
  const {writer, ref, committedPrefix, withAdoption, prepare, lookup, adopt} = await relationSampleWriter(t);
  const first = committedRelationSample(ref);
  const second = committedRelationSample(ref, {attempt: '2'});
  assert.equal(first.wires.relation, second.wires.relation);
  assert.notEqual(first.cid, second.cid);
  assert.throws(() => writer(second.wires), {code: 'ClientRelationSampleForeignLoan'});
  const another = prepare();
  assert.throws(() => another.withAdoption(committedPrefix(second.wires), () => true, loan => {
    writer(loan);
  }), {code: 'ClientRelationSampleForeignLoan'});
  let suspended;
  assert.throws(() => withAdoption(committedPrefix(first.wires), () => true, loan => {
    suspended = Promise.resolve().then(() => {
      assert.throws(() => writer(loan), {code: 'ClientRelationSampleForeignLoan'});
    });
    return suspended;
  }), {message: 'ClientRelationSampleVisitMustBeSynchronous'});
  await suspended;
  const read = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  assert.deepEqual(lookup(first.cid, read), {kind: 'unobserved'});
  assert.deepEqual(lookup(second.cid, read), {kind: 'unobserved'});
  assert.equal(adopt(first.wires, read).sampleRefCid, first.cid);
});

function readSampleRecords(path) {
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  try {
    return database.prepare(`SELECT sample_ref_cid, journal_receipt_ordinal, run_receipt_ordinal,
      source_generation_wire IS NOT NULL AS generation,
      capture_wire IS NOT NULL AS capture, emission_wire IS NOT NULL AS emission,
      reference_wire IS NOT NULL AS reference, relation_wire IS NOT NULL AS relation
      FROM client_relation_sample_adoptions ORDER BY sample_ref_cid`).all();
  } finally {database.close();}
}

test('Relation Sample retirement leaves other rows and durable receipt limits intact', async t => {
  const initial = Date.now();
  let now = initial;
  const options = {maxRecords: 4, submissionEpochNow: () => now};
  const a = await relationSampleWriter(t, options, {maxArtifacts: 2});
  const b = await relationSampleWriter(t, options, {shared: a.f, runName: 'second-original', maxArtifacts: 3});
  const access = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  const sample = (owner, attempt, maxArtifacts) => committedRelationSample(owner.ref, {attempt, maxArtifacts});
  const a1 = sample(a, '1', 2), a2 = sample(a, '2', 2), a3 = sample(a, '3', 2);
  const b1 = sample(b, '1', 3), b2 = sample(b, '2', 3), b3 = sample(b, '3', 3);

  const first = a.adopt(a1.wires, access);
  assert.equal(a.retire(a1.cid, access), false);
  now = initial + 1000;
  const next = a.adopt(a2.wires, access);
  const selectedPort = {compiledPlanCid: cid('4'), logicalMapCid: cid('5'), stepId: cid('6'),
    outputPortId: cid('7'), carrierContractCid: cid('a'), maxBytes: 1024};
  assert.deepEqual(a.f.journal.readRetainedRelationSample(a.ref, selectedPort, access, publication),
    {kind: 'ambiguous'}, 'more than one generation cannot select a replacement for this output port');
  assert.throws(() => a.adopt(a3.wires, access), {code: 'ClientRelationSampleCapacity'});
  now = initial + 2000;
  const other = b.adopt(b1.wires, access);
  const before = readSampleRecords(a.f.path);

  now = initial + 60_000;
  assert.equal(b.retire(a1.cid, access), false);
  assert.throws(() => a.retire(a1.cid, {...access, current: () => false}),
    {code: 'ClientRelationSampleDenied'});
  let checks = 0;
  assert.throws(() => a.retire(a1.cid, {...access, current: () => ++checks < 4}),
    {code: 'ClientRelationSampleDenied'});
  assert.deepEqual(readSampleRecords(a.f.path), before, 'authority loss rolled back retirement');

  assert.equal(a.retire(a1.cid, access), true);
  const find = ref => readSampleRecords(a.f.path).find(row => row.sample_ref_cid === ref.cid);
  assert.deepEqual({...find(a1)}, {sample_ref_cid: a1.cid, journal_receipt_ordinal: 1, run_receipt_ordinal: 1,
    generation: 0, capture: 0, emission: 0, reference: 0, relation: 0});
  assert.deepEqual(readSampleRecords(a.f.path).filter(row => row.sample_ref_cid !== a1.cid),
    before.filter(row => row.sample_ref_cid !== a1.cid), 'retirement leaves every other original row unchanged');
  assert.deepEqual(a.lookup(a1.cid, access), first);
  assert.deepEqual(a.lookup(a2.cid, access), next);
  assert.deepEqual(b.lookup(b1.cid, access), other);
  assert.deepEqual(a.adopt(a1.wires, access), first, 'retry of a retired key does not recreate its payload');
  assert.equal(find(a1).relation, 0);
  assert.equal(a.retire(a1.cid, access), false);
  const retired = readSampleRecords(a.f.path);
  assert.throws(() => a.adopt(a3.wires, access), {code: 'ClientRelationSampleCapacity'});
  assert.deepEqual(readSampleRecords(a.f.path), retired, 'expiry does not renew the original Run allowance');
  assert.equal(b.adopt(b2.wires, access).sampleRefCid, b2.cid);
  assert.deepEqual([find(b2).journal_receipt_ordinal, find(b2).run_receipt_ordinal], [4, 2]);
  const full = readSampleRecords(a.f.path);
  assert.throws(() => b.adopt(b3.wires, access), {code: 'ClientRelationSampleCapacity'});
  assert.deepEqual(readSampleRecords(a.f.path), full, 'the durable cap refuses a new key before any mutation');
  assert.deepEqual(b.lookup(b3.cid, access), {kind: 'unobserved'});
  a.f.reopen();
  now = initial;
  assert.equal(a.retire(a1.cid, access), false);
  assert.deepEqual(a.lookup(a1.cid, access), first);
  assert.throws(() => a.adopt(a1.wires, access), {code: 'ClientRequestJournalClosed'});
  assert.deepEqual(readSampleRecords(a.f.path), full);
});

test('Relation Sample retirement releases no observed slot on uncertain COMMIT', async t => {
  let now = Date.now();
  const {f, adopt, ref, retire, lookup} = await relationSampleWriter(t, {submissionEpochNow: () => now});
  const sample = committedRelationSample(ref);
  const access = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  const receipt = adopt(sample.wires, access);
  now = receipt.expiresAt;
  const exec = DatabaseSync.prototype.exec;
  let injected = false;
  DatabaseSync.prototype.exec = function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT' && !injected) {
      injected = true;
      throw new Error('RelationSampleRetirementCommitReplyLost');
    }
    return result;
  };
  try {
    assert.throws(() => retire(sample.cid, access), {
      code: 'ClientRelationSampleRetirementUnknown', outcome: 'unknown',
    });
  } finally {DatabaseSync.prototype.exec = exec;}
  assert.equal(injected, true);
  f.reopen();
  assert.equal(readSampleRecords(f.path)[0].relation, 0);
  assert.equal(retire(sample.cid, access), false);
  assert.deepEqual(lookup(sample.cid, access), receipt);
});

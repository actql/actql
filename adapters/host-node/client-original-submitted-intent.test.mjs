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

async function fixture(t, {selected = true, readOnly = false, link = true} = {}) {
  const path = await mkdtemp(join(tmpdir(), 'actql-original-submitted-intent-'));
  let journal = openClientRequestJournal(path);
  t.after(async () => {journal.close(); await rm(path, {recursive: true, force: true});});
  const epoch = journal.issueSubmissionEpoch(fields, moon);
  const reference = {epoch, nonce: 'same-original-content'};
  const intent = moon.clientSubmittedIntent(JSON.stringify({kind: 'program', input: {},
    parameters: null, ...(selected ? {stopBefore: 'commit'} : {}),
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
    version: 'actql-run-definition/0.1', scope_id: 'original-content-scope', run_id: 'same-original-run',
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
    try {return database.prepare('SELECT * FROM client_requests').get();}
    finally {database.close();}
  };
  const mutate = transform => {
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    try {
      const row = database.prepare('SELECT run_admission_evidence_json FROM client_requests').get();
      const material = JSON.parse(row.run_admission_evidence_json);
      transform(material);
      database.prepare('UPDATE client_requests SET run_admission_evidence_json = ?')
        .run(JSON.stringify(material));
    } finally {database.close();}
  };
  return {path, reference, intent, request, identity, accepted, readRow, mutate,
    get journal() {return journal;},
    read: (requestControl = moon, publicationControl = publication) =>
      journal.originalSubmittedIntent(identity, fields, requestControl, publicationControl),
    reopen() {journal.close(); journal = openClientRequestJournal(path);}};
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
  assert.deepEqual(counts, {identity: 1, intent: 1, definition: 1},
    'same selected scalar rows reuse the actual admitted originals, not another decode/hash');
  f.read(requestControl, publicationControl).assertCurrent();
  assert.deepEqual(counts, {identity: 2, intent: 2, definition: 2},
    'a distinct original operation has its own initial admission');
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

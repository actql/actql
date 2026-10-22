import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import test from 'node:test';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalJson} from './local-account-config.mjs';

const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
const scope = `sha256:${'a'.repeat(64)}`;
const fields = {authorityScopeCid: scope, namespaceId: 'submission-operation', currentAuthorization: true};
const start = 1_800_000_000_000;
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;
const cid = digit => `sha256:${digit.repeat(64)}`;

async function fixture(t, {prepare, submit} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-submission-operation-'));
  let now = start, allowed = true, parsing = 0, authentication = 0, clockWrites = 0;
  const intentAdmissions = new Map();
  const journal = openClientRequestJournal(root, {submissionEpochTtlMs: 1000, submissionEpochNow: () => now});
  t.after(async () => {journal.close(); await rm(root, {recursive: true, force: true});});
  const epoch = journal.issueSubmissionEpoch(fields, moon);
  const runtime = {...moon,
    clientSubmittedIntent(wire, ...limits) {
      intentAdmissions.set(wire, (intentAdmissions.get(wire) ?? 0) + 1);
      return moon.clientSubmittedIntent(wire, ...limits);
    },
    clientSubmissionEpoch(...args) {parsing++; return moon.clientSubmissionEpoch(...args);},
    clientSubmissionEpochWire(...args) {authentication++; return moon.clientSubmissionEpochWire(...args);},
  };
  const run = StatementSync.prototype.run;
  t.mock.method(StatementSync.prototype, 'run', function(...args) {
    if (this.sourceSQL.startsWith('UPDATE client_submission_epoch_authority SET observed_at')) clockWrites++;
    return Reflect.apply(run, this, args);
  });
  const body = {kind: 'aql', input: {format: 'aql-text', text: 'SELECT 1 AS value'}, parameters: null};
  const intent = moon.clientSubmittedIntent(JSON.stringify(body), 1048576, 65536, 64);
  const request = {principalId: 'principal', connection: {mode: 'local', owner: 'local',
    durability: 'durable', consentRefs: [], runners: []}, submissionRef: {epoch, nonce: 'original'},
  intentCid: moon.clientSubmittedIntentCid(intent),
  attemptRef: {operation: 'submit', attemptId: 'one-operation'}, ...body};
  const service = installNodeClientSubmission({journal, moon: runtime,
    authorizedScope: () => allowed ? fields : undefined,
    prepareSubmit: async value => {await prepare?.(value); now++; return {};},
    submit: async value => {
      if (submit !== undefined) return submit(value);
      const program = cid('1'), parameters = cid('2'), input = cid('3');
      const identity = moon.clientRequestAdmitRecord(scope, value.requestId, program, parameters, input,
        hash({authority_scope_cid: scope, caller_request_id: value.requestId, version: 'actql-logical-request/0.1'}),
        hash({caller_input_intent_cid: input, parameter_values_cid: parameters,
          program_definition_cid: program, version: 'actql-logical-request-intent/0.1'}));
      assert.ok(identity);
      const publication = runtimeCore(moon).publicationControl;
      const definition = publication.seal('run_definition', JSON.stringify({
        version: 'actql-run-definition/0.1', scope_id: 'submission-operation', run_id: 'original',
        compiled_plan_cid: cid('4'), invocation_template_cid: cid('5'), authorization_context_cid: cid('6'),
        input_artifact_set_cid: cid('7'), created_at: '2026-10-07T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z',
      }), {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});
      const accepted = journal.acceptDefinition(identity, {namespaceId: fields.namespaceId,
        runDefinition: definition, lookupExpiresAt: '2099-01-01T00:00:00.000Z', submission: value.submission}, runtime, publication);
      return {ref: accepted.ref, durability: accepted.durability, revision: accepted.revision};
    },
    lookupRequest: async value => {
      const found = journal.lookup({...fields, requestId: value.requestId}, runtime);
      return found === undefined ? {kind: 'not_found'} : {kind: 'found', ref: found.ref};
    },
  });
  return {journal, runtime, service, request, root,
    now(value) {now = value;}, deny() {allowed = false;},
    intentAdmissions() {return [...intentAdmissions.values()];},
    counts() {return {parsing, authentication, clockWrites};}};
}

test('one submit admits each unchanged intent wire once through preparation and original Run acceptance', async t => {
  const f = await fixture(t);
  f.now(start + 10);
  assert.equal((await f.service.submitAttempt(f.request)).outcome.kind, 'ready');
  assert.deepEqual(f.intentAdmissions(), [1], 'input and retained receipt share the same admitted immutable intent');
  assert.equal((await f.service.lookupSubmission(f.request)).kind, 'ready');
  assert.deepEqual(f.intentAdmissions(), [2], 'a new public observation admits its own saved original once');
  f.deny();
  assert.equal((await f.service.submitAttempt(f.request)).reason, 'authorization');
  assert.deepEqual(f.intentAdmissions(), [2], 'current Deny performs no intent admission or write');
});

test('intent reuse ends with its original operation and never crosses controls or changed wire', async t => {
  const f = await fixture(t), epoch = f.request.submissionRef.epoch;
  const wire = canonicalJson({kind: f.request.kind, input: f.request.input, parameters: null}, {dataKeys: true});
  const release = f.journal.retainSubmissionOperation(epoch, f.runtime);
  try {
    const original = f.journal.prepareSubmittedIntent(epoch, wire, f.runtime);
    assert.strictEqual(f.journal.prepareSubmittedIntent(epoch, moon.clientSubmittedIntentWire(original), f.runtime), original);
    const changed = f.journal.prepareSubmittedIntent(epoch, JSON.stringify({kind: f.request.kind,
      input: {...f.request.input, text: 'SELECT 2 AS value'}, parameters: null}), f.runtime);
    assert.notEqual(moon.clientSubmittedIntentCid(changed), moon.clientSubmittedIntentCid(original));
    let foreignAdmissions = 0;
    const other = {...f.runtime, clientSubmittedIntent(...args) {foreignAdmissions++; return moon.clientSubmittedIntent(...args);}};
    f.journal.prepareSubmittedIntent(epoch, moon.clientSubmittedIntentWire(changed), other);
    assert.equal(foreignAdmissions, 1, 'another control cannot borrow the operation original');
    assert.deepEqual(f.intentAdmissions(), [1, 1]);
  } finally {release();}
  f.journal.prepareSubmittedIntent(epoch, wire, f.runtime);
  assert.deepEqual(f.intentAdmissions(), [2, 1], 'the ended operation retains no reusable fact');
});

test('retained row identity is checked even when its wire is already admitted in this operation', async t => {
  const f = await fixture(t);
  assert.equal((await f.service.submitAttempt(f.request)).outcome.kind, 'ready');
  const epoch = f.request.submissionRef.epoch, release = f.journal.retainSubmissionOperation(epoch, f.runtime);
  try {
    const wire = canonicalJson({kind: f.request.kind, input: f.request.input, parameters: null}, {dataKeys: true});
    f.journal.prepareSubmittedIntent(epoch, wire, f.runtime);
    const database = new DatabaseSync(join(f.root, 'client-requests.sqlite3'));
    try {database.prepare('UPDATE client_submitted_intents SET intent_cid = ?').run(cid('f'));}
    finally {database.close();}
    assert.throws(() => f.journal.lookupSubmittedIntent(f.request.submissionRef, fields, f.runtime),
      {code: 'ClientSubmittedIntentCorrupt'});
    assert.deepEqual(f.intentAdmissions(), [2], 'the exact wire fact is reused, not the changed row identity');
  } finally {release();}
});

test('failed or oversized input is never retained and a closed Journal cannot reuse an admitted intent', async t => {
  const f = await fixture(t), epoch = f.request.submissionRef.epoch;
  const release = f.journal.retainSubmissionOperation(epoch, f.runtime);
  try {
    for (let i = 0; i < 2; i++) {
      assert.throws(() => f.journal.prepareSubmittedIntent(epoch, '{', f.runtime),
        {code: 'InvalidClientSubmittedIntent'});
    }
    assert.throws(() => f.journal.prepareSubmittedIntent(epoch, 'x'.repeat(1048577), f.runtime),
      {code: 'InvalidClientSubmittedIntent'});
    const wire = canonicalJson({kind: f.request.kind, input: f.request.input, parameters: null}, {dataKeys: true});
    f.journal.prepareSubmittedIntent(epoch, wire, f.runtime);
    assert.deepEqual(f.intentAdmissions(), [2, 1, 1]);
    f.journal.close();
    assert.throws(() => f.journal.prepareSubmittedIntent(epoch, wire, f.runtime),
      {code: 'ClientRequestJournalClosed'});
    assert.deepEqual(f.intentAdmissions(), [2, 1, 1]);
  } finally {release();}
});

test('one actual submit retains epoch authentication and one durable floor through the same Run acceptance', async t => {
  const f = await fixture(t);
  f.now(start + 10);
  assert.equal((await f.service.submitAttempt(f.request)).outcome.kind, 'ready');
  assert.deepEqual(f.counts(), {parsing: 1, authentication: 1, clockWrites: 1});
  const observed = await f.service.lookupSubmission(f.request);
  assert.equal(observed.kind, 'ready');
  assert.deepEqual(f.counts(), {parsing: 2, authentication: 2, clockWrites: 2},
    'a different public operation acquires its own current original');
  f.deny();
  const denied = await f.service.submitAttempt(f.request);
  assert.equal(denied.kind, 'refused');
  assert.equal(denied.reason, 'authorization');
  assert.deepEqual(f.counts(), {parsing: 2, authentication: 2, clockWrites: 2});
});

test('one actual submit and cold reopen use no whole-history quota aggregate',async t=>{
  const f=await fixture(t), queries=[];
  const get=StatementSync.prototype.get;
  t.mock.method(StatementSync.prototype,'get',function(...args) {
    if(/\bCOUNT\s*\(/iu.test(this.sourceSQL) &&
        /\bFROM\s+client_(?:requests|cancellation_operations|submission_names)\b/iu.test(this.sourceSQL)) {
      queries.push(this.sourceSQL);
    }
    return Reflect.apply(get,this,args);
  });
  f.now(start+10);
  assert.equal((await f.service.submitAttempt(f.request)).outcome.kind,'ready');
  assert.deepEqual(queries,[],'a real accepted Run reads its retained quota singleton, not unrelated rows');
  f.journal.close();
  const reopened=openClientRequestJournal(f.root,{submissionEpochNow:()=>start+20});
  try {
    assert.equal(reopened.lookupSubmittedIntent(f.request.submissionRef,fields,moon).phase,'ready');
    assert.deepEqual(queries,[],'an adopted ordinary reopen does not recount unrelated names or cancellations');
  } finally {reopened.close();}
});

for(const loss of ['table','row','trigger']) {
  test(`adopted request usage ${loss} loss refuses instead of resetting issuance`,async t=>{
    const f=await fixture(t);
    assert.equal((await f.service.submitAttempt(f.request)).outcome.kind,'ready');
    f.journal.close();
    const path=join(f.root,'client-requests.sqlite3'), database=new DatabaseSync(path);
    try {database.exec(loss==='table'?'DROP TABLE client_request_row_usage':
      loss==='row'?'DELETE FROM client_request_row_usage':'DROP TRIGGER client_request_row_usage_insert');}
    finally {database.close();}
    assert.throws(()=>openClientRequestJournal(f.root),{code:'UnknownClientRequestJournalFormat'});
    const retained=new DatabaseSync(path,{readOnly:true});
    try {assert.equal(retained.prepare('SELECT issued_count FROM client_submission_custody').get().issued_count,1);}
    finally {retained.close();}
  });
}

test('prior request quota adoption preserves original issued counts and commits no new Run',async t=>{
  const f=await fixture(t);
  assert.equal((await f.service.submitAttempt(f.request)).outcome.kind,'ready');
  f.journal.close();
  const database=new DatabaseSync(join(f.root,'client-requests.sqlite3'));
  try {
    for(const table of ['client_request_row_usage','client_cancellation_row_usage']) {
      for(const suffix of ['insert','delete']) database.exec(`DROP TRIGGER ${table}_${suffix}`);
      database.exec(`DROP TABLE ${table}`);
    }
    database.exec('PRAGMA user_version=1');
  } finally {database.close();}
  const queries=[], get=StatementSync.prototype.get;
  t.mock.method(StatementSync.prototype,'get',function(...args) {
    if(/\bCOUNT\s*\(/iu.test(this.sourceSQL)) queries.push(this.sourceSQL);
    return Reflect.apply(get,this,args);
  });
  const reopened=openClientRequestJournal(f.root,{submissionEpochNow:()=>start+20});
  try {
    assert.equal(queries.length,2,'only two bounded same-original adoption counts');
    assert(queries.every(sql=>sql.includes('LIMIT ?')));
    assert.equal(reopened.lookupSubmittedIntent(f.request.submissionRef,fields,moon).phase,'ready');
  } finally {reopened.close();}
  queries.length=0;
  const again=openClientRequestJournal(f.root,{submissionEpochNow:()=>start+30});
  try {assert.deepEqual(queries,[]);} finally {again.close();}
});

test('an interval crossed during preparation is durably expired without repeated authentication', async t => {
  let f;
  f = await fixture(t, {prepare() {f.now(start + 1000);}});
  f.now(start + 10);
  const answer = await f.service.submitAttempt(f.request);
  assert.equal(answer.kind, 'refused');
  assert.equal(answer.reason, 'epoch_expired');
  assert.deepEqual(f.counts(), {parsing: 1, authentication: 1, clockWrites: 2});
  f.journal.close();
  const reopened = openClientRequestJournal(f.root, {submissionEpochNow: () => start});
  try {
    assert.equal(reopened.verifySubmissionEpoch(f.request.submissionRef.epoch,
      {...fields, purpose: 'admit'}, moon).validity, 'expired');
  } finally {reopened.close();}
});

test('a changed original epoch key is not hidden by operation-local authentication reuse', async t => {
  let f;
  f = await fixture(t, {prepare() {
    const db = new DatabaseSync(join(f.root, 'client-requests.sqlite3'));
    try {db.prepare('UPDATE client_submission_epoch_authority SET authentication_key = ?').run('b'.repeat(64));}
    finally {db.close();}
  }});
  f.now(start + 10);
  await assert.rejects(f.service.submitAttempt(f.request), {code: 'ClientSubmissionEpochUnverifiable'});
  assert.deepEqual(f.counts(), {parsing: 1, authentication: 2, clockWrites: 1});
});

test('unknown initial floor COMMIT never turns the operation memo into a durable ACK', async t => {
  const f = await fixture(t);
  f.now(start + 10);
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (sql === 'COMMIT') throw new Error('lost commit reply');
    return Reflect.apply(exec, this, [sql]);
  });
  await assert.rejects(f.service.submitAttempt(f.request), {code: 'ClientRequestJournalCommitOutcomeUnknown'});
  t.mock.restoreAll();
  f.journal.close();
  const reopened = openClientRequestJournal(f.root, {submissionEpochNow: () => start});
  try {
    assert.equal(reopened.lookupSubmittedIntent(f.request.submissionRef, fields, moon), undefined);
  } finally {reopened.close();}
});

test('reentry is another public operation even when it receives the original private snapshot', async t => {
  let f, captured, observe;
  const entered = new Promise(resolve => {observe = resolve;});
  let resume;
  const pending = new Promise(resolve => {resume = resolve;});
  f = await fixture(t, {async prepare(value) {captured = value; observe(); await pending;}});
  f.now(start + 10);
  const first = f.service.submitAttempt(f.request);
  await entered;
  try {
    f.deny();
    assert.equal((await f.service.submitAttempt(captured)).reason, 'authorization');
  } finally {resume();}
  await assert.rejects(first, {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts(), {parsing: 1, authentication: 1, clockWrites: 1});
});

test('failed clock COMMIT retries the same observed expiry without reusing an uncommitted floor', async t => {
  const f = await fixture(t);
  const epoch = Object.freeze({...f.request.submissionRef.epoch});
  const release = f.journal.retainSubmissionOperation(epoch, f.runtime);
  const exec = DatabaseSync.prototype.exec;
  f.now(start + 1000);
  const intercepted = t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (sql === 'COMMIT') throw new Error('lost expiry commit reply');
    return Reflect.apply(exec, this, [sql]);
  });
  try {
    assert.throws(() => f.journal.verifySubmissionEpoch(epoch, {...fields, purpose: 'admit'}, f.runtime),
      {code: 'ClientRequestJournalCommitOutcomeUnknown'});
    intercepted.mock.restore();
    f.now(start);
    assert.equal(f.journal.verifySubmissionEpoch(epoch, {...fields, purpose: 'admit'}, f.runtime).validity,
      'expired');
    assert.equal(f.counts().clockWrites, 2);
  } finally {release();}
});

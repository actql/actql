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
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';

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
  const authenticatedEpochs = [];
  const childOperations = [];
  const operationStack = [];
  const originalInputs = new WeakMap();
  let submissions = 0;
  const journal = openClientRequestJournal(root, {submissionEpochTtlMs: 1000, submissionEpochNow: () => now});
  t.after(async () => {journal.close(); await rm(root, {recursive: true, force: true});});
  const epoch = journal.issueSubmissionEpoch(fields, moon);
  const runtime = {...moon,
    clientSubmittedIntent(wire, ...limits) {
      intentAdmissions.set(wire, (intentAdmissions.get(wire) ?? 0) + 1);
      return moon.clientSubmittedIntent(wire, ...limits);
    },
    clientSubmissionEpoch(...args) {parsing++; return moon.clientSubmissionEpoch(...args);},
    clientSubmissionEpochWire(...args) {
      authentication++;
      const wire = moon.clientSubmissionEpochWire(...args);
      authenticatedEpochs.push(JSON.parse(wire).epoch_nonce);
      return wire;
    },
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
  const serviceJournal = {...journal, retainSubmissionOperation(epoch, control, borrowedIntent) {
    const parent = operationStack.at(-1);
    if (parent !== undefined) childOperations.push({epoch, parentEpoch: parent.epoch, borrowedIntent,
      authenticationOffset: authenticatedEpochs.length});
    const release = journal.retainSubmissionOperation(epoch, control, borrowedIntent);
    const operation = {epoch};
    operationStack.push(operation);
    return () => {assert.strictEqual(operationStack.pop(), operation); release?.();};
  }};
  const service = installNodeClientSubmission({journal: serviceJournal, moon: runtime,
    authorizedScope: () => allowed ? fields : undefined,
    // The fixed preparation consumer lends one nominal input to this operation.
    // Journal admission itself deliberately has no inferred wire cache.
    bindOwnedRequest(parent, derived) {
      const original = originalInputs.get(parent);
      if (original !== undefined) originalInputs.set(derived, original);
    },
    submittedIntentOriginal(value) {
      if (!allowed) return undefined;
      let original = originalInputs.get(value);
      if (original === undefined) {
        const wire = canonicalJson({kind: value.kind, input: value.input, parameters: value.parameters}, {dataKeys: true});
        original = runtime.clientSubmittedIntent(wire, 1048576, 65536, 64);
        assert.ok(original);
        originalInputs.set(value, original);
      }
      return original;
    },
    prepareSubmit: async value => {await prepare?.(value); now++; return {};},
    submit: async value => {
      submissions++;
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
    authenticatedEpochs() {return authenticatedEpochs.slice();},
    childOperations() {return childOperations.slice();},
    submissions() {return submissions;},
    intentAdmissions() {return [...intentAdmissions.values()];},
    counts() {return {parsing, authentication, clockWrites};}};
}

test('request-key selected rows bind only through the same accepted original Run', async t => {
  const records = [];
  const publication = runtimeCore(moon).publicationControl;
  let returnedRows = 0;
  const nativeSelections = [];
  const originalGet = StatementSync.prototype.get;
  t.mock.method(StatementSync.prototype, 'get', function(...parameters) {
    const row = Reflect.apply(originalGet, this, parameters);
    const sql = this.sourceSQL.replace(/\s+/gu, ' ');
    if (!sql.startsWith('SELECT caller_request_id FROM') &&
        (sql.includes('FROM client_requests WHERE authority_scope_cid = ? AND caller_request_id = ?') ||
        sql.includes('FROM client_requests WHERE namespace_id = ? AND authority_scope_cid = ? AND') ||
        sql.includes('FROM client_requests WHERE run_definition_cid = ?'))) {
      returnedRows += row === undefined ? 0 : 1;
      nativeSelections.push({sql, returned: row === undefined ? 0 : 1});
    }
    return row;
  });
  // Capture before Journal preparation: its selected statements deliberately
  // retain their original get. Observation-budget reads use a separate reader.
  const f = await fixture(t);
  const observer = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record), include: ['run'],
    events: {level: 'diagnostic'}, measurements: {include: ['rows']},
  }), {journal: f.journal, runId(ref) {
    const found = f.journal.lookupRunDefinition(ref, f.runtime, publication);
    return found === undefined ? undefined : publication.runDefinitionRunId(found.runDefinition);
  }});
  f.journal.installObservationProjection(observer);
  let answer;
  try {
    answer = await observer.run('submit', {
      traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1,
    }, () => f.service.submitAttempt(f.request));
    assert.equal(answer.outcome.kind, 'ready');
    await observer.close();
  } finally {await observer.close();}
  const rows = records.filter(record => record.event === 'selected_rows_observed');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].attributes['actql.rows.selection'], 'mixed-selected');
  assert.equal(rows[0].attributes['actql.run.definition_cid'], answer.outcome.admission.ref.runDefinitionCid);
  assert.equal(rows[0].attributes['actql.rows.unrelated'], 0);
  assert.equal(rows[0].attributes['actql.rows.returned'], returnedRows,
    JSON.stringify(nativeSelections));
  assert(returnedRows > 0);
  assert.equal(f.submissions(), 1);
});

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
  const original = f.runtime.clientSubmittedIntent(wire, 1048576, 65536, 64);
  const release = f.journal.retainSubmissionOperation(epoch, f.runtime, original);
  try {
    assert.strictEqual(f.journal.prepareSubmittedIntent(epoch, wire, f.runtime), original);
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
  const epoch = f.request.submissionRef.epoch;
  const wire = canonicalJson({kind: f.request.kind, input: f.request.input, parameters: null}, {dataKeys: true});
  const original = f.runtime.clientSubmittedIntent(wire, 1048576, 65536, 64);
  const release = f.journal.retainSubmissionOperation(epoch, f.runtime, original);
  try {
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

test('named submission shares its admitted intent with new and original saved-reference consumers', async t => {
  const f = await fixture(t);
  const request = {...f.request, requestName: 'original-name'};
  assert.equal((await f.service.submitNamedAttempt(request)).outcome.kind, 'ready');
  assert.deepEqual(f.intentAdmissions(), [1]);
  const observed = await f.service.submitNamedAttempt({...request,
    submissionRef: {...request.submissionRef, nonce: 'fresh-nonce'}});
  assert.equal(observed.outcome.kind, 'ready');
  assert.deepEqual(f.intentAdmissions(), [2]);
  f.deny();
  assert.equal((await f.service.submitNamedAttempt(request)).reason, 'authorization');
  assert.deepEqual(f.intentAdmissions(), [2]);
});

test('a distinct valid epoch observes the named saved original with independent authentication and one intent admission', async t => {
  const f = await fixture(t), request = {...f.request, requestName: 'distinct-epoch-original'};
  const first = await f.service.submitNamedAttempt(request);
  assert.equal(first.outcome.kind, 'ready');
  const originalRef = first.outcome.submissionRef;
  const originalRun = first.outcome.admission.ref;
  assert.equal(f.submissions(), 1);
  assert.deepEqual(f.childOperations(), []);
  f.now(start + 900);
  const freshEpoch = f.journal.issueSubmissionEpoch(fields, f.runtime);
  assert.notEqual(freshEpoch.epochNonce, originalRef.epoch.epochNonce);
  assert.notDeepEqual(freshEpoch, originalRef.epoch);
  f.now(start + 1050);
  assert(originalRef.epoch.expiresAt <= start + 1050);
  assert(freshEpoch.notBefore <= start + 1050 && freshEpoch.expiresAt > start + 1050);
  const observed = await f.service.submitNamedAttempt({...request,
    submissionRef: {epoch: freshEpoch, nonce: 'fresh-epoch-reference'}});
  assert.equal(observed.outcome.kind, 'ready');
  assert.deepEqual(observed.outcome.submissionRef, originalRef);
  assert.deepEqual(observed.outcome.admission.ref, originalRun);
  assert.equal(f.submissions(), 1, 'name lookup does not submit, renew or replace its original Run');
  assert.deepEqual(f.intentAdmissions(), [2], 'each public operation admits the same immutable wire only once');
  const [child] = f.childOperations();
  assert.equal(f.childOperations().length, 1, 'the distinct saved-epoch child branch actually runs');
  assert.notStrictEqual(child.epoch, child.parentEpoch);
  assert.deepEqual(child.epoch, originalRef.epoch);
  assert.deepEqual(child.parentEpoch, freshEpoch);
  assert(f.authenticatedEpochs().slice(child.authenticationOffset).includes(originalRef.epoch.epochNonce),
    'the child independently authenticates its saved epoch after borrowing only the immutable input');
  const database = new DatabaseSync(join(f.root, 'client-requests.sqlite3'), {readOnly: true});
  try {
    assert.equal(database.prepare('SELECT observed_at FROM client_submission_epoch_authority').get().observed_at, start + 1050);
    assert.equal(database.prepare('SELECT issued_count FROM client_submission_custody').get().issued_count, 1);
    assert.equal(database.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 1);
  } finally {database.close();}
  const beforeDeny = {auth: f.authenticatedEpochs(), admissions: f.intentAdmissions()};
  f.deny();
  assert.equal((await f.service.submitNamedAttempt({...request,
    submissionRef: {epoch: freshEpoch, nonce: 'denied-fresh-reference'}})).reason, 'authorization');
  assert.deepEqual(f.authenticatedEpochs(), beforeDeny.auth);
  assert.deepEqual(f.intentAdmissions(), beforeDeny.admissions);
  assert.equal(f.submissions(), 1);
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

import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {validSubmissionLookup, validCheckOutcome} from '../../packages/client-wire/index.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';

const valuesWire = JSON.parse(await readFile(new URL(
  '../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8'));
const valuesEnvironment = moon.clientProgramCheckEnvironment(canonicalText(valuesWire),
  valuesWire.evidence_bundle_cid, false, false, true, false, false, false, false);
assert.ok(valuesEnvironment);
const checkValues = installNodeClientCheck({moon, environment: valuesEnvironment});

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const connection = {mode: 'local', owner: 'local', durability: 'durable', consentRefs: [], runners: []};
const principalId = 'submission-principal';
const fields = {authorityScopeCid, namespaceId: 'submission-test', currentAuthorization: true};
async function fixture(t, callbacks = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-d-submission-connection-'));
  let journal = openClientRequestJournal(root, callbacks.journalOptions);
  t.after(async () => {journal.close(); await rm(root, {recursive: true, force: true});});
  let authorized = true;
  let prepareCount = 0, submitCount = 0;
  let service;
  const install = () => service = installNodeClientSubmission({journal, moon,
    authorizedScope: () => authorized ? fields : undefined,
    prepareSubmit: async value => {prepareCount++; return callbacks.prepare?.(value) ?? {};},
    submit: async value => {submitCount++; return await callbacks.submit(value);},
    lookupRequest: async value => callbacks.lookup?.(value) ?? {kind: 'not_found'},
    checkSubmissionInput: callbacks.check ?? checkValues,
    admitPreparedSubmission: callbacks.admit,
    observeOriginalPreparationFailure: callbacks.originalObservation,
  });
  install();
  const ref = {epoch: await service.issueEpoch({principalId, connection}), nonce: 'original-nonce'};
  const body = (text = 'SELECT 1 AS value') => {
    const source = {kind: 'aql', input: {format: 'aql-text', text}, parameters: null};
    const intent = moon.clientSubmittedIntent(JSON.stringify(source), 1048576, 65536, 64);
    return {principalId, connection, submissionRef: ref, intentCid: moon.clientSubmittedIntentCid(intent),
      attemptRef: {operation: 'submit', attemptId: 'submission-test-invocation'}, ...source};
  };
  const port = () => createNodeInProcessClientHost({authenticate: () => principalId,
    authorizeConnection: () => authorized, negotiate: () => undefined,
    submitIntent: service.submitAttempt, submitNamedIntent: service.submitNamedAttempt,
    lookupSubmission: service.lookupSubmission, maxRowBytes: 65536});
  return {root, ref, body, port, get journal() {return journal;}, get service() {return service;},
    get counts() {return {prepare: prepareCount, submit: submitCount};},
    authorize: value => {authorized = value;}, restart() {journal.close(); journal = openClientRequestJournal(root, callbacks.journalOptions); install();}};
}

// Check observations are transient submit metadata, not durable acceptance.
function acceptanceFacts(response) {
  const {checkObservation, ...facts} = response;
  if (checkObservation !== undefined) assert.equal(validCheckOutcome(checkObservation), true);
  return facts;
}
function assertReferenceOnly(actual, original, message) {
  assert.equal(Object.hasOwn(actual, 'checkObservation'), false,
    '[check-mutation:submission-check-reference-only]');
  assert.deepEqual(actual, acceptanceFacts(original), message);
}

function admitOriginal(f, value) {
  const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
  const fixed = digit => 'sha256:' + digit.repeat(64);
  const program = fixed('1'), parameters = fixed('2'), input = fixed('3');
  const identity = moon.clientRequestAdmitRecord(authorityScopeCid, value.requestId,
    program, parameters, input,
    cid({version: 'actql-logical-request/0.1', authority_scope_cid: authorityScopeCid,
      caller_request_id: value.requestId}),
    cid({version: 'actql-logical-request-intent/0.1', program_definition_cid: program,
      parameter_values_cid: parameters, caller_input_intent_cid: input}));
  assert.ok(identity);
  const control = runtimeCore(moon).publicationControl;
  const definition = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: 'submission-test-scope', run_id: 'original-run',
    compiled_plan_cid: fixed('4'), invocation_template_cid: fixed('5'),
    authorization_context_cid: fixed('6'), input_artifact_set_cid: fixed('7'),
    created_at: '2026-10-07T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z',
  }), {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});
  const accepted = f.journal.acceptDefinition(identity, {namespaceId: fields.namespaceId,
    runDefinition: definition, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    submission: value.submission}, moon, control);
  return {ref: accepted.ref, durability: accepted.durability, revision: accepted.revision};
}

async function lookupClient(t, f, observe = value => f.service.lookupSubmission(value), ingress = {}) {
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'durable', scopeRef: 'submission-test', capabilities: [],
    submissionEpoch: f.ref.epoch, limits: {maxReadWireBytes: 4096,
      maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
      maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 2048}};
  const client = await connectInProcess({mode: 'local', owner: 'local'},
    createNodeInProcessClientHost({authenticate: () => principalId,
      authorizeConnection: () => true, negotiate: () => profile,
      lookupSubmission: observe, maxRowBytes: 65536, ...ingress}));
  t.after(() => client.close());
  return client;
}

async function acceptedLookupFixture(t) {
  let f;
  f = await fixture(t, {submit: value => admitOriginal(f, value), lookup(value) {
    const saved = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return saved === undefined ? {kind: 'not_found'} : {kind: 'found', ref: saved.ref};
  }});
  const original = await f.service.submitIntent(f.body());
  assert.equal(original.kind, 'ready');
  return {f, original};
}

test('public submission lookup keeps live signals outside the canonical request and original identity', async t => {
  const {f, original} = await acceptedLookupFixture(t);
  const snapshots = [];
  const client = await lookupClient(t, f, value => {
    assert.equal(Object.hasOwn(value, 'signal'), false);
    assert.ok(Object.isFrozen(value));
    snapshots.push(value);
    return f.service.lookupSubmission(value);
  });
  for (const kind of ['omitted-before', 'plain', 'timeout', 'omitted-after']) {
    const signal = kind === 'plain' ? new AbortController().signal :
      kind === 'timeout' ? AbortSignal.timeout(15000) : undefined;
    const started = performance.now();
    const found = await client.lookupSubmission(f.ref, signal === undefined ? undefined : {signal});
    t.diagnostic(JSON.stringify({kind, durationMs: performance.now() - started}));
    assert.equal(signal?.aborted ?? false, false);
    assert.deepEqual(found, original);
    assert.deepEqual(found.admission.ref, original.admission.ref);
  }
  assert.equal(snapshots.length, 4);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1}, 'lookup never resubmits the original');
  // No arbitrary non-data property is silently stripped by the durable owner.
  await assert.rejects(f.service.lookupSubmission({principalId, connection,
    submissionRef: f.ref, extra: new AbortController().signal}), /InvalidCanonicalValue/);
  assert.deepEqual(await client.lookupSubmission(f.ref), original);
});

test('public submission lookup rejects pre-abort without entering its handler', async t => {
  const {f, original} = await acceptedLookupFixture(t);
  let calls = 0;
  const client = await lookupClient(t, f, value => {calls++; return f.service.lookupSubmission(value);});
  const started = performance.now();
  await assert.rejects(client.lookupSubmission(f.ref, {signal: AbortSignal.abort()}),
    {code: 'ClientHostFailure'});
  t.diagnostic(JSON.stringify({kind: 'already-aborted', durationMs: performance.now() - started}));
  assert.equal(calls, 0);
  assert.deepEqual(await client.lookupSubmission(f.ref), original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('public submission lookup observes later abort after handler settlement without cancelling the original', async t => {
  const {f, original} = await acceptedLookupFixture(t);
  let enter, release, settled = false, returned = false;
  const entered = new Promise(resolve => {enter = resolve;});
  const gate = new Promise(resolve => {release = resolve;});
  const client = await lookupClient(t, f, async value => {
    enter();
    await gate;
    const found = await f.service.lookupSubmission(value);
    assert.deepEqual(found, original);
    settled = true;
    return found;
  });
  const controller = new AbortController();
  const reference = structuredClone(f.ref);
  const started = performance.now();
  const pending = client.lookupSubmission(reference, {signal: controller.signal});
  const rejected = assert.rejects(pending, error => {
    assert.equal(settled, true, 'the original handler retains custody until it settles');
    returned = true;
    return error.code === 'ClientHostFailure';
  });
  try {
    await entered;
    reference.nonce = 'caller-mutation-after-intake';
    controller.abort();
    await Promise.resolve();
    assert.equal(returned, false, 'this is not an interruptible service or early custody release');
  } finally {release();}
  await rejected;
  t.diagnostic(JSON.stringify({kind: 'later-aborted-after-settlement', durationMs: performance.now() - started}));
  assert.deepEqual(await client.lookupSubmission(f.ref), original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

for (const stage of ['authenticate', 'authorizeConnection']) {
  test(`public submission lookup abort during awaited ${stage} never enters the handler`,
    {timeout: 5000}, async t => {
      const {f, original} = await acceptedLookupFixture(t);
      let enter, release, paused = false, calls = 0;
      const entered = new Promise(resolve => {enter = resolve;});
      const gate = new Promise(resolve => {release = resolve;});
      const client = await lookupClient(t, f, value => {
        calls++;
        return f.service.lookupSubmission(value);
      }, {[stage]: async () => {
        if (paused) {enter(); await gate;}
        return stage === 'authenticate' ? principalId : true;
      }});
      paused = true;
      const controller = new AbortController();
      const started = performance.now();
      // Ordinary abort reasons keep the existing sanitized error taxonomy;
      // this does not introduce a cancellation wire code or interrupt the gate.
      const rejected = assert.rejects(client.lookupSubmission(f.ref,
        {signal: controller.signal}), {code: 'ClientHostFailure'});
      try {await entered; controller.abort();}
      finally {release();}
      await rejected;
      t.diagnostic(JSON.stringify({kind: `abort-during-${stage}`, durationMs: performance.now() - started}));
      assert.equal(calls, 0);
      paused = false;
      assert.deepEqual(await client.lookupSubmission(f.ref), original);
      assert.deepEqual(f.counts, {prepare: 1, submit: 1});
    });
}

test('public submission lookup preserves sanitized handler rejection when its signal also aborts',
  {timeout: 5000}, async t => {
    const {f, original} = await acceptedLookupFixture(t);
    let enter, release, rejectHandler = true, calls = 0;
    const entered = new Promise(resolve => {enter = resolve;});
    const gate = new Promise(resolve => {release = resolve;});
    const privateFailure = Object.assign(new Error('private lookup details'),
      {code: 'ClientRequestLookupDenied', cause: new Error('private cause'), stack: 'private handler stack'});
    const client = await lookupClient(t, f, async value => {
      calls++;
      if (!rejectHandler) return f.service.lookupSubmission(value);
      enter();
      await gate;
      throw privateFailure;
    });
    const controller = new AbortController();
    const started = performance.now();
    const rejected = assert.rejects(client.lookupSubmission(f.ref, {signal: controller.signal}), error => {
      assert.notStrictEqual(error, privateFailure);
      assert.equal(error.code, 'ClientRequestLookupDenied');
      assert.equal(error.status, 403);
      assert.equal(error.cause, undefined);
      assert.doesNotMatch(error.stack ?? '', /private handler stack/);
      assert.doesNotMatch(error.message, /private/);
      return true;
    });
    try {await entered; controller.abort();}
    finally {release();}
    await rejected;
    t.diagnostic(JSON.stringify({kind: 'handler-rejection-and-abort', durationMs: performance.now() - started}));
    assert.equal(calls, 1);
    rejectHandler = false;
    assert.deepEqual(await client.lookupSubmission(f.ref), original);
    assert.deepEqual(f.counts, {prepare: 1, submit: 1});
  });

test('named submission observes the same original Run after reopening without replaying preparation', async t => {
  let f;
  f = await fixture(t, {submit: value => admitOriginal(f, value), lookup(value) {
    const saved = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return saved === undefined ? {kind: 'not_found'} : {kind: 'found', ref: saved.ref};
  }});
  const {principalId: ignored, ...body} = f.body();
  void ignored;
  const request = {...body, requestName: 'same-original-run'};
  const first = await f.port().perform('submit-named-intent', request);
  assert.equal(first.kind, 'observed');
  assert.equal(first.outcome.kind, 'ready');
  assert.deepEqual(first.outcome.submissionRef, f.ref);
  f.restart();
  const candidate = {epoch: await f.service.issueEpoch({principalId, connection}), nonce: 'fresh-connection'};
  assert.notDeepEqual(candidate.epoch, f.ref.epoch);
  const repeated = await f.port().perform('submit-named-intent', {...request, submissionRef: candidate,
    attemptRef: {operation: 'submit', attemptId: 'second-connection'}});
  assert.equal(repeated.kind, 'observed');
  assert.deepEqual(repeated.outcome, first.outcome);
  assert.deepEqual(repeated.attemptRef, {operation: 'submit', attemptId: 'second-connection'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 1}, 'the named retry is observation, not explicit replay');
});

test('named submission cannot enter another preparation while its original is still pending', async t => {
  let f, release, entered;
  const started = new Promise(resolve => {entered = resolve;});
  const pending = new Promise(resolve => {release = resolve;});
  f = await fixture(t, {async prepare() {entered(); await pending; return {};},
    submit: value => admitOriginal(f, value), lookup(value) {
      const saved = f.journal.lookup({...fields, requestId: value.requestId}, moon);
      return saved === undefined ? {kind: 'not_found'} : {kind: 'found', ref: saved.ref};
    }});
  const value = {...f.body(), requestName: 'one-preparation'};
  const first = f.service.submitNamedAttempt(value);
  try {
    await started;
    const candidate = {epoch: await f.service.issueEpoch(value), nonce: 'competing-connection'};
    const observed = await f.service.submitNamedAttempt({...value, submissionRef: candidate});
    assert.equal(observed.kind, 'observed');
    assert.equal(observed.outcome.kind, 'preparing');
    assert.deepEqual(observed.outcome.submissionRef, f.ref);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  } finally {release(); await first;}
});

test('named submission preserves an unknown original and does not certify a forged capacity error', async t => {
  const interruption = Object.assign(new Error('fixture original preparation interrupted'),
    {code: 'ClientSubmissionNameCapacity'});
  const f = await fixture(t, {prepare() {throw interruption;}});
  const value = {...f.body(), requestName: 'unknown-original'};
  await assert.rejects(f.service.submitNamedAttempt(value), error => error === interruption);
  f.restart();
  const observed = await f.service.submitNamedAttempt({...value, submissionRef: {
    epoch: await f.service.issueEpoch(value), nonce: 'new-connection-after-loss'}});
  assert.equal(observed.kind, 'observed');
  assert.equal(observed.outcome.kind, 'preparing');
  assert.deepEqual(observed.outcome.submissionRef, f.ref);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('named submission keeps original binding when current authority disappears after preparation', async t => {
  let f;
  f = await fixture(t, {prepare() {f.authorize(false); return {};}});
  const value = {...f.body(), requestName: 'current-fence'};
  await assert.rejects(f.service.submitNamedAttempt(value), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(true);
  const observed = await f.service.submitNamedAttempt(value);
  assert.equal(observed.kind, 'observed');
  assert.equal(observed.outcome.kind, 'preparing');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('named submission conflict comes from original intent and never enters changed work', async t => {
  const f = await fixture(t, {prepare() {
    throw Object.assign(new Error('original invalid input'), {code: 'ClientProgramInvalidInput'});
  }});
  const original = {...f.body('SELECT ('), requestName: 'failed-original'};
  const first = await f.service.submitNamedAttempt(original);
  assert.equal(first.outcome.kind, 'preparation_failed');
  const changed = await f.service.submitNamedAttempt({...f.body('SELECT 2 AS value'), requestName: original.requestName,
    attemptRef: {operation: 'submit', attemptId: 'changed-original'}});
  assert.equal(changed.kind, 'conflict');
  assert.equal(changed.reason, 'intent');
  assert.equal(Object.hasOwn(changed, 'outcome'), false);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('named submission denied before binding cannot prepare or issue a Run', async t => {
  const f = await fixture(t);
  f.authorize(false);
  const answer = await f.service.submitNamedAttempt({...f.body(), requestName: 'denied'});
  assert.equal(answer.kind, 'refused');
  assert.equal(answer.reason, 'authorization');
  assert.equal(answer.guarantee, 'attempt_uncommitted_unconsumed');
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
  const db = new DatabaseSync(join(f.root, 'client-requests.sqlite3'), {readOnly: true});
  try {assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_names').get().n, 0);}
  finally {db.close();}
});

async function unresolvedSubmissionFixture(t, prepare) {
  const start = 1_800_000_000_000;
  let now = start, preparations = 0, f;
  f = await fixture(t, {
    journalOptions: {submissionEpochTtlMs: 1000, submissionEpochNow: () => now},
    async prepare(value) {
      if (++preparations === 1) throw Object.assign(new Error('FixtureInvalidInput'), {code: 'ClientProgramInvalidInput'});
      return await prepare?.(value, f);
    },
    submit: value => admitOriginal(f, value),
    lookup(value) {
      const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
      return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
    },
  });
  assert.equal((await f.service.submitIntent(f.body('SELECT ('))).kind, 'not_accepted');
  now = start + 1000;
  f.journal.retireSubmittedIntent(f.ref, {...fields, expectedRevision: 0}, moon);
  const fresh = {epoch: await f.service.issueEpoch({principalId, connection}), nonce: 'explicit-fresh-intent'};
  const value = {...f.body(), submissionRef: fresh, unresolvedHistory: {
    submissionRef: f.ref, acknowledgement: 'possible_prior_execution_and_effects'}};
  return {f, fresh, value};
}

test('typed Submission uses the existing receipt and rebinds AlreadySatisfied to the new invocation', async t => {
  let f;
  f = await fixture(t, {submit: value => admitOriginal(f, value), lookup(value) {
    const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
  }});
  const request = id => ({...f.body(), attemptRef: {operation: 'submit', attemptId: id}});
  const original = await f.service.submitAttempt(request('first-invocation'));
  assert.equal(original.kind, 'recorded');
  assert.equal(original.outcome.kind, 'ready');
  f.restart();
  const replay = await f.service.submitAttempt(request('second-invocation'));
  assert.deepEqual(replay, {kind: 'already_satisfied',
    attemptRef: {operation: 'submit', attemptId: 'second-invocation'}, outcome: original.outcome});
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original.outcome);
  assert.deepEqual(f.counts, {prepare: 2, submit: 2}, 'explicit replay still uses the original Run owner');
});

for (const change of ['unsupported', 'protected rejection', 'authority lost', 'Run lost',
  'intent corrupt', 'infrastructure failure']) {
  test(`ready replay after preparation failure preserves original ownership: ${change}`, async t => {
    let f, replay = false, missing = false;
    const infrastructure = new Error('fixture infrastructure interruption');
    f = await fixture(t, {
      async prepare() {
        if (!replay) return {};
        await Promise.resolve();
        if (change === 'authority lost') f.authorize(false);
        if (change === 'Run lost') missing = true;
        if (change === 'intent corrupt') {
          const db = new DatabaseSync(join(f.root, 'client-requests.sqlite3'));
          try {db.prepare('UPDATE client_submitted_intents SET intent_cid = ?')
            .run('sha256:' + '0'.repeat(64));} finally {db.close();}
        }
        if (change === 'infrastructure failure') throw infrastructure;
        throw Object.assign(new Error('current preparation refused'), {
          code: change === 'protected rejection' ? 'ClientProgramRejected' : 'ClientProgramUnsupported'});
      },
      submit: value => admitOriginal(f, value),
      lookup(value) {
        const admitted = missing ? undefined : f.journal.lookup({...fields, requestId: value.requestId}, moon);
        return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
      },
    });
    const first = await f.service.submitAttempt(f.body());
    assert.equal(first.outcome.kind, 'ready');
    replay = true;
    const attemptRef = {operation: 'submit', attemptId: 'replay-after-current-change'};
    const operation = f.service.submitAttempt({...f.body(), attemptRef});
    if (['unsupported', 'protected rejection'].includes(change)) {
      assert.deepEqual(await operation, {kind: 'already_satisfied', attemptRef, outcome: first.outcome});
      assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), first.outcome);
    } else if (change === 'infrastructure failure') {
      await assert.rejects(operation, error => error === infrastructure);
    } else {
      await assert.rejects(operation, {code: change === 'authority lost'
        ? 'ClientRequestLookupDenied' : 'ClientSubmissionUnresolvable'});
    }
    assert.deepEqual(f.counts, {prepare: 2, submit: 1},
      'a refused new preparation cannot enter physical dispatch or admit another Run');
  });
}

test('typed Submission changed-intent Conflict does not prepare or dispatch the changed request', async t => {
  let f;
  f = await fixture(t, {submit: value => admitOriginal(f, value), lookup(value) {
    const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
  }});
  const original = await f.service.submitAttempt({...f.body(),
    attemptRef: {operation: 'submit', attemptId: 'original-invocation'}});
  const changed = f.body('SELECT 2 AS value');
  const attemptRef = {operation: 'submit', attemptId: 'changed-invocation'};
  assert.deepEqual(await f.service.submitAttempt({...changed, attemptRef}), {
    kind: 'conflict', reason: 'intent', attemptRef, submissionRef: f.ref, intentCid: changed.intentCid});
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original.outcome);
});

test('initial typed Submission authorization Refused is neither a durable rejection nor permission to retry', async t => {
  const f = await fixture(t);
  const attemptRef = {operation: 'submit', attemptId: 'denied-invocation'};
  f.authorize(false);
  assert.deepEqual(await f.service.submitAttempt({...f.body(), attemptRef}), {
    kind: 'refused', reason: 'authorization', attemptRef, guarantee: 'attempt_uncommitted_unconsumed'});
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
  f.authorize(true);
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});

for (const phase of ['prepare', 'dispatch']) {
  test(`a ${phase} exception carrying an admission-conflict code does not certify a Submission Conflict`, async t => {
    const failure = () => {throw Object.assign(new Error('ClientSubmittedIntentConflict'), {code: 'ClientSubmittedIntentConflict'});};
    const f = await fixture(t, phase === 'prepare' ? {prepare: failure} : {submit: failure});
    await assert.rejects(f.service.submitAttempt({...f.body(),
      attemptRef: {operation: 'submit', attemptId: 'owner-error'}}), {code: 'ClientSubmittedIntentConflict'});
    assert.deepEqual(f.counts, phase === 'prepare' ? {prepare: 1, submit: 0} : {prepare: 1, submit: 1});
    assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon)?.phase,
      phase === 'prepare' ? undefined : 'preparing');
  });
}

test('typed Submission durable NotAccepted retains its original consumed identity', async t => {
  const f = await fixture(t, {prepare() {
    throw Object.assign(new Error('InvalidInput'), {code: 'ClientProgramInvalidInput'});
  }});
  const first = await f.service.submitAttempt({...f.body('SELECT ('),
    attemptRef: {operation: 'submit', attemptId: 'invalid-invocation'}});
  assert.equal(first.kind, 'recorded');
  assert.equal(first.outcome.kind, 'not_accepted');
  f.restart();
  const repeated = await f.service.submitAttempt({...f.body('SELECT ('),
    attemptRef: {operation: 'submit', attemptId: 'invalid-replay'}});
  assert.equal(repeated.kind, 'already_satisfied');
  assert.deepEqual(acceptanceFacts(repeated.outcome), acceptanceFacts(first.outcome));
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('submission adapter retains explicit restart decision with the authenticated actor', async t => {
  const {f, fresh, value} = await unresolvedSubmissionFixture(t);
  const result = await f.service.submitIntent({...value, actorId: 'caller-forged-actor'});
  assert.equal(result.kind, 'ready');
  f.restart();
  const retained = f.journal.lookupSubmittedIntent(fresh, fields, moon);
  assert.equal(retained.unresolvedHistory?.actorId, principalId);
  assert.deepEqual(retained.unresolvedHistory?.submissionRef, f.ref);
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: fresh}), result);
  assert.deepEqual(f.counts, {prepare: 2, submit: 1});
  const {unresolvedHistory, ...ordinary} = value;
  await assert.rejects(f.service.submitIntent(ordinary), {code: 'ClientSubmissionRestartConflict'});
  assert.deepEqual(f.counts, {prepare: 2, submit: 1});
});

test('restart decision is checked before preparation and again after awaited preparation', async t => {
  const {f, fresh, value} = await unresolvedSubmissionFixture(t, async (_value, f) => {
    await Promise.resolve();
    // Lose original receipt custody while preparation is suspended. A missing
    // original is not permission to admit new work after the await.
    const db = new DatabaseSync(join(f.root, 'client-requests.sqlite3'));
    try {db.exec('DELETE FROM client_submitted_intent_retirement');} finally {db.close();}
    return {};
  });
  const malformed = {...value, unresolvedHistory: {...value.unresolvedHistory, acknowledgement: 'retry'}};
  await assert.rejects(f.service.submitIntent(malformed), {code: 'InvalidClientSubmissionRestart'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  await assert.rejects(f.service.submitIntent(value), {code: 'ClientSubmittedIntentCustodyLost'});
  assert.deepEqual(f.counts, {prepare: 2, submit: 0});
  assert.equal(fresh.nonce, 'explicit-fresh-intent');
});

test('ready lookup stays read-only while explicit replay re-enters the original Run owner after restart', async t => {
  let f;
  f = await fixture(t, {submit: value => admitOriginal(f, value), lookup(value) {
    const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
  }});
  const original = await f.service.submitIntent(f.body());
  assert.equal(original.kind, 'ready');
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1}, 'lookup does not resume physical work');
  assert.deepEqual(await f.service.submitIntent(f.body()), original);
  assert.deepEqual(f.counts, {prepare: 2, submit: 2}, 'explicit replay reaches the existing Run owner');
  await assert.rejects(f.service.submitIntent(f.body('SELECT 2 AS value')), {code: 'ClientSubmittedIntentConflict'});
  assert.deepEqual(f.counts, {prepare: 2, submit: 2}, 'changed intent never enters the Run owner');
});

test('ready replay rechecks current authority after awaited preparation and retains its original receipt', async t => {
  let f, preparations = 0;
  f = await fixture(t, {async prepare() {
    preparations++;
    if (preparations === 2) {await Promise.resolve(); f.authorize(false);}
    return {};
  }, submit: value => admitOriginal(f, value), lookup(value) {
    const admitted = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return admitted === undefined ? {kind: 'not_found'} : {kind: 'found', ref: admitted.ref};
  }});
  const original = await f.service.submitIntent(f.body());
  await assert.rejects(f.service.submitIntent(f.body()), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 2, submit: 1});
  f.authorize(true);
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
});

test('public Local submission lookup returns a durable pre-admission refusal after restart', async t => {
  const failure = Object.assign(new Error('invalid fixture'), {code: 'ClientProgramInvalidInput'});
  let originals = 0, freshChecks = 0;
  const f = await fixture(t, {prepare() {throw failure;},
    originalObservation(error, value) {
      assert.strictEqual(error, failure);
      originals++;
      return checkValues({...value, kind: 'text', scope: 'bound_input'});
    }, check(value) {freshChecks++; return checkValues(value);}});
  const body = f.body('SELECT (');
  const {principalId: ignored, ...wireBody} = body;
  const initial = await f.port().perform('submit-intent', wireBody);
  assert.equal(initial.kind, 'recorded');
  assert.deepEqual(initial.attemptRef, wireBody.attemptRef);
  const reply = initial.outcome;
  assert.equal(reply.kind, 'not_accepted');
  assert.equal(reply.problem.classification, 'invalid_input');
  assert.equal(originals, 2, 'original observation retains both current fences');
  assert.equal(freshChecks, 0, 'initial refusal cannot borrow a later disclosure check');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.restart();
  const restored = await f.port().perform('lookup-submission', {connection, submissionRef: f.ref});
  assertReferenceOnly(restored, reply);
  assert.equal(originals, 2, 'restart lookup cannot reconstruct the original observation');
  assert.equal(validSubmissionLookup(restored, connection, f.ref), true);
  assert.deepEqual(await f.port().perform('submit-intent', wireBody), {
    kind: 'already_satisfied', attemptRef: wireBody.attemptRef, outcome: acceptanceFacts(reply)});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  await assert.rejects(f.service.submitIntent(f.body('SELECT 1 AS value')), {code: 'ClientSubmittedIntentConflict'});
});

test('reference-only lookup returns original acceptance without diagnostic enrichment', async t => {
  const f = await fixture(t, {prepare() {
    throw Object.assign(new Error('independent syntax fixture'), {code: 'ClientProgramInvalidInput'});
  }});
  const original = await f.service.submitIntent(f.body('SELECT ('));
  assert.equal(Object.hasOwn(original, 'checkObservation'), false);
  f.restart();
  let lookup;
  // A known closed-schema rejection is an assertion failure for this valid
  // reference-only operation; unrelated exceptions remain infrastructure errors.
  try {
    lookup = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  } catch (error) {
    if (error?.code !== 'InvalidClientHostSubmissionLookup') throw error;
    assert.fail('[check-mutation:submission-check-lookup-contract] A valid original lookup must match its closed response contract.');
  }
  assertReferenceOnly(lookup, original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('retained Source input problems recheck original intent and current disclosure without preparation', async t => {
  const wire = JSON.parse(await readFile(new URL(
    './fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const environment = moon.clientProgramCheckEnvironment(canonicalText(wire),
    wire.evidence_bundle_cid, false, false, true, true, false, false, false);
  assert.ok(environment);
  const view = wire.source_views[0];
  const sourceRef = 'connector://crm/main/r#v';
  const publication = {environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
    aliases: [{name: 'records', sourceRef, sourceViewContractCid: view.contract_cid,
      schemaContractCid: view.output.schema.cid}]};
  let visible = true, checks = 0;
  const checker = installNodeClientCheck({moon, environment, publication,
    sourceAccesses: [{sourceRef, resource: 'records', connection: {}, authorization: {
      authorize() {return {action: visible ? 'dispatch' : 'deny'};},
    }}]});
  const prepare = installNodeClientProgramPreparation({moon, environment, sourcePublication: publication});
  const f = await fixture(t, {prepare, check(value) {
    checks++;
    assert.deepEqual(value.input, {format: 'aql-text', text: 'SELECT missing AS n FROM records'});
    assert.equal(value.parameters, null);
    return checker(value);
  }});
  const expected = {code: 'ClientProgramInvalidInput', classification: 'invalid_input'};
  const first = await f.service.submitIntent(f.body('SELECT missing AS n FROM records'));
  assert.deepEqual(first.problem, expected, '[check-mutation:submission-disclosure]');
  f.restart();
  visible = false;
  const hidden = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.deepEqual(hidden.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'},
    '[check-mutation:submission-disclosure]');
  assert.equal(hidden.kind, 'not_accepted');
  assert.deepEqual(hidden.submissionRef, first.submissionRef);
  const replay = await f.service.submitIntent(f.body('SELECT missing AS n FROM records'));
  assert.deepEqual(acceptanceFacts(replay), hidden);
  assert.equal(Object.hasOwn(replay, 'checkObservation'), false);
  visible = true;
  const restored = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assertReferenceOnly(restored, first, '[check-mutation:submission-disclosure]');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  assert.ok(checks >= 4);
});

test('submission disclosure retains an admitted partial invalid report across original lookup', async t => {
  const failed = JSON.parse(await readFile(new URL(
    '../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
  const failure = Object.assign(new Error('typed input fixture'), {code: 'ClientProgramInvalidInput'});
  const partialInvalid = async value => {
    const completed = await checkValues({...value, kind: 'text', scope: 'bound_input'});
    const partial = {...failed, partial_report: completed.report};
    assert.equal(validCheckOutcome(partial), true);
    return partial;
  };
  let originals = 0, disclosureChecks = 0;
  const f = await fixture(t, {prepare() {throw failure;}, originalObservation(error, value) {
    assert.strictEqual(error, failure);
    originals++;
    return partialInvalid(value);
  }, check(value) {disclosureChecks++; return partialInvalid(value);}});
  const first = await f.service.submitIntent(f.body('SELECT missing AS n'));
  // The original exception already identifies input invalidity. This case
  // does not promote a generic Source refusal from partial reporting.
  assert.deepEqual(first.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
  assert.equal(first.checkObservation.outcome, 'failed');
  assert.equal(first.checkObservation.partial_report.verdict, 'invalid');
  assert.equal(originals, 2);
  assert.equal(disclosureChecks, 0, 'initial disclosure uses only the same original observation');
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), first);
  assert.equal(originals, 2, 'lookup cannot reconstruct the original observation');
  assert.equal(disclosureChecks, 1, 'lookup keeps its separate current disclosure check');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('submission disclosure refuses authorization lost during its awaited original observation', async t => {
  let entered, resume;
  const checking = new Promise(resolve => {entered = resolve;});
  const paused = new Promise(resolve => {resume = resolve;});
  let calls = 0;
  const failure = Object.assign(new Error('typed input fixture'), {code: 'ClientProgramInvalidInput'});
  const f = await fixture(t, {prepare() {throw failure;}, async originalObservation(error, value) {
    assert.strictEqual(error, failure);
    if (++calls === 1) {entered(); await paused;}
    return checkValues({...value, kind: 'text', scope: 'bound_input'});
  }, check() {assert.fail('no separate check may classify the initial refusal');}});
  const pending = f.service.submitIntent(f.body('SELECT missing AS n'));
  await checking;
  f.authorize(false); resume();
  await assert.rejects(pending, {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(true);
  const original = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(original.kind, 'unresolvable');
});

for (const mode of ['undetermined', 'failed', 'unavailable', 'malformed', 'exception', 'missing']) {
  test(`submission disclosure does not derive invalid input from ${mode} reporting`, async t => {
    const failure = Object.assign(new Error('typed input fixture'), {code: 'ClientProgramInvalidInput'});
    let originals = 0;
    const f = await fixture(t, {prepare() {throw failure;}, async originalObservation(error, original) {
      assert.strictEqual(error, failure);
      originals++;
      const value = {...original, kind: 'text', scope: 'bound_input'};
      if (mode === 'missing') return undefined;
      if (mode === 'exception') throw new Error('private-reporting-failure');
      if (mode === 'unavailable') return checkValues.unavailable();
      const report = await checkValues(value);
      if (mode === 'malformed') return {...report, outcome: 'malformed'};
      if (mode === 'failed') return {...report, outcome: 'failed'};
      return checkValues({...value, input: {format: 'sql', text: 'SELECT id FROM absent'}});
    }, check() {assert.fail('missing original reporting cannot start another check');}});
    const result = await f.service.submitIntent(f.body('SELECT missing AS n'));
    assert.equal(result.kind, 'not_accepted');
    assert.deepEqual(result.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'},
      '[check-mutation:submission-reporting]');
    assert.equal(originals, 2, 'observe the same original before and after durable write');
    f.restart();
    assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), result);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  });
}

test('accepted preparation failure remains accepted with no invented Run identity', async t => {
  const f = await fixture(t, {submit() {throw Object.assign(new Error('missing fixture input'), {code: 'ClientProgramNeedsInputs'});}});
  const reply = await f.service.submitIntent(f.body());
  assert.equal(reply.kind, 'preparation_failed');
  assert.equal(reply.problem.classification, 'requirements');
  assert.equal('ref' in reply, false);
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), reply);
  assert.deepEqual(await f.service.submitIntent(f.body()), reply);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('unclassified interruption leaves Preparing and lookup never dispatches work', async t => {
  const f = await fixture(t, {submit() {throw new Error('fixture lost transport');}});
  await assert.rejects(f.service.submitIntent(f.body()), /fixture lost transport/);
  f.restart();
  const restored = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(restored.kind, 'preparing');
  assert.deepEqual(restored.submissionRef, f.ref);
  assert.equal('ref' in restored, false);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('unknown original identity is unresolvable rather than evidence of nonexecution', async t => {
  const f = await fixture(t);
  const found = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(found.kind, 'unresolvable');
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
});

test('formal expiry retirement projects Unresolvable through original lookup without resubmitting', async t => {
  let now = 1_800_000_000_000;
  const f = await fixture(t, {
    journalOptions: {submissionEpochTtlMs: 1000, submissionEpochNow: () => now},
    prepare() {throw Object.assign(new Error('invalid fixture'), {code: 'ClientProgramInvalidInput'});},
  });
  const body = f.body('SELECT (');
  const original = await f.service.submitIntent(body);
  assert.equal(original.kind, 'not_accepted');
  now += 1000;
  assert.deepEqual(f.journal.retireSubmittedIntent(f.ref,
    {...fields, expectedRevision: 0}, moon), {retired: true});
  f.restart();
  const unresolved = {kind: 'unresolvable', submissionRef: f.ref,
    problem: {code: 'submission_history_unresolvable'}};
  assert.deepEqual(await f.port().perform('lookup-submission', {connection, submissionRef: f.ref}), unresolved);
  assert.deepEqual(await f.port().perform('lookup-submission', {connection, submissionRef: f.ref}), unresolved);
  await assert.rejects(f.service.submitIntent(body), {code: 'ClientSubmissionEpochExpired'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(false);
  await assert.rejects(f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}),
    {code: 'ClientRequestLookupDenied'});
});

test('intent digest mismatch is refused before preparation or admission', async t => {
  const f = await fixture(t);
  await assert.rejects(f.service.submitIntent({...f.body(), intentCid: `sha256:${'0'.repeat(64)}`}),
    {code: 'InvalidClientSubmittedIntent'});
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});

test('Local ingress owns nested submission values before authentication awaits', async t => {
  const f = await fixture(t, {prepare(value) {
    assert.equal(value.input.text, 'SELECT 1 AS value');
    throw Object.assign(new Error('fixture preflight'), {code: 'ClientProgramUnsupported'});
  }});
  let release;
  const authentication = new Promise(resolve => {release = resolve;});
  const port = createNodeInProcessClientHost({authenticate: () => authentication,
    authorizeConnection: () => true, negotiate: () => undefined, submitIntent: f.service.submitAttempt,
    lookupSubmission: f.service.lookupSubmission, maxRowBytes: 65536});
  const {principalId: ignored, ...body} = f.body();
  const pending = port.perform('submit-intent', body);
  body.input.text = 'SELECT changed AS value';
  body.submissionRef.nonce = 'changed-nonce';
  release(principalId);
  const result = await pending;
  assert.equal(result.kind, 'recorded');
  assert.equal(result.outcome.kind, 'not_accepted');
  assert.equal(result.outcome.submissionRef.nonce, 'original-nonce');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('current authorization is checked again after awaited preparation', async t => {
  let f;
  f = await fixture(t, {prepare: async () => {await Promise.resolve(); f.authorize(false); return {};}});
  await assert.rejects(f.service.submitIntent(f.body()), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(true);
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});


test('retained Source analysis budget rechecks original intent and current disclosure without preparation', async t => {
  const budget = JSON.parse(await readFile(new URL(
    '../../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  budget.report.verdict = 'undetermined';
  budget.report.coverage.limits = [{code: 'analysis_budget_exhausted'}];
  budget.report.runnable = {verdict: 'no', reasons: [{code: 'analysis_budget_exhausted'}]};
  assert.equal(validCheckOutcome(budget), true);
  assert.equal(validCheckOutcome({...budget, report: {...budget.report,
    runnable: {verdict: 'yes', reasons: []}}}), false);
  let disclosed = true;
  const observed = [];
  const f = await fixture(t, {prepare() {
    throw Object.assign(new Error('typed budget fixture'), {code: 'ClientProgramAnalysisLimit'});
  }, async check(value) {
    observed.push(value.input.text);
    const outcome = structuredClone(budget);
    if (!disclosed) {
      outcome.report.coverage.limits = [];
      outcome.report.coverage.unresolved = [{boundary: 'source_resolution', reason: 'unresolved_protected'}];
      outcome.report.runnable = {verdict: 'no', reasons: [{code: 'unresolved_protected'}]};
    }
    assert.equal(validCheckOutcome(outcome), true);
    return outcome;
  }});
  const first = await f.service.submitIntent(f.body('SELECT original AS n'));
  assert.deepEqual(first.problem, {code: 'ClientProgramAnalysisLimit', classification: 'implementation_limit'});
  f.restart();
  disclosed = false;
  const hidden = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(hidden.kind, first.kind);
  assert.deepEqual(hidden.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'},
    '[check-mutation:submission-budget-disclosure]');
  disclosed = true;
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), first);
  assert.ok(observed.every(text => text === 'SELECT original AS n'));
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});


for (const partial of [false, true]) {
  test(`retained Source implementation limit rechecks ${partial ? 'partial' : 'completed'} original disclosure`, async t => {
    const verified = JSON.parse(await readFile(new URL(
      '../../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
    const failed = JSON.parse(await readFile(new URL(
      '../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
    let limit = 'implementation_limit';
    const observed = [];
    const f = await fixture(t, {prepare() {
      throw Object.assign(new Error('typed implementation fixture'), {code: 'ClientProgramImplementationLimit'});
    }, async check(value) {
      observed.push(value.input.text);
      const report = structuredClone(verified.report);
      report.verdict = 'undetermined';
      report.coverage.limits = [{code: limit}];
      report.runnable = {verdict: 'no', reasons: [{code: limit}]};
      const outcome = partial ? {...failed, partial_report: report} : {...verified, report};
      assert.equal(validCheckOutcome(outcome), true);
      return outcome;
    }});
    const first = await f.service.submitIntent(f.body('SELECT original AS n'));
    assert.deepEqual(first.problem, {code: 'ClientProgramImplementationLimit', classification: 'implementation_limit'});
    f.restart();
    limit = 'analysis_budget_exhausted';
    const hidden = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
    assert.equal(hidden.kind, first.kind);
    assert.deepEqual(hidden.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'},
      '[check-mutation:submission-implementation-disclosure]');
    limit = 'implementation_limit';
    assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), first);
    assert.ok(observed.every(text => text === 'SELECT original AS n'));
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  });
}


// These are actual Host callback/holder bodies with explicit pre-Resource
// ports. The Journal and its immutable outcomes below use real SQLite/Common;
// this fixture does not claim a new Common/ordinary Host execution.
function pairedAdmissionFixture() {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}), declarations = new Map();
  let holder;
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.method &&
        node.key.name === 'isOriginalManagedComputePreparationRefusal') {assert.equal(holder, undefined); holder = node;}
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        ['admissionFailures', 'holderRefusal', 'admitPreparedSubmission'].includes(node.declarations[0].id.name)) {
      const name = node.declarations[0].id.name; assert.equal(declarations.has(name), false); declarations.set(name, node);
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) for (const value of child) visit(value);
      else if (child && typeof child === 'object') visit(child);
    }
  }
  visit(ast); assert(holder); assert.equal(declarations.size, 3);
  const text = node => source.slice(node.start, node.end), record = {computeRuns: new Map()};
  const runtime = {clientProgramSerializationOccurrences: () => []}, prepared = {}, requested = {};
  const originalInstallation = {initialControl: {}}, originals = {installation: originalInstallation};
  const error = Object.assign(new Error('original pure preparation Unsupported'), {code: 'ClientProgramUnsupported'});
  let current = true, requestReads = 0, projections = 0;
  const assertCurrent = () => {assert.equal(current, true, 'Original installation current');};
  const project = new Function('record', 'moon', 'originalInstallation', 'originals',
    'computeManaged', 'sourceManaged', 'assertInitialControlHostPreparation',
    'assertManagedComputeInstallationCurrent', 'assertSourceManagedInstallationCurrent',
    `return ({${text(holder)}}).isOriginalManagedComputePreparationRefusal;`)(
    record, runtime, originalInstallation, originals, {}, undefined, assertCurrent, assertCurrent, assertCurrent);
  const preparation = {
    admitResultPublicationRun(value) {assert.equal(value, prepared);},
    prepareManagedComputeRun(moon, value, request) {
      assert.equal(moon, runtime); assert.equal(value, prepared); assert.equal(request, requested);
      record.computeRuns.set(prepared, {runtime, prepared, request, failure: error, closed: false,
        preAdmissionRefusal: Object.freeze({error, prepared, request, control: originalInstallation.initialControl})});
      throw error;
    },
    isOriginalManagedComputePreparationRefusal(...args) {
      assert.equal(this, preparation); projections++; return Reflect.apply(project, preparation, args);
    },
  };
  const callback = new Function('preparation', 'moon', 'requestOf', 'inferSelections',
    ['admissionFailures', 'holderRefusal', 'admitPreparedSubmission'].map(name => text(declarations.get(name))).join('\n') +
      '\nreturn admitPreparedSubmission;')(preparation, runtime, candidate => {
    requestReads++; assert.equal(candidate.preparedProgram, prepared);
    return {requested, acquisitionCount: 0, effectful: false};
  }, new WeakMap());
  return {callback, error, prepared, requested, record, originalInstallation,
    get requestReads() {return requestReads;}, get projections() {return projections;}, stop() {current = false;}};
}

test('paired pre-admission original refusal is retained without entering the Run owner', async t => {
  const p = pairedAdmissionFixture();
  const f = await fixture(t, {prepare: () => p.prepared, admit: p.callback});
  const original = await f.service.submitIntent(f.body());
  assert.equal(original.kind, 'not_accepted');
  assert.deepEqual(original.problem, {code: 'ClientProgramUnsupported', classification: 'implementation_limit'});
  assert.equal('admission' in original, false);
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
  assert.deepEqual(await f.service.submitIntent(f.body()), original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  assert.equal(p.requestReads, 1, 'One original requestOf, not repeated lowering');
  assert.equal(p.projections, 1);
});

test('unclassified pre-admission interruption is not certified as a refusal', async t => {
  const interrupted = Object.assign(new Error('unknown original state'), {code: 'MoonBitHostFailure'});
  const f = await fixture(t, {admit() {throw interrupted;}});
  await assert.rejects(f.service.submitIntent(f.body()), error => error === interrupted);
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
  assert.equal((await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref})).kind, 'unresolvable');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('paired pre-admission refusal rechecks current authority before recording its outcome', async t => {
  let f;
  const p = pairedAdmissionFixture();
  const admit = candidate => p.callback(candidate);
  admit.isOriginalPreparationRefusal = function(error, candidate) {
    assert.equal(this, admit); const original = Reflect.apply(p.callback.isOriginalPreparationRefusal, p.callback, [error, candidate]);
    f.authorize(false); return original;
  };
  f = await fixture(t, {prepare: () => p.prepared, admit});
  await assert.rejects(f.service.submitIntent(f.body()), {code: 'ClientRequestLookupDenied'});
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('response loss after Run admission retains the original without redispatch', async t => {
  let f, admitted, admissions = 0;
  f = await fixture(t, {admit() {admissions++;}, submit(value) {
    admitted = admitOriginal(f, value);
    throw new Error('lost response after original COMMIT');
  }, lookup(value) {
    const saved = f.journal.lookup({...fields, requestId: value.requestId}, moon);
    return saved === undefined ? {kind: 'not_found'} : {kind: 'found', ref: saved.ref};
  }});
  const original = await f.service.submitIntent(f.body());
  assert.equal(original.kind, 'ready');
  assert.deepEqual(original.admission, admitted);
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), original);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
  assert.equal(admissions, 1);
});

for (const duty of ['code only', 'pending cleanup', 'cleanup handle']) {
  test(`unissued pre-admission ${duty} error cannot certify a refusal`, async t => {
    const error = Object.assign(new Error('borrowed callback failure'),
      {code: 'ClientProgramUnsupported'}, duty === 'pending cleanup' ? {cleanupPending: true} :
        duty === 'cleanup handle' ? {cleanupHandle: Object.freeze({status: () => ({pending: true})})} : {});
    const f = await fixture(t, {admit() {throw error;}});
    await assert.rejects(f.service.submitIntent(f.body()), cause => cause === error);
    assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  });
}

for (const backing of ['accessor', 'inherited', 'foreign receiver', 'copied candidate', 'Promise']) {
  test(`paired pre-admission ${backing} projection cannot certify refusal`, async t => {
    const p = pairedAdmissionFixture(), admit = candidate => p.callback(candidate);
    let getters = 0;
    const original = p.callback.isOriginalPreparationRefusal;
    if (backing === 'accessor') Object.defineProperty(admit, 'isOriginalPreparationRefusal', {get() {getters++; return original;}});
    else if (backing === 'inherited') Object.setPrototypeOf(admit, {isOriginalPreparationRefusal: original});
    else if (backing === 'foreign receiver') admit.isOriginalPreparationRefusal = original;
    else admit.isOriginalPreparationRefusal = function(error, candidate) {
      assert.equal(this, admit);
      return backing === 'copied candidate'
        ? Reflect.apply(original, p.callback, [error, {...candidate}])
        : Promise.resolve(Reflect.apply(original, p.callback, [error, candidate]));
    };
    const f = await fixture(t, {prepare: () => p.prepared, admit});
    await assert.rejects(f.service.submitIntent(f.body()), error => error === p.error);
    assert.equal(getters, 0); assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0}); assert.equal(p.requestReads, 1);
  });
}

test('paired pre-admission captures the original projection instead of a later replacement', async t => {
  const p = pairedAdmissionFixture(), admit = candidate => p.callback(candidate);
  admit.isOriginalPreparationRefusal = function(error, candidate) {
    assert.equal(this, admit); return Reflect.apply(p.callback.isOriginalPreparationRefusal, p.callback, [error, candidate]);
  };
  const f = await fixture(t, {prepare: () => p.prepared, admit});
  admit.isOriginalPreparationRefusal = () => assert.fail('Later method replacement');
  const outcome = await f.service.submitIntent(f.body()); assert.equal(outcome.kind, 'not_accepted');
  assert.equal(p.requestReads, 1); assert.equal(p.projections, 1);
});

test('paired pre-admission consumer keeps cleanup duty unknown even for a malformed positive projection', async t => {
  for (const duty of [{cleanupPending: true}, {cleanupHandle: Object.freeze({status: () => ({pending: true})})}]) {
    const error = Object.assign(new Error('original duty remains pending'), {code: 'ClientProgramUnsupported'}, duty);
    const admit = () => {throw error;};
    // An intentionally malformed explicit port must not erase its duty.
    admit.isOriginalPreparationRefusal = () => true;
    const f = await fixture(t, {admit});
    await assert.rejects(f.service.submitIntent(f.body()), cause => cause === error);
    assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  }
});

test('paired named refusal preserves its accepted intent without inventing a Run', async t => {
  const p = pairedAdmissionFixture(), f = await fixture(t, {prepare: () => p.prepared, admit: p.callback});
  const value = {...f.body(), requestName: 'same-original-profile-refusal'};
  const first = await f.service.submitNamedAttempt(value);
  assert.equal(first.kind, 'observed'); assert.equal(first.outcome.kind, 'preparation_failed');
  assert.deepEqual(first.outcome.problem, {code: 'ClientProgramUnsupported', classification: 'implementation_limit'});
  assert.equal(Object.hasOwn(first.outcome, 'admission'), false);
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), first.outcome);
  const replay = await f.service.submitNamedAttempt({...value, attemptRef: {operation: 'submit', attemptId: 'original-name-observation'}});
  assertReferenceOnly(replay.outcome, first.outcome);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0}); assert.equal(p.requestReads, 1); assert.equal(p.projections, 1);
});

test('journal lends only the explicitly registered original intent until its operation releases', async t => {
  const f = await fixture(t);
  const intent = moon.clientSubmittedIntent(JSON.stringify({kind: 'aql',
    input: {format: 'aql-text', text: 'SELECT 1 AS value'}, parameters: null}), 1048576, 65536, 64);
  const wire = moon.clientSubmittedIntentWire(intent);
  let parses = 0;
  const control = {...moon, clientSubmittedIntent(...args) {
    parses++; return moon.clientSubmittedIntent(...args);
  }};
  const epoch = Object.freeze({...f.ref.epoch});
  const release = f.journal.retainSubmissionOperation(epoch, control, intent);
  try {
    assert.equal(f.journal.prepareSubmittedIntent(epoch, wire, control), intent);
    assert.equal(parses, 0);
    const foreignControl = {...control};
    assert.notEqual(f.journal.prepareSubmittedIntent(epoch, wire, foreignControl), intent);
    assert.equal(parses, 1);
    const otherEpoch = Object.freeze({...epoch});
    const releaseOther = f.journal.retainSubmissionOperation(otherEpoch, control);
    try {
      assert.notEqual(f.journal.prepareSubmittedIntent(otherEpoch, wire, control), intent);
      assert.equal(parses, 2, 'a different epoch never inherits the borrowed original');
    } finally {releaseOther();}
  } finally {release();}
  assert.notEqual(f.journal.prepareSubmittedIntent(epoch, wire, control), intent);
  assert.equal(parses, 3, 'release removes the exact borrowed original rather than retaining a cache');
});

test('Journal intent reader honors exact UTF8 budget and rejects one byte short before parsing', async t => {
  const wire = canonicalText({kind: 'aql', input: {format: 'aql-text',
    text: 'SELECT 1 /*' + '猫'.repeat(20000) + '*/'}, parameters: null});
  const bytes = Buffer.byteLength(wire, 'utf8');
  const exact = await fixture(t, {journalOptions: {maxInspectionBytes: bytes}});
  assert.ok(exact.journal.prepareSubmittedIntent(undefined, wire, moon));
  const narrow = await fixture(t, {journalOptions: {maxInspectionBytes: bytes - 1}});
  let calls = 0;
  const control = {...moon, clientSubmittedIntent() {calls++; assert.fail('narrow policy must refuse before parser');}};
  assert.throws(() => narrow.journal.prepareSubmittedIntent(undefined, wire, control),
    {code: 'ClientSubmittedIntentCapacity'});
  assert.equal(calls, 0);
  const intent = moon.clientSubmittedIntent(wire, bytes, bytes, bytes);
  assert.throws(() => narrow.journal.retainSubmissionOperation(Object.freeze({...narrow.ref.epoch}),
    moon, intent), {code: 'ClientSubmittedIntentCapacity'});
});

test('current-version Journal intent larger than 1MiB survives record, lost reply, and reopen', async t => {
  const f = await fixture(t);
  const wire = canonicalText({kind: 'aql', input: {format: 'aql-text',
    text: 'SELECT 1 /*' + 'x'.repeat(1048576) + '*/'}, parameters: null});
  const bytes = Buffer.byteLength(wire, 'utf8');
  assert.ok(bytes > 1048576);
  const intent = f.journal.prepareSubmittedIntent(undefined, wire, moon);
  assert.ok(intent);
  const originalCid = moon.clientSubmittedIntentCid(intent);
  // Deliberately discard the first accepted receipt: the same saved original,
  // not resubmission or a reconstructed identity, is observed after reopen.
  f.journal.recordSubmittedIntent(f.ref, intent, fields, moon);
  const before = f.journal.lookupSubmittedIntent(f.ref, fields, moon);
  assert.equal(before.intentCid, originalCid);
  assert.equal(before.intentWire, wire);
  f.restart();
  const after = f.journal.lookupSubmittedIntent(f.ref, fields, moon);
  assert.equal(after.intentCid, originalCid);
  assert.equal(after.intentWire, wire);
  assert.equal(after.requestId, before.requestId);
  assert.equal(after.phase, 'preparing');
});

for (const failureAt of ['original_getter', 'journal_registration']) {
  test(`submission finishes original handler when ${failureAt} refuses before action`, async t => {
    const f = await fixture(t);
    let finished = 0, authorized = 0, registered = 0;
    const failure = Object.assign(new Error('ClientSubmittedIntentCapacity'), {code: 'ClientSubmittedIntentCapacity'});
    const service = installNodeClientSubmission({moon,
      journal: {...f.journal, retainSubmissionOperation() {registered++; throw failure;}},
      authorizedScope() {authorized++; return fields;},
      prepareSubmit() {assert.fail('no preparation');}, submit() {assert.fail('no submit');},
      lookupRequest() {assert.fail('no lookup');},
      preparationCustody: {capture: value => value, finishHandler() {finished++;}},
      submittedIntentOriginal() {if (failureAt === 'original_getter') throw failure;},
    });
    await assert.rejects(service.submitAttempt(f.body()), error => error === failure);
    assert.equal(finished, 1);
    assert.equal(authorized, 0);
    assert.equal(registered, failureAt === 'original_getter' ? 0 : 1);
  });
}

test('stale Journal operation release cannot remove a newer same-epoch original', async t => {
  const f = await fixture(t);
  const epoch = Object.freeze({...f.ref.epoch});
  const wire = canonicalText({kind: 'aql', input: {format: 'aql-text', text: 'SELECT 1'}, parameters: null});
  const intent = moon.clientSubmittedIntent(wire, 1048576, 65536, 64);
  const oldRelease = f.journal.retainSubmissionOperation(epoch, moon, intent);
  oldRelease();
  const nextRelease = f.journal.retainSubmissionOperation(epoch, moon, intent);
  try {
    oldRelease();
    assert.equal(f.journal.prepareSubmittedIntent(epoch, wire, moon), intent);
  } finally {nextRelease();}
});

test('selected Journal metadata envelope derives durable/inspection policy and SQL operands share one total', async () => {
  const {default: recipe} = await import('./host-journal-service-recipe.cjs');
  const selected = recipe.declareHostJournalServiceRecipe(Object.freeze({}));
  assert.equal(selected.numericalBackingClaim, false);
  const limits = selected.journal;
  assert.equal(limits.primaryExecutionLimits.maxParameterBytes,
    Math.min(limits.maxDatabaseBytes, limits.maxInspectionBytes));
  assert.equal(limits.maxRunDefinitionWireBytes, limits.primaryExecutionLimits.maxParameterBytes);
  const source = readFileSync(new URL('./client-request-journal.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const owner = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'boundedPrimarySql');
  const declaration = owner.body.body.flatMap(node => node.type === 'VariableDeclaration' ? node.declarations : [])
    .find(node => node.id.name === 'operands');
  assert.ok(declaration);
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const operands = new Function('executionLimits', 'assertCurrent', 'cursors', 'fail',
    'applyOriginal', 'byteLength', 'buffer', 'return ' +
    source.slice(declaration.init.start, declaration.init.end))(
      {maxParameters: 4, maxParameterBytes: 16},
      () => {}, [], fail, Reflect.apply, Buffer.byteLength, Buffer);
  operands(['12345678', '12345678']);
  assert.throws(() => operands(['12345678', '123456789']), {code: 'ClientRequestJournalSqlUnavailable'});
  operands(['猫'.repeat(5), 'x']);
  assert.throws(() => operands(['猫'.repeat(5), 'xx']), {code: 'ClientRequestJournalSqlUnavailable'});
});


test('original Request observation is transient initial metadata and never Journal or replay evidence', async t => {
  const failure = Object.assign(new Error('original typed preparation'), {code: 'ClientProgramInvalidInput'});
  let observations = 0;
  const f = await fixture(t, {prepare() {throw failure;}, async originalObservation(error, value) {
    assert.strictEqual(error, failure); observations++;
    return checkValues({...value, kind: 'text', scope: 'bound_input'});
  }});
  const initial = await f.service.submitIntent(f.body('SELECT ('));
  assert.equal(initial.checkObservation.report.verdict, 'invalid');
  assert.equal(observations, 2, 'observe the same original before and after its durable write');
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), initial);
  assertReferenceOnly(await f.service.submitIntent(f.body('SELECT (')), initial);
  assert.equal(observations, 2, 'lookup and replay cannot reconstruct the original observation'); assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('original Request observation failure omits report while authorization loss refuses disclosure', async t => {
  for (const loseAuthorization of [false, true]) {
    let f;
    f = await fixture(t, {prepare() {throw Object.assign(new Error('original typed preparation'),
      {code: 'ClientProgramInvalidInput'});}, async originalObservation() {
      await Promise.resolve();
      if (loseAuthorization) f.authorize(false);
      throw new Error('original report unavailable');
    }});
    const pending = f.service.submitIntent(f.body('SELECT ('));
    if (loseAuthorization) await assert.rejects(pending, {code: 'ClientRequestLookupDenied'});
    else {const result = await pending; assert.equal(result.kind, 'not_accepted');
      assert.equal(Object.hasOwn(result, 'checkObservation'), false);}
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  }
});


test('original Request compiled Check observation uses actual parent preparation report and retirement', async () => {
  const publication = {environmentCid: moon.clientProgramCheckingEnvironmentCid(valuesEnvironment), aliases: []};
  const preparedEnvironment = moon.clientProgramPreparePublicSourceEnvironment(valuesEnvironment, JSON.stringify(publication));
  assert.ok(preparedEnvironment);
  const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const {checked} = await import('../host-common/runtime-result.mjs');
  const admission = checked(moon.clientPrepareInstalledSequenceContracts(registry,
    JSON.stringify(contracts.execution_contracts['REL.values']), undefined, undefined));
  const context = Object.freeze({runtime: moon, environment: valuesEnvironment,
    preparedEnvironment, retainedRelationOutput: false});
  const originals = {installation: {sequenceContractOriginal: {moon, admission}}};
  const view = await prepareOrdinarySourceManagedInstallation(originals, {
    validator(actual) {assert.strictEqual(actual, originals);},
    preparationContext(actual) {assert.strictEqual(actual, originals); return context;},
  }, false);
  const checker = installNodeClientCheck({moon, environment: valuesEnvironment, publication});
  // Independent invalid operator argument, checked by the real original Core.
  const program = {version: 'actql/0.1', id: 'original-observation', stages: [{id: 's', inputs: {},
    steps: [{values: {schema: {id: {type: 'number', nullable: false}}, rows: []}, as: 'v'},
      {take: -1, as: 'bad'}], results: {rows: {from: 'bad', fields: ['id']}}}],
    results: {rows: {from: {stage: 's', result: 'rows'}}}};
  const originalConnection = Object.freeze({mode: 'local', owner: 'local',
    consentRefs: Object.freeze([]), runners: Object.freeze([])});
  const request = {};
  const receipt = view.beforeSourceSnapshot('program', program, {parameters: null}, originalConnection);
  const {snapshotClientRequest} = await import('../../packages/client-wire/index.mjs');
  const body = view.captureSourceSnapshot(receipt, {kind: 'program', input: program, parameters: null}, snapshotClientRequest);
  view.bindSourceSnapshot(receipt, body); view.bindSourceRequest(receipt, body, request);
  let failure;
  try {
    await assert.rejects(view.fundedPreparation(request, valuesEnvironment), error => {
      assert.equal(error.code, 'ClientProgramInvalidInput'); failure = error; return true;
    });
    const outcome = await view.observeOriginalCheckOutcome(request, failure, project =>
      checker.projectOriginal({principalId, kind: 'program', scope: 'bound_input',
        input: body.input, parameters: body.parameters}, project));
    assert.equal(validCheckOutcome(outcome), true); assert.equal(outcome.report.verdict, 'invalid');
    assert.equal(outcome.report.scope.kind, 'bound_input');
    assert.equal(outcome.report.inputs[0].byte_length, Buffer.byteLength(JSON.stringify(body.input)));
    assert.equal(view.observeOriginalCheckOutcome(request, new Error('foreign failure'), () =>
      assert.fail('No metadata for a foreign failure')), undefined);
    view.finishSourceProducer(receipt, 'failed');
    assert.equal(await view.observeOriginalCheckOutcome(request, failure, () =>
      assert.fail('No metadata after original retirement')), undefined);
  } finally {await view.close();}
});


test('same original completed Source violation classifies before its first durable refusal', async t => {
  const failure = Object.assign(new Error('original unresolved Source fixture'), {code: 'ClientProgramRejected'});
  let originalCalls = 0, freshChecks = 0;
  const f = await fixture(t, {prepare() {throw failure;},
    async originalObservation(error, value) {
      assert.strictEqual(error, failure);
      originalCalls++;
      return checkValues({...value, kind: 'text', scope: 'bound_input'});
    }, async check(value) {
      freshChecks++;
      return checkValues(value);
    }});
  const initial = await f.service.submitIntent(f.body('SELECT ('));
  assert.equal(initial.kind, 'not_accepted');
  assert.deepEqual(initial.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
  assert.equal(initial.checkObservation.report.verdict, 'invalid');
  assert.equal(initial.checkObservation.report.scope.kind, 'bound_input');
  assert.equal(failure.code, 'ClientProgramRejected', 'projection must not rewrite the original exception');
  assert.equal(originalCalls, 2, 'retain original current observation before and after durable write');
  assert.equal(freshChecks, 0, 'initial classification cannot borrow another check');
  f.restart();
  assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), initial);
  assert.equal(originalCalls, 2, 'reference-only lookup cannot reconstruct the original observer');
  assert.equal(freshChecks, 1, 'lookup retains its separate current disclosure check');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('typed SubmitAttempt classifies only its completed original Source observation', async t => {
  const failure = Object.assign(new Error('original unresolved Source fixture'), {code: 'ClientProgramRejected'});
  let observations = 0;
  const f = await fixture(t, {prepare() {throw failure;}, async originalObservation(error, value) {
    assert.strictEqual(error, failure);
    observations++;
    return checkValues({...value, kind: 'text', scope: 'bound_input'});
  }, check() {assert.fail('no separate check may classify the original invocation');}});
  const reply = await f.service.submitAttempt(f.body('SELECT ('));
  assert.equal(reply.kind, 'recorded');
  assert.deepEqual(reply.attemptRef, {operation: 'submit', attemptId: 'submission-test-invocation'});
  assert.equal(reply.outcome.kind, 'not_accepted');
  assert.deepEqual(reply.outcome.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
  assert.equal(reply.outcome.checkObservation.report.verdict, 'invalid');
  assert.equal(observations, 2);
  assert.equal(failure.code, 'ClientProgramRejected');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

for (const mode of ['missing', 'partial', 'undetermined', 'unavailable', 'malformed', 'exception', 'template', 'lost authority']) {
  test(`generic Source refusal cannot borrow invalidity from ${mode} original reporting`, async t => {
    let f, freshChecks = 0;
    f = await fixture(t, {prepare() {
      throw Object.assign(new Error('original unresolved Source fixture'), {code: 'ClientProgramRejected'});
    }, async originalObservation(_error, value) {
      if (mode === 'missing') return undefined;
      if (mode === 'exception') throw new Error('original observation unavailable');
      if (mode === 'unavailable') return checkValues.unavailable();
      if (mode === 'undetermined') return checkValues({...value, kind: 'text', scope: 'bound_input',
        input: {format: 'sql', text: 'SELECT id FROM missing'}});
      if (mode === 'template') {
        const {parameters, ...unbound} = value;
        void parameters;
        return checkValues({...unbound, kind: 'text', scope: 'template_only'});
      }
      const report = await checkValues({...value, kind: 'text', scope: 'bound_input'});
      if (mode === 'malformed') return {...report, outcome: 'malformed'};
      if (mode === 'partial') {
        const failure = JSON.parse(await readFile(new URL(
          '../../packages/client-wire/fixtures/check-reporting-failure.json', import.meta.url), 'utf8'));
        return {...failure, partial_report: report.report};
      }
      f.authorize(false);
      return report;
    }, check() {freshChecks++; assert.fail('a generic original cannot request another checker');}});
    const pending = f.service.submitIntent(f.body('SELECT ('));
    if (mode === 'lost authority') {
      await assert.rejects(pending, {code: 'ClientRequestLookupDenied'});
      f.authorize(true);
      assert.equal((await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref})).kind, 'unresolvable');
    } else {
      const initial = await pending;
      assert.equal(initial.kind, 'not_accepted');
      assert.deepEqual(initial.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'});
      f.restart();
      assertReferenceOnly(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), initial);
    }
    assert.equal(freshChecks, 0);
    assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  });
}


test('original Source input classification never rewrites an accepted preparation phase', async t => {
  const failure = Object.assign(new Error('original unresolved Source fixture'), {code: 'ClientProgramRejected'});
  const f = await fixture(t, {prepare() {throw failure;}, originalObservation(_error, value) {
    return checkValues({...value, kind: 'text', scope: 'bound_input'});
  }});
  const value = f.body('SELECT (');
  const intent = moon.clientSubmittedIntent(JSON.stringify({kind: value.kind, input: value.input,
    parameters: value.parameters}), 1048576, 65536, 64);
  f.journal.recordSubmittedIntent(f.ref, intent, {...fields, phase: 'preparing'}, moon);
  const response = await f.service.submitAttempt(value);
  assert.equal(response.outcome.kind, 'preparation_failed');
  assert.deepEqual(response.outcome.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
  assert.equal(response.outcome.checkObservation.report.verdict, 'invalid');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('original Source classification retains the post-write authority fence and recorded outcome', async t => {
  let f, observations = 0;
  f = await fixture(t, {prepare() {
    throw Object.assign(new Error('original unresolved Source fixture'), {code: 'ClientProgramRejected'});
  }, async originalObservation(_error, value) {
    const report = await checkValues({...value, kind: 'text', scope: 'bound_input'});
    if (++observations === 2) f.authorize(false);
    return report;
  }});
  await assert.rejects(f.service.submitAttempt(f.body('SELECT (')), {code: 'ClientRequestLookupDenied'});
  assert.equal(observations, 2);
  f.authorize(true);
  const retained = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(retained.kind, 'not_accepted');
  assert.deepEqual(retained.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
  assert.equal(Object.hasOwn(retained, 'checkObservation'), false);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

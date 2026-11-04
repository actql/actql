// Source-execution acceptance. Fresh-packed identity is established separately
// by the existing packed consumer; these tests do not claim package evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect as connectRemote, getSubmissionInput, getSubmissionOutcome,
  getSubmissionAttempt, explainSubmission, formatSubmission} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const invocationHint = 'Keep the original submission reference and use a currently authorized lookup. This invocation outcome does not establish another invocation\'s acceptance, grant permission to resubmit, or authorize changed input or a new restart decision.';
const storedAdmissionCounts = root => {
  const database = new DatabaseSync(join(root, 'host/requests/client-requests.sqlite3'),
    {readOnly: true});
  try {
    return {...database.prepare(`SELECT
      (SELECT COUNT(*) FROM client_submitted_intents) AS intents,
      (SELECT issued_count FROM client_submitted_intent_custody WHERE singleton = 1) AS issued,
      (SELECT COUNT(*) FROM client_requests) AS requests`).get()};
  } finally {database.close();}
};

async function installedFixture(t, entrance, {loseSubmissionReply = false, outcome = 'allow', epochClock} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-d-submission-public-'));
  const directory = join(root, 'host');
  const principalId = userInfo().username;
  const keys = generateKeyPairSync('ed25519');
  let computes = 0, client, host, server, port = 0, loseReply = loseSubmissionReply;
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'submission-public', entries: [{entry_id: 'acceptance', outcome,
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      {entry_id: 'owner-read', outcome: 'allow', principal: {any_of: [principalId]},
        connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['result/answer', 'run']},
        operation: {any_of: ['read']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [principalId], hostKey: {keyId: 'host',
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name) {if (name === 'computed') computes++;},
    ...(epochClock === undefined ? {} : {faultInjection: Object.assign(async () => {}, {
      submissionEpochTtlMs: 1000, submissionEpochNow: epochClock,
    })}),
  };
  const certificates = entrance === 'https' ? await fixtureCertificates(root) : undefined;
  const originalTrust = getCACertificates('default');
  if (certificates) setDefaultCACertificates([...originalTrust, certificates.ca.toString('utf8')]);
  const close = async () => {
    await client?.close(); client = undefined;
    if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); server = undefined;}
    await host?.close(); host = undefined;
  };
  t.after(async () => {
    await close();
    if (certificates) setDefaultCACertificates(originalTrust);
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      console.error(`Submission acceptance fixture retained: ${root}`);
    } else {
      await rm(root, {recursive: true, force: true});
    }
  });
  const open = async () => {
    if (entrance === 'local') client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      durability: 'durable', installation: {directory, authorization}});
    else {
      host = await openInstalledRemoteHttpHost({directory, authorization, authenticate: () => principalId});
      server = createServer({key: certificates.key, cert: certificates.cert}, (request, response) => {
        if (loseReply && ['/submit-intent', '/restart-intent'].some(route => request.url.endsWith(route))) {
          loseReply = false;
          // The installed handler commits its answer before calling end.
          // Drop only that response, without retrying the submission.
          response.end = () => {response.destroy(); return response;};
        }
        return host.handler(request, response);
      });
      await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
      port = server.address().port;
      client = await connectRemote({mode: 'remote', token: 'fixture-principal', durability: 'durable',
        endpoint: `https://127.0.0.1:${server.address().port}/`});
    }
  };
  await open();
  return {get client() {return client;}, get computes() {return computes;},
    get root() {return root;}, get certificates() {return certificates;},
    get endpoint() {return server && `https://127.0.0.1:${server.address().port}/`;},
    loseNextReply() {loseReply = true;}, close, open};
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: preparation authorization denial retains the accepted original submission`, async t => {
    const f = await installedFixture(t, entrance, {outcome: 'deny'});
    const submissionRef = f.client.newSubmission({nonce: 'denied-invocation'});
    const before = storedAdmissionCounts(f.root);
    assert.deepEqual(before, {intents: 0, issued: 0, requests: 0});
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef,
      attemptId: 'authorization-invocation'}), error => {
      assert.equal(error.code, 'SubmissionPreparationFailed');
      assert.equal(getSubmissionAttempt(error).kind, 'recorded');
      assert.equal(getSubmissionOutcome(error).kind, 'preparation_failed');
      assert.equal(explainSubmission(error).observation, 'preparation_failed');
      assert.deepEqual(explainSubmission(error).next.submissionRef, submissionRef);
      assert.equal(Object.hasOwn(explainSubmission(error), 'guarantee'), false);
      assert.equal(explainSubmission({...error}), undefined);
      assert.deepEqual(JSON.parse(formatSubmission(error, {format: 'json'})).explanation, explainSubmission(error));
      return true;
    });
    assert.deepEqual(storedAdmissionCounts(f.root), {intents: 1, issued: 1, requests: 0});
    assert.equal(f.computes, 0);
  });

  test(`${entrance}: typed Submission Conflict and AlreadySatisfied preserve the installed original Run`, async t => {
    const f = await installedFixture(t, entrance);
    const submissionRef = f.client.newSubmission({nonce: 'typed-original'});
    const original = await f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef,
      attemptId: 'typed-first-invocation'});
    assert.equal(getSubmissionAttempt(original).kind, 'recorded');
    assert.equal((await original.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    assert.deepEqual(await original.result('answer').all(), [{n: 1}]);
    const before = storedAdmissionCounts(f.root);
    await assert.rejects(f.client.startSource('SELECT 2 AS n', {format: 'sql', submissionRef,
      attemptId: 'typed-changed-invocation'}), error => {
      assert.equal(error.code, 'SubmissionConflict');
      assert.equal(getSubmissionAttempt(error).reason, 'intent');
      assert.deepEqual(getSubmissionAttempt(error).attemptRef,
        {operation: 'submit', attemptId: 'typed-changed-invocation'});
      assert.deepEqual(getSubmissionAttempt(error).submissionRef, submissionRef);
      assert.equal(getSubmissionOutcome(error), undefined);
      const expected = {observation: 'conflict', reason: 'intent',
        attemptRef: {operation: 'submit', attemptId: 'typed-changed-invocation'}, submissionRef,
        summary: 'The Host reports a conflicting intent for this original submission identity.',
        hint: invocationHint, next: {operation: 'lookupSubmission', submissionRef,
          lookupContext: getSubmissionInput(error).lookupContext}};
      assert.deepEqual(explainSubmission(error), expected, '[check-mutation:submit-attempt-conflict]');
      assert.equal(Object.hasOwn(explainSubmission(error), 'guarantee'), false);
      assert.equal(explainSubmission({...error}), undefined);
      assert.deepEqual(JSON.parse(formatSubmission(error, {format: 'json'})).explanation, expected);
      assert.deepEqual(storedAdmissionCounts(f.root), before);
      return true;
    });
    assert.equal(f.computes, 1);
    const replay = await f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef,
      attemptId: 'typed-original-replay'});
    assert.equal(getSubmissionAttempt(replay).kind, 'already_satisfied');
    assert.deepEqual(replay.ref, original.ref);
    assert.deepEqual(await replay.result('answer').all(), [{n: 1}]);
    assert.equal(f.computes, 1);
    await f.close(); await f.open();
    const restored = await f.client.lookupSubmission(submissionRef);
    assert.equal(restored.kind, 'ready');
    assert.deepEqual(restored.admission.ref, original.ref);
    assert.equal(f.computes, 1, 'lookup never dispatches a new Compute');
  });

  test(`${entrance}: typed fresh-epoch refusal is distinct from the durable original acceptance`, async t => {
    let now = 1_800_000_000_000;
    const f = await installedFixture(t, entrance, {epochClock: () => now});
    const submissionRef = f.client.newSubmission({nonce: 'accepted-before-expiry'});
    const original = await f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef,
      attemptId: 'accepted-invocation'});
    assert.equal((await original.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    now += 1000;
    const fresh = f.client.newSubmission({nonce: 'fresh-after-expiry'});
    const before = storedAdmissionCounts(f.root);
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef: fresh,
      attemptId: 'expired-invocation'}), error => {
      assert.equal(error.code, 'SubmissionRefused');
      assert.equal(getSubmissionAttempt(error).reason, 'epoch_expired');
      assert.equal(getSubmissionAttempt(error).guarantee, 'attempt_uncommitted_unconsumed');
      assert.deepEqual(getSubmissionAttempt(error).submissionRef, fresh);
      assert.deepEqual(getSubmissionAttempt(error).attemptRef,
        {operation: 'submit', attemptId: 'expired-invocation'});
      assert.equal(getSubmissionOutcome(error), undefined);
      const expected = {observation: 'refused', reason: 'epoch_expired',
        guarantee: 'attempt_uncommitted_unconsumed',
        attemptRef: {operation: 'submit', attemptId: 'expired-invocation'}, submissionRef: fresh,
        summary: 'The Host refused this submission invocation because its submitted epoch has expired. This does not establish the original submission outcome.',
        hint: invocationHint, next: {operation: 'lookupSubmission', submissionRef: fresh,
          lookupContext: getSubmissionInput(error).lookupContext}};
      assert.deepEqual(explainSubmission(error), expected, '[check-mutation:submit-attempt-refused]');
      assert.equal(explainSubmission({...error}), undefined);
      assert.deepEqual(JSON.parse(formatSubmission(error, {format: 'json'})).explanation, expected);
      assert.deepEqual(storedAdmissionCounts(f.root), before);
      return true;
    });
    assert.equal(f.computes, 1);
    const retained = await f.client.lookupSubmission(submissionRef);
    assert.equal(retained.kind, 'ready');
    assert.deepEqual(retained.admission.ref, original.ref);
    assert.deepEqual(await original.result('answer').all(), [{n: 1}]);
    assert.equal(f.computes, 1);
  });
}

for (const [entrance, loseSubmissionReply, defaultSubmission] of [
  ['local', false, false], ['https', false, false], ['https', true, false],
  ['local', false, true], ['https', false, true],
]) {
  test(`${entrance}${loseSubmissionReply ? ' lost reply' : ''}${defaultSubmission ? ' default submission' : ''}: ordinary installed Program retains its submission identity and Run after Host restart`, async t => {
    const f = await installedFixture(t, entrance, {loseSubmissionReply});
    let client = f.client;
    let submissionRef = defaultSubmission ? undefined : client.newSubmission({nonce: 'ordinary-original'});
    let run, recovery;
    if (loseSubmissionReply) {
      await assert.rejects(client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef}), error => {
        assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
        assert.equal(explainSubmission(error).observation, 'acceptance_unknown');
        assert.deepEqual(explainSubmission(error).next.submissionRef, submissionRef);
        recovery = client.recoverRequest(error);
        return error.code === 'SubmissionUnknown';
      });
      const original = await recovery.lookup();
      assert.equal(original.kind, 'ready');
      run = await recovery.attach(original);
    } else {
      const pending = client.startSource('SELECT 1 AS n', {format: 'sql',
        ...(submissionRef === undefined ? {} : {submissionRef})});
      if (defaultSubmission) {
        submissionRef = getSubmissionInput(pending).submissionRef;
        assert.deepEqual(submissionRef.epoch, client.profile.submissionEpoch);
      }
      run = await pending;
      recovery = client.recoverRequest(run);
    }
    assert.equal((await run.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), [{n: 1}]);
    assert.deepEqual(recovery.target.submissionRef, submissionRef);
    const savedTarget = JSON.parse(JSON.stringify(recovery.target));
    const first = await recovery.lookup();
    assert.equal(first.kind, 'ready');
    assert.deepEqual(first.admission.ref, run.ref);
    assert.deepEqual(explainSubmission(first), {observation: 'run_reference_received',
      summary: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
      next: {operation: 'status', ref: run.ref}});
    assert.equal(f.computes, 1);
    await f.close(); await f.open(); client = f.client;
    assert.notDeepEqual(client.newSubmission({nonce: submissionRef.nonce}), submissionRef);
    const restored = client.recoverRequest(savedTarget);
    const found = await restored.lookup();
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.submissionRef, submissionRef);
    assert.deepEqual(found.admission.ref, run.ref);
    assert.deepEqual((await restored.attach(found)).ref, run.ref);
    await assert.rejects(restored.attach({...found}), {code: 'InvalidRequestRecoveryObservation'});
    const repeated = await client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef});
    assert.deepEqual(repeated.ref, run.ref);
    assert.deepEqual(await repeated.result('answer').all(), [{n: 1}]);
    assert.equal(f.computes, 1);
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: an accepted unsupported pre-Run wait remains a preparation failure after reconnect`, async t => {
    const f = await installedFixture(t, entrance, {outcome: 'delegate'});
    const pending = f.client.startSource('SELECT 1 AS n', {format: 'sql'});
    const original = getSubmissionInput(pending);
    let outcome, recovery;
    let returnedRun, failure;
    try {returnedRun = await pending;} catch (error) {failure = error;}
    const checkpointDatabase = new DatabaseSync(join(f.root,
      'host/checkpoints/journal/checkpoint-journal.sqlite3'), {readOnly: true});
    const requestDatabase = new DatabaseSync(join(f.root,
      'host/requests/client-requests.sqlite3'), {readOnly: true});
    let records;
    try {
      records = {
        preparations: checkpointDatabase.prepare('SELECT * FROM preparations ORDER BY prepare_attempt_id')
          .all().map(row => ({...row})),
        checkpoints: checkpointDatabase.prepare('SELECT * FROM checkpoints ORDER BY checkpoint_cid')
          .all().map(row => ({...row})),
        runs: checkpointDatabase.prepare('SELECT * FROM runs ORDER BY run_id')
          .all().map(row => ({...row})),
        intents: requestDatabase.prepare('SELECT * FROM client_submitted_intents ORDER BY submission_id')
          .all().map(row => ({...row})),
        requests: requestDatabase.prepare('SELECT * FROM client_requests ORDER BY caller_request_id')
          .all().map(row => ({...row})),
      };
    } finally {checkpointDatabase.close(); requestDatabase.close();}
    const listed = await f.client.checkpoints();
    await writeFile(join(f.root, 'unsupported-wait-observation.json'), JSON.stringify({
      entrance, original, outcome: getSubmissionOutcome(failure ?? returnedRun),
      failureCode: failure?.code, returnedRef: returnedRun?.ref,
      records, listed, computes: f.computes,
    }), {mode: 0o600});
    // Read the actual Checkpoint and request journals before interpreting
    // presentation. A durable wait can exist even with zero Compute.
    assert.deepEqual({outcome: getSubmissionOutcome(failure ?? returnedRun)?.kind,
      preparations: records.preparations.map(row => row.status),
      checkpoints: records.checkpoints.length, runs: records.runs.length,
      intents: records.intents.map(row => row.phase), requests: records.requests.length,
      listed: listed.items.length, computes: f.computes},
    {outcome: 'preparation_failed', preparations: [], checkpoints: 0, runs: 0,
      intents: ['preparation_failed'], requests: 0, listed: 0, computes: 0},
    '[check-mutation:unsupported-preparation-wait]');
    await assert.rejects(async () => {throw failure;}, error => {
      assert.equal(error.code, 'SubmissionPreparationFailed');
      assert.deepEqual(getSubmissionInput(error), original);
      recovery = f.client.recoverRequest(error);
      outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'preparation_failed');
      assert.deepEqual(outcome.submissionRef, original.submissionRef);
      assert.equal(outcome.problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
      assert.equal(Object.hasOwn(outcome, 'admission'), false);
      const expected = {observation: 'preparation_failed',
        summary: 'The Host accepted this submission, then preparation failed. No Run reference was returned; this is not a rejection before acceptance.',
        hint: 'Keep the original submission reference and use an authorized lookup. This observation grants no permission to resubmit, execute or release resources.',
        problem: {code: 'ACTQL_E_DELEGATION_UNAVAILABLE', classification: 'operation_failed'},
        next: {operation: 'lookupSubmission', submissionRef: original.submissionRef,
          lookupContext: original.lookupContext}};
      assert.deepEqual(explainSubmission(error), expected, '[check-mutation:submission-public-phase]');
      assert.deepEqual(JSON.parse(formatSubmission(error, {format: 'json'})).explanation, expected);
      return true;
    });
    assert.equal(f.computes, 0);
    assert.deepEqual((await f.client.checkpoints()).items, []);
    const found = await recovery.lookup();
    assert.deepEqual(found, outcome);
    await assert.rejects(recovery.attach(found), {code: 'InvalidRequestRecoveryObservation'});
    assert.equal(explainSubmission(found).observation, 'preparation_failed');
    await f.close(); await f.open();
    const recovered = await f.client.lookupSubmission(original.submissionRef);
    assert.deepEqual(recovered, outcome);
    assert.equal(explainSubmission(recovered).observation, 'preparation_failed');
    assert.deepEqual(explainSubmission(recovered).next.submissionRef, original.submissionRef);
    assert.deepEqual((await f.client.checkpoints()).items, []);
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql',
      submissionRef: original.submissionRef}), error => {
      assert.deepEqual(getSubmissionOutcome(error), outcome);
      return error.code === 'SubmissionPreparationFailed';
    });
    assert.equal(f.computes, 0);
  });
}

for (const [entrance, lostReply] of [['local', false], ['https', false], ['https', true]]) {
  test(`${entrance}${lostReply ? ' lost reply' : ''}: explicit unresolved-history restart retains both identities at the public Host`, async t => {
    let now = 1_800_000_000_000;
    const f = await installedFixture(t, entrance, {epochClock: () => now});
    const originalRef = f.client.newSubmission({nonce: 'original-retired-refusal'});
    await assert.rejects(f.client.startSource('SELECT missing AS n', {format: 'sql', submissionRef: originalRef}),
      {code: 'SubmissionNotAccepted'});
    assert.equal(f.computes, 0);
    await f.close(); now += 1000;
    const journal = openClientRequestJournal(join(f.root, 'host/requests'), {
      submissionEpochTtlMs: 1000, submissionEpochNow: () => now,
    });
    try {
      assert.deepEqual(journal.retireSubmittedIntent(originalRef, {
        authorityScopeCid: originalRef.epoch.authorityScopeCid,
        currentAuthorization: true, expectedRevision: 0,
      }, moon), {retired: true});
    } finally {journal.close();}
    await f.open();
    assert.equal((await f.client.lookupSubmission(originalRef)).kind, 'unresolvable');
    const freshRef = f.client.newSubmission({nonce: 'deliberately-new-work'});
    const unresolvedHistory = {submissionRef: originalRef, acknowledgement: 'possible_prior_execution_and_effects'};
    // Persist the exact original, new identity and decision before first send.
    await writeFile(join(f.root, 'explicit-restart.json'), JSON.stringify({
      submissionRef: freshRef, unresolvedHistory, text: 'SELECT 1 AS n', format: 'sql',
    }), {flag: 'wx', mode: 0o600});
    if (lostReply) f.loseNextReply();
    const pending = f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef: freshRef, unresolvedHistory});
    assert.deepEqual(getSubmissionInput(pending).unresolvedHistory, unresolvedHistory);
    let run;
    if (lostReply) {
      await assert.rejects(pending, error => {
        assert.deepEqual(getSubmissionInput(error).unresolvedHistory, unresolvedHistory);
        return error.code === 'SubmissionUnknown';
      });
      const found = await f.client.lookupSubmission(freshRef);
      assert.equal(found.kind, 'ready');
      assert.deepEqual(found.unresolvedHistory, unresolvedHistory);
      run = await f.client.attach(found.admission.ref);
    } else run = await pending;
    assert.equal((await run.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), [{n: 1}]);
    const expected = await f.client.lookupSubmission(freshRef);
    assert.deepEqual(expected.unresolvedHistory, unresolvedHistory);
    assert.deepEqual(expected.admission.ref, run.ref);
    assert.equal(f.computes, 1);
    await f.close(); await f.open();
    assert.deepEqual(await f.client.lookupSubmission(freshRef), expected);
    assert.deepEqual(await f.client.lookupSubmission(freshRef), expected);
    assert.equal((await f.client.lookupSubmission(originalRef)).kind, 'unresolvable');
    assert.equal(f.computes, 1, 'read-only recovery neither submits nor recomputes');
    console.log('SUBMISSION_RESTART_PUBLIC_EVIDENCE', JSON.stringify({root: f.root, entrance,
      lostReply, originalRef, freshRef, restored: expected.kind, computes: 1}));
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: durable input rejection explains nonacceptance and survives original lookup`, async t => {
    const f = await installedFixture(t, entrance);
    const pending = f.client.startSource('SELECT missing AS n', {format: 'sql'});
    const original = getSubmissionInput(pending);
    let outcome;
    await assert.rejects(pending, error => {
      assert.equal(error.code, 'SubmissionNotAccepted');
      outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'not_accepted');
      assert.deepEqual(outcome.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
      const expected = {observation: 'not_accepted',
        summary: 'The Host durably rejected this submission before acceptance. Its identity is consumed; no Run reference was returned.',
        hint: 'Keep the original submission reference and use an authorized lookup. This observation grants no permission to resubmit, execute or release resources.',
        problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'},
        next: {operation: 'lookupSubmission', submissionRef: original.submissionRef,
          lookupContext: original.lookupContext}};
      assert.deepEqual(explainSubmission(error), expected, '[check-mutation:submission-public-phase]');
      assert.deepEqual(JSON.parse(formatSubmission(error, {format: 'json'})).explanation, expected);
      assert.equal(explainSubmission({...error}), undefined);
      return true;
    });
    assert.equal(f.computes, 0);
    await f.close(); await f.open();
    const found = await f.client.lookupSubmission(original.submissionRef);
    assert.deepEqual(found, outcome);
    assert.equal(explainSubmission(found).observation, 'not_accepted');
    assert.deepEqual(explainSubmission(found).next.submissionRef, original.submissionRef);
    await assert.rejects(f.client.startSource('SELECT missing AS n', {format: 'sql',
      submissionRef: original.submissionRef}), error => {
      assert.deepEqual(getSubmissionOutcome(error), outcome);
      assert.equal(explainSubmission(error).observation, 'not_accepted');
      return error.code === 'SubmissionNotAccepted';
    });
    assert.equal(f.computes, 0);
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: retired pre-Run history stays unresolvable at the public original lookup`, async t => {
    let now = 1_800_000_000_000;
    const f = await installedFixture(t, entrance, {epochClock: () => now});
    const submissionRef = f.client.newSubmission({nonce: 'retired-original-refusal'});
    await writeFile(join(f.root, 'retired-original-submission.json'),
      JSON.stringify({submissionRef, text: 'SELECT missing AS n', format: 'sql'}),
      {flag: 'wx', mode: 0o600});
    await assert.rejects(f.client.startSource('SELECT missing AS n', {format: 'sql', submissionRef}),
      error => error.code === 'SubmissionNotAccepted');
    const original = await f.client.lookupSubmission(submissionRef);
    assert.equal(original.kind, 'not_accepted');
    assert.equal(f.computes, 0);
    await f.close();
    now += 1000;
    // Trusted Host retention maintenance uses the same existing request
    // journal. Client observation below never invokes this maintenance API.
    const journal = openClientRequestJournal(join(f.root, 'host/requests'), {
      submissionEpochTtlMs: 1000, submissionEpochNow: () => now,
    });
    try {
      assert.deepEqual(journal.retireSubmittedIntent(submissionRef, {
        authorityScopeCid: submissionRef.epoch.authorityScopeCid,
        currentAuthorization: true, expectedRevision: 0,
      }, moon), {retired: true});
    } finally {journal.close();}
    await f.open();
    const expected = {kind: 'unresolvable', submissionRef,
      problem: {code: 'submission_history_unresolvable'}};
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), expected);
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), expected);
    assert.equal(f.computes, 0);
    console.log('RETIRED_SUBMISSION_PUBLIC_EVIDENCE', JSON.stringify({root: f.root,
      entrance, submissionRef, original: original.kind, restored: expected.kind, computes: 0}));
  });
}

test('installed HTTPS Host refuses epoch-less legacy execution without a Run', async t => {
  const f = await installedFixture(t, 'https');
  const response = await fetch(new URL('actql/client/0.1/submit', f.endpoint), {
    method: 'POST', headers: {'content-type': 'application/json',
      authorization: 'Bearer fixture-principal'},
    body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
      consentRefs: [], runners: [], durability: 'durable'},
    requestId: 'legacy-unbound', kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'},
    parameters: null}),
  });
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {code: 'ClientSubmissionReferenceRequired'});
  assert.deepEqual(await f.client.lookupRequest('legacy-unbound'), {kind: 'not_found'});
  assert.equal(f.computes, 0);
});

for (const entrance of ['local', 'https']) {
  test(`${entrance}: exact epoch expiry and restart fence new work while retaining original acceptance`, async t => {
    let clock = Date.now();
    const f = await installedFixture(t, entrance, {epochClock: () => clock});
    const saved = f.client.newSubmission({nonce: 'accepted-before-expiry'});
    const unaccepted = f.client.newSubmission({nonce: 'never-accepted'});
    clock = saved.epoch.expiresAt - 1;
    const pending = f.client.sql('SELECT 1 AS n', undefined, {submissionRef: saved});
    assert.deepEqual(getSubmissionInput(pending).submissionRef, saved);
    const result = await pending;
    assert.deepEqual(await result.all(), [{n: 1}]);
    const original = await f.client.lookupSubmission(saved);
    assert.equal(original.kind, 'ready');
    assert.equal(f.computes, 1);
    clock = saved.epoch.expiresAt;
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef: unaccepted}));
    const unresolved = await f.client.lookupSubmission(unaccepted);
    assert.equal(unresolved.kind, 'unresolvable');
    assert.deepEqual(explainSubmission(unresolved), {observation: 'history_unresolvable',
      summary: 'The Host cannot establish the original submission outcome. Work may already have started.',
      hint: 'Keep the original submission reference and use an authorized lookup. This observation grants no permission to resubmit, execute or release resources.',
      next: {operation: 'lookupSubmission', submissionRef: unaccepted,
        lookupContext: {endpoint: f.endpoint ?? 'actql:embedded', scopeRef: f.client.profile.scopeRef}}},
    '[check-mutation:submission-public-history]');
    assert.deepEqual(await f.client.lookupSubmission(saved), original);
    assert.equal(f.computes, 1);
    await f.close();
    clock = saved.epoch.notBefore; // The persisted high-water clock cannot go backwards.
    await f.open();
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef: unaccepted}));
    assert.equal((await f.client.lookupSubmission(unaccepted)).kind, 'unresolvable');
    assert.deepEqual(await f.client.lookupSubmission(saved), original);
    const replay = await f.client.sql('SELECT 1 AS n', undefined, {submissionRef: saved});
    assert.deepEqual(replay.execution.ref, original.admission.ref);
    assert.deepEqual(await replay.all(), [{n: 1}]);
    assert.equal(f.computes, 1, 'expiry/restart observation and replay never create a second Compute');
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: expired retired submission cannot regain admission custody or create a Run`, async t => {
    let now = 1_800_000_000_000;
    const f = await installedFixture(t, entrance, {epochClock: () => now});
    const originalRef = f.client.newSubmission({nonce: 'expired-retired-admission'});
    await assert.rejects(f.client.startSource('SELECT missing AS n',
      {format: 'sql', submissionRef: originalRef}), {code: 'SubmissionNotAccepted'});
    assert.equal(f.computes, 0);
    await f.close(); now = originalRef.epoch.expiresAt;
    const journal = openClientRequestJournal(join(f.root, 'host/requests'), {
      submissionEpochTtlMs: 1000, submissionEpochNow: () => now,
    });
    try {
      assert.deepEqual(journal.retireSubmittedIntent(originalRef, {
        authorityScopeCid: originalRef.epoch.authorityScopeCid,
        currentAuthorization: true, expectedRevision: 0,
      }, moon), {retired: true});
    } finally {journal.close();}
    await f.open();
    const counts = () => {
      const database = new DatabaseSync(join(f.root, 'host/requests/client-requests.sqlite3'),
        {readOnly: true});
      try {
        const row = database.prepare(`SELECT
          (SELECT COUNT(*) FROM client_submitted_intents) AS intents,
          (SELECT issued_count FROM client_submitted_intent_custody WHERE singleton = 1) AS issued,
          (SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton = 1) AS retired,
          (SELECT COUNT(*) FROM client_requests) AS requests`).get();
        return Object.fromEntries(Object.entries(row).map(([key, value]) => [key, Number(value)]));
      } finally {database.close();}
    };
    const expectedCounts = {intents: 0, issued: 1, retired: 1, requests: 0};
    assert.deepEqual(counts(), expectedCounts);
    // Corrected text cannot reactivate an expired original identity, even
    // after its per-submission record has been retired by the same Owner.
    let returned, errorCode;
    try {
      returned = await f.client.startSource('SELECT 1 AS n',
        {format: 'sql', submissionRef: originalRef});
    } catch (cause) {
      if (cause?.code !== 'SubmissionRefused') throw cause;
      assert.equal(getSubmissionAttempt(cause).reason, 'epoch_expired');
      assert.equal(getSubmissionAttempt(cause).guarantee, 'attempt_uncommitted_unconsumed');
      assert.deepEqual(getSubmissionAttempt(cause).submissionRef, originalRef);
      errorCode = cause.code;
    }
    const observed = counts();
    await writeFile(join(f.root, 'expired-admission-observation.json'), JSON.stringify({
      originalRef, now, expectedCounts, observed, errorCode,
      returnedRef: returned?.ref, computes: f.computes,
    }), {mode: 0o600});
    assert.deepEqual(observed, expectedCounts, '[check-mutation:expired-admission-custody]');
    assert.equal(returned, undefined, '[check-mutation:expired-admission-run]');
    assert.equal(f.computes, 0, '[check-mutation:expired-admission-compute]');
    const expectedLookup = {kind: 'unresolvable', submissionRef: originalRef,
      problem: {code: 'submission_history_unresolvable'}};
    assert.deepEqual(await f.client.lookupSubmission(originalRef), expectedLookup);
    assert.deepEqual(await f.client.lookupSubmission(originalRef), expectedLookup);
    assert.deepEqual(counts(), expectedCounts);
    await f.close(); now = originalRef.epoch.notBefore;
    await f.open();
    await assert.rejects(f.client.startSource('SELECT 1 AS n',
      {format: 'sql', submissionRef: originalRef}), error => {
      assert.equal(error.code, 'SubmissionRefused');
      assert.equal(getSubmissionAttempt(error).reason, 'epoch_expired');
      assert.deepEqual(getSubmissionAttempt(error).submissionRef, originalRef);
      return true;
    });
    assert.deepEqual(await f.client.lookupSubmission(originalRef), expectedLookup);
    assert.deepEqual(counts(), expectedCounts);
    assert.equal(f.computes, 0);
  });
}

// Execute only when the matching-target native gate supplies its real binary.
// A refusal's phase and public input category survive the original lookup.
// This test uses the installed preparation/check/journal owners, with no Run.
for (const entrance of ['local', 'https']) {
  test(`${entrance}: durable known-input category survives original submission lookup after Host restart`, async t => {
    const f = await installedFixture(t, entrance);
    const submissionRef = f.client.newSubmission({nonce: 'known-input-original'});
    const pending = f.client.startSource('SELECT missing AS n', {format: 'sql', submissionRef});
    const original = getSubmissionInput(pending);
    let outcome;
    await assert.rejects(pending, error => {
      outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'not_accepted');
      assert.deepEqual(outcome.submissionRef, submissionRef);
      assert.deepEqual(outcome.problem, {code: 'ClientProgramInvalidInput', classification: 'invalid_input'});
      assert.equal('admission' in outcome, false);
      return true;
    });
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
    assert.equal(f.computes, 0);
    await f.close(); await f.open();
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
    await assert.rejects(f.client.startSource(original.input.text,
      {format: original.input.format, submissionRef}), error => {
      assert.deepEqual(getSubmissionOutcome(error), outcome);
      return true;
    });
    // This initial Owner decision certifies the changed invocation's conflict,
    // without replacing the original durable input rejection or its custody.
    await assert.rejects(f.client.startSource('SELECT 1 AS n', {format: 'sql', submissionRef,
      attemptId: 'known-input-changed-invocation'}), error => {
      assert.equal(error.code, 'SubmissionConflict');
      assert.equal(getSubmissionAttempt(error).reason, 'intent');
      assert.deepEqual(getSubmissionAttempt(error).attemptRef,
        {operation: 'submit', attemptId: 'known-input-changed-invocation'});
      assert.equal(getSubmissionOutcome(error), undefined);
      assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
      return true;
    });
    assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
    assert.equal(f.computes, 0, 'lookup/replay never prepares a new Run or performs Model/Effect work');
  });
}

// Ordinary Node gates still exercise both public SDK entrances above.
if (process.env.ACTQL_NATIVE_SUBMISSION_CLIENT) {
  test('Native HTTPS: original submission survives a lost reply and Host restart', async t => {
    const f = await installedFixture(t, 'https', {loseSubmissionReply: true});
    const original = f.client.newSubmission({nonce: 'native-original'});
    await writeFile(join(f.root, 'connection.json'), JSON.stringify({mode: 'remote', owner: 'remote',
      consentRefs: [], runners: [], durability: 'durable'}));
    await writeFile(join(f.root, 'token.txt'), 'fixture-principal', {mode: 0o600});
    await writeFile(join(f.root, 'original.json'), JSON.stringify(original));
    await writeFile(join(f.root, 'query.sql'), 'SELECT 1 AS n');
    for (const [name, bytes] of [['ca.pem', f.certificates.ca], ['cert.pem', f.certificates.cert], ['key.pem', f.certificates.key]]) {
      await writeFile(join(f.root, name), bytes, {mode: 0o600});
    }
    const run = (...args) => promisify(execFile)(process.env.ACTQL_NATIVE_SUBMISSION_CLIENT,
      ['--endpoint', f.endpoint, '--connection-root', f.root, '--connection-file', 'connection.json',
        '--token-root', f.root, '--token-file', 'token.txt', '--http-library',
        process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4',
        '--ca', join(f.root, 'ca.pem'), '--cert', join(f.root, 'cert.pem'), '--key', join(f.root, 'key.pem'), ...args],
      {cwd: f.root, env: {...process.env, PATH: ''}, timeout: 20000});
    await assert.rejects(run('aql', '--program-file', 'query.sql', '--format', 'sql',
      '--submission-ref-file', 'original.json', '--operation-attempt-id', 'native-original-invocation'), error => /SubmissionUnknown submission-ref-file=original.json/u.test(error.stderr));
    const lookedUp = JSON.parse((await run('lookup-submission', '--submission-ref-file', 'original.json')).stdout);
    assert.equal(lookedUp.kind, 'ready');
    assert.deepEqual(lookedUp.submissionRef, original);
    const execution = await f.client.attach(lookedUp.admission.ref);
    assert.equal((await execution.wait({until: 'terminal'})).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), [{n: 1}]);
    await f.close(); await f.open();
    const restored = JSON.parse((await run('lookup-submission', '--submission-ref-file', 'original.json')).stdout);
    assert.deepEqual(restored, lookedUp);
    const replay = JSON.parse((await run('aql', '--program-file', 'query.sql', '--format', 'sql',
      '--submission-ref-file', 'original.json')).stdout);
    assert.deepEqual(replay.ref, lookedUp.admission.ref);
    assert.equal(f.computes, 1, 'Native lookup/replay never allocates another Run or Compute');
  });
}

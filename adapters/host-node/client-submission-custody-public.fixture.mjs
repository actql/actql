// Ordinary public Clients against an installed Host in a fresh process.
import assert from 'node:assert/strict';
import {appendFile, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {openClientRequestJournal} from './client-request-journal.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
const options = JSON.parse(await new Promise(resolve => {
  let input = ''; process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => {input += chunk;});
  process.stdin.on('end', () => resolve(input));
}));
const {root, runtime, entrance, phase, program, scenario} = options;
const {connect} = await import(runtime.client);
const {getSubmissionInput, getSubmissionAttempt, getSubmissionOutcome} = await import(runtime.sdk);
const {openInstalledRemoteHttpHost} = await import(runtime.httpHost);
const keys = JSON.parse(await readFile(join(root, 'keys.json'), 'utf8'));
const principalId = userInfo().username;
let computes = 0, client, host, server, report;
let epochNow = 1_800_000_000_000, loseRestartReply = false, loseSubmitReply = false;
if (phase === 'restart-lookup') epochNow += 1000;
const progress = boundary => appendFile(join(root, `${phase}.progress.jsonl`),
  JSON.stringify({boundary, at: new Date().toISOString(), computes}) + '\n');
const authorization = {
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'submission-custody', entries: [{entry_id: 'acceptance', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []},
    {entry_id: 'owner-read', outcome: 'allow', principal: {any_of: [principalId]},
      connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['result/answer', 'run']},
      operation: {any_of: ['read']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId, publicKey: keys.publicKey}],
  reviewReaders: [principalId], hostKey: {keyId: 'host', privateKey: keys.privateKey},
  observe(name) {if (name === 'computed') computes++;},
  ...(scenario === 'explicit_restart' ? {faultInjection: Object.assign(async () => {}, {
    submissionEpochTtlMs: 1000, submissionEpochNow: () => epochNow,
  })} : {}),
};
const close = async () => {
  await client?.close(); client = undefined;
  if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); server = undefined;}
  await host?.close(); host = undefined;
};
const open = async () => {
  const installation = {directory: join(root, 'host'), authorization};
  if (entrance === 'local') client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
  else {
    const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(root, name))));
    setDefaultCACertificates([...getCACertificates('default'), cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: () => principalId});
    server = createServer({key, cert}, (request, response) => {
      if ((loseRestartReply && request.url.endsWith('/restart-intent')) ||
          (loseSubmitReply && request.url.endsWith('/submit-intent'))) {
        loseRestartReply = false;
        loseSubmitReply = false;
        response.end = () => {response.destroy(); return response;};
      }
      return host.handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', token: 'fixture-owner', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
};
try {
  await progress('opening_host');
  await open();
  await progress('connected');
  if (scenario === 'typed_submission') {
    const originalPath = join(root, 'original-submission-input.json');
    let original, run, initialAttempt, initialUnknown;
    if (phase === 'typed-initial') {
      original = {submissionRef: client.newSubmission({nonce: 'typed-process-original'}),
        input: program};
      await writeFile(originalPath, JSON.stringify(original), {flag: 'wx', mode: 0o600});
      loseSubmitReply = entrance === 'https';
      const pending = client.start(original.input, {submissionRef: original.submissionRef,
        attemptId: 'typed-process-initial'});
      if (entrance === 'https') {
        try {await pending; throw new Error('FixtureSubmissionReplyShouldBeLost');}
        catch (error) {
          if (error.code !== 'SubmissionUnknown') throw error;
          assert.equal(getSubmissionAttempt(error), undefined);
          assert.equal(getSubmissionOutcome(error), undefined);
          assert.deepEqual(getSubmissionInput(error).attemptRef,
            {operation: 'submit', attemptId: 'typed-process-initial'});
          initialUnknown = error.code;
        }
      } else {
        run = await pending;
        initialAttempt = getSubmissionAttempt(run);
        assert.equal(initialAttempt.kind, 'recorded');
      }
    } else original = JSON.parse(await readFile(originalPath, 'utf8'));
    const lookup = await client.lookupSubmission(original.submissionRef);
    const second = await client.lookupSubmission(original.submissionRef);
    run ??= await client.attach(lookup.admission.ref);
    const state = await run.wait({signal: AbortSignal.timeout(15000)});
    const rows = await run.result('answer').all();
    let conflict;
    if (phase === 'typed-lookup') {
      const changed = structuredClone(original.input);
      changed.stages[0].steps[0].values.rows[0].id = 2;
      try {
        await client.start(changed, {submissionRef: original.submissionRef,
          attemptId: 'typed-process-changed'});
        throw new Error('FixtureChangedIntentShouldBeRefused');
      } catch (error) {
        if (error.code !== 'SubmissionConflict') throw error;
        conflict = getSubmissionAttempt(error);
        assert.equal(getSubmissionOutcome(error), undefined);
      }
    }
    report = {pid: process.pid, ref: run.ref, submissionRef: original.submissionRef,
      initialAttempt, initialUnknown, state, rows, lookup, second, conflict, computes};
    await progress('original_submission_lookup_without_resend');
  } else if (scenario === 'explicit_restart') {
    const decisionPath = join(root, 'explicit-restart.json');
    let decision, run;
    if (phase === 'restart-initial') {
      const originalRef = client.newSubmission({nonce: 'expired-original'});
      await writeFile(join(root, 'original-submission-input.json'), JSON.stringify({
        submissionRef: originalRef, text: 'SELECT missing AS n', format: 'sql',
      }), {flag: 'wx', mode: 0o600});
      try {
        await client.startSource('SELECT missing AS n', {format: 'sql', submissionRef: originalRef});
        throw new Error('FixtureOriginalShouldBeRejected');
      } catch (error) {if (error.code !== 'SubmissionNotAccepted') throw error;}
      await close(); epochNow += 1000;
      const journal = openClientRequestJournal(join(root, 'host/requests'), {
        submissionEpochTtlMs: 1000, submissionEpochNow: () => epochNow,
      });
      try {
        const retired = journal.retireSubmittedIntent(originalRef, {
          authorityScopeCid: originalRef.epoch.authorityScopeCid,
          currentAuthorization: true, expectedRevision: 0,
        }, moon);
        if (!retired.retired) throw new Error('FixtureOriginalRetirementMissing');
      } finally {journal.close();}
      await open();
      decision = {submissionRef: client.newSubmission({nonce: 'deliberately-new-work'}),
        unresolvedHistory: {submissionRef: originalRef,
          acknowledgement: 'possible_prior_execution_and_effects'}};
      await writeFile(decisionPath, JSON.stringify(decision), {flag: 'wx', mode: 0o600});
      await progress('explicit_decision_retained_before_send');
      loseRestartReply = entrance === 'https';
      const pending = client.start(program, decision);
      const saved = getSubmissionInput(pending);
      assert.deepEqual(saved.unresolvedHistory, decision.unresolvedHistory);
      if (entrance === 'https') {
        try {await pending; throw new Error('FixtureRestartReplyShouldBeLost');}
        catch (error) {if (error.code !== 'SubmissionUnknown') throw error;}
      } else run = await pending;
    } else decision = JSON.parse(await readFile(decisionPath, 'utf8'));
    const lookup = await client.lookupSubmission(decision.submissionRef);
    const second = await client.lookupSubmission(decision.submissionRef);
    run ??= await client.attach(lookup.admission.ref);
    const state = await run.wait({signal: AbortSignal.timeout(15000)});
    report = {pid: process.pid, ref: run.ref, state,
      rows: await run.result('answer').all(), decision, lookup, second,
      original: await client.lookupSubmission(decision.unresolvedHistory.submissionRef), computes};
    await progress('restart_lookup_without_resubmission');
  } else {
  const originalPath = join(root, 'original-submission-input.json');
  const original = phase === 'initial'
    ? {submissionRef: client.newSubmission({nonce: 'original-submission'}),
      kind: 'program', input: program, parameters: null}
    : JSON.parse(await readFile(originalPath, 'utf8'));
  if (phase === 'initial') await writeFile(originalPath, JSON.stringify(original));
  await progress('original_input_retained');
  try {
    const run = await client.start(original.input, {submissionRef: original.submissionRef,
      parameters: original.parameters});
    await progress('run_admitted');
    const state = await run.wait({signal: AbortSignal.timeout(15000)});
    await progress('terminal_observed');
    report = {outcome: 'accepted', ref: run.ref, submissionRef: original.submissionRef,
      state, rows: await run.result('answer').all()};
    await progress('rows_delivered');
  } catch (error) {
    report = {outcome: 'unknown', code: error.code,
      requestId: getSubmissionInput(error)?.requestId,
      submissionRef: getSubmissionInput(error)?.submissionRef, message: error.message};
  }
  report.lookup = await client.lookupSubmission(original.submissionRef);
  await progress('original_submission_looked_up');
  report.computes = computes;
  }
} catch (error) {
  const causes = [];
  for (let cause = error.cause; cause && causes.length < 8; cause = cause.cause) {
    causes.push({name: cause.name, code: cause.code});
  }
  report = {error: error.code ?? error.message, stack: error.stack, causes, computes};
}
finally {
  await close();
  await progress('client_closed');
}
await writeFile(join(root, `${phase}.json`), JSON.stringify(report));
process.exit(report.error === undefined ? 0 : 1);

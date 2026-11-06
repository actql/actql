// Fresh external consumers exercise the real installed Local and TLS HTTPS
// owners. Only independently expected rows and observed Compute counts pass.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {setImmediate} from 'node:timers/promises';
import {connect, open} from '@actql/node';
import {getSubmissionInput, getSubmissionOutcome} from '@actql/sdk';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {assertObservedTransition, createComputedBarrier, observedRevision,
  observeSettledResult, publishedFacts} from './run-revision-assertions.mjs';
import {closeFixtureClient, withFixtureClientCleanup} from './client-cleanup.mjs';

function authorization(outcome = 'allow') {
  const keys = generateKeyPairSync('ed25519');
  let computes = 0, nextComputed;
  return {count: () => computes, holdNextComputed() {
    assert.equal(nextComputed, undefined, 'One fixture-owned pending barrier');
    nextComputed = createComputedBarrier();
    return nextComputed;
  }, value: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: `short-${outcome}`, entries: [{entry_id: 'write', outcome,
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      // Current Host observation and each named Result use distinct read
      // tuples. Neither grants a write or answers a delegated preparation.
      {entry_id: 'owner-read', outcome: 'allow',
        principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'result/main', 'result/named', 'run']},
        operation: {any_of: ['read']}, exclusions: []}]
        .sort((left, right) => left.entry_id.localeCompare(right.entry_id))}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name) {if (name === 'computed') computes++;},
    async faultInjection(name, detail) {
      if (name === 'computed' && nextComputed !== undefined) {
        const original = nextComputed;
        nextComputed = undefined;
        await original.observe(detail.ref);
      }
    },
  }};
}

const defaults = await open();
await withFixtureClientCleanup(defaults, async () => {
  assert.equal(defaults.info.stateDir, resolve('.actql'));
  assert.deepEqual(await defaults.sql('SELECT 0 AS id').all(), [{id: 0}]);
});

async function checkRunnable(db, counter, label) {
  const before = counter.count();
  const check = (text, options) => db.check(text, {kind: 'text', format: 'sql', ...options});
  const plain = await check('SELECT 1 AS id', {scope: 'bound_input'});
  assert.equal(plain.outcome, 'completed');
  assert.equal(plain.report.verdict, 'verified');
  assert.deepEqual(plain.report.runnable, {verdict: 'yes', reasons: []});
  const parameterDeclarations = {id: {type: 'number'}};
  const template = await check('SELECT @id AS id', {scope: 'template_only', parameterDeclarations});
  assert.equal(template.outcome, 'completed');
  assert.equal(template.report.verdict, 'verified');
  assert.equal(template.report.runnable.verdict, 'no');
  assert.ok(template.report.runnable.reasons.some(reason => reason.code === 'parameter_value_required'));
  const bound = await check('SELECT @id AS id', {scope: 'bound_input',
    parameterDeclarations, parameters: {id: 1}});
  assert.equal(bound.outcome, 'completed');
  assert.equal(bound.report.verdict, 'verified');
  assert.deepEqual(bound.report.runnable, {verdict: 'yes', reasons: []});
  const invalid = await check('SELECT @id AS id', {scope: 'bound_input',
    parameterDeclarations, parameters: {id: 'not-a-number'}});
  assert.equal(invalid.outcome, 'completed');
  assert.equal(invalid.report.verdict, 'invalid');
  assert.equal(invalid.report.runnable.verdict, 'no');
  assert.ok(invalid.report.runnable.reasons.length > 0);
  const program = JSON.parse(await readFile('values.json', 'utf8'));
  const structured = await db.check(program, {kind: 'program', scope: 'bound_input'});
  assert.equal(structured.outcome, 'completed');
  assert.equal(structured.report.verdict, 'verified');
  assert.deepEqual(structured.report.runnable, {verdict: 'yes', reasons: []});
  assert.equal(counter.count(), before, `${label}: check must not execute the Program`);
  console.log(JSON.stringify({kind: 'current-wire-check', transport: label,
    runnable: {plain: 'yes', templateWithoutValue: 'no', bound: 'yes', invalid: 'no', structured: 'yes'},
    additionalCompute: counter.count() - before}));
}

async function exercise(db, counter, label) {
  await checkRunnable(db, counter, label);
  const query = db.sql('SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id', undefined,
    {submissionRef: db.newSubmission({nonce: `${label}-original`})});
  const savedId = query.requestId;
  assert.ok(query instanceof Promise);
  const [first, repeated] = await Promise.all([query, query]);
  assert.equal(first, repeated);
  assert.equal(first.then, undefined);
  assert.equal(getSubmissionInput(first).requestId, savedId);
  const recovery = db.recoverRequest(first);
  assert.equal(recovery.target.submissionRef.nonce, savedId);
  const lookup = await recovery.lookup();
  assert.equal(lookup.kind, 'ready');
  assert.deepEqual((await recovery.attach(lookup)).ref, first.execution.ref);
  await assert.rejects(recovery.attach({...lookup}), {code: 'InvalidRequestRecoveryObservation'});
  assert.deepEqual(await query.all(), [{id: 1}, {id: 2}]);
  const schema = {'~standard': {version: 1, vendor: 'packed-test', async validate(value) {
    if (value === null || typeof value !== 'object' || typeof value.id !== 'number') {
      return {issues: [{message: 'Expected numeric id', path: ['id']}]};
    }
    return {value: {label: `id-${value.id}`, at: new Date(value.id)}};
  }}};
  const expected = [{label: 'id-1', at: new Date(1)}, {label: 'id-2', at: new Date(2)}];
  assert.deepEqual(await query.all(schema), expected);
  assert.deepEqual(await first.all(schema), expected);
  const typedRows = first.rows(schema);
  assert.deepEqual(await Array.fromAsync(typedRows), expected);
  assert.equal(typedRows.rowsYielded(), 2); assert.equal(typedRows.state(), 'complete');
  const rejectsSecond = {'~standard': {version: 1, vendor: 'packed-test', validate(value) {
    return value.id === 1 ? {value: 'first'} :
      {issues: [{message: 'Second row refused', path: ['id']}]};
  }}};
  await assert.rejects(query.all(rejectsSecond), error =>
    error.code === 'ResultValidationFailed' && error.validationKind === 'issues' &&
    error.rowIndex === 1 && error.rowsYielded === 0 &&
    error.resultRef.resultName === first.ref.resultName &&
    error.resultRef.run.runDefinitionCid === first.ref.run.runDefinitionCid &&
    error.issues[0].path[0] === 'id');
  const invalid = first.rows(rejectsSecond), iterator = invalid[Symbol.asyncIterator]();
  assert.deepEqual(await iterator.next(), {done: false, value: 'first'});
  await assert.rejects(iterator.next(), {code: 'ResultValidationFailed',
    attemptId: invalid.attemptId, rowIndex: 1, rowsYielded: 1});
  let validates = 0;
  const mutates = {'~standard': {version: 1, vendor: 'packed-test', validate(value) {
    validates++; delete value.id; return {value: null};
  }}};
  await assert.rejects(query.all(mutates, {maxRetainedValueBytes: 270}),
    {code: 'ResultRetainedLimit', rowsYielded: 0});
  assert.equal(validates, 1, `${label}: raw collection charge precedes mutation`);

  assert.deepEqual(await query.all(), [{id: 1}, {id: 2}]);
  const one = first.rows(), two = first.rows();
  assert.notEqual(one.attemptId, two.attemptId);
  assert.deepEqual(await Array.fromAsync(one), [{id: 1}, {id: 2}]);
  assert.deepEqual(await Array.fromAsync(two), [{id: 1}, {id: 2}]);
  await assert.rejects(query.all({maxRows: 1}), {code: 'ResultRetainedLimit', rowsYielded: 0});
  assert.deepEqual(await Array.fromAsync(first.rows()), [{id: 1}, {id: 2}]);
  assert.deepEqual((await db.lookupSubmission(getSubmissionInput(first).submissionRef)).admission.ref, first.execution.ref);
  assert.deepEqual(await (await db.attach(first.ref.run)).result(first.ref.resultName).all(),
    [{id: 1}, {id: 2}]);
  await setImmediate();
  assert.equal(counter.count(), 1, `${label}: repeated awaits/reads must not repeat Compute`);
  const named = await db.aql('SELECT @id AS id |> RESULT named', {id: 3},
    {submissionRef: db.newSubmission({nonce: `${label}-named`}), result: 'named', parameterDeclarations: {id: {type: 'number'}}});
  assert.deepEqual(await named.all(), [{id: 3}]);
  assert.equal(named.ref.resultName, 'named');
  // Complete the preceding Run's hook before arming one for the next original.
  const computeDeadline = AbortSignal.timeout(5000);
  while (counter.count() < 2) {computeDeadline.throwIfAborted(); await setImmediate();}
  assert.equal(counter.count(), 2);
  const barrier = counter.holdNextComputed();
  let low, firstTerminal;
  try {
    low = await db.startSource('SELECT 4 AS id',
      {format: 'sql', submissionRef: db.newSubmission({nonce: `${label}-low`})});
    await barrier.waitForOriginal(low.ref, AbortSignal.timeout(5000));
    firstTerminal = await low.wait();
    assert.equal(firstTerminal.status, 'succeeded');
    assert.equal(firstTerminal.control.physical_stop, 'unknown');
  } finally {barrier.release();}
  const earlierRevision = observedRevision(firstTerminal, label);
  const immediate = await low.status();
  assertObservedTransition(firstTerminal, immediate, `${label}: immediate status`);
  const completed = await observeSettledResult(low, immediate, 'main', label,
    AbortSignal.timeout(5000));
  const completedRevision = observedRevision(completed, label);
  const reread = await low.status();
  assertObservedTransition(completed, reread, `${label}: settled no-op status`);
  assert.deepEqual(publishedFacts(reread), publishedFacts(completed));
  assert.ok(completedRevision > earlierRevision && completedRevision < Number.MAX_SAFE_INTEGER);
  const newer = await low.wait({since: earlierRevision, signal: AbortSignal.timeout(5000)});
  assert.equal(newer.run_id, completed.run_id);
  assertObservedTransition(completed, newer, `${label}: earlier since`);
  assert.equal(observedRevision(newer, label), completedRevision);
  await assert.rejects(low.wait({since: completedRevision, signal: AbortSignal.timeout(250)}),
    {code: 'WaitTimeout'});
  await assert.rejects(low.wait({since: completedRevision + 1, signal: AbortSignal.timeout(5000)}),
    {code: 'InvalidWaitRevision'});
  const abort = new AbortController();
  const waiting = low.wait({since: completedRevision, signal: abort.signal});
  const aborted = assert.rejects(waiting, {code: 'WaitAborted'});
  await setImmediate();
  abort.abort();
  await aborted;
  const afterWait = await low.status();
  assertObservedTransition(completed, afterWait, `${label}: timeout/abort do not change facts`);
  assert.equal(observedRevision(afterWait, label), completedRevision);
  console.log(JSON.stringify({kind: 'current-wire-wait', transport: label,
    earlierRevision, stateRevision: completedRevision, newerRevision: newer.revision,
    equalSince: 'WaitTimeout', futureSince: 'InvalidWaitRevision', aborted: 'WaitAborted'}));
  assert.deepEqual(await low.result('main').all(), [{id: 4}]);
  await setImmediate();
  assert.equal(counter.count(), 3);
  const state = await first.execution.status();
  return {ref: first.ref, target: recovery.target,
    runId: state.run_id, stateRevision: observedRevision(state, label)};
}

const localAuthorization = authorization();
const localOptions = {stateDir: resolve('short-local'), installation: {
  authorization: localAuthorization.value}};
let local = await open(localOptions);
const saved = await withFixtureClientCleanup(local, async () => {
  assert.equal(local.info.stateDir, localOptions.stateDir);
  return exercise(local, localAuthorization, 'local');
});
local = await open(localOptions);
await withFixtureClientCleanup(local, async () => {
  const recovery = local.recoverRequest(JSON.parse(JSON.stringify(saved.target)));
  const observed = await recovery.lookup();
  assert.equal(observed.kind, 'ready');
  assert.deepEqual((await recovery.attach(observed)).ref, saved.ref.run);
  assert.deepEqual(await (await local.attach(saved.ref.run)).result(saved.ref.resultName).all(),
    [{id: 1}, {id: 2}]);
  const attached = await local.attach(saved.ref.run);
  const restored = await attached.status();
  assert.equal(restored.run_id, saved.runId);
  assert.equal(restored.status, 'succeeded');
  assert.ok(observedRevision(restored, 'local restart') >= saved.stateRevision);
  const reread = await attached.status();
  assertObservedTransition(restored, reread, 'local restart reread');
  assert.equal(observedRevision(reread, 'local reread'), restored.revision,
    'A stable original Run read must not advance its revision');
  await assert.rejects(attached.wait({since: restored.revision, signal: AbortSignal.timeout(250)}),
    {code: 'WaitTimeout'});
  assert.equal(localAuthorization.count(), 3, 'reopen/attach/wait must not repeat Compute');
});

const remoteAuthorization = authorization();
const host = await openInstalledRemoteHttpHost({directory: resolve('short-remote'),
  authorization: remoteAuthorization.value,
  authenticate: header => header === 'Bearer short-token' ? userInfo().username : undefined});
const server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let remote;
try {
  remote = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'short-token'});
  await exercise(remote, remoteAuthorization, 'https');
  const originalFetch = globalThis.fetch;
  let lost = false;
  globalThis.fetch = async (...args) => {
    const response = await originalFetch(...args);
    if (!lost && new URL(args[0]).pathname.endsWith('/submit-intent')) {
      lost = true; await response.body.cancel();
      throw new TypeError('Test-owned acceptance reply lost');
    }
    return response;
  };
  try {
    const query = remote.sql('SELECT 5 AS id', undefined, {submissionRef: remote.newSubmission({nonce: 'https-lost'})});
    let original;
    await assert.rejects(query, error => {
      original = error; assert.equal(error.code, 'SubmissionUnknown');
      assert.equal(getSubmissionInput(error).requestId, 'https-lost'); return true;
    });
    await assert.rejects(query.all(), error => error === original);
    await assert.rejects(query.all({'~standard': {}}), error => error === original);
    await assert.rejects(query.one({get maxRows() {throw new Error('local capture');}}),
      error => error === original);
    const recovery = remote.recoverRequest(original);
    const found = await recovery.lookup();
    assert.equal(found.kind, 'ready');
    const execution = await recovery.attach(found);
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('main').all(), [{id: 5}]);
    await setImmediate();
    assert.equal(remoteAuthorization.count(), 4, 'lost reply must not cause resubmission');
  } finally {globalThis.fetch = originalFetch;}
  if (process.env.ACTQL_SDK_ONLY_ACCEPTANCE) {
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [process.env.ACTQL_SDK_ONLY_ACCEPTANCE],
        {stdio: 'inherit', env: {...process.env,
          ACTQL_RELEASE_TEST_ENDPOINT: `https://127.0.0.1:${server.address().port}/`}});
      const timeout = setTimeout(() => child.kill('SIGTERM'), 60_000);
      child.once('error', error => {clearTimeout(timeout); reject(error);});
      child.once('close', code => {
        clearTimeout(timeout);
        code === 0 ? resolve() : reject(Error(`SDKOnlyConsumerFailed:${code}`));
      });
    });
    await setImmediate();
    assert.equal(remoteAuthorization.count(), 6, 'SDK-only README, reads and lookup must not repeat Compute');
  }
} finally {
  if (remote !== undefined) await closeFixtureClient(remote); server.closeAllConnections();
  await new Promise(resolve => server.close(resolve)); await host.close();
}

const heldAuthorization = authorization('delegate');
const held = await open({stateDir: resolve('short-held'), installation: {authorization: heldAuthorization.value}});
await withFixtureClientCleanup(held, async () => {
  const query = held.sql('SELECT 6 AS id', undefined, {submissionRef: held.newSubmission({nonce: 'held-query'})});
  let original;
  await assert.rejects(query, error => {
    original = error; assert.equal(error.code, 'SubmissionPreparationFailed');
    assert.equal(getSubmissionOutcome(error).problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
    assert.equal(error.execution, undefined); assert.equal(error.executionRef, undefined);
    assert.equal(getSubmissionInput(error).requestId, 'held-query'); return true;
  });
  await assert.rejects(query, error => error === original);
  await assert.rejects(query.all({'~standard': {}}), error => error === original);
  await assert.rejects(query.scalar({get maxRows() {throw new Error('local capture');}}),
    error => error === original);
  const recovery = held.recoverRequest(original);
  const observation = await recovery.lookup();
  assert.equal(observation.kind, 'preparation_failed');
  assert.deepEqual(observation, getSubmissionOutcome(original));
  await assert.rejects(recovery.attach(observation), {code: 'InvalidRequestRecoveryObservation'});
  assert.deepEqual((await held.checkpoints()).items, []);
  assert.equal(heldAuthorization.count(), 0);
});
console.log('Packed short-query Local/HTTPS: default open, raw/typed rows, schema failures, same Run, read limits, lost reply and unsupported pre-Run wait passed');

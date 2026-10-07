// The initial Host and execution Owner live only in this child process.
// The orchestrator waits for its exit before starting the restoration process.
import assert from 'node:assert/strict';
import {readFile, readdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import * as sdk from '../../packages/sdk/index.mjs';
import {openReadOpeningFixture, connectOpeningHost} from './client-read-opening.fixture.mjs';

const program = JSON.parse(await readFile(new URL('./fixtures/read-121.program.json', import.meta.url), 'utf8'));
const expected = JSON.parse(await readFile(new URL('./fixtures/read-121.expected.json', import.meta.url), 'utf8'));

export function assertSameResult(actual, original) {
  for (const key of ['run_definition_cid', 'result_name', 'result_manifest_cid',
    'result_artifact_cid', 'serialization_contract_cid']) {
    assert.equal(actual.attempt[key], original.attempt[key], key);
  }
}

export async function attemptBytes(directory) {
  const root = join(directory, 'publication/deliveries');
  const names = (await readdir(root)).filter(name => /^[0-9a-f]{64}$/u.test(name)).sort();
  return Promise.all(names.map(name => readFile(join(root, name, 'attempt.json'), 'utf8')));
}

function assertReadExplanation(failure, consumer, ref, endpoint, attemptId) {
  const count = consumer === 'rows' ? 120 : 0;
  const explanation = sdk.explainReadFailure(failure);
  assert.equal(explanation.rowsYielded, count, '[check-mutation:read-121-count]');
  const {cleanup, ...facts} = explanation;
  assert.ok(cleanup === undefined || cleanup === 'unknown');
  assert.deepEqual(facts, {
    observation: 'read_incomplete', attemptId, rowsYielded: count,
    summary: `This read stopped after returning ${count} rows.`,
    hint: 'Keep this read reference. Look it up before deciding whether to open a new read from the beginning.',
    next: {operation: 'deliveryAttempt', ref, resultName: 'answer', attemptId,
      lookupContext: {endpoint, scopeRef: 'principal'}},
  }, '[check-mutation:read-121-facts]');
  assert.equal(sdk.explainReadFailure({...failure}), undefined, '[check-mutation:read-121-custody]');
  for (const format of ['text', 'html', 'json']) {
    const output = sdk.formatReadFailure(failure, {format});
    assert.ok(output);
    assert.doesNotMatch(output, /InjectedPhysicalRowInterruption|fixture-token/);
    if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, explanation,
      '[check-mutation:read-121-format]');
  }
  failure.code = 'Succeeded'; failure.rowsYielded = 999; failure.attemptId = 'foreign-read';
  assert.deepEqual(sdk.explainReadFailure(failure), explanation, '[check-mutation:read-121-custody]');
  return explanation;
}

async function initialRead({directory, entrance, consumer}) {
  const fixture = await openReadOpeningFixture(directory, undefined,
    {valuesMaxRows: 121, expectedRowCount: 121,
      observeSubmission: (stage, error) => console.log('READ_121_SUBMISSION', entrance, stage,
        error === undefined ? '' : inspect(error, {depth: 8}))});
  const host = await connectOpeningHost(fixture, entrance, directory);
  let release, ref, submissionRef, attemptId, observed, originalPolicy, completeAttempt, failure, explanation;
  const yielded = new Promise(resolve => {release = resolve;});
  if (consumer === 'all') release();
  fixture.beforeRow(async index => {
    if (index !== 120) return;
    fixture.beforeRow(undefined);
    await yielded;
    throw new Error('InjectedPhysicalRowInterruption');
  });
  try {
    submissionRef = host.client.newSubmission({nonce: 'read-121-run'});
    const run = await host.client.start(program, {submissionRef});
    ref = run.ref;
    assert.equal((await run.status()).status, 'succeeded');
    assert.deepEqual((await host.client.lookupSubmission(submissionRef)).admission.ref, ref);
    const result = run.result('answer');
    const description = await result.describe();
    assert.deepEqual(description.columns, [{name: 'id', contract: {type: 'number', nullable: false}}]);
    const reader = consumer === 'rows' ? result.rows() : undefined;
    attemptId = reader?.attemptId;
    const seen = [];
    await assert.rejects(async () => {
      if (reader === undefined) seen.push(...await result.all());
      else for await (const row of reader) {
          seen.push(row);
          if (seen.length === 120) release();
        }
    }, error => {
      failure = error;
      if (reader === undefined) attemptId = error.attemptId;
      return typeof attemptId === 'string' && error.attemptId === attemptId &&
        error.rowsYielded === (consumer === 'rows' ? 120 : 0);
    });
    release(); await host.settled();
    assert.deepEqual(seen, consumer === 'rows' ? expected.slice(0, 120) : []);
    if (reader) {
      assert.equal(reader.rowsYielded(), 120);
      assert.equal(reader.state(), 'prefix');
    }
    observed = await result.deliveryAttempt(attemptId);
    assert.equal(observed.kind, 'found');
    assert.equal(observed.record.state, 'failed');
    assert.equal(observed.hostReleaseReceipt, null);
    const beforeExplanation = {...fixture.counts};
    explanation = assertReadExplanation(failure, consumer, ref, host.endpoint, attemptId);
    assert.deepEqual(fixture.counts, beforeExplanation, '[check-mutation:read-121-passive]');
    assert.equal((await run.status()).status, 'succeeded');
    const bytes = await attemptBytes(directory);
    assert.equal(bytes.length, 1);
    assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
    assert.deepEqual(await attemptBytes(directory), bytes);
    assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
    if (reader) await assert.rejects(Array.fromAsync(reader), {code: 'ReadAttemptAlreadyStarted'});
    fixture.authorize(false);
    await assert.rejects(Array.fromAsync(result.rows()));
    await host.settled();
    assert.deepEqual(fixture.counts, beforeExplanation);
    assert.deepEqual(await attemptBytes(directory), bytes);
    fixture.authorize(true);
    const fresh = result.rows();
    assert.notEqual(fresh.attemptId, attemptId);
    assert.deepEqual(await Array.fromAsync(fresh), expected);
    assert.equal(fresh.rowsYielded(), 121);
    assert.equal(fresh.state(), 'complete');
    assert.deepEqual(sdk.explainReadFailure(failure), explanation);
    assert.equal((await run.status()).status, 'succeeded');
    await host.settled();
    completeAttempt = await result.deliveryAttempt(fresh.attemptId);
    assertSameResult(completeAttempt, observed);
    assert.equal(completeAttempt.record.state, 'succeeded');
    assert.notEqual(completeAttempt.hostReleaseReceipt, null);
    assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
    assert.deepEqual(fixture.counts, {admissions: 2, readers: 2, computes: 1, definitions: 1});
    const admissions = await attemptBytes(directory);
    assert.equal(admissions.length, 2);
    for (const wire of admissions) {
      const attempt = JSON.parse(wire);
      const grant = await fixture.store.readPublicationContract(attempt.result_read_grant_cid, 'result_read_grant');
      assert.equal(JSON.parse(grant.wire).max_uses, 1);
      assert.equal(admissions.filter(value => JSON.parse(value).result_read_grant_cid === attempt.result_read_grant_cid).length, 1);
    }
    originalPolicy = fixture.retainedAdmission(ref).valuesHostPolicyOriginal;
    assert.deepEqual(JSON.parse(originalPolicy.wire), {max_rows: 121,
      name: 'source-free-values', version: 'actql-installed-local-policy/0.1'});
  } finally {release(); await host.close(); await fixture.close();}
  return {pid: process.pid, ref, submissionRef, attemptId, observed, originalPolicy,
    completeAttempt, explanation, counts: {...fixture.counts}};
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const facts = JSON.parse(process.argv[2]);
  const initial = await initialRead(facts);
  await writeFile(facts.output, JSON.stringify(initial));
  console.log('READ_121_INITIAL_PROCESS', JSON.stringify({pid: initial.pid,
    entrance: facts.entrance, consumer: facts.consumer, counts: initial.counts}));
}

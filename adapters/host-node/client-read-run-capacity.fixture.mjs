// The initial Host and execution Owner live only in this child process.
// The orchestrator waits for its exit before starting the restoration process.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import * as sdk from '../../packages/sdk/index.mjs';
import {openReadOpeningFixture, connectOpeningHost, traceReadRecovery} from './client-read-opening.fixture.mjs';

const program = JSON.parse(await readFile(new URL('./fixtures/read-121.program.json', import.meta.url), 'utf8'));
const expected = JSON.parse(await readFile(new URL('./fixtures/read-121.expected.json', import.meta.url), 'utf8'));

export function assertSameResult(actual, original) {
  for (const key of ['run_definition_cid', 'result_name', 'result_manifest_cid',
    'result_artifact_cid', 'serialization_contract_cid']) {
    assert.equal(actual.attempt[key], original.attempt[key], key);
  }
}

export async function attemptBytes(directory) {
  // Read every original attempt wire from its current native Store index.
  // A read-only open must fail if the index is absent; never create or fall
  // back to retired per-attempt files or to a public lookup projection.
  const database = new DatabaseSync(join(directory, 'publication', 'delivery-attempts.sqlite3'),
    {readOnly: true, allowExtension: false});
  try {
    return database.prepare('SELECT attempt_cid, attempt_wire FROM attempts ORDER BY attempt_cid').all()
      .map(row => {
        assert.match(row.attempt_cid, /^sha256:[0-9a-f]{64}$/u);
        assert.equal(typeof row.attempt_wire, 'string');
        return row.attempt_wire;
      });
  } finally {database.close();}
}

function readDiagnostics(failure) {
  // Return actual SDK observations; the named parent test owns assertions.
  const explanation = sdk.explainReadFailure(failure);
  const copiedExplanationAbsent = sdk.explainReadFailure({...failure}) === undefined;
  const formats = ['text', 'html', 'json'].map(format =>
    ({format, output: sdk.formatReadFailure(failure, {format})}));
  failure.code = 'Succeeded'; failure.rowsYielded = 999; failure.attemptId = 'foreign-read';
  return {explanation, copiedExplanationAbsent, formats,
    editedExplanation: sdk.explainReadFailure(failure)};
}

async function initialRead({directory, entrance, consumer}) {
  traceReadRecovery('initial-121-process:start', {entrance, consumer});
  const fixture = await openReadOpeningFixture(directory, undefined,
    {valuesMaxRows: 121, expectedRowCount: 121,
      observeSubmission: (stage, error) => console.log('READ_121_SUBMISSION', entrance, stage,
        error === undefined ? '' : inspect(error, {depth: 8}))});
  const host = await connectOpeningHost(fixture, entrance, directory);
  let release, ref, submissionRef, attemptId, observed, originalAdmission, failure, diagnostics;
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
    traceReadRecovery('result-description:finished', {entrance});
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
    traceReadRecovery('interrupted-read:finished', {entrance, consumer});
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
    diagnostics = readDiagnostics(failure);
    assert.deepEqual(fixture.counts, beforeExplanation, '[check-mutation:read-121-passive]');
    assert.equal((await run.status()).status, 'succeeded');
    const bytes = await attemptBytes(directory);
    assert.equal(bytes.length, 1);
    assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
    assert.deepEqual(await attemptBytes(directory), bytes);
    assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
    traceReadRecovery('interrupted-lookup:finished', {entrance});
    if (reader) await assert.rejects(Array.fromAsync(reader), {code: 'ReadAttemptAlreadyStarted'});
    fixture.authorize(false);
    await assert.rejects(Array.fromAsync(result.rows()));
    await host.settled();
    assert.deepEqual(fixture.counts, beforeExplanation);
    assert.deepEqual(await attemptBytes(directory), bytes);
    fixture.authorize(true);
    // Stop this Host/Owner after the interrupted attempt. The existing
    // restoration child owns the explicit new read and its durable receipt.
    diagnostics.finalExplanation = sdk.explainReadFailure(failure);
    assert.equal((await run.status()).status, 'succeeded');
    assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
    assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
    const admissions = await attemptBytes(directory);
    assert.equal(admissions.length, 1);
    for (const wire of admissions) {
      const attempt = JSON.parse(wire);
      const grant = await fixture.store.readPublicationContract(attempt.result_read_grant_cid, 'result_read_grant');
      assert.equal(JSON.parse(grant.wire).max_uses, 1);
      assert.equal(admissions.filter(value => JSON.parse(value).result_read_grant_cid === attempt.result_read_grant_cid).length, 1);
    }
    // The installed Values profile has a stable identity. The checked Plan
    // owns the original demand; no per-row-count replacement policy is issued.
    originalAdmission = fixture.retainedAdmission(ref);
    assert.deepEqual(Object.keys(originalAdmission).sort(),
      ['authorization', 'logicalPlanOriginal', 'prepared', 'submittedIntentCid']);
    assert.match(originalAdmission.submittedIntentCid, /^sha256:[0-9a-f]{64}$/u);
    const expectedPolicyCid = 'sha256:' + createHash('sha256').update(
      '{"version":"actql-installed-local-policy/0.1","name":"source-free-values"}').digest('hex');
    assert.equal(JSON.parse(originalAdmission.prepared).host_policy_cid, expectedPolicyCid);
    assert.equal(JSON.parse(originalAdmission.authorization).host_policy_cid, expectedPolicyCid);
    assert.deepEqual(Object.keys(originalAdmission.logicalPlanOriginal).sort(),
      ['compiledPlanWire', 'planViewWire']);
    for (const wire of Object.values(originalAdmission.logicalPlanOriginal)) {
      assert.equal(typeof wire, 'string'); assert.notEqual(wire, '');
    }
  } finally {
    traceReadRecovery('initial-121-close:start', {entrance});
    release(); await host.close(); await fixture.close();
    traceReadRecovery('initial-121-close:finished', {entrance});
  }
  return {pid: process.pid, ref, submissionRef, attemptId, observed, originalAdmission,
    endpoint: host.endpoint, diagnostics, counts: {...fixture.counts}};
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const facts = JSON.parse(process.argv[2]);
  const initial = await initialRead(facts);
  await writeFile(facts.output, JSON.stringify(initial));
  console.log('READ_121_INITIAL_PROCESS', JSON.stringify({pid: initial.pid,
    entrance: facts.entrance, consumer: facts.consumer, counts: initial.counts}));
}

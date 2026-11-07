import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {open} from '../../packages/node/index.mjs';
import {valuesHostPolicyOriginal} from './local-values-capacity.mjs';
import {openInstalledRemoteHttpHost as openPublicHttpHost} from '../../packages/local-node/http-host.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';

const expected = JSON.parse(await readFile(new URL('./fixtures/read-121.expected.json', import.meta.url), 'utf8'));
const fixture = fileURLToPath(new URL('./client-values-row-limit.fixture.mjs', import.meta.url));

async function invoke(directory, facts, phase) {
  try {
    const log = execFileSync(process.execPath, [fixture, JSON.stringify(facts)], {timeout: 20000, stdio: 'pipe', encoding: 'utf8'});
    await writeFile(join(directory, `${phase}.log`), log);
  } catch (error) {
    const log = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
    await writeFile(join(directory, `${phase}.log`), log);
    throw new Error(`${error.code ?? 'InstalledReadFailed'}: ${log}`, {cause: error});
  }
}

test('finite Values policy originals retain represented row budgets without a product ceiling', () => {
  for (const rows of [10001, 100000, 2147483647]) {
    const original = valuesHostPolicyOriginal(rows);
    assert.equal(Object.isFrozen(original), true);
    assert.equal(JSON.parse(original.wire).max_rows, rows);
  }
  for (const rows of [0, -1, 1.5, 2147483648, Infinity]) {
    assert.throws(() => valuesHostPolicyOriginal(rows), {message: 'InvalidLocalValuesRowLimit'});
  }
});

test('invalid explicit row configurations are refused before installing a Host', async () => {
  for (const valuesMaxRows of [null, 0, -1, 1.5, 2147483648, Number.MAX_SAFE_INTEGER, NaN, Infinity, '121']) {
    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {valuesMaxRows}}), {message: 'InvalidLocalValuesRowLimit'});
    await assert.rejects(openInstalledRemoteHttpHost({directory: '/unused',
      authenticate: () => 'principal', valuesMaxRows}), {message: 'InvalidLocalValuesRowLimit'});
  }
});

// This is policy configuration plus a real small Run, not a 100k-row workload.
for (const valuesMaxRows of [10001, 100000]) {
  test(`public open accepts explicit ${valuesMaxRows}-row policy through ordinary admission`, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-values-policy-',
      label: 'public Values policy configuration'});
    let client;
    try {
      client = await open({stateDir: scratch.path, installation: {valuesMaxRows}});
      const run = await client.start({version: 'actql/0.1', id: 'values-policy',
        stages: [{id: 'main', inputs: {}, steps: [{as: 'input', values: {
          schema: {id: {type: 'number', nullable: false}}, rows: [{id: 7}],
        }}], results: {rows: {from: 'input', fields: ['id']}}}],
        results: {answer: {from: {stage: 'main', result: 'rows'}}}});
      assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), [{id: 7}]);
    } finally {
      await client?.close();
    }
    scratch.passed();
  });
  test(`HTTP Host accepts explicit ${valuesMaxRows}-row policy at its public installation boundary`, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-http-values-policy-',
      label: 'HTTP Values policy configuration'});
    let host;
    try {
      host = await openPublicHttpHost({directory: scratch.path,
        authenticate: () => 'principal', valuesMaxRows});
      assert.equal(typeof host.handler, 'function');
    } finally {
      await host?.close();
    }
    scratch.passed();
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: installed 121-row Run keeps a 120-row prefix distinct from its original Delivery receipt across process restart`,
    {timeout: 40000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-installed-read-prefix-',
        label: `${entrance} installed interrupted read recovery`});
      const directory = scratch.path;
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
      const initialOutput = join(directory, 'initial.json');
      await invoke(directory, {directory, entrance, output: initialOutput, interruptAfterRows: 120}, 'initial');
      // The original Host and execution process have exited before recovery.
      const initial = JSON.parse(await readFile(initialOutput, 'utf8'));
      assert.notEqual(initial.pid, process.pid);
      assert.equal(initial.status.status, 'succeeded');
      assert.equal(initial.computes, 1);
      assert.deepEqual(initial.rows, expected.slice(0, 120));
      assert.equal(initial.rowsYielded, 120);
      assert.equal(initial.readState, 'prefix');
      assert.equal(initial.attempts.length, 1);
      assert.equal(initial.grants.length, 1);
      assert.equal(initial.grants[0].max_uses, 1);
      assert.deepEqual(JSON.parse(await readFile(join(directory, 'submission-ref.json'), 'utf8')),
        initial.submissionRef);
      const originalAttemptId = initial.attempt.attempt.attempt_id;
      const restoredOutput = join(directory, 'restored.json');
      await invoke(directory, {directory, entrance, output: restoredOutput, ref: initial.ref,
        submissionRef: initial.submissionRef, originalAttemptId}, 'restored');
      const restored = JSON.parse(await readFile(restoredOutput, 'utf8'));
      assert.notEqual(restored.pid, process.pid);
      assert.deepEqual(restored.ref, initial.ref);
      assert.deepEqual(restored.request.submissionRef, initial.submissionRef);
      assert.deepEqual(restored.request.admission.ref, initial.ref);
      assert.equal(restored.status.status, 'succeeded');
      assert.equal(restored.computes, 0);
      assert.deepEqual(restored.lookupBefore, initial.admissions);
      assert.deepEqual(restored.lookupAfter, restored.lookupBefore);
      assert.deepEqual(restored.originalFirst.attempt, initial.attempt.attempt);
      assert.deepEqual(restored.originalSecond, restored.originalFirst);
      assert.deepEqual(restored.originalAfterRead, restored.originalFirst);
      // The transport can finish before a consumer stops at row 120. Only the
      // Owner's durable record and receipt establish that Delivery's outcome;
      // the consumer's prefix is never upgraded to a complete read.
      assert.ok(['succeeded', 'failed', 'cancelled'].includes(restored.originalFirst.record.state));
      assert.equal(restored.originalFirst.hostReleaseReceipt !== null,
        restored.originalFirst.record.state === 'succeeded');
      assert.deepEqual(restored.rows, expected);
      assert.equal(restored.rowsYielded, 121);
      assert.equal(restored.readState, 'complete');
      assert.deepEqual(restored.description.columns, [{name: 'id', contract: {type: 'number', nullable: false}}]);
      assert.equal(restored.attempt.record.state, 'succeeded');
      assert.notEqual(restored.attempt.hostReleaseReceipt, null);
      assert.notEqual(restored.attempt.attempt.attempt_id, originalAttemptId);
      assert.notEqual(restored.attempt.attempt.result_read_grant_cid,
        initial.attempt.attempt.result_read_grant_cid);
      for (const key of ['run_definition_cid', 'result_name', 'result_manifest_cid',
        'result_artifact_cid', 'serialization_contract_cid']) {
        assert.equal(restored.attempt.attempt[key], initial.attempt.attempt[key], key);
      }
      assert.equal(restored.attempts.length, 2);
      assert.ok(restored.attempts.includes(initial.attempts[0]));
      assert.equal(new Set(restored.grants.map(grant => grant.result_read_grant_cid)).size, 2);
      for (const grant of restored.grants) assert.equal(grant.max_uses, 1);
      // These are the Store's independently persisted original START/grant
      // records, not inferred counts from rows(), deliveryAttempt() or SDK I/O.
      // Lookup alone leaves both issuance wires and consumed grant uses exact.
      for (const observed of [initial, restored]) {
        assert.equal(observed.admissions.length, observed.attempts.length);
        for (const admission of observed.admissions) {
          const attempt = JSON.parse(admission.attempt_wire);
          const grant = JSON.parse(admission.grant_wire);
          assert.equal(admission.run_cid, initial.ref.runDefinitionCid);
          assert.equal(admission.attempt_cid, attempt.delivery_attempt_cid);
          assert.equal(admission.grant_cid, attempt.result_read_grant_cid);
          assert.equal(admission.grant_cid, grant.result_read_grant_cid);
          assert.equal(admission.ready, 1);
          assert.match(admission.initial_cid, /^sha256:[0-9a-f]{64}$/u);
          assert.equal(admission.uses, 1);
        }
      }
      console.log('INSTALLED_READ_PREFIX_EVIDENCE', JSON.stringify({directory, entrance,
        ref: initial.ref, originalAttemptId, prefixRows: initial.rowsYielded,
        originalOwnerState: restored.originalFirst.record.state,
        originalOwnerReceipt: restored.originalFirst.hostReleaseReceipt,
        newAttemptId: restored.attempt.attempt.attempt_id, rows: restored.rowsYielded,
        initialProcess: {pid: initial.pid, exitCode: 0}, restoredProcess: {pid: restored.pid, exitCode: 0},
        initialComputes: initial.computes, restoredComputes: restored.computes}));
      scratch.passed();
    });

  test(`${entrance}: installed explicit row capacity publishes 121 rows and restores the original Run under current defaults`,
    {timeout: 40000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-installed-read-121-', label: `${entrance} installed row capacity`});
      const directory = scratch.path;
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
      const output = join(directory, 'initial.json');
      await invoke(directory, {directory, entrance, output}, 'initial');
      const initial = JSON.parse(await readFile(output, 'utf8'));
      assert.equal(initial.status.status, 'succeeded');
      assert.equal(initial.computes, 1);
      assert.deepEqual(initial.rows, expected);
      assert.equal(initial.readState, 'complete');
      assert.equal(initial.attempt.record.state, 'succeeded');
      assert.notEqual(initial.attempt.hostReleaseReceipt, null);
      assert.deepEqual(initial.description.columns, [{name: 'id', contract: {type: 'number', nullable: false}}]);
      const restoredOutput = join(directory, 'restored.json');
      await invoke(directory, {directory, entrance,
        output: restoredOutput, ref: initial.ref, submissionRef: initial.submissionRef}, 'restored');
      const restored = JSON.parse(await readFile(restoredOutput, 'utf8'));
      assert.deepEqual(restored.ref, initial.ref);
      assert.deepEqual(restored.request.admission.ref, initial.ref);
      assert.deepEqual(restored.request.submissionRef, initial.submissionRef);
      assert.equal(restored.status.status, 'succeeded');
      assert.equal(restored.computes, 0);
      assert.deepEqual(restored.rows, expected);
      assert.equal(restored.readState, 'complete');
      assert.notEqual(restored.attempt.attempt.attempt_id, initial.attempt.attempt.attempt_id);
      assert.equal(restored.attempt.record.state, 'succeeded');
      assert.notEqual(restored.attempt.hostReleaseReceipt, null);
      console.log('INSTALLED_READ_121_EVIDENCE', JSON.stringify({directory, entrance,
        ref: initial.ref, rows: expected.length, initialComputes: initial.computes,
        restoredComputes: restored.computes}));
      scratch.passed();
    });
}

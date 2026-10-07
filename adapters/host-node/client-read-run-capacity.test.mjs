import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost} from './client-read-opening.fixture.mjs';

const program = JSON.parse(await readFile(new URL('./fixtures/read-121.program.json', import.meta.url), 'utf8'));
const expected = JSON.parse(await readFile(new URL('./fixtures/read-121.expected.json', import.meta.url), 'utf8'));

function assertSameResult(actual, original) {
  for (const key of ['run_definition_cid', 'result_name', 'result_manifest_cid',
    'result_artifact_cid', 'serialization_contract_cid']) {
    assert.equal(actual.attempt[key], original.attempt[key], key);
  }
}

async function attemptBytes(directory) {
  const root = join(directory, 'publication/deliveries');
  const names = (await readdir(root)).filter(name => /^[0-9a-f]{64}$/u.test(name)).sort();
  return Promise.all(names.map(name => readFile(join(root, name, 'attempt.json'), 'utf8')));
}

for (const entrance of ['local', 'https']) {
  for (const consumer of ['rows', 'all']) {
    test(`${entrance}: actual 121-row Run preserves its interrupted ${consumer} attempt and permits an explicit new read after restart`,
      {timeout: 30000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-read-121-', label: `${entrance} actual 121-row Run`});
        const directory = scratch.path;
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
        const fixture = await openReadOpeningFixture(directory, undefined,
          {valuesMaxRows: 121, expectedRowCount: 121,
            observeSubmission: (stage, error) => console.log('READ_121_SUBMISSION', entrance, stage,
              error === undefined ? '' : inspect(error, {depth: 8}))});
        const host = await connectOpeningHost(fixture, entrance, directory);
        let release, ref, attemptId, observed, originalPolicy, completeAttempt;
        const yielded = new Promise(resolve => {release = resolve;});
        if (consumer === 'all') release();
        fixture.beforeRow(async index => {
          if (index !== 120) return;
          fixture.beforeRow(undefined);
          await yielded;
          throw new Error('InjectedPhysicalRowInterruption');
        });
        try {
          const run = await host.client.start(program, {requestId: 'read-121-run'});
          ref = run.ref;
          assert.equal((await run.status()).status, 'succeeded');
          assert.deepEqual((await host.client.lookupRequest('read-121-run')).ref, ref);
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
          const bytes = await attemptBytes(directory);
          assert.equal(bytes.length, 1);
          assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
          assert.deepEqual(await attemptBytes(directory), bytes);
          assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
          if (reader) await assert.rejects(Array.fromAsync(reader), {code: 'ReadAttemptAlreadyStarted'});
          const fresh = result.rows();
          assert.notEqual(fresh.attemptId, attemptId);
          assert.deepEqual(await Array.fromAsync(fresh), expected);
          assert.equal(fresh.rowsYielded(), 121);
          assert.equal(fresh.state(), 'complete');
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
        const beforeRestart = await attemptBytes(directory);
        const output = join(directory, 'restart.json');
        // The new process restores the original Run under the default current
        // profile. Lookup never recompiles it or replaces its original ceiling.
        try {
          const log = execFileSync(process.execPath, [fileURLToPath(new URL('./client-read-opening-restart.fixture.mjs', import.meta.url)),
            JSON.stringify({directory, entrance, ref, attemptId, output,
              requestId: 'read-121-run', newRead: true})], {timeout: 15000, stdio: 'pipe', encoding: 'utf8'});
          await writeFile(join(directory, 'restart.log'), log);
        } catch (error) {
          const log = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
          await writeFile(join(directory, 'restart.log'), log);
          throw new Error(`${error.code ?? 'RestoredReadFailed'}: ${log}`, {cause: error});
        }
        const restored = JSON.parse(await readFile(output, 'utf8'));
        assert.deepEqual(restored.ref, ref);
        assert.equal(restored.status, 'succeeded');
        assert.deepEqual(restored.request.ref, ref);
        assert.deepEqual(restored.first, observed);
        assert.deepEqual(restored.second, observed);
        assert.deepEqual(restored.valuesHostPolicyOriginal, originalPolicy);
        assert.deepEqual(restored.lookupCounts, {admissions: 0, readers: 0, computes: 0, definitions: 0});
        assert.deepEqual(restored.rows, expected);
        assert.notEqual(restored.readAttempt.attempt.attempt_id, attemptId);
        assert.notEqual(restored.readAttempt.attempt.attempt_id, completeAttempt.attempt.attempt_id);
        assertSameResult(restored.readAttempt, observed);
        assert.equal(restored.readAttempt.record.state, 'succeeded');
        assert.notEqual(restored.readAttempt.hostReleaseReceipt, null);
        assert.deepEqual(restored.counts, {admissions: 1, readers: 1, computes: 0, definitions: 0});
        const afterRestart = await attemptBytes(directory);
        for (const original of beforeRestart) assert(afterRestart.includes(original));
        assert.equal(afterRestart.length, 3);
        console.log('READ_121_EVIDENCE', JSON.stringify({directory, entrance, consumer, ref,
          attemptId, originalState: observed.record.state, originalPolicy,
          restoredAttemptId: restored.readAttempt.attempt.attempt_id,
          restartCounts: restored.counts, rows: restored.rows.length}));
        scratch.passed();
      });
  }
}

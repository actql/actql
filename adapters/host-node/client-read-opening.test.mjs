import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram, openingExpected} from './client-read-opening.fixture.mjs';

async function attempts(directory) {
  const root = join(directory, 'publication', 'deliveries');
  const names = (await readdir(root)).filter(name => /^[0-9a-f]{64}$/u.test(name)).sort();
  return Promise.all(names.map(async name => ({name, wire: await readFile(join(root, name, 'attempt.json'), 'utf8')})));
}

for (const entrance of ['local', 'https']) {
  for (const phase of ['before-commit', 'after-commit']) {
    test(`${entrance}: opening reply lost ${phase} is looked up without reopening or consuming another grant`, {timeout: 20000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-read-opening-', label: `${entrance} ${phase}`});
      const directory = scratch.path;
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
      const fixture = await openReadOpeningFixture(directory);
      const host = await connectOpeningHost(fixture, entrance, directory);
      let ref, attemptId, observed;
      try {
        // Publish the unmodified normal Program through the public submit path.
        const run = await host.client.start(openingProgram, {requestId: 'opening-run'});
        ref = run.ref;
        assert.equal((await run.status()).status, 'succeeded');
        const result = run.result('answer');
        const baseline = result.rows();
        assert.deepEqual(await Array.fromAsync(baseline), openingExpected);
        await host.settled();
        const completed = await result.deliveryAttempt(baseline.attemptId);
        assert.equal(completed.kind, 'found');
        assert.equal(completed.record.state, 'succeeded');
        assert.notEqual(completed.hostReleaseReceipt, null);
        assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
        fixture.arm(phase);
        const reader = result.rows();
        attemptId = reader.attemptId;
        const returned = [];
        await assert.rejects(async () => {for await (const row of reader) returned.push(row);},
          error => error.attemptId === attemptId && error.rowsYielded === 0);
        await host.settled();
        assert.deepEqual(returned, []);
        assert.equal(reader.state(), 'open_unknown');
        assert.equal(reader.rowsYielded(), 0);
        await assert.rejects(Array.fromAsync(reader), {code: 'ReadAttemptAlreadyStarted'});
        const retained = await attempts(directory);
        assert.equal(retained.length, phase === 'after-commit' ? 2 : 1);
        const original = retained.map(entry => JSON.parse(entry.wire)).filter(value => value.attempt_id === attemptId);
        assert.equal(original.length, phase === 'after-commit' ? 1 : 0);
        observed = await result.deliveryAttempt(attemptId);
        if (phase === 'after-commit') {
          assert.equal(observed.kind, 'found');
          assert.equal(observed.attempt.attempt_id, attemptId);
          assert.equal(observed.attempt.run_definition_cid, ref.runDefinitionCid);
          assert.equal(observed.attempt.result_name, 'answer');
          assert.equal(observed.record, null);
          assert.equal(observed.hostReleaseReceipt, null);
          assert.deepEqual(observed.attempt, original[0]);
          const grant = await fixture.store.readPublicationContract(
            original[0].result_read_grant_cid, 'result_read_grant');
          assert.equal(JSON.parse(grant.wire).max_uses, 1);
          assert.equal(retained.filter(entry => JSON.parse(entry.wire).result_read_grant_cid ===
            original[0].result_read_grant_cid).length, 1);
        } else {
          // Absence is not an authoritative proof that the operation never ran.
          assert.deepEqual(observed, {kind: 'not_found'});
          assert.equal(reader.state(), 'open_unknown');
        }
        assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
        assert.deepEqual(await result.deliveryAttempt('different-original-attempt'), {kind: 'not_found'});
        fixture.authorize(false);
        await assert.rejects(result.deliveryAttempt(attemptId));
        fixture.authorize(true);
        assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
        assert.deepEqual(await attempts(directory), retained);
        assert.deepEqual(fixture.counts, {admissions: 2, readers: 1, computes: 1, definitions: 1});
        assert.equal((await run.status()).status, 'succeeded');
      } finally {
        await host.close(); await fixture.close();
      }
      const beforeRestart = await attempts(directory);
      const output = join(directory, 'restart.json');
      execFileSync(process.execPath, [fileURLToPath(new URL('./client-read-opening-restart.fixture.mjs', import.meta.url)),
        JSON.stringify({directory, entrance, ref, attemptId, output})], {timeout: 15000, stdio: 'pipe'});
      const restored = JSON.parse(await readFile(output, 'utf8'));
      assert.deepEqual(restored.ref, ref);
      assert.equal(restored.status, 'succeeded');
      assert.deepEqual(restored.first, observed);
      assert.deepEqual(restored.second, observed);
      assert.deepEqual(restored.counts, {admissions: 0, readers: 0, computes: 0, definitions: 0});
      assert.deepEqual(await attempts(directory), beforeRestart);
      console.log('READ_OPENING_EVIDENCE', JSON.stringify({entrance, phase, ref, attemptId,
        lookup: observed.kind, attemptCid: observed.attempt?.delivery_attempt_cid,
        grantCid: observed.attempt?.result_read_grant_cid,
        retainedAttempts: beforeRestart.length, restartCounts: restored.counts}));
      scratch.passed();
    });
  }
}

import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram, openingExpected, traceReadRecovery} from './client-read-opening.fixture.mjs';

async function attempts(directory) {
  // Observe the actual durable START metadata independently of the SDK lookup.
  // A read-only open cannot invent an absent database; inspect every attempt,
  // without filtering pending states or falling back to obsolete alias files.
  const database = new DatabaseSync(join(directory, 'publication', 'delivery-attempts.sqlite3'),
    {readOnly: true, allowExtension: false});
  try {
    return database.prepare('SELECT attempt_cid, attempt_wire FROM attempts ORDER BY attempt_cid').all()
      .map(row => {
        assert.match(row.attempt_cid, /^sha256:[0-9a-f]{64}$/u);
        return {name: row.attempt_cid.slice('sha256:'.length), wire: row.attempt_wire};
      });
  } finally {database.close();}
}

for (const entrance of ['local', 'https']) {
  for (const phase of ['before-commit', 'after-commit']) {
    test(`${entrance}: opening reply lost ${phase} is looked up without reopening or consuming another grant`, {timeout: 20000}, async () => {
      traceReadRecovery('opening-case:start', {entrance, loss: phase});
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-read-opening-', label: `${entrance} ${phase}`});
      const directory = scratch.path;
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
      traceReadRecovery('certificate:finished', {entrance});
      const fixture = await openReadOpeningFixture(directory);
      const host = await connectOpeningHost(fixture, entrance, directory);
      traceReadRecovery('connection:finished', {entrance});
      let ref, attemptId, observed;
      try {
        // Publish the unmodified normal Program through the public submit path.
        const run = await host.client.start(openingProgram,
          {submissionRef: host.client.newSubmission({nonce: 'opening-run'})});
        traceReadRecovery('submission:finished', {entrance});
        ref = run.ref;
        assert.equal((await run.status()).status, 'succeeded');
        const result = run.result('answer');
        const baseline = result.rows();
        assert.deepEqual(await Array.fromAsync(baseline), openingExpected);
        traceReadRecovery('baseline-read:finished', {entrance});
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
        let openingFailure;
        try {for await (const row of reader) returned.push(row);}
        catch (cause) {openingFailure = cause;}
        traceReadRecovery('lost-read:finished', {entrance, loss: phase});
        await host.settled();
        const retained = await attempts(directory);
        const expectedAttempts = phase === 'after-commit' ? 2 : 1;
        // Read persisted attempts independently before interpreting the SDK
        // failure. A lost admission reply cannot authorize a new read identity.
        await writeFile(join(directory, 'opening-custody-observation.json'),
          JSON.stringify({entrance, phase, expectedAttempts,
            retainedAttempts: retained.map(entry => JSON.parse(entry.wire)),
            counts: fixture.counts, returnedRows: returned.length,
            openingFailure: openingFailure?.code}), {mode: 0o600});
        assert.equal(retained.length, expectedAttempts, '[check-mutation:read-opening-no-retry]');
        assert.deepEqual(fixture.counts, {admissions: 2, readers: 1, computes: 1, definitions: 1},
          '[check-mutation:read-opening-no-retry]');
        assert.equal(openingFailure?.attemptId, attemptId);
        assert.equal(openingFailure.rowsYielded, 0);
        assert.deepEqual(returned, []);
        assert.equal(reader.state(), 'open_unknown');
        assert.equal(reader.rowsYielded(), 0);
        await assert.rejects(Array.fromAsync(reader), {code: 'ReadAttemptAlreadyStarted'});

        const original = retained.map(entry => JSON.parse(entry.wire)).filter(value => value.attempt_id === attemptId);
        assert.equal(original.length, phase === 'after-commit' ? 1 : 0);
        observed = await result.deliveryAttempt(attemptId);
        if (phase === 'after-commit') {
          assert.equal(observed.kind, 'found');
          assert.equal(observed.attempt.attempt_id, attemptId);
          assert.equal(observed.attempt.run_definition_cid, ref.runDefinitionCid);
          assert.equal(observed.attempt.result_name, 'answer');
          // START committed its original streaming record atomically even
          // though its reply was lost. This is not terminal completion or ACK.
          assert.equal(observed.record.state, 'streaming');
          assert.equal(observed.record.sequence, 0);
          assert.equal(observed.record.delivery_attempt_cid,
            observed.attempt.delivery_attempt_cid);
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
        traceReadRecovery('original-lookup:finished', {entrance});
      } finally {
        traceReadRecovery('original-close:start', {entrance});
        await host.close(); await fixture.close();
        traceReadRecovery('original-close:finished', {entrance});
      }
      const beforeRestart = await attempts(directory);
      const output = join(directory, 'restart.json');
      traceReadRecovery('restore-process:start', {entrance});
      execFileSync(process.execPath, [fileURLToPath(new URL('./client-read-opening-restart.fixture.mjs', import.meta.url)),
        JSON.stringify({directory, entrance, ref, attemptId, output})], {timeout: 15000, stdio: 'pipe'});
      traceReadRecovery('restore-process:finished', {entrance});
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

// The same actual published Program and physical Store exercise receipt
// durability. These two-row cases do not establish the later 121-row Run.
for (const entrance of ['local', 'https']) {
  for (const completion of ['commit', 'fail']) {
    test(`${entrance}: published Run read waits for durable receipt record (${completion})`,
      {timeout: 20000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(),
          prefix: 'actql-read-completion-', label: `${entrance} ${completion}`});
        const directory = scratch.path;
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
        {cwd: directory, stdio: 'ignore'});
        const fixture = await openReadOpeningFixture(directory);
        const host = await connectOpeningHost(fixture, entrance, directory);
        let entered, release, ref, attemptId, observed;
        let recordUnavailable = completion === 'fail';
        let pendingRecordState, closeRetryConfirmed = false;
        const reached = new Promise(resolve => {entered = resolve;});
        const gate = new Promise(resolve => {release = resolve;});
        fixture.beforeSuccessRecord(async () => {
          entered(); await gate;
          if (recordUnavailable) throw new Error('InjectedReceiptRecordFailure');
        });
        try {
          const run = await host.client.start(openingProgram,
            {submissionRef: host.client.newSubmission({nonce: 'completion-run'})});
          ref = run.ref;
          assert.equal((await run.status()).status, 'succeeded');
          const result = run.result('answer');
          const reader = result.rows();
          attemptId = reader.attemptId;
          const iterator = reader[Symbol.asyncIterator]();
          try {
            assert.deepEqual(await iterator.next(), {done: false, value: {id: 1}});
            assert.deepEqual(await iterator.next(), {done: false, value: {id: 2}});
            await reached;
            const pending = await result.deliveryAttempt(attemptId);
            assert.equal(pending.kind, 'found');
            assert.equal(pending.record.state, 'streaming');
            assert.equal(pending.hostReleaseReceipt, null);
            assert.equal(reader.state(), 'prefix');
            const final = iterator.next();
            release();
            if (completion === 'commit') {
              assert.deepEqual(await final, {done: true, value: undefined});
              assert.equal(reader.state(), 'complete');
            } else {
              await assert.rejects(final, error => error.attemptId === attemptId && error.rowsYielded === 2);
              assert.equal(reader.state(), 'prefix');
            }
          } finally {release(); await iterator.return();}
          await host.settled();
          observed = await result.deliveryAttempt(attemptId);
          assert.equal(observed.record.state, completion === 'commit' ? 'succeeded' : 'streaming');
          assert.equal(observed.hostReleaseReceipt === null, completion === 'fail');
          assert.deepEqual(await result.deliveryAttempt(attemptId), observed);
          assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
          assert.equal((await attempts(directory)).length, 1);
          assert.equal((await run.status()).status, 'succeeded');
          if (completion === 'fail' && entrance === 'local') {
            pendingRecordState = observed.record.state;
            const originalAttempt = observed.attempt;
            const beforeRetry = {...fixture.counts};
            const admitted = await attempts(directory);
            // The Local response retains the exact delivery-record retry owner.
            // A sealed Client cannot release it while the write remains blocked.
            await assert.rejects(host.close(), error => {
              assert.equal(error.code, 'ClientCleanupPending');
              assert.equal(error.cleanupPending, true);
              assert.equal(error.cleanupHandle, undefined);
              return true;
            });
            assert.equal(reader.state(), 'prefix');
            assert.deepEqual(fixture.counts, beforeRetry);
            assert.deepEqual(await attempts(directory), admitted);
            recordUnavailable = false;
            await host.close();
            // Retry persisted the retained terminal record. It did not reopen
            // a payload, consume another grant or retroactively finish reader.
            assert.equal(reader.state(), 'prefix');
            assert.deepEqual(fixture.counts, beforeRetry);
            assert.deepEqual(await attempts(directory), admitted);
            const observer = await connectOpeningHost(fixture, entrance, directory);
            try {
              const restoredRun = await observer.client.attach(ref);
              observed = await restoredRun.result('answer').deliveryAttempt(attemptId);
              assert.deepEqual(observed.attempt, originalAttempt);
              assert.equal(observed.record.state, 'succeeded');
              assert.notEqual(observed.hostReleaseReceipt, null);
              assert.deepEqual(fixture.counts, beforeRetry);
              closeRetryConfirmed = true;
            } finally {await observer.close();}
          }
        } finally {
          release(); recordUnavailable = false;
          await host.close(); await fixture.close();
        }
        const output = join(directory, 'restart.json');
        execFileSync(process.execPath, [fileURLToPath(new URL('./client-read-opening-restart.fixture.mjs', import.meta.url)),
          JSON.stringify({directory, entrance, ref, attemptId, output})], {timeout: 15000, stdio: 'pipe'});
        const restored = JSON.parse(await readFile(output, 'utf8'));
        assert.deepEqual(restored.ref, ref);
        assert.equal(restored.status, 'succeeded');
        assert.deepEqual(restored.first, observed);
        assert.deepEqual(restored.second, observed);
        assert.deepEqual(restored.counts, {admissions: 0, readers: 0, computes: 0, definitions: 0});
        assert.equal((await attempts(directory)).length, 1);
        console.log('READ_COMPLETION_EVIDENCE', JSON.stringify({entrance, completion, ref, attemptId,
          recordState: observed.record.state, receiptCid: observed.hostReleaseReceipt?.result_delivery_receipt_cid,
          pendingRecordState, closeRetryConfirmed, restartCounts: restored.counts}));
        scratch.passed();
      });
  }
}

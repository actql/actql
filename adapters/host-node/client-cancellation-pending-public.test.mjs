import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const fixture = fileURLToPath(new URL('./client-cancellation-public.fixture.mjs', import.meta.url));
async function invoke(directory, facts, phase) {
  try {
    const log = execFileSync(process.execPath, [fixture, JSON.stringify(facts)],
      {timeout: 20000, stdio: 'pipe', encoding: 'utf8'});
    await writeFile(join(directory, `${phase}.log`), log);
  } catch (error) {
    const log = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
    await writeFile(join(directory, `${phase}.log`), log);
    throw new Error(`InstalledPendingCancellationFailed: ${log}`, {cause: error});
  }
}

for (const entrance of ['local', 'https']) {
  for (const loss of ['before-commit', 'after-commit']) {
    test(`${entrance}: pending cancellation ${loss} reply loss retains original identity before stop and after restart`,
      {timeout: 40000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(),
          prefix: 'actql-pending-cancel-', label: `${entrance} pending cancellation ${loss}`});
        const directory = scratch.path;
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
        const initialOutput = join(directory, 'initial.json');
        await invoke(directory, {directory, entrance, loss, output: initialOutput,
          phase: 'initial', boundary: 'physical-start'}, 'initial');
        const initial = JSON.parse(await readFile(initialOutput, 'utf8'));
        const committed = loss === 'after-commit';
        assert.equal(initial.status.status, 'running');
        assert.equal(initial.status.result_available, false);
        assert.equal(initial.status.control.physical_stop, 'unknown');
        assert.deepEqual(initial.failure, {code: 'CancellationUnknown', cancelRef: initial.cancelRef});
        assert.deepEqual(initial.explanation, {
          observation: 'outcome_unknown',
          summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
          next: {operation: 'lookupCancellation', cancelRef: initial.cancelRef},
        });
        assert.deepEqual(initial.afterCancellationBeforeStop.control, {
          revision: initial.cancelRef.expectedRevision + (committed ? 1 : 0),
          cancellation_requested: committed, physical_stop: 'unknown'},
        '[check-mutation:cancel-pending-public-stop]');
        const expected = committed ? {kind: 'found', cancellation: {
          ref: initial.ref, cancelRef: initial.cancelRef, kind: 'accepted',
          revision: initial.cancelRef.expectedRevision + 1}} : {kind: 'unknown', cancelRef: initial.cancelRef};
        assert.deepEqual(initial.originalLookup, expected);
        assert.equal(initial.stopped.status, committed ? 'cancelled' : 'succeeded');
        assert.equal(initial.stopped.control.physical_stop, 'confirmed');
        assert.equal(initial.computes, committed ? 0 : 1);
        assert.equal(initial.snapshot.issued, 1);
        assert.equal(initial.snapshot.operations.length, 1);
        assert.equal(initial.snapshot.requests[0].cancellation_requested, committed ? 1 : 0);
        assert.equal(initial.snapshot.requests[0].observed_terminal_outcome, committed ? 'cancelled' : null);
        assert.equal(initial.snapshot.operations[0].outcome_wire === null, !committed);
        if (committed) assert.deepEqual(JSON.parse(initial.snapshot.operations[0].outcome_wire), expected.cancellation);
        const restoredOutput = join(directory, 'restored.json');
        await invoke(directory, {directory, entrance, output: restoredOutput, phase: 'restored',
          boundary: 'physical-start', cancelRef: initial.cancelRef,
          submissionRef: initial.submissionRef}, 'restored');
        const restored = JSON.parse(await readFile(restoredOutput, 'utf8'));
        assert.deepEqual(restored.lookup, expected);
        assert.deepEqual(restored.repeated, expected);
        assert.deepEqual(restored.snapshot, initial.snapshot);
        assert.equal(restored.computes, 0);
        assert.equal(restored.status.status, initial.stopped.status);
        assert.equal(restored.copiedExplanationAbsent, true);
        const view = committed ? {
          observation: 'accepted', revision: initial.cancelRef.expectedRevision + 1,
          summary: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.',
          next: {operation: 'status', ref: initial.ref},
        } : initial.explanation;
        assert.deepEqual(restored.explanation, view, '[check-mutation:cancel-pending-public-explanation]');
        for (const format of ['text', 'html', 'json']) {
          assert.ok(restored.formats[format]);
          assert.doesNotMatch(restored.formats[format], /fixture-token|CANCELLATION_FINAL_COMMIT_REPLY_LOST|edited-after-lookup/);
          if (format === 'json') assert.deepEqual(JSON.parse(restored.formats.json).explanation, view);
        }
        console.log('PENDING_CANCELLATION_PUBLIC_EVIDENCE', JSON.stringify({entrance, loss,
          ref: initial.ref, cancelRef: initial.cancelRef,
          beforeStop: initial.afterCancellationBeforeStop.control, afterStop: initial.stopped.control,
          acceptedLookup: expected.kind, originalComputes: initial.computes, restoredComputes: 0}));
        scratch.passed();
      });
  }
}

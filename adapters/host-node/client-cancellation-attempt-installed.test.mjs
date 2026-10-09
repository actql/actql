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
    await writeFile(join(directory, `${phase}.log`), `${error.stdout ?? ''}\n${error.stderr ?? ''}`);
    throw error;
  }
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: installed typed cancellation facts survive a different Host process without recancelling`,
    {timeout: 40000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-installed-cancel-attempt-',
        label: `${entrance} typed cancellation and original lookup`});
      const directory = scratch.path;
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
      const initialOutput = join(directory, 'initial.json');
      await invoke(directory, {directory, entrance, phase: 'typed-initial',
        boundary: 'physical-start', output: initialOutput}, 'initial');
      // execFileSync has observed the first Host process exit. The next child
      // only looks up the original submission and cancellation and attaches.
      const initial = JSON.parse(await readFile(initialOutput, 'utf8'));
      assert.equal(initial.conflict.kind, 'conflict');
      assert.equal(initial.accepted.kind, 'accepted');
      assert.equal(initial.already.kind, 'already_satisfied');
      assert.equal(initial.stopped.status, 'cancelled');
      assert.equal(initial.stopped.control.physical_stop, 'confirmed');
      assert.equal(initial.snapshot.issued, 2);
      assert.equal(initial.snapshot.operations.length, 2);
      assert.equal(initial.computes, 0);
      const restoredOutput = join(directory, 'restored.json');
      await invoke(directory, {directory, entrance, phase: 'restored', output: restoredOutput,
        cancelRef: initial.cancelRef, submissionRef: initial.submissionRef}, 'restored');
      const restored = JSON.parse(await readFile(restoredOutput, 'utf8'));
      assert.deepEqual(restored.ref, initial.ref);
      assert.deepEqual(restored.request.submissionRef, initial.submissionRef);
      assert.deepEqual(restored.lookup, {kind: 'found', cancellation: initial.accepted.cancellation});
      assert.deepEqual(restored.repeated, initial.originalLookup);
      assert.deepEqual(restored.snapshot, initial.snapshot);
      assert.equal(restored.computes, 0);
      assert.equal(restored.status.status, 'cancelled');
      console.log('INSTALLED_CANCELLATION_ATTEMPT_EVIDENCE', JSON.stringify({directory, entrance,
        ref: initial.ref, cancelRef: initial.cancelRef, acceptedAttempt: initial.accepted.attemptRef,
        issued: 2, initialComputes: 0, restoredComputes: 0}));
      scratch.passed();
    });
}

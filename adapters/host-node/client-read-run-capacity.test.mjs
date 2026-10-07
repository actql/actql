import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {assertSameResult, attemptBytes} from './client-read-run-capacity.fixture.mjs';

const expected = JSON.parse(await readFile(new URL('./fixtures/read-121.expected.json', import.meta.url), 'utf8'));

for (const entrance of ['local', 'https']) {
  for (const consumer of ['rows', 'all']) {
    test(`${entrance}: actual 121-row Run preserves its interrupted ${consumer} attempt and permits an explicit new read after restart`,
      {timeout: 30000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-read-121-', label: `${entrance} actual 121-row Run`});
        const directory = scratch.path;
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
        const initialOutput = join(directory, 'initial.json');
        try {
          const log = execFileSync(process.execPath, [fileURLToPath(new URL('./client-read-run-capacity.fixture.mjs', import.meta.url)),
            JSON.stringify({directory, entrance, consumer, output: initialOutput})],
          {timeout: 15000, stdio: 'pipe', encoding: 'utf8'});
          await writeFile(join(directory, 'initial.log'), log);
        } catch (error) {
          const log = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
          await writeFile(join(directory, 'initial.log'), log);
          throw new Error(`${error.code ?? 'InitialReadFailed'}: ${log}`, {cause: error});
        }
        // execFileSync returned only after the initial Host/Owner process exited.
        const initial = JSON.parse(await readFile(initialOutput, 'utf8'));
        assert.notEqual(initial.pid, process.pid);
        assert.deepEqual(initial.counts, {admissions: 2, readers: 2, computes: 1, definitions: 1});
        const {ref, submissionRef, attemptId, observed, originalPolicy, completeAttempt, explanation} = initial;
        const beforeRestart = await attemptBytes(directory);
        const output = join(directory, 'restart.json');
        // The new process restores the original Run under the default current
        // profile. Lookup never recompiles it or replaces its original ceiling.
        try {
          const log = execFileSync(process.execPath, [fileURLToPath(new URL('./client-read-opening-restart.fixture.mjs', import.meta.url)),
            JSON.stringify({directory, entrance, ref, attemptId, output,
              submissionRef, newRead: true})], {timeout: 15000, stdio: 'pipe', encoding: 'utf8'});
          await writeFile(join(directory, 'restart.log'), log);
        } catch (error) {
          const log = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
          await writeFile(join(directory, 'restart.log'), log);
          throw new Error(`${error.code ?? 'RestoredReadFailed'}: ${log}`, {cause: error});
        }
        const restored = JSON.parse(await readFile(output, 'utf8'));
        assert.notEqual(restored.pid, process.pid);
        // A terminated child PID may be reused; completed invocations, not PID
        // inequality between children, establish the process restart boundary.
        assert.deepEqual(restored.ref, ref);
        assert.equal(restored.status, 'succeeded');
        assert.deepEqual(restored.request.admission.ref, ref);
        assert.deepEqual(restored.request.submissionRef, submissionRef);
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
          initialProcess: {pid: initial.pid, exitCode: 0}, restoredProcess: {pid: restored.pid, exitCode: 0},
          restartCounts: restored.counts, rows: restored.rows.length, readExplanation: explanation}));
        scratch.passed();
      });
  }
}

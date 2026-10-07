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
    throw new Error(`InstalledCancellationFailed: ${log}`, {cause: error});
  }
}

for (const entrance of ['local', 'https']) {
  for (const loss of ['before-commit', 'after-commit']) {
    test(`${entrance}: original cancellation lookup after ${loss} loss and process restart uses a successful Run`,
      {timeout: 40000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(),
          prefix: 'actql-installed-cancel-', label: `${entrance} original cancellation ${loss}`});
        const directory = scratch.path;
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
        const initialOutput = join(directory, 'initial.json');
        await invoke(directory, {directory, entrance, loss, output: initialOutput, phase: 'initial'}, 'initial');
        const initial = JSON.parse(await readFile(initialOutput, 'utf8'));
        assert.equal(initial.status.status, 'succeeded');
        assert.deepEqual(initial.rows, [{id: 1}, {id: 2}]);
        assert.equal(initial.computes, 1);
        assert.equal(initial.snapshot.issued, 1);
        assert.equal(initial.snapshot.operations.length, 1);
        assert.equal(initial.snapshot.requests[0].cancellation_requested, 0);
        const unresolved = {
          observation: 'outcome_unknown',
          summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
          next: {operation: 'lookupCancellation', cancelRef: initial.cancelRef},
        };
        assert.deepEqual(initial.explanation, unresolved);
        const restoredOutput = join(directory, 'restored.json');
        // The initial Host and its execution process have exited. The next
        // child only attaches and looks up the original operation; no cancel.
        await invoke(directory, {directory, entrance, output: restoredOutput,
          phase: 'restored', cancelRef: initial.cancelRef}, 'restored');
        const restored = JSON.parse(await readFile(restoredOutput, 'utf8'));
        assert.deepEqual(restored.ref, initial.ref);
        assert.deepEqual(restored.request.ref, initial.ref);
        assert.equal(restored.status.status, 'succeeded');
        assert.equal(restored.computes, 0);
        assert.deepEqual(restored.snapshot, initial.snapshot);
        assert.deepEqual(restored.lookup, loss === 'after-commit'
          ? {kind: 'found', cancellation: {ref: initial.ref, cancelRef: initial.cancelRef,
            kind: 'already_terminal', revision: initial.cancelRef.expectedRevision}}
          : {kind: 'unknown', cancelRef: initial.cancelRef});
        assert.deepEqual(restored.repeated, restored.lookup);
        const expectedExplanation = loss === 'after-commit' ? {
          observation: 'already_terminal', revision: initial.cancelRef.expectedRevision,
          summary: 'The Host reports the Run is already terminal for cancellation. Refresh Run state for Effect and release details.',
          next: {operation: 'status', ref: initial.ref},
        } : unresolved;
        assert.deepEqual(restored.explanation, expectedExplanation, '[check-mutation:cancel-lookup-public]');
        assert.deepEqual(restored.repeatedExplanation, expectedExplanation);
        assert.equal(restored.copiedExplanationAbsent, true);
        for (const format of ['text', 'html', 'json']) {
          assert.ok(restored.formats[format]);
          assert.doesNotMatch(restored.formats[format], /fixture-token|CANCELLATION_FINAL_COMMIT_REPLY_LOST|edited-after-lookup/);
          if (format === 'json') assert.deepEqual(JSON.parse(restored.formats.json).explanation, expectedExplanation);
        }
        console.log('INSTALLED_CANCELLATION_EVIDENCE', JSON.stringify({directory,
          entrance, loss, ref: initial.ref, cancelRef: initial.cancelRef,
          lookup: restored.lookup.kind, initialComputes: 1, restoredComputes: 0}));
        scratch.passed();
      });
  }
}

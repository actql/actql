import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, open, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

for (const variant of ['status unavailable', 'handle replaced during retry']) {
  test(`initialization retains its original Reader and SQLite Site when ${variant}`, async t => {
    const scratch = fileURLToPath(new URL('../../_build/original-cleanup-observation/', import.meta.url));
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'owned-'));
    await writeFile(join(root, 'original-reader'), 'original physical custody');
    const reader = await open(join(root, 'original-reader'), 'r');
    const authority = generateKeyPairSync('ed25519');
    const journal = openSqliteCredentialJournal(join(root, 'credential-journal'), {
      credentialAuthorities: new Map([['original-authority',
        new Map([['original-key', authority.publicKey]])]]),
    });
    let permitClose = false, readerClosed = false, sourceClosed = false;
    let statusAvailable = variant !== 'status unavailable';
    let retries = 0, replacementRetries = 0, sourceCloses = 0;
    const observationFailure = new Error('OriginalCleanupObservationUnavailable');
    const primary = new Error('OriginalInitializationFailure');
    const replacement = Object.freeze({
      status: () => ({pending: false, errors: []}),
      async retry() { replacementRetries++; },
    });
    const original = Object.freeze({
      status() {
        if (!statusAvailable) throw observationFailure;
        return {pending: !readerClosed, errors: []};
      },
      async retry() {
        retries++;
        if (variant === 'handle replaced during retry') primary.cleanupHandle = replacement;
        if (permitClose && !readerClosed) {
          await reader.close();
          readerClosed = true;
        }
      },
    });
    primary.cleanupHandle = original;
    primary.cleanupPending = true;
    const source = Object.freeze({close() {
      if (sourceClosed) return;
      sourceCloses++;
      journal.close();
      sourceClosed = true;
    }});
    t.after(async () => {
      // Retire the actual original Reader before this fresh journal even
      // after a red assertion. No raw FD or old Run is retried/reset.
      permitClose = true;
      statusAvailable = true;
      await original.retry();
      source.close();
      if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
        console.error(`Original cleanup observation custody retained: ${root}`);
      } else await rm(root, {recursive: true, force: true});
    });
    const failure = await retainInstalledHostInitializationFailure(primary,
      {sourceProfile: source});
    assert.equal(failure.code, 'InstalledHostInitializationFailed');
    assert.equal(failure.cause, primary);
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(sourceCloses, 0, 'the still-owned original Reader gates Site release');
    assert.equal(readerClosed, false);
    assert.ok((await reader.stat()).size > 0);
    assert.deepEqual(journal.recover(), []);
    assert.equal(retries, 1);
    if (variant === 'status unavailable') {
      assert.ok(failure.cleanupHandle.status().errors.some(item => item.error === observationFailure));
    } else assert.equal(primary.cleanupHandle, replacement);
    statusAvailable = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(sourceCloses, 0);
    assert.equal(replacementRetries, 0, 'never adopt another cleanup Owner after await');
    permitClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal(readerClosed, true);
    assert.equal(sourceCloses, 1);
    assert.equal(replacementRetries, 0);
    await assert.rejects(reader.stat(), {code: 'EBADF'});
    assert.throws(() => journal.recover(), {code: 'RemoteCredentialJournalClosed'});
    const completedRetries = retries;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(retries, completedRetries);
    assert.equal(sourceCloses, 1);
  });
}

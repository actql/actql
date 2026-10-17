import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, open, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {retainInstalledCredentialSiteCleanup, releaseInstalledCredentialSite} from
  './installed-host-cleanup.mjs';

async function physicalSite(t, closeFailures) {
  const parent = fileURLToPath(new URL('../../_build/credential-site-cleanup/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'owned-'));
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['authority', new Map([['key', authority.publicKey]])]]),
  });
  let closing = false, released = false, closes = 0;
  const closeFailure = new Error('InjectedCredentialJournalCloseFailure');
  const site = Object.freeze({
    close() {
      if (released) return;
      closing = true;
      if (++closes <= closeFailures) throw closeFailure;
      journal.close();
      released = true;
    },
    cleanupPending: () => closing && !released,
  });
  t.after(() => {
    site.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      console.error(`Original Credential Site cleanup scratch retained: ${root}`);
    } else return rm(root, {recursive: true, force: true});
  });
  return {site, journal, root, closeFailure, closes: () => closes};
}

for (const closeFailures of [0, 1]) {
  test(`shared Site cleanup retains an independent original Reader with ${closeFailures} physical Site close failures`, async t => {
    const fixture = await physicalSite(t, closeFailures);
    await writeFile(join(fixture.root, 'reader'), 'same original Reader');
    const reader = await open(join(fixture.root, 'reader'), 'r');
    let closed = false, observable = false, permitClose = false, retries = 0;
    const observationFailure = new Error('OriginalReaderObservationUnavailable');
    const earlier = Object.freeze({
      status() {
        assert.equal(this, earlier);
        if (!observable) throw observationFailure;
        return {pending: !closed, errors: []};
      },
      async retry() {
        assert.equal(this, earlier);
        retries++;
        if (!permitClose) throw new Error('OriginalReaderCleanupPending');
        if (!closed) { await reader.close(); closed = true; }
      },
    });
    t.after(async () => { if (!closed) await reader.close(); });
    const primary = Object.freeze(Object.assign(new Error('OriginalSiteCallerFailure'), {
      code: 'OriginalSiteCallerFailure', cleanupPending: true, cleanupHandle: earlier,
    }));
    const failure = retainInstalledCredentialSiteCleanup(fixture.site, primary);
    assert.equal(failure.cause, primary);
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.code, primary.code);
    assert.equal(failure.cleanupPending, true);
    assert.ok(failure.cleanupErrors.includes(observationFailure));
    assert.equal(fixture.closes(), 1);
    if (closeFailures) assert.deepEqual(fixture.journal.recover(), []);
    assert.ok((await reader.stat()).size > 0);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(closed, false);
    assert.equal(fixture.site.cleanupPending(), false);
    assert.throws(() => fixture.journal.recover(), {code: 'RemoteCredentialJournalClosed'});
    observable = permitClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    await assert.rejects(reader.stat(), {code: 'EBADF'});
    assert.equal(fixture.closes(), closeFailures + 1);
    const completedRetries = retries;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(retries, completedRetries);
    assert.equal(fixture.closes(), closeFailures + 1);
  });
}

test('shared successful-caller release keeps the original physical Site failure and retries that journal', async t => {
  const fixture = await physicalSite(t, 1);
  let failure;
  assert.throws(() => releaseInstalledCredentialSite(fixture.site), error => {
    failure = error;
    return error === fixture.closeFailure;
  });
  assert.equal(failure.cleanupPending, true);
  assert.deepEqual(failure.cleanupErrors, [fixture.closeFailure]);
  assert.deepEqual(fixture.journal.recover(), []);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.throws(() => fixture.journal.recover(), {code: 'RemoteCredentialJournalClosed'});
  releaseInstalledCredentialSite(fixture.site);
  assert.equal(fixture.closes(), 2);
});

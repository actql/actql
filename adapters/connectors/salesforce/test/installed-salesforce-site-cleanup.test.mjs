import assert from 'node:assert/strict';
import test from 'node:test';
import {retainSalesforceSiteCleanup} from
  '../host/installed-salesforce-site.mjs';

function siteOwner(closeFailures) {
  let pending = true;
  let calls = 0;
  return {
    close() {
      if (++calls <= closeFailures) throw new Error('SiteCloseFailed');
      pending = false;
    },
    cleanupPending: () => pending,
    closeCalls: () => calls,
  };
}

for (const closeFailures of [0, 1]) {
  test(`frozen primary retains its cleanup owner with ${closeFailures} Site close failures`,
    async () => {
      const site = siteOwner(closeFailures);
      const earlierError = new Error('EarlierCloseFailed');
      let pending = true;
      let retries = 0;
      const primary = Object.freeze(Object.assign(new Error('Primary'), {
        cleanupPending: true,
        cleanupHandle: Object.freeze({
          status: () => ({pending, errors: [earlierError]}),
          async retry() { retries++; pending = false; },
        }),
      }));
      const failure = retainSalesforceSiteCleanup(site, primary);
      assert.equal(failure.primaryFailure, primary);
      assert.equal(failure.cause, primary);
      assert.equal(failure.cleanupPending, true);
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.equal(failure.cleanupErrors[0], earlierError);
      const after = await failure.cleanupHandle.retry();
      assert.equal(pending, false);
      assert.equal(retries, 1);
      assert.equal(site.cleanupPending(), false);
      assert.equal(site.closeCalls(), closeFailures + 1);
      assert.equal(after.pending, false);
      assert.equal(failure.cleanupPending, false);
      // Both completed owners stay completed on another retry.
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(retries, 1);
      assert.equal(site.closeCalls(), closeFailures + 1);
    });

  for (const cleanupHandle of [undefined, {retry() {}}]) {
    test(`unconfirmed primary cleanup stays pending with ${closeFailures} Site close failures and handle=${cleanupHandle !== undefined}`,
      async () => {
        const site = siteOwner(closeFailures);
        const earlierError = new Error('EarlierCloseFailed');
        const primary = Object.freeze(Object.assign(new Error('Primary'), {
          cleanupPending: true, cleanupErrors: [earlierError], cleanupHandle,
        }));
        const failure = retainSalesforceSiteCleanup(site, primary);
        assert.equal(failure.cleanupPending, true);
        assert.equal(failure.cleanupErrors[0], earlierError);
        assert.equal((await failure.cleanupHandle.retry()).pending, true);
        assert.equal(failure.cleanupPending, true);
        assert.equal(site.cleanupPending(), false);
      });
  }
}

test('an earlier retry failure does not prevent the independent Site release',
  async () => {
    const site = siteOwner(1);
    const earlierError = new Error('EarlierRetryFailed');
    let pending = true;
    let retries = 0;
    const primary = Object.assign(new Error('Primary'), {
      cleanupPending: true,
      cleanupHandle: Object.freeze({
        status: () => ({pending, errors: []}),
        async retry() {
          if (++retries === 1) throw earlierError;
          pending = false;
        },
      }),
    });
    const failure = retainSalesforceSiteCleanup(site, primary);
    assert.equal(failure, primary);
    const first = await failure.cleanupHandle.retry();
    assert.equal(first.pending, true);
    assert.ok(first.errors.includes(earlierError));
    assert.equal(site.cleanupPending(), false);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(retries, 2);
    assert.equal(site.closeCalls(), 2);
  });

for (const closeFailures of [0, 1]) {
  test(`an unavailable earlier status retains custody with ${closeFailures} Site close failures`,
    async () => {
      const site = siteOwner(closeFailures);
      const observationError = new Error('CleanupStatusUnavailable');
      let observable = false;
      let retries = 0;
      const primary = Object.assign(new Error('Primary'), {
        cleanupPending: true,
        cleanupHandle: Object.freeze({
          status() {
            if (!observable) throw observationError;
            return {pending: false, errors: []};
          },
          async retry() { retries++; },
        }),
      });
      const failure = retainSalesforceSiteCleanup(site, primary);
      assert.equal(failure, primary);
      assert.equal(failure.cleanupPending, true);
      assert.equal(failure.cleanupErrors.filter(error =>
        error === observationError).length, 1);
      // Neither handoff nor retry may replace the primary with an
      // observation error or skip the independent Site release.
      assert.equal((await failure.cleanupHandle.retry()).pending, true);
      assert.equal(site.cleanupPending(), false);
      assert.equal(retries, 1);
      observable = true;
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(retries, 1);
    });
}

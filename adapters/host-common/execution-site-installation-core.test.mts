import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from './runtime-core.mjs';
import type {siteControl} from './site-control.mjs';
import {
  createInProcessExecutionSite, executionSitePlacements, executionSiteStatus,
  installExecutionSites, prepareExecutionSitePolicy,
  releaseExecutionSiteCleanup, retainExecutionSiteCleanup,
} from './execution-sites.mjs';

const moon: unknown = await import(new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url,
).href);

test('partial installation keeps the actual Core cleanup duty and original healthy binding', () => {
  const original = (runtimeCore(moon) as {siteControl: ReturnType<typeof siteControl>}).siteControl;
  let creates = 0, cleanup: ReturnType<typeof retainExecutionSiteCleanup>;
  const primary = Object.freeze(new Error('Injected third create failure'));
  const control = Object.freeze({...original, create(configuration: Parameters<typeof original.create>[0]) {
    creates++;
    if (creates === 3) {
      cleanup = retainExecutionSiteCleanup(fresh, Object.freeze({physical: 'original duty'}));
      throw primary;
    }
    return original.create(configuration);
  }});
  const site = (key: string) => createInProcessExecutionSite({key, generation: 1, runtimeRevision: 'core-installation/1'});
  const healthy = site('healthy'), fresh = site('new'), failed = site('failed');
  const contribution = Object.freeze({managedSelectionKey: 'core'});
  const old = installExecutionSites(prepareExecutionSitePolicy({sites: [healthy]}), [contribution], control);
  let failure: {cause?: unknown; cleanupPending: boolean; cleanupHandle: {retry(): {pending: boolean}}};
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: [healthy, fresh, failed]}),
    [contribution], control), error => { failure = error as typeof failure; return true; });
  assert.equal(failure!.cause, primary);
  assert.equal(failure!.cleanupPending, true);
  assert.equal(failure!.cleanupHandle.retry().pending, true);
  assert.equal(executionSiteStatus(fresh).cleanupResponsibilities, 1);
  assert.equal(executionSiteStatus(fresh).accepting, false);
  assert.equal(executionSiteStatus(healthy).accepting, true);
  assert.deepEqual(executionSitePlacements(old, contribution), [healthy]);
  assert.equal(releaseExecutionSiteCleanup(cleanup!), true);
  assert.equal(failure!.cleanupHandle.retry().pending, false);
  assert.equal(executionSiteStatus(fresh).teardownComplete, true);
  assert.equal(releaseExecutionSiteCleanup(cleanup!), false);
  assert.equal(creates, 3, 'cleanup retry must not repeat create');
});

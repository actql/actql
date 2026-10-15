import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {
  createInProcessExecutionSite, executionSitePlacements, executionSiteStatus,
  installExecutionSites, prepareExecutionSitePolicy,
  releaseExecutionSiteCleanup, retainExecutionSiteCleanup,
} from './execution-sites.mjs';

test('partial installation keeps the actual Core cleanup duty and original healthy binding', () => {
  const original = runtimeCore(moon).siteControl;
  let creates = 0, cleanup;
  const primary = Object.freeze(new Error('Injected third create failure'));
  const control = Object.freeze({...original, create(configuration) {
    creates++;
    if (creates === 3) {
      cleanup = retainExecutionSiteCleanup(fresh, Object.freeze({physical: 'original duty'}));
      throw primary;
    }
    return original.create(configuration);
  }});
  const site = key => createInProcessExecutionSite({key, generation: 1, runtimeRevision: 'core-installation/1'});
  const healthy = site('healthy'), fresh = site('new'), failed = site('failed');
  const contribution = Object.freeze({managedSelectionKey: 'core'});
  const old = installExecutionSites(prepareExecutionSitePolicy({sites: [healthy]}), [contribution], control);
  let failure;
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: [healthy, fresh, failed]}),
    [contribution], control), error => { failure = error; return true; });
  assert.equal(failure.cause, primary);
  assert.equal(failure.cleanupPending, true);
  assert.equal(failure.cleanupHandle.retry().pending, true);
  assert.equal(executionSiteStatus(fresh).cleanupResponsibilities, 1);
  assert.equal(executionSiteStatus(fresh).accepting, false);
  assert.equal(executionSiteStatus(healthy).accepting, true);
  assert.deepEqual(executionSitePlacements(old, contribution), [healthy]);
  assert.equal(releaseExecutionSiteCleanup(cleanup), true);
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.equal(executionSiteStatus(fresh).teardownComplete, true);
  assert.equal(releaseExecutionSiteCleanup(cleanup), false);
  assert.equal(creates, 3, 'cleanup retry must not repeat create');
});

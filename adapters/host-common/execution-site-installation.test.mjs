import assert from 'node:assert/strict';
import test from 'node:test';
import {
  beginExecutionSiteTeardown,
  createInProcessExecutionSite,
  executionSitePlacements,
  executionSiteStatus,
  installExecutionSites,
  prepareExecutionSitePolicy,
} from './execution-sites.mjs';
import {createExecutionSiteControlFixture} from './execution-site-control.fixture.mjs';

const site = key => createInProcessExecutionSite({key, generation: 1, runtimeRevision: 'site-installation-test/1'});
const contribution = key => Object.freeze({managedSelectionKey: key});
const controlFixture = () => {
  const original = createExecutionSiteControlFixture();
  const created = [], teardown = [];
  let createFault, teardownFault;
  const control = Object.freeze({...original,
    create(configuration) {
      const failure = createFault?.(configuration);
      if (failure !== undefined) throw failure;
      const handle = original.create(configuration);
      created.push(handle);
      return handle;
    },
    beginTeardown(handle) {
      teardown.push(handle);
      const failure = teardownFault?.(handle);
      if (failure !== undefined) throw failure;
      return original.beginTeardown(handle);
    },
  });
  return {control, original, created, teardown,
    failCreate(value) { createFault = value; },
    failTeardown(value) { teardownFault = value; }};
};

test('default-only placement limits reject during policy preparation without creating a Site', () => {
  for (const count of [1, 2]) {
    const values = Array.from({length: count}, (_, index) => site('default-' + index));
    const tracked = controlFixture();
    assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({
      sites: values, defaultSites: values, maxPlacements: count - 1,
    }), [contribution('one')], tracked.control), {code: 'ExecutionSitePlacementLimit'});
    assert.equal(tracked.created.length, 0);
    // Still unbound, not erased after a hidden create.
    const other = controlFixture();
    installExecutionSites(prepareExecutionSitePolicy({sites: values}), [contribution('other')], other.control);
    assert.equal(other.created.length, count);
  }
});

test('duplicate contributions reject before any Site binding', () => {
  const value = site('duplicate-contribution'), item = contribution('one');
  const tracked = controlFixture();
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: [value]}),
    [item, item], tracked.control), {code: 'InvalidExecutionSiteInstallation'});
  assert.equal(tracked.created.length, 0);
});

test('expanded default placements reject before create even when the prepared policy fits', () => {
  const values = [site('expanded-a'), site('expanded-b')], tracked = controlFixture();
  const policy = prepareExecutionSitePolicy({sites: values, defaultSites: values, maxPlacements: 3});
  assert.throws(() => installExecutionSites(policy,
    [contribution('one'), contribution('two')], tracked.control), {code: 'ExecutionSitePlacementLimit'});
  assert.equal(tracked.created.length, 0);
});

test('expanded explicit and fallback placements share the same installation bound before create', () => {
  const values = [site('explicit-a'), site('explicit-b')], tracked = controlFixture();
  const policy = prepareExecutionSitePolicy({sites: values,
    placements: new Map([['two-sites', values]]), maxPlacements: 3});
  assert.throws(() => installExecutionSites(policy,
    [contribution('two-sites'), contribution('fallback-a'), contribution('fallback-b')], tracked.control),
  {code: 'ExecutionSitePlacementLimit'});
  assert.equal(tracked.created.length, 0);
});

test('a later foreign binding rejects before creating an earlier unbound Site', () => {
  const fresh = site('fresh-before-foreign'), existing = site('foreign-existing');
  const original = controlFixture(), incoming = controlFixture();
  const oldItem = contribution('original');
  const oldInstallation = installExecutionSites(prepareExecutionSitePolicy({sites: [existing]}), [oldItem], original.control);
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: [fresh, existing]}),
    [contribution('incoming')], incoming.control), {code: 'ForeignExecutionSiteControl'});
  assert.equal(incoming.created.length, 0);
  assert.equal(executionSiteStatus(existing).accepting, true);
  assert.deepEqual(executionSitePlacements(oldInstallation, oldItem), [existing]);
  assert.equal(original.teardown.length, 0);
  const independent = controlFixture();
  installExecutionSites(prepareExecutionSitePolicy({sites: [fresh]}), [contribution('independent')], independent.control);
  assert.equal(independent.created.length, 1);
});

test('mid-create failure retains the new original handle and pending cleanup but does not tear down existing bindings', () => {
  const old = site('old-normal'), fresh = site('new-pending'), failed = site('create-failed');
  const tracked = controlFixture(), oldItem = contribution('old');
  const oldInstallation = installExecutionSites(prepareExecutionSitePolicy({sites: [old]}), [oldItem], tracked.control);
  const primary = Object.freeze(Object.assign(new Error('IndependentCreateFailure'), {code: 'IndependentCreateFailure'}));
  let cleanup;
  tracked.failCreate(configuration => {
    if (configuration.key !== 'create-failed') return;
    cleanup = tracked.original.retainCleanup(tracked.created[1]);
    return primary;
  });
  let failure;
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: [old, fresh, failed]}),
    [contribution('new')], tracked.control), error => { failure = error; return true; });
  assert.equal(failure.cause, primary);
  assert.equal(failure.code, primary.code);
  assert.equal(tracked.created.length, 2);
  assert.equal(executionSiteStatus(old).accepting, true);
  assert.deepEqual(executionSitePlacements(oldInstallation, oldItem), [old]);
  assert.equal(tracked.teardown.includes(tracked.created[0]), false);
  assert.equal(executionSiteStatus(fresh).accepting, false);
  assert.equal(executionSiteStatus(fresh).cleanupResponsibilities, 1);
  assert.equal(executionSiteStatus(fresh).teardownComplete, false);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(failure.cleanupHandle.retry().pending, true);
  assert.equal(tracked.original.releaseCleanup(cleanup), true);
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.equal(executionSiteStatus(fresh).teardownComplete, true);
  // No WeakMap deletion/rebind pretending to undo the original handle.
  const foreign = controlFixture();
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: [fresh]}),
    [contribution('foreign')], foreign.control), {code: 'ForeignExecutionSiteControl'});
  assert.equal(foreign.created.length, 0);
  assert.equal(tracked.created.length, 2);
});

test('failed teardown keeps every new handle available to the same cleanup retry', () => {
  const values = [site('new-a'), site('new-b'), site('fails-c')], tracked = controlFixture();
  const primary = Object.freeze(new Error('Original creation failure'));
  const teardownFailure = Object.freeze(new Error('Original teardown failure'));
  tracked.failCreate(configuration => configuration.key === 'fails-c' ? primary : undefined);
  tracked.failTeardown(handle => handle.key === 'new-a' ? teardownFailure : undefined);
  let failure;
  assert.throws(() => installExecutionSites(prepareExecutionSitePolicy({sites: values}),
    [contribution('one')], tracked.control), error => { failure = error; return true; });
  assert.equal(failure.cause, primary);
  assert.equal(failure.cleanupFailure, teardownFailure);
  assert.equal(tracked.created.length, 2);
  assert.ok(tracked.teardown.includes(tracked.created[1]), 'later created Site still receives teardown');
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.throws(() => failure.cleanupHandle.retry(), error => error === teardownFailure);
  tracked.failTeardown(undefined);
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.ok(values.slice(0, 2).every(value => executionSiteStatus(value).teardownComplete));
  assert.equal(tracked.created.length, 2);
});

test('successful repeated installation reuses the original normal binding and immutable placement', () => {
  const values = [site('success-a'), site('success-b')], tracked = controlFixture();
  const item = contribution('two'), fallback = contribution('fallback');
  const policy = prepareExecutionSitePolicy({sites: values,
    placements: new Map([['two', values]]), maxPlacements: 3});
  const first = installExecutionSites(policy, [item, fallback], tracked.control);
  const again = installExecutionSites(policy, [item], tracked.control);
  assert.equal(tracked.created.length, 2);
  assert.equal(tracked.teardown.length, 0);
  assert.deepEqual(executionSitePlacements(first, item), values);
  assert.deepEqual(executionSitePlacements(first, fallback), [values[0]]);
  assert.ok(Object.isFrozen(executionSitePlacements(again, item)));
  assert.ok(values.every(value => executionSiteStatus(value).accepting));
});

test('a teardown requested before installation still reaches the original created control', () => {
  const value = site('already-stopping'), tracked = controlFixture();
  beginExecutionSiteTeardown(value);
  installExecutionSites(prepareExecutionSitePolicy({sites: [value]}), [contribution('one')], tracked.control);
  assert.equal(tracked.created.length, 1);
  assert.equal(executionSiteStatus(value).accepting, false);
  assert.equal(executionSiteStatus(value).teardownComplete, true);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareOrdinaryProjectSourceManagedInstallation,
  assertOrdinarySourcePreparationCurrent} from './ordinary-source-managed.mjs';
import {localFilesLookupExecutionPolicy} from './installed-host-policy.mjs';

// Actual JS installation/retirement and lookup-policy projection. The original
// Source initializer/current ports are explicit; no native backing, Account,
// provider read, Request or public Host is manufactured by this fixture.
const limits = Object.freeze({maxFiles: 2, maxPages: 3,
  maxPageBytes: 128, maxDurationMs: 1000});

test('ordinary Project initialization retains all original Source inventory beyond128 through close', async () => {
  const originals = {}, declarations = Array.from({length: 129}, () => Object.freeze({}));
  const sources = Object.freeze(declarations.map(declaration => Object.freeze({declaration, limits})));
  const bundle = Object.freeze({sources});
  let live = true, prepared = 0, reads = 0, view;
  const callbacks = {
    validator(value) {
      assert.strictEqual(value, originals);
      if (!live) throw new Error('OriginalProjectRetired');
    },
    async prepare(value, installed) {
      assert.strictEqual(value, originals); assert.equal(typeof installed.close, 'function');
      prepared++;
    },
    read(value) {assert.strictEqual(value, originals); reads++; return bundle;},
  };
  try {
    try {view = await prepareOrdinaryProjectSourceManagedInstallation(originals, callbacks);}
    catch (error) {
      if (error.cleanupHandle !== undefined) {
        assert.equal((await error.cleanupHandle.retry()).pending, false);
      }
      throw error;
    }
    assertOrdinarySourcePreparationCurrent(view, originals, true);
    assert.equal(prepared, 1);
    // Existing current checks reread the same bundle identity after awaits.
    // This is not another Source preparation or a reconstructed inventory.
    const completedReads = reads;
    assert.ok(completedReads > 0);
    assert.equal(new Set(sources.map(source => source.declaration)).size, 129);
    assert.deepEqual(localFilesLookupExecutionPolicy(sources.map(source => source.limits)),
      localFilesLookupExecutionPolicy([limits]));
    live = false;
    assert.throws(() => assertOrdinarySourcePreparationCurrent(view, originals, true),
      /OriginalProjectRetired/u);
    assert.equal(reads, completedReads,
      'A refused original-current check never reads a replacement inventory');
  } finally {
    if (view !== undefined) assert.equal((await view.close()).pending, false);
  }
});

test('Local lookup folds every declared bound beyond128 and preserves the last invalid-field refusal', () => {
  const many = Array(128).fill(limits);
  const last = Object.freeze({...limits, maxPageBytes: 256, maxDurationMs: 2000});
  const policy = localFilesLookupExecutionPolicy([...many, last]);
  assert.deepEqual(policy, localFilesLookupExecutionPolicy([last]));
  for (const invalid of [{...last, maxFiles: 0}, {...last, maxPages: -1},
    {...last, maxFiles: 2147483647, maxPages: 2147483647, maxPageBytes: 2147483647}]) {
    assert.throws(() => localFilesLookupExecutionPolicy([...many, invalid]),
      /InvalidLocalFilesLookupExecutionPolicy/u);
  }
  assert.throws(() => localFilesLookupExecutionPolicy([]),
    /InvalidLocalFilesLookupExecutionPolicy/u);
});

test('ordinary initialization current failure retains only its original cleanup continuation', async () => {
  const originals = {}, sources = Object.freeze(Array.from({length: 129}, () => Object.freeze({})));
  const primary = new Error('OriginalProjectRetired');
  let live = true, reads = 0, failure;
  try {
    await prepareOrdinaryProjectSourceManagedInstallation(originals, {
      validator(value) {assert.strictEqual(value, originals); if (!live) throw primary;},
      async prepare() {},
      read() {reads++; live = false; return Object.freeze({sources});},
    });
  } catch (error) {failure = error;}
  assert.equal(failure?.code, 'InstalledSourcePreparationCleanupPending');
  assert.strictEqual(failure.cause, primary);
  assert.equal(reads, 1);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(reads, 1);
});

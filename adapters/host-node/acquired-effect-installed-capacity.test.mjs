// Host sequencing controls only. Opaque Common capacity and resource admission
// are explicit doubles here; these tests do not claim Source or Host E2E.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledAcquiredEffectLedger, selectAcquiredEffectSources}
  from './acquired-effect-sources.mjs';

function fixture() {
  const events = {capacity: [], admission: [], io: 0};
  const preparedEffect = {}, ledger = {};
  const budgets = [{capacity: {}, transferBytes: 11n, executionBytes: 13n},
    {capacity: {}, transferBytes: 17n, executionBytes: 19n}];
  const sources = ['duckdb-acquired', 'row-source-acquired'].map((realizationKey, index) => {
    const preparedSource = {};
    return {preparedSource, occurrence: {stage: index, input: 0, task: index}, adapter: {
      realizationKey, supportsRetainedRelationOutput: true,
      admitsSource: ref => ref === `source-${index}`,
      prepare() { events.io++; }, open() { events.io++; },
      ledgerCapacity(actual) {
        assert.equal(actual, preparedSource);
        events.capacity.push(index);
        return budgets[index];
      },
    }};
  });
  const moon = {
    clientProgramEffectAcquisitionCount: () => 2,
    clientProgramEffectDirectSourceCoordinates: () => ({$tag: 1, _0: [[0, 0, 0, 0], [1, 0, 1, 1]]}),
    clientProgramEffectPrepareLocalQueryRequirement: (_, task) => ({$tag: 1, _0: task}),
    clientProgramQueryRequirementSourceRef: task => `source-${task}`,
    clientProgramPrepareMultiCapturedEffectInstalledLedger(...args) {
      events.admission.push(args);
      return ledger;
    },
  };
  return {events, budgets, sources, ledger,
    options: {moon, preparedEffect, sources, registry: 'registry', values: 'values',
      fragment: 'fragment', ordered: undefined}};
}

for (const reverse of [false, true]) {
  test(`mixed installed Effect selection preserves authored occurrence order (reverse ${reverse})`, () => {
    const f = fixture();
    if (reverse) {
      [f.sources[0].adapter.realizationKey, f.sources[1].adapter.realizationKey] =
        [f.sources[1].adapter.realizationKey, f.sources[0].adapter.realizationKey];
    }
    const selected = selectAcquiredEffectSources({...f.options,
      sourceProfile: {sources: f.sources.map(value => value.adapter)}});
    assert.deepEqual(selected.map(value => value.adapter), f.sources.map(value => value.adapter));
    assert.deepEqual(selected.map(value => value.occurrence), f.sources.map(value => value.occurrence));
    assert.equal(f.events.io, 0);
    assert.deepEqual(f.events.capacity, []);
  });
}

test('mixed Effect ledger forwards both original opaque capacities and all transport contributions', () => {
  const f = fixture();
  assert.equal(prepareInstalledAcquiredEffectLedger(f.options), f.ledger);
  assert.deepEqual(f.events.capacity, [0, 1]);
  assert.equal(f.events.admission[0][0], f.options.preparedEffect);
  assert.deepEqual(f.events.admission[0].slice(1), [f.budgets.map(value => value.capacity),
    [11n, 17n], [13n, 19n], 'registry', 'values', 'fragment', undefined]);
  assert.equal(f.events.io, 0);
});

for (const fault of ['missing-api', 'missing-source', 'missing-owner', 'unsupported-owner',
  'unsupported-retention', 'missing-capacity', 'missing-transfer', 'negative-transfer',
  'negative-execution', 'number-instead-of-bigint', 'swapped-occurrence']) {
  test(`mixed Effect ${fault} refuses before resource admission or Source I/O`, () => {
    const f = fixture();
    if (fault === 'missing-api') delete f.options.moon.clientProgramPrepareMultiCapturedEffectInstalledLedger;
    if (fault === 'missing-source') f.sources.pop();
    if (fault === 'missing-owner') delete f.sources[0].adapter.ledgerCapacity;
    if (fault === 'unsupported-owner') f.sources[0].adapter.realizationKey = 'foreign';
    if (fault === 'unsupported-retention') f.sources[0].adapter.supportsRetainedRelationOutput = false;
    if (fault === 'missing-capacity') delete f.budgets[0].capacity;
    if (fault === 'missing-transfer') delete f.budgets[0].transferBytes;
    if (fault === 'negative-transfer') f.budgets[0].transferBytes = -1n;
    if (fault === 'negative-execution') f.budgets[0].executionBytes = -1n;
    if (fault === 'number-instead-of-bigint') f.budgets[0].transferBytes = 11;
    if (fault === 'swapped-occurrence') [f.sources[0], f.sources[1]] = [f.sources[1], f.sources[0]];
    assert.throws(() => prepareInstalledAcquiredEffectLedger(f.options),
      /Installed(?:MultiSourceCapacity|SourceCapacity)Unavailable/);
    assert.equal(f.events.admission.length, 0);
    assert.equal(f.events.io, 0);
  });
}

test('Common capacity refusal is preserved without a replacement ledger or read', () => {
  const f = fixture();
  f.options.moon.clientProgramPrepareMultiCapturedEffectInstalledLedger = (...args) => {
    f.events.admission.push(args);
    return undefined;
  };
  assert.throws(() => prepareInstalledAcquiredEffectLedger(f.options),
    /InstalledMultiSourceLedgerUnavailable/);
  assert.equal(f.events.admission.length, 1);
  assert.deepEqual(f.events.capacity, [0, 1]);
  assert.equal(f.events.io, 0);
});

test('original installed capacity owner failure is preserved before any provider work', () => {
  const f = fixture(), failure = new Error('FixtureOriginalCapacityOwner');
  f.sources[1].adapter.ledgerCapacity = () => { throw failure; };
  assert.throws(() => prepareInstalledAcquiredEffectLedger(f.options), error => error === failure);
  assert.equal(f.events.admission.length, 0);
  assert.equal(f.events.io, 0);
});

test('managed Effect borrows both Source capacities from the same original Run and request', () => {
  const f = fixture(), original = {}, request = {};
  f.options.requestIdentity = request;
  for (const budget of f.budgets) budget.managedRun = original;
  const calls = [];
  f.options.moon.clientProgramInstalledEffectManagedRunPrepareLedger = (...args) => {
    calls.push(args); return {$tag: 1, _0: f.ledger};
  };
  assert.strictEqual(prepareInstalledAcquiredEffectLedger(f.options), f.ledger);
  assert.deepEqual(calls, [[original, f.options.preparedEffect, request,
    f.budgets.map(value => value.capacity), [11n, 17n], [13n, 19n],
    'registry', 'values', 'fragment', undefined]]);
  assert.equal(f.events.admission.length, 0, 'no replacement scalar Ledger');
  assert.equal(f.events.io, 0);
});

for (const fault of ['missing-first-original', 'missing-sibling-original', 'foreign-sibling-original',
  'missing-request', 'missing-managed-port', 'refused-original']) {
  test(`managed Effect ${fault} never substitutes the legacy Ledger`, () => {
    const f = fixture(), original = {}, failure = new Error('OriginalEffectRunRefused');
    f.options.requestIdentity = {};
    for (const budget of f.budgets) budget.managedRun = original;
    let calls = 0;
    f.options.moon.clientProgramInstalledEffectManagedRunPrepareLedger = () => {
      calls++;
      if (fault === 'refused-original') throw failure;
      assert.fail('An incomplete original cannot reach Common');
    };
    if (fault === 'missing-first-original') delete f.budgets[0].managedRun;
    if (fault === 'missing-sibling-original') delete f.budgets[1].managedRun;
    if (fault === 'foreign-sibling-original') f.budgets[1].managedRun = {};
    if (fault === 'missing-request') delete f.options.requestIdentity;
    if (fault === 'missing-managed-port') delete f.options.moon.clientProgramInstalledEffectManagedRunPrepareLedger;
    assert.throws(() => prepareInstalledAcquiredEffectLedger(f.options), error =>
      fault === 'refused-original' ? error === failure : error.message === 'InstalledEffectOriginalRunUnavailable');
    assert.equal(calls, fault === 'refused-original' ? 1 : 0);
    assert.equal(f.events.admission.length, 0);
    assert.equal(f.events.io, 0);
  });
}

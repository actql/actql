import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import { computePhysicalCapacity, sourceTransportLimits } from '../physical-capacity.mjs';
import { provisionComputeDatabase, validateLimits } from '../session.mjs';
import {runtimeField} from '../../../../host-common/compiler-binding.generated.mjs';

const limits = { memoryBytes: 1000, maxTransportBytes: 10, maxCells: 2,
  maxColumns: 3, maxParameters: 4, maxSqlBytes: 5, maxRows: 2, threads: 1 };

test('Source receiver window funds actual batches without changing cumulative policy', () => {
  const supplied = {maxRows: 10000, maxCells: 100000, maxTransportBytes: 10000000,
    maxSqlBytes: 10000, maxParameters: 100, maxColumns: 100,
    memoryBytes: 128 * 1024 * 1024, threads: 1};
  const bounded = sourceTransportLimits(supplied, 100, 100000);
  assert.deepEqual(bounded, {...supplied, maxChunkRows: 100, maxChunkBytes: 100000});
  assert.equal(Object.isFrozen(bounded), true);
  assert.equal(Object.hasOwn(supplied, 'maxChunkRows'), false);
  const actual = computePhysicalCapacity(bounded);
  assert.equal(actual.executionBytes,
    134217728n + 100000n * 32n + (10000n + 204800n + 200n) * 256n + 40000n);
  assert.equal(actual.transferBytes, 10000000n);
  const broader = sourceTransportLimits({...supplied, maxRows: 1000000, maxCells: 1000000,
    maxTransportBytes: 100000000}, 100, 100000);
  assert.equal(computePhysicalCapacity(broader).executionBytes, actual.executionBytes);
  assert.equal(computePhysicalCapacity(broader).transferBytes, 100000000n);
});

test('Source receiver window preserves tighter explicit batch bounds and refuses invalid DATA', () => {
  const small = sourceTransportLimits(limits, 100, 100000);
  assert.deepEqual(small, {...limits, maxChunkRows: 2, maxChunkBytes: 10});
  assert.equal(computePhysicalCapacity(small).scratchBytes,
    10n * 32n + (2n + 6144n + 7n) * 256n + 20n);
  for (const selected of [{maxChunkRows: 1}, {maxChunkBytes: 5}, {maxChunkRows: 1, maxChunkBytes: 5}]) {
    assert.deepEqual(sourceTransportLimits({...limits, ...selected}, 100, 100000),
      {...limits, maxChunkRows: 2, maxChunkBytes: 10, ...selected});
  }
  for (const empty of [{maxRows: 0}, {maxTransportBytes: 0}, {maxRows: 0, maxTransportBytes: 0}]) {
    for (const explicit of [{}, {maxChunkRows: 1, maxChunkBytes: 5}]) {
      const supplied = {...limits, ...empty, ...explicit};
      const unchanged = sourceTransportLimits(supplied, 0, 0);
      assert.deepEqual(unchanged, supplied);
      assert.equal(Object.isFrozen(unchanged), true);
      assert.deepEqual(computePhysicalCapacity(unchanged), computePhysicalCapacity(supplied));
    }
  }
  for (const invalid of [0, -1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => sourceTransportLimits(limits, invalid, 100000), {code: 'InvalidLimits'});
    assert.throws(() => sourceTransportLimits(limits, 100, invalid), {code: 'InvalidLimits'});
  }
});

// Actual Host bodies with explicit pre-provider ports. These controls stop at
// the real Session handoff, without issuing a capture or claiming native work.
for (const broad of [false, true]) {
  test(`${broad ? 'Broad' : 'Native'} Source uses the same selected window for quote and Session`, async () => {
    const source = readFileSync(new URL('../host.mjs', import.meta.url), 'utf8');
    const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
    const name = broad ? 'runBroadHostQuery' : 'runHostNativeQuery';
    const node = ast.body.map(value => value.declaration ?? value).find(value => value.id?.name === name);
    assert.ok(node);
    const setup = {}, ledger = {}, grant = {}, primary = new Error('StoppedAtOriginalSession');
    const supplied = {...limits, maxTransportBytes: 10000000, maxRows: 10000,
      maxCells: 100000, maxChunkRows: 50};
    let quotes = 0, reads = 0, quoted;
    const window = original => {assert.equal(original, setup);return {_0: 100, _1: 100000};};
    const moon = {[broad ? 'broadHostTransportWindow' : 'nativeHostTransportWindow']: window,
      [broad ? 'broadHostCapacity' : 'nativeHostCapacity']: original => {
        assert.equal(original, setup);return 3n;
      }};
    const read = async (actualGrant, _prepare, actual) => {
      reads++;
      assert.equal(actualGrant, grant);assert.equal(actual, quoted);
      assert.deepEqual(actual, {...supplied, maxChunkBytes: 100000});
      throw primary;
    };
    const ports = {loadRuntime: async () => moon, runtimeField, sourceTransportLimits,
      checked: value => value,
      computePhysicalCapacity(actual) {quotes++;quoted = actual;return computePhysicalCapacity(actual);},
      [broad ? 'runBroadQuery' : 'runNativeQuery']: read};
    const run = new Function('ports', `const {${Object.keys(ports).join(',')}}=ports;return (${source.slice(node.start, node.end)});`)(ports);
    const execute = () => broad
      ? run(grant, setup, supplied, undefined, {clientBroadResidualPrepare() {assert.fail('No residual work');}}, ledger)
      : run(grant, setup, supplied, undefined, ledger);
    await assert.rejects(execute(), error => error === primary);
    assert.equal(quotes, 1);assert.equal(reads, 1);
    // A refused selected original is neither permission to quote nor to read.
    moon[broad ? 'broadHostTransportWindow' : 'nativeHostTransportWindow'] = () => {throw primary;};
    await assert.rejects(execute(), error => error === primary);
    assert.equal(quotes, 1);assert.equal(reads, 1);
  });
}

test('physical capacity keeps DB, transport scratch and consumed transfer distinct', () => {
  const cap = computePhysicalCapacity(limits);
  assert.deepEqual(cap, {
    databaseBytes: 1000n, scratchBytes: 2404n, executionBytes: 3404n,
    transferBytes: 10n,
  });
  assert.equal(Object.isFrozen(cap), true);
  assert.equal(computePhysicalCapacity({ ...limits, maxCells: 3 }).scratchBytes, 2660n);
  // Same payload sizes do not allow discounts for unimplemented buffer sharing.
  assert.equal(cap.executionBytes + cap.executionBytes, 6808n);
});

test('capacity rejects invalid or overflowing envelopes before reservation', () => {
  for (const value of [-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => computePhysicalCapacity({ ...limits, maxCells: value }), { code: 'InvalidLimits' });
  }
  assert.throws(() => computePhysicalCapacity({ ...limits, memoryBytes: 0 }), { code: 'InvalidLimits' });
  // Arithmetic stays integer-exact even beyond Number's exact summation range.
  assert.equal(computePhysicalCapacity({ ...limits, maxTransportBytes: Number.MAX_SAFE_INTEGER }).transferBytes,
    9007199254740991n);
});

test('bounded transport capacity is independent of cumulative rows and bytes', () => {
  const config = {...limits, maxRows: 10000, maxCells: 10000, maxTransportBytes: 1000000,
    maxChunkRows: 16, maxChunkBytes: 1024};
  const cap = computePhysicalCapacity(config);
  // 16*3 delivered cells, 2048*3 raw SDK vector cells, 3 fields and 4 parameters.
  assert.equal(cap.scratchBytes, 1024n * 32n + (48n + 6144n + 7n) * 256n + 20n);
  const larger = computePhysicalCapacity({...config, maxRows: 1000000, maxCells: 1000000,
    maxTransportBytes: 100000000});
  assert.equal(larger.scratchBytes, cap.scratchBytes);
  assert.equal(larger.transferBytes, 100000000n);
  assert.equal(computePhysicalCapacity({...config, maxChunkBytes: 1025}).scratchBytes, cap.scratchBytes + 32n);
  // Neither bound alone selects the smaller physical representation policy.
  const whole = computePhysicalCapacity({...config, maxChunkRows: undefined, maxChunkBytes: undefined});
  assert.equal(computePhysicalCapacity({...config, maxChunkBytes: undefined}).scratchBytes, whole.scratchBytes);
  assert.equal(computePhysicalCapacity({...config, maxChunkRows: undefined}).scratchBytes, whole.scratchBytes);
});

test('provider preflight freezes all transport settings before any start or settlement', async () => {
  const source = { ...limits, cancelWaitMs: 0 };
  const fixed = validateLimits(source);
  source.threads = 0;
  assert.equal(fixed.threads, 1);
  assert.equal(Object.isFrozen(fixed), true);
  const events = [];
  for (const invalid of [{ threads: 0 }, { maxRows: -1 }, { cancelWaitMs: -1 }]) {
    await assert.rejects(provisionComputeDatabase({ ...limits, ...invalid }, {
      started() { events.push('started'); },
      settled(value) { events.push(value); },
    }), { code: 'InvalidLimits' });
  }
  assert.deepEqual(events, []);
});

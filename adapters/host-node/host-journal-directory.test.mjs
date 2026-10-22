import assert from 'node:assert/strict';
import test from 'node:test';
import {createHostJournalDirectoryInspector, assertHostJournalDirectoryInspector,
  inspectHostJournalDirectory} from './host-journal-directory.mjs';

// Explicit native-port fixtures: these test the consumer's custody protocol,
// not a Darwin syscall, an operational issuer or an installed Host.
const limits = Object.freeze({maxEntries: 3, maxNameBytes: 32, maxWork: 100, maxInspections: 8});
function fixture(names = ['b', 'a'], selected = limits) {
  let reads = 0, opens = 0, closes = 0, currents = 0;
  const handle = Object.freeze({});
  const native = {
    open(...args) { assert.equal(this, native); opens++;
      assert.deepEqual(args, ['/original', selected.maxEntries, selected.maxNameBytes, selected.maxWork]);
      return handle; },
    next(value) { assert.equal(value, handle); return reads < names.length ?
      Buffer.from(names[reads++]) : null; },
    current(value) { assert.equal(value, handle); currents++; },
    close(value) { assert.equal(value, handle); closes++; return Object.freeze({outcome: 'closed'}); },
  };
  return {native, handle, count: () => ({opens, reads, closes, currents})};
}

test('selected consumer uses the same receiver and captured operations through physical close', () => {
  const f = fixture();
  const original = f.native.close;
  let fences = 0;
  const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {
    fences++;
    f.native.close = () => assert.fail('replacement close must not run');
  });
  assert.deepEqual(inspect('/original'), ['a', 'b']);
  assert.deepEqual(f.count(), {opens: 1, reads: 2, closes: 1, currents: 2});
  assert.equal(fences, 6);
  f.native.close = original;
});

test('post-acquisition current refusal retains the acquired handle until its original close', () => {
  const f = fixture();
  const original = new Error('OriginalCurrentFailure');
  let checks = 0;
  const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {
    if (++checks === 2) throw original;
  });
  assert.throws(() => inspect('/original'), error => error === original);
  assert.deepEqual(f.count(), {opens: 1, reads: 0, closes: 1, currents: 0});
});

test('consumed close uncertainty is retained without another close or replacement acquisition', () => {
  const f = fixture();
  let attempts = 0;
  f.native.close = value => {
    assert.equal(value, f.handle); attempts++;
    return Object.freeze({outcome: 'unknown', errno: 5});
  };
  const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
  let failure;
  assert.throws(() => inspect('/original'), error => {
    failure = error; return error.code === 'HostJournalDirectoryCleanupPending';
  });
  for (let index = 0; index < 3; index++) {
    const observed = failure.cleanupHandle.retry();
    assert.equal(observed.pending, true);
    assert.deepEqual(observed.outcome, {outcome: 'unknown', errno: 5});
  }
  assert.throws(() => inspect('/original'), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(attempts, 1);
  assert.equal(f.count().opens, 1);
});

test('throwing and invalid close outcomes remain uncertain and cannot be replaced', () => {
  for (const outcome of [undefined, {}, true, {outcome: 'retry'}]) {
    const f = fixture(); let attempts = 0;
    f.native.close = () => { attempts++; return outcome; };
    const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
    assert.throws(() => inspect('/original'), error => {
      assert.equal(error.cleanupHandle.retry().pending, true);
      assert.equal(error.cleanupHandle.retry().pending, true);
      return error.code === 'HostJournalDirectoryCleanupPending';
    });
    assert.equal(attempts, 1);
  }
  const f = fixture(); const original = new Error('ConsumedCloseFailure');
  let attempts = 0;
  f.native.close = () => { attempts++; throw original; };
  const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
  assert.throws(() => inspect('/original'), error => {
    assert.equal(error.cleanupHandle.retry().errors[0], original);
    return error.code === 'HostJournalDirectoryCleanupPending';
  });
  assert.equal(attempts, 1);
});

test('count, name, UTF8, duplicate and work refusals close only the same acquired handle', () => {
  for (const names of [['a', 'b', 'c', 'd'], ['a', 'a'], ['.'], ['..'], ['a/b'],
    ['a\0b'], ['x'.repeat(33)], [Buffer.from([0xff])]]) {
    const f = fixture(names);
    const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
    assert.throws(() => inspect('/original'));
    assert.equal(f.count().closes, 1);
  }
  const selected = {...limits, maxWork: 3}, f = fixture(['a', 'b'], selected);
  const inspect = createHostJournalDirectoryInspector(f.native, selected, () => {});
  assert.throws(() => inspect('/original'), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(f.count().reads, 2);
  assert.equal(f.count().closes, 1);
});

test('selected UTF8 names retain a leading BOM rather than silently normalizing it', () => {
  const f = fixture(['\uFEFForiginal']);
  const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
  assert.deepEqual(inspect('/original'), ['\uFEFForiginal']);
});

test('proxy or getter operation tables are rejected without executing traps', () => {
  let reads = 0;
  const native = fixture().native;
  const getter = {...native};
  Object.defineProperty(getter, 'open', {get() { reads++; return native.open; }});
  const proxy = new Proxy(native, {getOwnPropertyDescriptor() { reads++; throw new Error('ProxyTrap'); }});
  for (const value of [getter, proxy]) {
    assert.throws(() => createHostJournalDirectoryInspector(value, limits, () => {}),
      {code: 'HostJournalDirectoryUnavailable'});
  }
  assert.equal(reads, 0);
});

test('reentry from the native close cannot acquire a sibling or retry the consumed original', () => {
  const f = fixture(); let attempts = 0, inspect;
  f.native.close = () => {
    attempts++;
    assert.throws(() => inspect('/original'), {code: 'HostJournalDirectoryUnavailable'});
    return {outcome: 'closed'};
  };
  inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
  assert.deepEqual(inspect('/original'), ['a', 'b']);
  assert.equal(attempts, 1);
  assert.equal(f.count().opens, 1);
});

test('private view membership and its exact bound cannot be replaced by a callable copy', () => {
  const f = fixture();
  const inspect = createHostJournalDirectoryInspector(f.native, limits, () => {});
  assert.equal(assertHostJournalDirectoryInspector(inspect, 3), undefined);
  for (const candidate of [() => [], inspect.bind(undefined), new Proxy(inspect, {})]) {
    for (const bound of [undefined, 3]) {
      assert.throws(() => assertHostJournalDirectoryInspector(candidate, bound),
        {code: 'HostJournalDirectoryUnavailable'});
    }
  }
  assert.throws(() => inspectHostJournalDirectory(inspect, '/original', 2),
    {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(f.count().opens, 0);
  assert.deepEqual(inspectHostJournalDirectory(inspect, '/original', 3), ['a', 'b']);
});

test('confirmed closes do not refill the captured original inspection allowance', () => {
  const selected = {...limits, maxInspections: 2}, f = fixture(['a'], selected);
  const inspect = createHostJournalDirectoryInspector(f.native, selected, () => {});
  selected.maxInspections = 100;
  assert.deepEqual(inspect('/original'), ['a']);
  assert.deepEqual(inspect('/original'), []);
  assert.throws(() => inspect('/original'), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(f.count().opens, 2); assert.equal(f.count().closes, 2);
});

test('pre-open current refusal consumes the same attempt without creating or retrying a native original', () => {
  const selected = {...limits, maxInspections: 1}, f = fixture([], selected);
  const cause = new Error('OriginalBeforeOpenCurrentRefusal');
  let currents = 0;
  const inspect = createHostJournalDirectoryInspector(f.native, selected, () => { currents++; throw cause; });
  assert.throws(() => inspect('/original'), error => error === cause);
  assert.throws(() => inspect('/original'), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(currents, 1); assert.equal(f.count().opens, 0); assert.equal(f.count().closes, 0);
});

test('native opening refusal cannot restart the exhausted inspection original', () => {
  const selected = {...limits, maxInspections: 1}, f = fixture([], selected);
  const cause = new Error('OriginalNativeOpenRefusal');
  let opens = 0;
  f.native.open = function () { assert.strictEqual(this, f.native); opens++; throw cause; };
  const inspect = createHostJournalDirectoryInspector(f.native, selected, () => {});
  assert.throws(() => inspect('/original'), error => error === cause);
  assert.throws(() => inspect('/original'), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(opens, 1); assert.equal(f.count().closes, 0);
});

test('finite inspection history is required before native acquisition without invoking getters', () => {
  const f = fixture();
  for (const maxInspections of [undefined, 0, -1, 1.5, NaN, Infinity, 2 ** 53]) {
    assert.throws(() => createHostJournalDirectoryInspector(f.native,
      {...limits, maxInspections}, () => {}), {code: 'HostJournalDirectoryUnavailable'});
  }
  let getters = 0;
  const getter = {...limits};
  Object.defineProperty(getter, 'maxInspections', {get() { getters++; return 1; }});
  assert.throws(() => createHostJournalDirectoryInspector(f.native, getter, () => {}),
    {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(getters, 0); assert.equal(f.count().opens, 0);
});

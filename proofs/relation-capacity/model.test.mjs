import test from 'node:test';
import assert from 'node:assert/strict';
import { liveBytes, maximum, reserve, checkedAdd } from './model.mjs';
test('physical sharing counts once; equal-value copies retain both allocations', () => {
  const allocations = [{ id: 'a', value: 'same', bytes: 8n }, { id: 'b', value: 'same', bytes: 8n }];
  assert.equal(liveBytes(allocations, ['a', 'a']), 8n);
  assert.equal(liveBytes(allocations, ['a', 'b']), 16n);
  assert.throws(() => liveBytes([...allocations, allocations[0]], ['a']));
  assert.throws(() => liveBytes(allocations, ['unknown']));
});
test('handoff and pending cleanup preserve every still-live predecessor', () => {
  const allocations = [{ id: 'old', bytes: 5n }, { id: 'fresh', bytes: 7n }];
  assert.equal(liveBytes(allocations, ['old']), 5n);
  const overlap = ['old', 'old', 'fresh'];
  assert.equal(liveBytes(allocations, overlap), 12n);
  for (const outcome of ['terminal', 'false', 'error']) {
    assert.equal(liveBytes(allocations, overlap), 12n, outcome);
  }
  assert.equal(liveBytes(allocations, ['fresh']), 7n);
});
test('finite arbitrary-sharing domains satisfy the conditional union bound', () => {
  const allocations = Array.from({ length: 5 }, (_, id) => ({ id, bytes: BigInt(id + 1) }));
  // Enumerate all child live sets and their intersections for two children;
  // include a third owner as parent control. This is finite model evidence.
  for (let a = 0; a < 32; a++) for (let b = 0; b < 32; b++) {
    const refs = bits => allocations.filter(x => bits & (1 << x.id)).map(x => x.id);
    const left = refs(a), right = refs(b), parent = [0];
    const childA = liveBytes(allocations, left), childB = liveBytes(allocations, right);
    const reservation = reserve({ retained: 0n, execution: 0n }, [
      { retained: 0n, execution: childA }, { retained: 0n, execution: childB },
    ]);
    assert.ok(liveBytes(allocations, [...left, ...right, ...parent]) <= reservation.execution);
  }
});
test('Int64 exact/overflow boundaries use independently checked mathematical integers', () => {
  assert.equal(checkedAdd(maximum, 0n), maximum);
  assert.equal(checkedAdd(maximum, 1n), null);
  assert.equal(checkedAdd(-1n, 1n), null);
  const base = { retained: 0n, execution: 0n }, suffix = { retained: 0n, execution: 5n };
  assert.equal(reserve(base, [{ retained: 0n, execution: maximum - 517n }, suffix]).execution, maximum);
  assert.equal(reserve(base, [{ retained: 0n, execution: maximum - 516n }, suffix]), null);
  assert.equal(reserve(base, [{ retained: maximum, execution: maximum }, suffix]), null);
  assert.equal(BigInt(2147483647) * 256n <= maximum, true);
});

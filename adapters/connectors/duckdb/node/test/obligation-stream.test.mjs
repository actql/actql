import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {checked} from '../runtime-result.mjs';

let moon;
test.before(async () => {
  await promisify(execFile)('moon', ['build', 'src/benchmark_obligations', '--target', 'js', '--release'],
    {cwd: new URL('../../../../../', import.meta.url)});
  moon = await import('../../../../../_build/js/release/build/benchmark_obligations/benchmark_obligations.js');
});
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
test('retention reserves metadata and retains uncertain allocations until confirmed cleanup', () => {
  const owner = checked(moon.obligationRetention(100n));
  const first = checked(moon.obligationReserveOutput(owner, 80, 10));
  assert.throws(() => checked(moon.obligationReserveOutput(owner, 10, 1)));
  checked(moon.obligationHoldOutput(first, 20, 5));
  assert.equal(moon.obligationRetentionUsage(owner).held_bytes, 25n);
  assert.throws(() => checked(moon.obligationHoldOutput(first, 20, 5)));
  assert.throws(() => checked(moon.obligationReserveOutput(owner, 66, 10)));
  const second = checked(moon.obligationReserveOutput(owner, 60, 10));
  assert.throws(() => checked(moon.obligationHoldOutput(second, 20, 11)));
  const pending = moon.obligationRetentionUsage(owner);
  assert.equal(pending.held_bytes, 25n);
  assert.equal(pending.reserved_retention_bytes, 70n);
  checked(moon.obligationRetentionReleased(owner));
  assert.equal(moon.obligationRetentionUsage(owner).held_bytes, 0n);
  assert.equal(moon.obligationRetentionUsage(owner).reserved_retention_bytes, 0n);
  assert.throws(() => checked(moon.obligationRetentionReleased(owner)));
  assert.throws(() => checked(moon.obligationReserveOutput(owner, 1, 0)));
});

test('execution admission combines database and simultaneous scratch', () => {
  const owner = checked(moon.obligationExecution(100n, 60n, 40n));
  assert.equal(moon.obligationExecutionUsage(owner).reserved_execution_bytes,
    100n);
  assert.throws(() => checked(moon.obligationExecution(100n, 60n, 41n)));
  checked(moon.obligationExecutionReleased(owner));
  assert.equal(moon.obligationExecutionUsage(owner).reserved_execution_bytes,
    0n);
  assert.throws(() => checked(moon.obligationExecutionReleased(owner)));
});
function begin({work = 1000, ceiling = 1000, retain = true, identity = true, budget, records = false,
  names = ['z', 'a'], kinds = [0, 1], nullable = [false, true]} = {}) {
  return checked(moon.obligationBegin(names, kinds, nullable,
    {max_rows: 10, max_cells: 30, max_nodes: 1000, max_text_bytes: 10000},
    {max_columns: 3, max_order_work: 1000, max_bytes: 10000, max_nodes: 1000, max_depth: 10},
    {max_bytes: 10000, max_nodes: 1000, max_columns: 3, max_rows: 10, max_text_bytes: 10000},
    budget ?? checked(moon.obligationBudget(work, 10000, 1000, 10, ceiling)),
    records, retain, identity, 10000));
}

test('shared canonical encoding retains order duplicates NULL and Unicode independently of column order', () => {
  const stream = begin();
  const text = checked(moon.obligationAppend(stream, 3,
    '[["4000000000000000","3ff0000000000000","4000000000000000"],["é",null,"é"]]'));
  const result = checked(moon.obligationFinish(stream));
  const expected = '[{"a":"é","z":2},{"a":null,"z":1},{"a":"é","z":2}]';
  assert.equal(text + result._0, expected);
  assert.equal(result._1, hash(expected)); assert.equal(result._4, 3);
  assert.throws(() => checked(moon.obligationFinish(stream)));
});

test('physical invalidity, missing cells and guard exhaustion poison the stream', () => {
  for (const [options, columns] of [
    [{}, '[["7ff0000000000000"],["x"]]'],
    [{}, '[[null],["x"]]'],
    [{}, '[[],["x"]]'],
    [{work: 1}, '[["3ff0000000000000"],["x"]]'],
    [{ceiling: 2}, '[["3ff0000000000000"],["long"]]'],
  ]) {
    const stream = begin(options);
    assert.throws(() => checked(moon.obligationAppend(stream, 1, columns)));
    assert.throws(() => checked(moon.obligationFinish(stream)));
  }
});

test('consumer measurement shares cumulative budget without inventing a content identity', () => {
  const budget = checked(moon.obligationBudget(4, 10000, 1000, 10, 1000));
  const columns = '[["3ff0000000000000"],["x"]]';
  const first = begin({budget, retain: false, identity: false});
  assert.equal(checked(moon.obligationAppend(first, 1, columns)), '');
  assert.equal(checked(moon.obligationFinish(first))._1, undefined);
  const second = begin({budget, retain: false, identity: false});
  assert.throws(() => checked(moon.obligationAppend(second, 1, columns)));
});

test('owned completed measurement can be charged again but never waives a consumer budget', () => {
  const stream = begin();
  checked(moon.obligationAppend(stream, 1, '[["3ff0000000000000"],["x"]]'));
  const summary = checked(moon.obligationFinish(stream))._5;
  const budget = checked(moon.obligationBudget(3, 10000, 1000, 10, 1000));
  assert.equal(moon.obligationReuseMeasurement(summary, budget), true);
  assert.equal(moon.obligationReuseMeasurement(summary, budget), false);
  assert.equal(moon.obligationReuseMeasurement(summary,
    checked(moon.obligationBudget(10, 10000, 1000, 10, 2))), false);
  const shared = checked(moon.obligationBudget(100, 10000, 1000, 10, 1000));
  begin({budget: shared});
  assert.throws(() => begin({budget: shared}));
  assert.equal(moon.obligationReuseMeasurement(summary, shared), false);
});

test('comparison demand is bound to a finished scan and discharges each consumer once', () => {
  const stream = begin({names: ['id'], kinds: [0], nullable: [true]});
  const demand = checked(moon.obligationComparison(stream, 'id', '[["0000000000000000"]]', 5,
    {max_work: 4, max_bytes: 8, max_nodes: 4, max_depth: 1}, false));
  const resolved = checked(moon.obligationComparison(stream, 'id', '[["0000000000000000"]]', 5,
    {max_work: 8, max_bytes: 8, max_nodes: 4, max_depth: 1}, true));
  assert.throws(() => checked(moon.obligationComparisonFinish(demand, 1)));
  checked(moon.obligationAppend(stream, 3, '[["3ff0000000000000",null,"bff0000000000000"]]'));
  assert.throws(() => checked(moon.obligationComparison(stream, 'id', '[["0000000000000000"]]', 5,
    {max_work: 4, max_bytes: 8, max_nodes: 4, max_depth: 1}, false)));
  checked(moon.obligationFinish(stream));
  const usage = checked(moon.obligationComparisonFinish(demand, 1));
  assert.equal(usage.rows, 3);
  assert.equal(usage.field_bytes, 7n);
  assert.equal(usage.predicate_bytes, 13n);
  assert.equal(usage.physical_work, 4);
  assert.equal(usage.physical_bytes, 8);
  assert.equal(checked(moon.obligationComparisonFinish(resolved, 1)).physical_work, 8);
  assert.throws(() => checked(moon.obligationComparisonFinish(demand, 1)));
});

test('future consumer demand failure does not retroactively fail its producer', () => {
  for (const work of [1, 100]) {
    const stream = begin({names: ['id'], kinds: [0], nullable: [false]});
    const demand = checked(moon.obligationComparison(stream, 'id', '[["0000000000000000"]]', 4,
      {max_work: work, max_bytes: 100, max_nodes: 100, max_depth: 1}, false));
    const text = checked(moon.obligationAppend(stream, 1, '[["3ff0000000000000"]]'));
    const receipt = checked(moon.obligationFinish(stream));
    assert.equal(text + receipt._0, '[{"id":1}]');
    assert.equal(receipt._1, hash('[{"id":1}]'));
    // With work=1 RHS measurement failed; otherwise a false predicate needs
    // five bytes, exceeding this consumer's four-byte limit.
    assert.throws(() => checked(moon.obligationComparisonFinish(demand, 0)));
    assert.throws(() => checked(moon.obligationComparisonFinish(demand, 0)));
  }
});

test('source record guards wait for complete admission, including invalid later batches', () => {
  for (const invalidTail of [false, true]) {
    const stream = begin({records: true, ceiling: 1});
    // The full record exceeds one byte, but it remains provisional: a later
    // source value must still be admitted before selecting the guard failure.
    checked(moon.obligationAppend(stream, 1, '[["3ff0000000000000"],["x"]]'));
    if (invalidTail) {
      assert.throws(() => checked(moon.obligationAppend(stream, 1,
        '[["7ff0000000000000"],["x"]]')));
    } else {
      checked(moon.obligationAppend(stream, 1, '[["4000000000000000"],["y"]]'));
    }
    assert.throws(() => checked(moon.obligationFinish(stream)));
    assert.throws(() => checked(moon.obligationFinish(stream)));
  }
});

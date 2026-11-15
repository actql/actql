import assert from 'node:assert/strict';
import test from 'node:test';
import {graphSourceSuccesses, graphSourceExecutionFailures} from './fixtures/graph-source-input.mjs';

test('WITH Graph core keeps parallel paths and NULL exclusion independent from typed empty output', () => {
  const cases = new Map(graphSourceSuccesses.map(item => [item.name, item]));
  for (const [mode, count] of [['walk', 4], ['default-walk', 4], ['trail', 2], ['acyclic', 0]]) {
    const input = cases.get('keyed-parallel-one-definition-' + mode);
    assert.equal(input.results.paths.rows.length, count);
    assert.deepEqual(input.results.paths.columns, [{name: 'depth', contract: {type: 'number', nullable: false}}]);
  }
  assert.deepEqual(cases.get('keyed-all-null-key-typed-empty').results.nodes,
    {rows: [], columns: [{name: 'id', contract: {type: 'number', nullable: true}}]});
  assert.equal(graphSourceExecutionFailures.length, 3, 'duplicate keys remain runtime failures');
});

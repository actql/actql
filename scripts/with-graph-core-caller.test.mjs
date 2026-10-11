import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {graphSourceSuccesses, graphSourceExecutionFailures, graphSourceRefusals} from './fixtures/graph-source-input.mjs';
import {relationDataSuccesses, relationDataRefusals} from './fixtures/public-query-input.mjs';
import {uniquePublicQueryCases} from './fixtures/public-query-cases.mjs';

const original = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/pre-with-graph-core-source-input.json', import.meta.url), 'utf8'));
// Compare authored obligations, including duplicate multiplicity, NULLs, complete
// ordered schemas and Source counts. No product output supplies these oracles.
test('WITH Graph core retains every original acceptance and failure obligation', () => {
  for (const [family, key, current] of [
    ['graph', 'successes', graphSourceSuccesses],
    ['graph', 'executionFailures', graphSourceExecutionFailures],
    ['graph', 'refusals', graphSourceRefusals],
    ['relation', 'successes', relationDataSuccesses],
    ['relation', 'refusals', relationDataRefusals],
  ]) {
    assert.equal(current.length, original[family][key].length);
    for (const input of current) {
      const previous = original[family][key].find(item => item.name === input.name);
      assert.ok(previous, input.name);
      const {text: oldText, ...oldObligations} = previous;
      const {text, ...obligations} = input;
      assert.deepEqual(obligations, oldObligations, input.name);
      if (input.format === 'json' || input.name === 'data-sql-format') {
        assert.equal(text, oldText, input.name);
      } else {
        assert.notEqual(text, oldText, input.name);
        assert.ok(text.startsWith('WITH '), input.name);
        assert.ok(!/\bDATA\b|PROPERTY GRAPH/.test(text), input.name);
      }
    }
  }
  assert.equal(uniquePublicQueryCases([...relationDataSuccesses, ...graphSourceSuccesses]).length, 42);
});

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

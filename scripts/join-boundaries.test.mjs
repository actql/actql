import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = new URL('../src/', import.meta.url);

// Conservative closure: include test imports too. The lower join package must
// never reach evidence or the upper facade through any repository dependency.
function closure(root) {
  const seen = new Set();
  const pending = [root];
  while (pending.length) {
    const name = pending.pop();
    if (seen.has(name)) continue;
    seen.add(name);
    const manifest = readFileSync(new URL(`${name}/moon.pkg`, source), 'utf8');
    for (const match of manifest.matchAll(/"actql\/actql\/([^"\n]+)"/g)) {
      pending.push(match[1]);
    }
  }
  return seen;
}

test('checked join shape remains below key evidence and as-of completion', () => {
  const lower = closure('relation_join_shape');
  assert.ok(lower.has('relation_key_obligation'));
  assert.ok(!lower.has('relation_evidence'));
  assert.ok(!lower.has('relation_join'));
  assert.ok(closure('relation_join').has('relation_evidence'));
  assert.ok(!closure('relation_evidence').has('relation_join'));
  assert.ok(!closure('graph_typing').has('relation_evidence'));
  assert.ok(!closure('vector_checking').has('relation_evidence'));
  assert.ok(!closure('vector_checking').has('vector_typing'));
  assert.ok(closure('relation_evidence').has('vector_checking'));
  assert.ok(!closure('relation_evidence').has('vector_typing'));
  assert.ok(closure('vector_typing').has('relation_evidence'));
  assert.deepEqual([...closure('relation_key_obligation')], ['relation_key_obligation']);
});

test('Graph input capacity admission remains below Program applications and consumer aggregation', () => {
  const input = closure('capacity_graph_input');
  assert.ok(input.has('capacity_host_witness'));
  assert.ok(input.has('capacity_witness'));
  for (const upper of ['capacity_program_step', 'capacity_graph_preflight', 'capacity_sequence_limit']) {
    assert.ok(!input.has(upper), `${upper} must not enter the input admission dependency closure`);
  }
  const facade = closure('capacity_graph_preflight');
  assert.ok(facade.has('capacity_graph_input'));
  assert.ok(facade.has('capacity_program_step'));
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {productionDependencyClosure} from './source-dependency-closure.mjs';

const source = new URL('../src/', import.meta.url);

// Check the production dependency direction. Explicit test composition is not
// a dependency of the installed checker; the existing scoped reader validates
// each import instead of treating every quoted package spelling as an edge.
const readManifest = name => readFileSync(new URL(`${name}/moon.pkg`, source), 'utf8');
function closure(root, read = readManifest) {
  return new Set([root, ...productionDependencyClosure(root, read)]);
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

test('scoped test composition cannot hide a direct or transitive production facade edge', () => {
  const actual = [...closure('relation_evidence')];
  for (const scope of ['test', 'wbtest']) {
    const read = name => readManifest(name) + (name === 'relation_evidence'
      ? `\nimport { "actql/actql/relation_join", } for "${scope}"\n` : '');
    assert.deepEqual([...closure('relation_evidence', read)], actual);
  }
  for (const owner of ['relation_evidence', 'check_environment']) {
    const read = name => readManifest(name) + (name === owner
      ? '\nimport { "actql/actql/relation_join", }\n' : '');
    const dependencies = closure('relation_evidence', read);
    assert.ok(dependencies.has('relation_join'), 'production facade edge remains visible');
    assert.throws(() => assert.ok(!dependencies.has('relation_join')), {code: 'ERR_ASSERTION'});
  }
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const contract = read('spec/contracts/actql-aoa.json');
const registry = read(contract.pipeline_registry_file);
const coverage = read(
  'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json',
);
const vectors = read('spec/operation-integration-vectors.json');
const language = readFileSync('docs/spec/language.md', 'utf8');

const expectedOperations = [
  'SGA.normalize',
  'SGA.match_nodes',
  'SGA.match_edges',
  'SGA.traverse',
  'SGA.shortest_path',
  'SGA.components',
  'SGA.reachable',
  'SGA.bounds_check',
  'SGA.degree_metrics',
  'SGA.diff',
  'SGA.graft',
  'SGA.union_structural',
  'SGA.diff_structural',
  'SGA.subgraph',
  'SGA.equal',
  'SGA.apply_delta',
  'SGA.mean_structural',
  'TEA.window.fixed_label',
  'TEA.window.sliding_assign',
  'TEA.watermark.label',
  'TEA.window.session_assign',
  'TEA.time_series',
  'TEA.join.interval',
  'TEA.dedupe',
  'TEA.join.asof',
  'TEA.sequence.match',
  'VEC.normalize_l2',
  'VEC.score_sort',
  'VEC.knn_join',
  'VEC.pool',
  'VEC.merge_rankings',
  'BRIDGE.rows.to_graph',
  'BRIDGE.graph.to_node_rows',
  'BRIDGE.graph.to_edge_rows',
  'BRIDGE.rows.to_events',
  'BRIDGE.events.to_rows',
  'BRIDGE.rows.to_vectors',
  'BRIDGE.vectors.to_rows',
];

test('the execution profile covers the fixed non-expression mother set', () => {
  const profile = contract.local_family_execution_profile;
  assert.equal(profile.version, 'actql-local-family-execution/0.1');
  assert.deepEqual(profile.registry_operations, expectedOperations);
  assert.equal(new Set(profile.registry_operations).size, expectedOperations.length);
  const fromCoverage = coverage.operations
    .filter(item => item.family !== 'VecAExpression')
    .flatMap(item => item.canonical);
  // Preserve the frozen legacy profile; the keyed constructor is a separately
  // admitted additive operation, never a replacement for rows.to_graph.
  assert.equal(fromCoverage.filter(operation =>
    operation === 'BRIDGE.rows.to_graph').length, 1);
  assert.deepEqual(fromCoverage.filter(operation =>
    operation !== 'BRIDGE.rows.to_graph'), expectedOperations);
  for (const operation of expectedOperations) {
    assert.ok(registry[operation], `missing registry operation ${operation}`);
  }
});

test('variable arities preserve one ordered typed occurrence', () => {
  assert.deepEqual(registry['SGA.traverse'], {
    input_alternatives: [['graph'], ['graph', 'relation']],
    output: 'relation',
  });
  assert.deepEqual(registry['SGA.shortest_path'], {
    input_alternatives: [
      ['graph'],
      ['graph', 'relation'],
      ['graph', 'relation', 'relation'],
    ],
    output: 'relation',
  });
  assert.deepEqual(registry['SGA.union_structural'], {
    finite_inputs: { repeated_input: 'graph', minimum_inputs: 2 },
    output: 'graph',
  });
  assert.deepEqual(registry['SGA.mean_structural'], {
    finite_inputs: { repeated_input: 'graph', minimum_inputs: 1 },
    output: 'graph',
  });
  assert.deepEqual(
    registry['VEC.merge_rankings'],
    contract.target_registry_requirements['VEC.merge_rankings'],
  );
  for (const operation of [
    'SGA.traverse',
    'SGA.shortest_path',
    'SGA.union_structural',
    'SGA.subgraph',
    'SGA.mean_structural',
    'VEC.merge_rankings',
  ]) {
    assert.deepEqual(
      registry[operation],
      contract.target_registry_requirements[operation],
      `${operation} selected and required signatures differ`,
    );
  }
  assert.deepEqual(contract.local_family_execution_profile.input_contract, {
    ordered: true,
    retain_repeated_positions: true,
    finite_list_is_one_occurrence: true,
    input_position_is_not_producer_port: true,
  });
});

test('newly required operations have exact carrier signatures', () => {
  for (const operation of [
    'SGA.subgraph',
    'SGA.equal',
    'SGA.mean_structural',
    'TEA.time_series',
    'TEA.join.interval',
  ]) {
    assert.deepEqual(
      registry[operation],
      contract.target_registry_requirements[operation],
      `${operation} selected and required signatures differ`,
    );
  }
  assert.deepEqual(registry['SGA.apply_delta'], {
    inputs: ['graph', 'relation'],
    output: 'graph',
  });
  assert.deepEqual(
    registry['SGA.apply_delta'],
    contract.target_registry_requirements['SGA.apply_delta'],
  );
});

test('profile obligations and laws are pinned to the selected contract', () => {
  const profile = contract.local_family_execution_profile;
  assert.deepEqual(profile.parameter_contract, {
    closed_checked_source_bodies: true,
    remove_bound_input_references: true,
    preserve_authored_list_order: true,
    no_runtime_layout_members: true,
  });
  assert.deepEqual(profile.required_obligations, [
    'typed_carrier_admission',
    'exact_input_binding',
    'operation_parameter_admission',
    'semantic_failure_order',
    'logical_resource_accounting',
    'physical_capacity_admission',
    'managed_generation_lifetime',
  ]);
  assert.deepEqual(profile.law_manifest_cids, {
    pipeline: contract.pipeline_law_manifest_cid,
    relation: contract.rela_primitive_law_manifest_cid,
    vector_numeric: contract.veca_numeric_law_manifest_cid,
    graph_structural: contract.sga_structural_law_manifest_cid,
    graph_identity: contract.sga_identity_law_manifest_cid,
  });
});

test('union vectors retain list positions without a canonical fold tree', () => {
  const cases = vectors.wiring.filter(item => item.operation === 'union_graphs');
  assert.equal(cases.length, 2);
  for (const item of cases) {
    assert.equal(item.expected.length, 1);
    assert.deepEqual(item.expected[0].in, ['a', 'b', 'a']);
    assert.equal(item.expected[0].id, item.operation_base);
  }
  assert.match(language, /Finite-list operations retain every authored input position/);
  assert.doesNotMatch(language, /emit the binary\s+union nodes as a left fold/);
});

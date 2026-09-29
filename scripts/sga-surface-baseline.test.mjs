import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {structuralToJson, jsonAdmissionDiagnostic} from
  '../_build/js/debug/build/aql_text_test_bridge/aql_text_test_bridge.js';
const fixture = name => readFileSync(new URL(
  `../spec/frontend/fixtures/sga-surface/${name}`, import.meta.url), 'utf8');

test('existing Graph OP source preserves shared producers and explicit Results', () => {
  const expected = fixture('reach-subgraph.expected-program.json');
  assert.equal(jsonAdmissionDiagnostic(expected), '');
  assert.deepEqual(JSON.parse(structuralToJson(fixture('reach-subgraph.op.aql'))),
    JSON.parse(expected));
});

test('named Graph calls retain the independently authored Program', () => {
  const expected = JSON.parse(fixture('reach-subgraph.expected-program.json'));
  assert.deepEqual(JSON.parse(structuralToJson(
    fixture('reach-subgraph.named.aql'))), expected);
});

test('Reach Relation selector resolves bare, quoted and DATA producers', () => {
  const source = fixture('reach-selector.named.aql');
  const expected = JSON.parse(fixture('reach-selector.expected-program.json'));
  assert.equal(jsonAdmissionDiagnostic(JSON.stringify(expected)), '');
  for (const text of [
    source,
    fixture('reach-selector.op.aql'),
    source.replace('from: seeds', 'from: nodes'),
    source.replace('DATA seeds = FROM nodes;',
      'DATA `seed list` = FROM nodes;').replace('from: seeds',
      'from: `seed list`'),
  ]) {
    assert.deepEqual(JSON.parse(structuralToJson(text)), expected);
  }
});

test('Reach selector rejects missing, forward and JSON-string references', () => {
  const source = fixture('reach-selector.named.aql');
  for (const text of [
    source.replace('from: seeds', 'from: missing'),
    source.replace('DATA seeds = FROM nodes;', '').replace(
      'RESULT answer =', 'DATA seeds = FROM nodes; RESULT answer ='),
    source.replace('from: seeds', 'from: "seeds"'),
  ]) {
    assert.equal(structuralToJson(text), '', text);
  }
});

test('components call and Relation SELECT preserve the authored Result', () => {
  const expected = fixture('components.expected-program.json');
  assert.equal(jsonAdmissionDiagnostic(expected), '');
  assert.deepEqual(JSON.parse(structuralToJson(fixture('components.named.aql'))),
    JSON.parse(expected));
});

test('Graph diff and apply retain base and Delta producer references', () => {
  const expected = fixture('diff-apply.expected-program.json');
  assert.equal(jsonAdmissionDiagnostic(expected), '');
  assert.deepEqual(JSON.parse(structuralToJson(fixture('diff-apply.named.aql'))),
    JSON.parse(expected));
});

test('mean_graphs retains explicit sample order and repeated producers', () => {
  const expected = fixture('mean-graphs.expected-program.json');
  assert.equal(jsonAdmissionDiagnostic(expected), '');
  assert.deepEqual(JSON.parse(structuralToJson(fixture('mean-graphs.named.aql'))),
    JSON.parse(expected));
});

test('graphs_equal reuses one Graph producer without adding a sort', () => {
  const expected = fixture('graphs-equal.expected-program.json');
  assert.equal(jsonAdmissionDiagnostic(expected), '');
  assert.deepEqual(JSON.parse(structuralToJson(
    fixture('graphs-equal.named.aql'))), JSON.parse(expected));
});

const envelope = body => `AQL '0.1'; PROGRAM 'roles' { STAGE s {
  INPUT g = {"carrier":"graph"}; INPUT target = {"carrier":"graph"};
  DATA output = ${body}; RESULT r = {"from":"output"};
  } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;

test('reference names and literal values retain different argument roles', () => {
  const reached = JSON.parse(structuralToJson(envelope(
    'FROM g |> reach(start: "target", direction: "out", max_depth: 2)')));
  assert.deepEqual(reached.stages[0].steps,
    [{from: 'g', reach: {start: 'target', direction: 'out', max_depth: 2},
      as: 'output'}]);
  const diff = JSON.parse(structuralToJson(envelope(
    'FROM g |> graph_diff(with: target)')));
  assert.deepEqual(diff.stages[0].steps,
    [{from: 'g', graph_diff: {with: 'target'}, as: 'output'}]);
  assert.equal(structuralToJson(envelope('FROM g |> graph_diff(with: "target")')), '');
});

test('Graph composition, Delta and explicit graph lists keep producer edges', () => {
  const body = `AQL '0.1'; PROGRAM 'roles' { STAGE s {
    INPUT g = {"carrier":"graph"}; INPUT target = {"carrier":"graph"};
    DATA groups = FROM g |> components(kind: "weak");
    DATA changes = FROM g |> graph_diff(with: target);
    DATA restored = FROM g |> apply_graph_delta(with: changes, field: "delta");
    DATA average = mean_graphs(with: [g, target, g], weights: [1, 2, 1],
      support: {nodes: 0.5, edges: 0.5},
      properties: {nodes: {}, edges: {}});
    DATA rows = FROM average |> node_rows();
    RESULT r = {"from":"rows"};
  } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
  const lowered = structuralToJson(body);
  assert.notEqual(lowered, '', 'named composition source should be admitted');
  const program = JSON.parse(lowered);
  assert.deepEqual(program.stages[0].steps, [
    {from: 'g', components: {kind: 'weak'}, as: 'groups'},
    {from: 'g', graph_diff: {with: 'target'}, as: 'changes'},
    {from: 'g', apply_graph_delta: {with: 'changes', field: 'delta'},
      as: 'restored'},
    {mean_graphs: {with: ['g', 'target', 'g'], weights: [1, 2, 1],
      support: {nodes: 0.5, edges: 0.5},
      properties: {nodes: {}, edges: {}}}, as: 'average'},
    {from: 'average', node_rows: true, as: 'rows'},
  ]);
});

test('closed named SGA vocabulary lowers to existing operation bodies', () => {
  const cases = [
    ['reach(start: "A", direction: "out", max_depth: 2)',
      {reach: {start: 'A', direction: 'out', max_depth: 2}}],
    ['traverse(start: {from: target, id: "id"}, direction: "out", max_hops: 2)',
      {traverse: {start: {from: 'target', id: 'id'},
        direction: 'out', max_hops: 2}}],
    ['shortest_path(source: {from: target, id: "id"}, target: {from: g, id: "id"}, max_hops: 2)',
      {shortest_path: {source: {from: 'target', id: 'id'},
        target: {from: 'g', id: 'id'}, max_hops: 2}}],
    ['components(kind: "weak")', {components: {kind: 'weak'}}],
    ['degree(direction: "both")', {degree: {direction: 'both'}}],
    ['graph_bounds(max_nodes: 3)', {graph_bounds: {max_nodes: 3}}],
    ['match_nodes(fields: ["id"])', {match_nodes: {fields: ['id']}}],
    ['match_edges(fields: ["src"])', {match_edges: {fields: ['src']}}],
    ['normalize_graph()', {normalize_graph: true}],
    ['subgraph(nodes: {from: target, id: "id"})',
      {subgraph: {nodes: {from: 'target', id: 'id'}}}],
    ['graft_graph(with: target)', {graft_graph: {with: 'target'}}],
    ['union_graphs(with: [target, g])',
      {union_graphs: {with: ['target', 'g']}}],
    ['subtract_graphs(with: target)', {subtract_graphs: {with: 'target'}}],
    ['graphs_equal(with: target)', {graphs_equal: {with: 'target'}}],
    ['graph_diff(with: target)', {graph_diff: {with: 'target'}}],
    ['apply_graph_delta(with: target, field: "delta")',
      {apply_graph_delta: {with: 'target', field: 'delta'}}],
    ['node_rows()', {node_rows: true}],
    ['edge_rows()', {edge_rows: true}],
  ];
  for (const [call, operation] of cases) {
    const program = structuralToJson(envelope(`FROM g |> ${call}`));
    assert.notEqual(program, '', call);
    assert.deepEqual(JSON.parse(program).stages[0].steps,
      [{...operation, from: 'g', as: 'output'}], call);
  }
  const mean = structuralToJson(envelope(
    'mean_graphs(with: [g, target], weights: [1, 1], ' +
    'support: {nodes: 0.5, edges: 0.5}, ' +
    'properties: {nodes: {}, edges: {}})'));
  assert.notEqual(mean, '');
  assert.deepEqual(JSON.parse(mean).stages[0].steps, [{
    mean_graphs: {with: ['g', 'target'], weights: [1, 1],
      support: {nodes: 0.5, edges: 0.5},
      properties: {nodes: {}, edges: {}}}, as: 'output',
  }]);
});

test('quoted producer spelling is resolved only at reference positions', () => {
  const source = `AQL '0.1'; PROGRAM 'quoted' { STAGE s {
    INPUT g = {"carrier":"graph"}; INPUT \`peer graph\` = {"carrier":"graph"};
    DATA changes = FROM g |> graph_diff(with: \`peer graph\`);
    RESULT r = {"from":"changes"};
  } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
  const program = JSON.parse(structuralToJson(source));
  assert.deepEqual(program.stages[0].steps,
    [{from: 'g', graph_diff: {with: 'peer graph'}, as: 'changes'}]);
});

test('quoted DATA aliases reuse one logical Graph producer', () => {
  const source = `AQL '0.1'; PROGRAM 'shared-graph' { STAGE s {
    INPUT g = {"carrier":"graph"};
    DATA \`peer graph\` = FROM g;
    DATA same = FROM \`peer graph\` |>
      graphs_equal(with: \`peer graph\`);
    RESULT r = {"from":"same"};
  } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
  const expected = {
    version: 'actql/0.1', id: 'shared-graph', stages: [{id: 's',
      inputs: {g: {carrier: 'graph'}},
      steps: [{from: 'g', graphs_equal: {with: 'g'}, as: 'same'}],
      results: {r: {from: 'same'}}}],
    results: {r: {from: {stage: 's', result: 'r'}}},
  };
  assert.deepEqual(JSON.parse(structuralToJson(source)), expected);
});

test('a quoted producer name stays literal in value and field positions', () => {
  const source = `AQL '0.1'; PROGRAM 'roles' { STAGE s {
    INPUT g = {"carrier":"graph"};
    DATA \`peer graph\` = FROM g;
    DATA reached = FROM g |>
      reach(start: "peer graph", direction: "out", max_depth: 1);
    DATA restored = FROM g |>
      apply_graph_delta(with: \`peer graph\`, field: "peer graph");
    RESULT r = {"from":"restored"};
  } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
  const program = JSON.parse(structuralToJson(source));
  assert.deepEqual(program.stages[0].steps, [
    {from: 'g', reach: {start: 'peer graph', direction: 'out',
      max_depth: 1}, as: 'reached'},
    {from: 'g', apply_graph_delta: {with: 'g', field: 'peer graph'},
      as: 'restored'},
  ]);
});

test('DATA scope rejects forward and duplicate Graph producers', () => {
  const source = declarations => `AQL '0.1'; PROGRAM 'scope' { STAGE s {
    INPUT g = {"carrier":"graph"};
    ${declarations}
    RESULT r = {"from":"output"};
  } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
  for (const declarations of [
    'DATA output = FROM later; DATA later = FROM g;',
    'DATA output = FROM g; DATA output = FROM g;',
    'DATA output = FROM g; DATA g = FROM output;',
    'DATA output = FROM later; DATA later = FROM output;',
  ]) {
    assert.equal(structuralToJson(source(declarations)), '', declarations);
  }
});

test('mean_graphs never adds a Pipe current Graph to its explicit list', () => {
  const namedArgs = 'with: [target], weights: [1], ' +
    'support: {nodes: 0.5, edges: 0.5}, ' +
    'properties: {nodes: {}, edges: {}}';
  assert.equal(structuralToJson(envelope(
    `FROM g |> mean_graphs(${namedArgs})`)), '');
  const generated = JSON.parse(structuralToJson(envelope(
    `mean_graphs(${namedArgs})`)));
  assert.deepEqual(generated.stages[0].steps, [{
    mean_graphs: {with: ['target'], weights: [1],
      support: {nodes: 0.5, edges: 0.5},
      properties: {nodes: {}, edges: {}}}, as: 'output',
  }]);
});

test('named Graph arguments reject duplicates and incomplete syntax', () => {
  for (const source of [
    'FROM g |> reach(start: "A", start: "B", direction: "out", max_depth: 2)',
    'FROM g |> graph_diff(with: target,)',
    'FROM g |> graph_diff(with: [target,])',
    'FROM g |> graph_diff(with: missing)',
    'FROM g |> reach(start: target, direction: "out", max_depth: 2)',
    'FROM g |> graph_diff(from: target, with: target)',
    'FROM g |> node_rows(,)',
    'FROM g |> unknown_graph(with: target)',
  ]) {
    assert.equal(structuralToJson(envelope(source)), '', source);
  }
});

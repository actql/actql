import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';

const readJson = path => JSON.parse(readFileSync(new URL(path,
  import.meta.url), 'utf8'));
const fixture = name => readJson(
  `../spec/frontend/fixtures/sga-surface/${name}.expected-program.json`);
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;

const {evidence_bundle_cid: ignored, ...baseEnvironment} = readJson(
  '../spec/local-check-environment.json');
void ignored;
baseEnvironment.host_policy_profile = {...baseEnvironment.host_policy_profile,
  capacity: {...baseEnvironment.host_policy_profile.capacity,
    max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000}};
const environment = {...baseEnvironment,
  evidence_bundle_cid: cid(baseEnvironment)};
const numericProfile = readJson('../spec/contracts/actql-numeric-reduction.json');
const owner = moon.clientProgramCheckEnvironmentWithNumericProfile(
  canonicalText(environment), environment.evidence_bundle_cid,
  false, false, true, true, false, false, false, cid(numericProfile));
assert.ok(owner, 'the installed Local Check Environment is admitted');

const prepare = program => moon.clientProgramPrepareEffectFreeWithParameters(
  canonicalText(program), 'json', owner, undefined);

test('named SGA Programs pass common preparation without a new checker', () => {
  for (const name of ['components', 'reach-subgraph', 'diff-apply',
    'mean-graphs', 'graphs-equal', 'normalize-rows', 'degree-rows',
    'shortest-path',
    'graph-bounds', 'traverse-paths', 'union-graphs', 'graft-graphs',
    'subtract-graphs', 'match-projections']) {
    const outcome = prepare(fixture(name));
    assert.ok(moon.clientProgramPreparationReady(outcome),
      `${name}: ${String(moon.clientProgramPreparationIssueCode(outcome))}`);
  }
});

test('intermediate Graph delta Result retains its own task output', () => {
  const program = fixture('diff-apply');
  program.stages[0].steps = program.stages[0].steps.slice(0, 7);
  program.stages[0].steps.push(
    {from: 'changes', select: ['delta'], as: 'delta_out'});
  program.stages[0].results = {
    changes: {from: 'changes', fields: ['delta']},
    selected: {from: 'delta_out', fields: ['delta']},
  };
  program.results = {
    changes: {from: {stage: 'main', result: 'changes'}},
    selected: {from: {stage: 'main', result: 'selected'}},
  };
  const outcome = prepare(program);
  const ready = moon.clientProgramPreparationReady(outcome);
  assert.ok(ready, String(moon.clientProgramPreparationIssueCode(outcome)));
  assert.equal(moon.clientProgramTaskCount(ready), 8);
  const compiled = moon.clientProgramCompileLocalTasks(ready);
  assert.equal(compiled.$tag, 1);
  const plan = JSON.parse(moon.clientProgramTaskCompilationPlanWire(compiled._0));
  assert.deepEqual(plan.nodes.map(node => node.pipeline.output),
    ['values_0', 'values_1', 'values_2', 'values_3', 'graph_4',
      'graph_5', 'graph_diff_6', 'select_7']);
  assert.deepEqual(plan.data_edges.filter(edge =>
    ['task_6', 'task_7'].includes(edge.to.node_id)).map(edge =>
      [edge.carrier, edge.from, edge.to]), [
    ['graph', {node_id: 'task_4', port: 'graph_4'},
      {node_id: 'task_6', port: 'input_0'}],
    ['graph', {node_id: 'task_5', port: 'graph_5'},
      {node_id: 'task_6', port: 'input_1'}],
    ['relation', {node_id: 'task_6', port: 'graph_diff_6'},
      {node_id: 'task_7', port: 'input_0'}],
  ]);
  assert.deepEqual(plan.root_refs.map(root => [root.name, root.ref]), [
    ['changes', {node_id: 'task_6', port: 'graph_diff_6'}],
    ['selected', {node_id: 'task_7', port: 'select_7'}],
  ]);
  assert.equal(plan.nodes[7].pipeline.steps.length, 1);
});

test('terminal Graph-to-Relation path selects bounded task providers', () => {
  const program = fixture('normalize-rows');
  program.id = 'sga.terminal_relation_tasks';
  program.stages[0].steps = [
    ...program.stages[0].steps.slice(0, 2),
    {values: {schema: {id: {type: 'string', nullable: false}},
      rows: [{id: 'A'}]}, as: 'seeds'},
    program.stages[0].steps[2],
    {from: 'g', traverse: {start: {from: 'seeds', id: 'id'},
      direction: 'out', min_hops: 1, max_hops: 2,
      max_output_rows: 4, emit: 'paths'}, as: 'paths'},
  ];
  program.stages[0].results = {answer: {from: 'paths',
    fields: ['start_id', 'end_id', 'hop_count', 'node_ids', 'edge_ids']}};
  const outcome = prepare(program);
  const ready = moon.clientProgramPreparationReady(outcome);
  assert.ok(ready, String(moon.clientProgramPreparationIssueCode(outcome)));
  assert.equal(moon.clientProgramTaskCount(ready), 5);
  const compiled = moon.clientProgramCompileLocalTasks(ready);
  assert.equal(compiled.$tag, 1);
  const plan = JSON.parse(moon.clientProgramTaskCompilationPlanWire(compiled._0));
  assert.deepEqual(plan.nodes.map(node => node.pipeline.output),
    ['values_0', 'values_1', 'values_2', 'graph_3', 'traverse_4']);
  assert.deepEqual(plan.root_refs.map(root => [root.name, root.ref]), [
    ['answer', {node_id: 'task_4', port: 'traverse_4'}],
  ]);
});

test('a Relation cannot enter a Graph-only named operation', () => {
  const program = fixture('normalize-rows');
  program.stages[0].steps.splice(4, 2,
    {from: 'normalized', node_rows: true, as: 'relation'},
    {from: 'relation', normalize_graph: true, as: 'invalid'});
  program.stages[0].results.answer = {from: 'invalid'};
  const outcome = prepare(program);
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(outcome),
    'check_invalid_input');
  assert.ok(moon.clientProgramPreparationIssue(outcome));
});

test('graph_bounds requires an authored bound in common preparation', () => {
  const program = fixture('graph-bounds');
  program.stages[0].steps[3].graph_bounds = {};
  const outcome = prepare(program);
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(outcome),
    'check_invalid_input');
  assert.ok(moon.clientProgramPreparationIssue(outcome));
});

test('invalid shortest path bounds retain a definitive input rejection', () => {
  const program = fixture('shortest-path');
  program.stages[0].steps.at(-1).shortest_path.max_hops = 0;
  const outcome = prepare(program);
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(outcome),
    'check_invalid_input');
  assert.ok(moon.clientProgramPreparationIssue(outcome));
});

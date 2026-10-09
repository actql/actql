import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphTraverseHopProgram, graphTraversePathSuccesses, graphTraversePathRefusals}
  from './fixtures/graph-traverse-path-source-input.mjs';
import {graphTraverseSourceRefusals} from './fixtures/graph-traverse-source-input.mjs';

test('typed hop control retains two filters, path mode and exact output bound', () => {
  assert.deepEqual(graphTraverseHopProgram.stages[0].steps[6].traverse, {
    start: {from: 'seeds', id: 'element'},
    hops: [{direction: 'out', edge_types: ['R'], node_where: {literal: true}},
      {direction: 'out', edge_where: {literal: true}}],
    path_mode: 'trail', emit: 'paths', max_output_rows: 10,
  });
  const control = graphTraversePathSuccesses.find(item => item.name.endsWith('hop-vocabulary-json-control'));
  assert.deepEqual(JSON.parse(control.text), graphTraverseHopProgram);
  assert.deepEqual(control.results.paths.rows.map(row => row.edge_ids.map(cell => cell.$json.key[0])),
    [[10, 11], [11, 10]]);
});

test('nonempty path and node oracles preserve identity multiplicity and minimum eligible depth', () => {
  const byName = new Map(graphTraversePathSuccesses.map(item => [item.name, item]));
  const paths = byName.get('graph-traverse-hop-vocabulary-uppercase-paths').results.paths;
  assert.deepEqual(paths.rows.map(row => row.edge_ids.map(cell => cell.$json.key[0])), [[10, 11], [11, 10]]);
  const nodes = byName.get('graph-traverse-hop-vocabulary-uppercase-nodes').results.nodes;
  assert.deepEqual(nodes.columns.map(column => column.name), ['start_id', 'node_id', 'depth']);
  assert.equal(nodes.rows.length, 1);
  assert.equal(nodes.rows[0].depth, 2);
  for (const name of ['empty-labels', 'false-predicate']) {
    assert.deepEqual(byName.get('graph-traverse-hop-vocabulary-' + name).results.paths.rows, []);
  }
  assert.ok(graphTraversePathSuccesses.every(item => item.sourceReadCount === 0));
});

test('case-folded vocabulary refuses collisions without folding values or weakening closed modes', () => {
  const cases = graphTraversePathRefusals.filter(item => item.name.includes('hop-vocabulary-refuse-'));
  assert.equal(cases.length, 5);
  assert.ok(cases.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(cases.some(item => item.text.includes("DIRECTION: 'OUT'")));
  assert.ok(cases.some(item => item.text.includes('EXTRA: true')));
  assert.equal(new Set([...graphTraversePathSuccesses, ...graphTraversePathRefusals]
    .map(item => item.name)).size, graphTraversePathSuccesses.length + graphTraversePathRefusals.length);
});

test('normal and narrow packed consumers both include the same unchanged traversal groups', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...graphTraversePathSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...graphTraversePathRefusals)'));
  assert.ok(fixture.includes('graphTraversePathsOnly ? {successes: [...graphTraverseSourceSuccesses, ...graphTraversePathSuccesses]'));
});

test('existing unavailable traversal emissions retain their exact lowerer refusal category', () => {
  const names = ['graph-traverse-unknown-emission', 'graph-traverse-paths-missing-emission',
    'graph-traverse-paths-unknown-emission', 'graph-traverse-paths-parameter-emission'];
  const refusals = new Map([...graphTraverseSourceRefusals, ...graphTraversePathRefusals]
    .map(item => [item.name, item]));
  for (const name of names) assert.equal(refusals.get(name).expectedCode, 'ClientProgramImplementationLimit');
});

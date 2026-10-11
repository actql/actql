import assert from 'node:assert/strict';
import test from 'node:test';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {PlanExplorer} from './dist/plan-explorer.js';
import {flowPresentation} from './flow-model.mjs';

// Independently authored presentation fixture. It does not prove Host admission
// or actual Provider execution; the public SDK/read-model boundaries own those.
const cid = n => `sha256:${n.repeat(64)}`;
function fixture() {
  const producer = cid('1'), join = cid('2'), out = cid('3');
  const port = (id, role, ordinal, source) => ({port_id: cid(id), role,
    port_ordinal: ordinal, carrier: 'relation', carrier_contract_cid: cid('a'), source});
  const source = {kind: 'logical_output', step_id: producer, output_port_id: out};
  return {observation: 'static', providerIO: 0, compiledPlanCid: cid('b'),
    logicalMapCid: cid('c'), programDefinitionCid: cid('d'),
    sourceOrigins: {state: 'unavailable', reason: 'not_in_projection'},
    nodes: [{id: producer, names: ['e\u0301\r\n<script>alert(1)</script>'],
      operator: 'values', kind: 'operation', key: {}, ports: [port('3', 'output', 0, source)]},
    {id: join, names: ['Join'], operator: 'join', kind: 'operation', key: {},
      ports: [port('4', 'input', 0, source), port('5', 'input', 1, source)]}],
    inputs: [], edges: [0, 1].map(ordinal => ({id: cid(ordinal ? '5' : '4'),
      sourceStepId: producer, sourcePortId: out, targetStepId: join,
      targetPortId: cid(ordinal ? '5' : '4'), targetPortOrdinal: ordinal}))};
}
test('Flow retains both Join input roles and exact original handles', () => {
  const model = fixture(), flow = flowPresentation(model);
  assert.deepEqual(flow.edges.map(e => [e.id, e.sourceHandle, e.targetHandle, e.label]),
    [[cid('4'), cid('3'), cid('4'), 'input 0'], [cid('5'), cid('3'), cid('5'), 'input 1']]);
  assert.deepEqual(flow.nodes.map(n => n.id), [cid('1'), cid('2')]);
  assert(flow.nodes.every(n => !n.draggable && !n.connectable && !n.deletable));
  assert(flow.edges.every(e => !e.deletable));
  assert.equal(flow.nodes[0].data.original.names[0], 'e\u0301\r\n<script>alert(1)</script>');
});
test('array reversal changes presentation positions, not original edges', () => {
  const model = fixture(), expected = flowPresentation(model).edges;
  model.nodes.reverse();
  assert.deepEqual(flowPresentation(model).edges, expected);
});
test('Stage locator remains unresolved and does not become another node or edge', () => {
  const model = fixture(), input = model.nodes[1].ports[0];
  input.source = {kind: 'stage_input', stage_ordinal: 7, input_port_ordinal: 3};
  model.edges.shift(); model.inputs.push({stepId: model.nodes[1].id,
    inputPortId: input.port_id, locator: {...input.source}});
  const flow = flowPresentation(model);
  assert.equal(flow.nodes.length, 2); assert.equal(flow.edges.length, 1);
  model.inputs[0].locator.input_port_ordinal = 4;
  assert.throws(() => flowPresentation(model), {code: 'ExplorerInvalidPresentation'});
});
for (const mutate of [m => {m.edges[0].sourcePortId = cid('f');},
  m => {m.edges[0].targetPortOrdinal = 1;}, m => {m.edges.push(m.edges[0]);},
  m => {m.nodes[1].ports[0].carrier_contract_cid = cid('f');},
  m => {m.edges.shift();}, m => {m.nodes.push(m.nodes[0]);}]) {
  test('invalid, duplicated or missing original port refuses without synthetic repair', () => {
    const model = fixture(); mutate(model);
    assert.throws(() => flowPresentation(model), {code: 'ExplorerInvalidPresentation'});
  });
}
test('finite graph limit refuses instead of silently truncating', () => {
  const model = fixture(); model.nodes = Array(257).fill(model.nodes[0]);
  assert.throws(() => flowPresentation(model), {code: 'ExplorerInvalidPresentation'});
});
test('real React render escapes source text and labels unavailable controls without a Run', () => {
  const html = renderToStaticMarkup(createElement(PlanExplorer, {model: fixture(), scopeKey: 'scope-a'}));
  assert(html.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
  assert(!html.includes('<script>')); assert(html.includes('e\u0301\r\n'));
  assert(html.includes('Original logical occurrences')); assert(html.includes(cid('1')));
  assert(html.includes('Controls, Samples and physical observations are unavailable'));
  assert(!html.includes('Pause')); assert(!html.includes('Approve')); assert(!html.includes('Run ID'));
});
test('different supplied scopes and Plans render only their own data', () => {
  const old = fixture(), current = fixture(); current.nodes[0].names = ['current only'];
  const html = renderToStaticMarkup(createElement(PlanExplorer, {model: current, scopeKey: 'scope-b'}));
  assert(html.includes('current only')); assert(!html.includes('&lt;script&gt;'));
  assert.equal(old.nodes[0].names[0], 'e\u0301\r\n<script>alert(1)</script>');
});

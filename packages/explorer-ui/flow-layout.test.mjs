import assert from 'node:assert/strict';
import test from 'node:test';
import ELK from 'elkjs/lib/elk.bundled.js';
import {layoutInput, elkGraph, layoutPositions, flowNodeWidth, flowNodeHeight,
  flowLayoutDeadlineMs} from './flow-layout-engine.mjs';
import {requestFlowLayout} from './flow-layout.mjs';

// Independent topology, not an execution graph or a Plan admission fixture.
function fixture() {
  const port = (id, role) => ({port_id: id, role, secret: 'not-layout-data'});
  return {nodes: [
    {id: 'values', data: {original: {ports: [port('out', 'output')], names: ['private label']}}},
    {id: 'join', data: {original: {ports: [port('left', 'input'), port('right', 'input'), port('result', 'output')]}}},
    {id: 'readback', data: {original: {ports: [port('input', 'input')]}}},
  ], edges: [
    {id: 'left', source: 'values', sourceHandle: 'out', target: 'join', targetHandle: 'left'},
    {id: 'right', source: 'values', sourceHandle: 'out', target: 'join', targetHandle: 'right'},
    {id: 'input', source: 'join', sourceHandle: 'result', target: 'readback', targetHandle: 'input'},
  ]};
}
function worker() {
  return {onmessage: null, onerror: null, terminations: 0, message: undefined,
    postMessage(message) {this.message = message;}, terminate() {this.terminations++;}};
}
function reply(w, positions = w.message.graph.children.map((n, i) => ({id: n.id, x: i * 400, y: 0}))) {
  w.onmessage({data: {id: w.message.id, data: {children: positions}}});
}
test('Worker input contains only bounded original IDs, port roles and real edges', () => {
  const flow = fixture(), snapshot = structuredClone(flow), input = layoutInput(flow);
  assert.deepEqual(input.nodes[0], {id: 'values', ports: [{id: 'out', role: 'output'}]});
  assert.deepEqual(input.edges, [
    {id: 'left', source: 'out', target: 'left'}, {id: 'right', source: 'out', target: 'right'},
    {id: 'input', source: 'result', target: 'input'}]);
  assert(!JSON.stringify(input).includes('private label'));
  assert(!JSON.stringify(input).includes('secret'));
  assert.deepEqual(flow, snapshot);
});
test('real ELK retains parallel Join ports, original topology and disjoint bounded rectangles', async () => {
  const input = layoutInput(fixture()), graph = elkGraph(input), before = structuredClone(graph);
  assert.deepEqual(graph.children[1].ports.map(p => [p.id, p.x, p.y]),
    [['port:left', 0, 28], ['port:right', 0, 46], ['port:result', 260, 64]]);
  const actual = await new ELK().layout(graph), points = layoutPositions(input, actual);
  assert.deepEqual(points.map(p => p.id), ['values', 'join', 'readback']);
  assert(points[0].x < points[1].x && points[1].x < points[2].x);
  assert.deepEqual(actual.edges.map(e => [e.id, e.sources, e.targets]),
    before.edges.map(e => [e.id, e.sources, e.targets]));
  for (let i = 0; i < points.length; i++) for (let j = i + 1; j < points.length; j++) {
    const a = points[i], b = points[j];
    assert(a.x + flowNodeWidth <= b.x || b.x + flowNodeWidth <= a.x ||
      a.y + flowNodeHeight(input.nodes[i].ports.length) <= b.y ||
      b.y + flowNodeHeight(input.nodes[j].ports.length) <= a.y);
  }
});
test('exact graph limits are admitted, one more step or port refuses without truncation', () => {
  const flow = {nodes: Array.from({length: 256}, (_, i) => ({id: `n${i}`, data: {original: {
    ports: Array.from({length: 4}, (_, j) => ({port_id: `p${i}-${j}`, role: 'output'}))}}})), edges: []};
  assert.equal(elkGraph(layoutInput(flow)).children.length, 256);
  flow.nodes[0].data.original.ports.push({port_id: 'overflow', role: 'output'});
  assert.throws(() => layoutInput(flow), {code: 'ExplorerInvalidLayout'});
  flow.nodes[0].data.original.ports.pop();
  flow.nodes.push({id: 'extra', data: {original: {ports: []}}});
  assert.throws(() => layoutInput(flow), {code: 'ExplorerInvalidLayout'});
});
for (const mutate of [f => {f.nodes.push(f.nodes[0]);},
  f => {f.nodes[1].data.original.ports[0].port_id = 'out';},
  f => {f.edges[0].targetHandle = 'result';}, f => {f.edges[0].source = 'join';},
  f => {f.edges.push(f.edges[0]);}, f => {f.nodes[0].id = '';},
]) test('malformed original topology refuses; layout creates no inferred repairs', () => {
  const f = fixture(); mutate(f);
  assert.throws(() => layoutInput(f), {code: 'ExplorerInvalidLayout'});
});
for (const children of [[], [{id: 'node:foreign', x: 0, y: 0}],
  [{id: 'node:values', x: NaN, y: 0}], [{id: 'node:values', x: Infinity, y: 0}],
  [{id: 'node:values', x: '0', y: 0}],
  [{id: 'node:values', x: 0, y: 0}, {id: 'node:values', x: 1, y: 1}, {id: 'node:readback', x: 2, y: 2}],
]) test('incomplete, foreign or invalid placement cannot replace original nodes', () => {
  const complete = children.length === 1 && children[0].id === 'node:values'
    ? [...children, {id: 'node:join', x: 400, y: 0}, {id: 'node:readback', x: 800, y: 0}] : children;
  assert.throws(() => layoutPositions(layoutInput(fixture()), {children: complete}), {code: 'ExplorerInvalidLayout'});
});
test('successful Worker response returns positions only and terminates once', async () => {
  const w = worker(), promise = requestFlowLayout(fixture(), {createWorker: () => w});
  const points = w.message.graph.children.map(n => ({id: n.id, x: 10, y: 20, secret: 'discard'}));
  reply(w, points);
  assert.deepEqual(await promise, points.map(({id, x, y}) => ({id: id.slice(5), x, y})));
  assert.equal(w.terminations, 1); assert.equal(w.onmessage, null);
});
test('scope abort retires its Worker and captured delayed response cannot publish', async () => {
  const w = worker(), controller = new AbortController();
  const promise = requestFlowLayout(fixture(), {signal: controller.signal, createWorker: () => w});
  const delayed = w.onmessage, id = w.message.id;
  controller.abort();
  delayed({data: {id, data: {children: []}}});
  await assert.rejects(promise, {code: 'ExplorerLayoutAborted'});
  assert.equal(w.terminations, 1);
  const fresh = worker(), next = requestFlowLayout(fixture(), {createWorker: () => fresh});
  fresh.onmessage({data: {id: 999, data: {children: []}}});
  assert.equal(fresh.terminations, 0);
  reply(fresh); assert.equal((await next).length, 3);
});
test('Worker error, unavailable or malformed response refuses and retires original Worker', async () => {
  for (const fail of [w => w.onerror(),
    w => w.onmessage({data: {id: w.message.id, error: {message: 'layout unavailable'}}}),
    w => reply(w, [{id: 'foreign', x: 0, y: 0}])]) {
    const w = worker(), promise = requestFlowLayout(fixture(), {createWorker: () => w});
    fail(w); await assert.rejects(promise); assert.equal(w.terminations, 1);
  }
});
test('presentation deadline terminates only its layout Worker', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  const w = worker(), promise = requestFlowLayout(fixture(), {createWorker: () => w});
  const rejected = assert.rejects(promise, {code: 'ExplorerLayoutUnavailable'});
  t.mock.timers.tick(flowLayoutDeadlineMs - 1); assert.equal(w.terminations, 0);
  t.mock.timers.tick(1); await rejected; assert.equal(w.terminations, 1);
});
test('already aborted or empty input creates no Worker', async () => {
  const c = new AbortController(); c.abort();
  const createWorker = () => {throw new Error('must not create');};
  await assert.rejects(requestFlowLayout(fixture(), {signal: c.signal, createWorker}), {code: 'ExplorerLayoutAborted'});
  assert.deepEqual(await requestFlowLayout({nodes: [], edges: []}, {createWorker}), []);
});

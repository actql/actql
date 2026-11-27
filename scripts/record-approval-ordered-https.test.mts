import assert from 'node:assert/strict';
import {request} from 'node:https';
import test from 'node:test';
import {openRecordApprovalExchange} from './fixtures/record-approval/installed.fixture.mjs';
import {recordApprovalOrderedMockProject} from './fixtures/record-approval/mock-project.mjs';
import {createOrderedRecordApprovalProviderState} from './fixtures/record-approval/provider-state.mjs';
import {admitAuthoredRecordApprovalCase} from './fixtures/record-approval/workflow.mjs';

const a = {id: '9007199254740993', note: 'old'};
const b = {id: '9007199254740994'};
const newer = {id: 'new-key', note: 'new'};
const leftControl = {id: 'keep-left', note: 'left'};
const rightControl = {id: 'keep-right', note: 'right'};
const resources = ['Left', 'Right'] as const;
const before = {fixture: {Left: {key: ['id'], rows: [a, leftControl]}, Right: {key: ['id'], rows: [b, rightControl]}}};
const after = {fixture: {Left: {key: ['id'], rows: [{...a, note: null}, leftControl, newer]},
  Right: {key: ['id'], rows: [rightControl]}}};

function orderedCase() {
  const catalog = {connections: {fixture: {
    data: resources.map(resource => ({resource, items_path: ['fixture', resource, 'rows'],
      key_path: ['fixture', resource, 'key'], primary_identity: 'id'})),
    writes: [{resource: 'Left', primary_identity: 'id', operation: 'update'},
      {resource: 'Right', primary_identity: 'id', operation: 'delete'},
      {resource: 'Left', primary_identity: 'id', operation: 'upsert'}],
  }}};
  const wire = JSON.stringify;
  const parts = {document: 'SELECT 1', format: 'sql', resultName: 'main', parameterDeclarations: {}, parameters: {}};
  return admitAuthoredRecordApprovalCase({
    name: 'ordered transport component', effect: {...parts, expectedRows: []}, read: {...parts, beforeRows: [], afterRows: []},
    review: {effects: [
      {effectId: 'edit', kind: 'update', target: 'connector://fixture/Left',
        rows: [{identity: a.id, before: a, changes: {note: null}}]},
      {effectId: 'remove', kind: 'delete', target: 'connector://fixture/Right',
        rows: [{identity: b.id, before: b}]},
      {effectId: 'insert', kind: 'upsert', target: 'connector://fixture/Left',
        rows: [{identity: newer.id, before: null, changes: newer}]},
    ]},
    collection: {connection: 'fixture', expectedWrites: 3, expectedData: wire(after),
      controls: [{resource: 'Left', key: [leftControl.id]}, {resource: 'Right', key: [rightControl.id]}],
      projectFiles: {
        'actql.config.json': wire({version: 'actql-config/0.1', profile: 'mock', connectors: './connectors.json',
          state_dir: './.actql', mock: {catalog: './mock/catalog.json', data: './mock/data.json', answers: {}}}),
        'connectors.json': wire({connections: {fixture: {connector: 'fixture'}}}),
        'mock/catalog.json': wire(catalog), 'mock/data.json': wire(before),
      }},
  });
}

type Fault = NonNullable<Parameters<typeof openRecordApprovalExchange>[1]['faults']>[number];
type Tls = Awaited<ReturnType<typeof openRecordApprovalExchange>>;
function exchange(tls: Tls, method: string, pathname: string, body?: unknown) {
  return new Promise<{status: number; body: unknown}>((resolve, reject) => {
    const wire = body === undefined ? '' : JSON.stringify(body);
    const sent = request(new URL(pathname, tls.origin), {method, ca: tls.ca, agent: false,
      headers: {authorization: 'fixture-test', 'content-length': Buffer.byteLength(wire)}}, response => {
      const chunks: Buffer[] = [];
      response.on('data', (data: Buffer) => chunks.push(data));
      response.once('error', reject);
      response.once('end', () => resolve({
        status: response.statusCode!, body: JSON.parse(Buffer.concat(chunks).toString('utf8')),
      }));
    });
    sent.once('error', reject);
    sent.setTimeout(3000, () => sent.destroy(new Error('Fixture HTTPS response timeout')));
    sent.end(wire);
  });
}

const writes = [
  {method: 'PATCH', pathname: '/rows/Left', body: {key: [a.id], row: {...a, note: null}}},
  {method: 'DELETE', pathname: '/rows/Right', body: {key: [b.id], row: null}},
  {method: 'POST', pathname: '/rows/Left', body: {key: [newer.id], row: newer}},
] as const;

async function fixture(fault?: Fault) {
  const plan = recordApprovalOrderedMockProject(orderedCase(), 'fixture');
  const state = createOrderedRecordApprovalProviderState(plan);
  const routes = writes.map((write, index) => {
    const resource = index === 1 ? 'Right' : 'Left';
    return state.route(write.method, write.pathname, incoming => {
      const {key, row} = JSON.parse(incoming.body);
      return state.apply(resource, key, (['update', 'delete', 'create'] as const)[index], row);
    });
  });
  routes.push(state.route('GET', '/rows/Left', incoming => {
    assert(incoming.query.page === '1' || incoming.query.page === '2');
    const first = incoming.query.page === '1';
    const rows = state.snapshot().rows.find(resource => resource.resource === 'Left')!.rows;
    return {rows: first ? rows.slice(0, 1) : rows.slice(1), next: first && rows.length > 1 ? '2' : null};
  }));
  const tls = await openRecordApprovalExchange(undefined, {provider: {routes}, faults: fault === undefined ? [] : [fault]});
  return {tls, state, plan};
}

test('the same typed case preserves original row order across Mock and real loopback HTTPS', async () => {
  const {tls, state, plan} = await fixture();
  try {
    assert.deepEqual(plan.writes.map(write => [write.resource, write.operation]),
      [['Left', 'update'], ['Right', 'delete'], ['Left', 'create']]);
    assert.deepEqual(await exchange(tls, 'GET', '/rows/Left?page=1'), {status: 200, body: {rows: [a], next: '2'}});
    assert.deepEqual(await exchange(tls, 'GET', '/rows/Left?page=2'), {status: 200, body: {rows: [leftControl], next: null}});
    assert.equal(state.snapshot().writes, 0);
    for (const write of writes) assert.equal((await exchange(tls, write.method, write.pathname, write.body)).status, 200);
    const recorded = state.snapshot();
    assert.equal(recorded.writes, plan.approvedWrites);
    assert.deepEqual(recorded.rows, plan.resources.map(resource => ({resource: resource.resource, rows: resource.after})));
    assert.deepEqual(recorded.failures, []);
    assert.deepEqual(tls.seen().filter(item => item.method !== 'GET').map(item => item.method), ['PATCH', 'DELETE', 'POST']);
  } finally {
    await tls.close();
  }
});

test('an out-of-order HTTPS request records the typed refusal and changes no row', async () => {
  const {tls, state} = await fixture();
  try {
    const second = writes[1];
    await assert.rejects(exchange(tls, second.method, second.pathname, second.body), {code: 'ECONNRESET'});
    const observed = state.snapshot();
    assert.equal(tls.seen().length, 1);
    assert.equal(observed.writes, 0);
    assert.deepEqual(observed.failures, [{
      name: 'AssertionError', code: 'ERR_ASSERTION', message: 'Unexpected original ordered HTTPS write',
    }]);
    assert.deepEqual(observed.rows, resources.map(resource => ({resource, rows: before.fixture[resource].rows})));
  } finally {
    await tls.close();
  }
});

test('ordered HTTPS observes rate limit and applied reply loss as separate finite cases', async () => {
  for (const fault of [
    {kind: 'reply', reply: {status: 429, body: {limited: true}}},
    {kind: 'apply-then-lose-reply'},
  ] as const) {
    const first = writes[0];
    const {tls, state} = await fixture({method: first.method, pathname: first.pathname, ...fault});
    try {
      const request = exchange(tls, first.method, first.pathname, first.body);
      if (fault.kind === 'reply') assert.deepEqual(await request, {status: 429, body: {limited: true}});
      else await assert.rejects(request, {code: 'ECONNRESET'});
      const observed = state.snapshot();
      assert.equal(observed.writes, fault.kind === 'reply' ? 0 : 1);
      assert.equal(tls.remainingFaults(), 0);
      assert.equal(tls.seen().length, 1);
      assert.deepEqual(observed.rows[0].rows, fault.kind === 'reply' ? [a, leftControl] : [{...a, note: null}, leftControl]);
      assert.deepEqual(observed.rows[1].rows, [b, rightControl]);
    } finally {
      await tls.close();
    }
  }
});

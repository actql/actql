import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {residentSourceEnvironment} from '../../scripts/fixtures/resident-source.mjs';
import {admitEnvironment, prepare, compileTasks, taskExecutionShape, taskKeys,
  issueAllowedTaskRun, issueTaskRunDefinition, privateRunDefinition,
  prepareRetainedTaskInputEdge, retainedTaskInputEdgeFacts, taskInputBinding}
  from './index.mjs';

// The ordinary two-stage Program has one checked Source producer and one
// dependent Compute consumer. Expected physical schema is authored separately.
const document = JSON.stringify({version: 'actql/0.1',
  id: 'retained-source-compute', stages: [{id: 'acquire',
    inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > 0', as: 'filtered'},
      {select: ['id'], as: 'captured'}],
    results: {rows: {from: 'captured', fields: ['id']}}},
  {id: 'compute', inputs: {input: {result: {stage: 'acquire', result: 'rows'}}},
    steps: [{filter: 'id > 2', as: 'filtered'},
      {select: ['id'], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'compute', result: 'rows'}}}});
const cid = fill => `sha256:${fill.repeat(64)}`;
const fixture = await residentSourceEnvironment(fileURLToPath(new URL('../../', import.meta.url)));
const environment = admitEnvironment(fixture.wire, fixture.cid, {rela: true});

function run(body = document) {
  const prepared = prepare(body, 'json', environment);
  const compilation = compileTasks(prepared);
  const allowed = issueAllowedTaskRun(prepared, compilation, {
    executionContextCid: cid('a'), hostPolicyCid: cid('b'),
    expiresAt: '2099-01-01T00:00:00.000Z',
  });
  const definition = issueTaskRunDefinition(prepared, compilation,
    allowed.admission, 'retained-scope', 'original-run',
    '2026-10-06T00:00:00.000Z', '2099-01-01T00:00:00.000Z');
  const edge = (task = 1, input = 0, selected = definition) =>
    prepareRetainedTaskInputEdge(prepared, compilation,
      allowed.admission, selected, task, input);
  return {prepared, compilation, admission: allowed.admission, definition, edge};
}

test('retained edge comes from the original two checked tasks and keeps both schema domains', () => {
  const original = run();
  assert.deepEqual(taskExecutionShape(original.prepared, original.compilation),
    {taskCount: 2, acquisitionCount: 1});
  const keys = taskKeys(original.prepared, original.compilation);
  const edge = original.edge();
  const facts = retainedTaskInputEdgeFacts(edge);
  assert.equal(facts.runDefinitionCid, privateRunDefinition(original.definition).cid);
  assert.equal(facts.producerTaskKey, keys[0]);
  assert.equal(facts.consumerTaskKey, keys[1]);
  assert.notEqual(facts.producerLogicalCid, facts.consumerLogicalCid);
  assert.equal(facts.consumerInputPort, 'input');
  assert.equal(facts.carrierContractCid,
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  const schema = '{"id":{"nullable":false,"type":"number"}}';
  assert.equal(facts.physicalSchemaCid,
    `sha256:${createHash('sha256').update(schema).digest('hex')}`);
  assert.notEqual(facts.physicalSchemaCid, facts.carrierContractCid);
  assert(Object.isFrozen(edge));
  assert(Object.isFrozen(facts));
  assert.deepEqual(retainedTaskInputEdgeFacts(original.edge()), facts);
  // Topology is not physical custody: the old consumer binding issuer must
  // still refuse until producer completion and Transfer have been admitted.
  assert.throws(() => taskInputBinding(original.prepared, 1),
    {code: 'RunHostTaskBindingRejected'});
});

test('retained edge rejects absent edges, foreign Run owners and forged handles', () => {
  const original = run();
  for (const [task, input] of [[0, 0], [1, 1], [2, 0]]) {
    assert.throws(() => original.edge(task, input),
      {code: 'RunHostRetainedInputEdgeRejected'});
  }
  for (const [task, input] of [[-1, 0], [1, -1], [1.5, 0], [1, Infinity], [2 ** 31, 0]]) {
    assert.throws(() => original.edge(task, input),
      {message: 'InvalidRunHostRetainedInputEdge'});
  }
  const foreign = run(document.replace('id > 2', 'id > 1'));
  assert.throws(() => original.edge(1, 0, foreign.definition),
    {code: 'RunHostRetainedInputEdgeRejected'});
  assert.throws(() => prepareRetainedTaskInputEdge(foreign.prepared,
    original.compilation, original.admission, original.definition, 1, 0),
  {message: 'ForeignRunHostCompilation'});
  for (const forged of [{kind: 'retained-input-edge'},
    retainedTaskInputEdgeFacts(original.edge()), original.definition]) {
    assert.throws(() => retainedTaskInputEdgeFacts(forged),
      {message: 'ForeignRunHostHandle'});
  }
});

// Public SDK + actual ingress, with authored DATA/authority ports. No compiler
// original issuance, funded Host installation or execution acceptance is implied.
import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {validClientBody} from '../../packages/client-wire/index.mjs';
import {runExplanation, unprojectedRunExplanation} from '../../scripts/fixtures/explanation-facts-vectors.mjs';
const ref = runExplanation.run_ref;
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'structural-explanation', capabilities: [], limits: {
    maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []};

test('Execution.explain reads frozen original structural DATA without Client alias or dispatch', async t => {
  let reads = 0, starts = 0;
  const port = createNodeInProcessClientHost({authenticate: () => 'caller',
    authorizeConnection: () => true, negotiate: () => profile, maxRowBytes: 1024,
    attach: value => ({ref: value.ref, durability: 'volatile', revision: 0}),
    runExplanation(value, consume) {reads++; assert.deepEqual(value.ref, ref); return consume(structuredClone(runExplanation));},
    submit() {starts++; throw Error('No execution');}});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  assert.equal(client.explain, undefined);
  const run = await client.attach(ref), view = await run.explain();
  assert.deepEqual(view, runExplanation);
  assert.equal(Object.isFrozen(view.explanation.facts.steps[0].meaning), true);
  assert.equal(reads, 1); assert.equal(starts, 0);
});

test('run-explanation is a closed bounded original Run request', () => {
  const body = {connection, ref, maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64};
  assert.equal(validClientBody('run-explanation', body), true);
  for (const delta of [{maxWireBytes: 0}, {maxNodes: 0}, {maxDepth: 65}, {sampleItems: 1},
    {rawLiterals: true}, {expectedRevision: 0}, {ref: {...ref, extra: true}}]) {
    assert.equal(validClientBody('run-explanation', {...body, ...delta}), false);
  }
});

test('SDK accepts authorized NotProjected without pretending missing facts were rebuilt', async t => {
  const operations = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
    operations.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') return {ref: body.ref, durability: 'volatile', revision: 0};
    assert.equal(operation, 'run-explanation'); return structuredClone(unprojectedRunExplanation);
  }});
  t.after(() => client.close());
  assert.deepEqual(await (await client.attach(ref)).explain(), unprojectedRunExplanation);
  assert.deepEqual(operations, ['connect', 'attach', 'run-explanation']);
});

test('SDK independently refuses foreign, leaked, corrupt or over-budget explanation responses', async t => {
  for (const mutation of ['foreignRun', 'factsCid', 'keyCid', 'leak', 'nodes', 'depth', 'bytes']) {
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref: body.ref, durability: 'volatile', revision: 0};
      const value = structuredClone(runExplanation), facts = value.explanation.facts;
      if (mutation === 'foreignRun') value.run_ref.namespaceId = 'foreign';
      if (mutation === 'factsCid') facts.self_cid = 'sha256:' + '0'.repeat(64);
      if (mutation === 'keyCid') facts.steps[0].key.compiled_plan_cid = 'sha256:' + '0'.repeat(64);
      if (mutation === 'leak') facts.steps[0].meaning.predicate.nodes[2].value = 'private';
      return value;
    }});
    t.after(() => client.close());
    const options = mutation === 'nodes' ? {maxNodes: 2} : mutation === 'depth' ? {maxDepth: 2}
      : mutation === 'bytes' ? {maxWireBytes: 1024} : {};
    await assert.rejects((await client.attach(ref)).explain(options), {code: 'InvalidClientHostRunExplanationView'}, mutation);
  }
});

test('explain signal belongs to this read and never issues Run cancel', async t => {
  const controller = new AbortController(), operations = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body, signal) {
    operations.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') return {ref: body.ref, durability: 'volatile', revision: 0};
    assert.equal(operation, 'run-explanation'); assert.equal(signal, controller.signal);
    controller.abort(new Error('Read cancelled')); signal.throwIfAborted();
  }});
  t.after(() => client.close());
  await assert.rejects((await client.attach(ref)).explain({signal: controller.signal}));
  assert.deepEqual(operations, ['connect', 'attach', 'run-explanation']);
});

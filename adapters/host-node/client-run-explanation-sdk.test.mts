// Public SDK + actual ingress, with authored DATA/authority ports. No compiler
// original issuance, funded Host installation or execution acceptance is implied.
import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installClientRunSample} from './client-run-plan.mjs';
import {validClientBody} from '../../packages/client-wire/index.mjs';
import type {ClientHostOperation} from '../../packages/client-wire/index.js';
import {runExplanation, unprojectedRunExplanation} from '../../scripts/fixtures/explanation-facts-vectors.mjs';
import {effectfulStaticExplanationFixture} from '../../scripts/fixtures/effectful-static-plan-vectors.mjs';
const ref = runExplanation.run_ref;
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'structural-explanation', capabilities: [], limits: {
    maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []};

test('Execution.explain reads frozen original structural DATA without dispatch', async t => {
  let reads = 0, starts = 0;
  const port = createNodeInProcessClientHost({authenticate: () => 'caller',
    authorizeConnection: () => true, negotiate: () => profile, maxRowBytes: 1024,
    attach: value => ({ref: value.ref, durability: 'volatile', revision: 0}),
    runExplanation(value, consume) {reads++; assert.deepEqual(value.ref, ref); return consume(structuredClone(runExplanation));},
    submit() {starts++; throw Error('No execution');}});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  assert.equal(typeof client.explain, 'function', 'static Client API remains distinct');
  assert.equal(Reflect.get(client, 'explainContext'), undefined);
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
  const operations: ClientHostOperation[] = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
    operations.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') {
      assert.ok('ref' in body);
      return {ref: body.ref, durability: 'volatile', revision: 0};
    }
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
      if (operation === 'attach') {
        assert.ok('ref' in body);
        return {ref: body.ref, durability: 'volatile', revision: 0};
      }
      const value = structuredClone(runExplanation), facts = value.explanation.facts;
      if (mutation === 'foreignRun') value.run_ref.namespaceId = 'foreign';
      if (mutation === 'factsCid') facts.self_cid = 'sha256:' + '0'.repeat(64);
      if (mutation === 'keyCid') facts.steps[0].key.compiled_plan_cid = 'sha256:' + '0'.repeat(64);
      if (mutation === 'leak') Object.assign(facts.steps[0].meaning.predicate.nodes[2], {value: 'private'});
      return value;
    }});
    t.after(() => client.close());
    const options = mutation === 'nodes' ? {maxNodes: 2} : mutation === 'depth' ? {maxDepth: 2}
      : mutation === 'bytes' ? {maxWireBytes: 1024} : {};
    await assert.rejects((await client.attach(ref)).explain(options), {code: 'InvalidClientHostRunExplanationView'}, mutation);
  }
});

test('explain signal belongs to this read and never issues Run cancel', async t => {
  const controller = new AbortController();
  const operations: ClientHostOperation[] = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body, signal) {
    operations.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') {
      assert.ok('ref' in body);
      return {ref: body.ref, durability: 'volatile', revision: 0};
    }
    assert.equal(operation, 'run-explanation'); assert.equal(signal, controller.signal);
    controller.abort(new Error('Read cancelled')); signal.throwIfAborted();
  }});
  t.after(() => client.close());
  await assert.rejects((await client.attach(ref)).explain({signal: controller.signal}));
  assert.deepEqual(operations, ['connect', 'attach', 'run-explanation']);
});


test('Execution.explainContext reads one original projection and independently checks its bindings', async t => {
  const operations: string[] = [];
  const original = effectfulStaticExplanationFixture();
  const inner = {...original, plan: original.plan.computation.plan_view};
  const response = {version: 'actql-run-explanation-context-view/0.1', run_ref: ref,
    explanation: {state: 'projected', view: inner}};
  let supplied: typeof response | {
    version: string;
    run_ref: typeof ref;
    explanation: {state: 'not_projected'; reason: 'not_retained'};
  } = response;
  const port = createNodeInProcessClientHost({authenticate: () => 'caller',
    authorizeConnection: () => true, negotiate: () => profile, maxRowBytes: 1024,
    attach: value => ({ref: value.ref, durability: 'volatile', revision: 0}),
    runExplanationContext(input, consume) {
      operations.push('context'); assert.deepEqual(input.ref, ref);
      return consume(structuredClone(supplied));
    },
    runExplanation(input, consume) {
      operations.push('legacy'); return consume(structuredClone(runExplanation));
    },
    submit() {assert.fail('read cannot submit');}});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  const run = await client.attach(ref);
  const answer = await run.explainContext();
  assert.deepEqual(answer, response);
  assert.equal(answer.explanation.state, 'projected');
  assert(Object.isFrozen(answer.explanation.view.context.binding));
  assert.deepEqual(await run.explain(), runExplanation);
  assert.deepEqual(operations, ['context', 'legacy']);
  supplied = structuredClone(response);
  supplied.explanation.view.context.binding.logical_map_cid = 'sha256:' + '0'.repeat(64);
  await assert.rejects(run.explainContext(), {code: 'InvalidClientHostRunExplanationView'});
  supplied = {...response, explanation: {state: 'not_projected', reason: 'not_retained'}};
  assert.deepEqual(await run.explainContext(), supplied);
  assert.equal(validClientBody('run-explanation-context', {connection, ref,
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64, reconstruct: true}), false);
});

test('Execution.sample uses the original producer port and repeats current egress before returning data', async t => {
  const cid = (digit: string) => 'sha256:' + digit.repeat(64);
  const compiledPlan = cid('b'), logicalMap = cid('c'), producerId = cid('1'), consumerId = cid('2');
  const outputId = cid('3'), inputId = cid('4'), carrier = cid('a');
  const selector = {step: {by: 'id', step_id: consumerId}, role: 'input', input_port_id: inputId} as const;
  const planWire = JSON.stringify({logical_map: {compiled_plan_cid: compiledPlan, self_cid: logicalMap, steps: [
    {step_id: producerId, ports: [{port_id: outputId, role: 'output', carrier: 'relation', carrier_contract_cid: carrier}]},
    {step_id: consumerId, ports: [{port_id: inputId, role: 'input', carrier: 'relation', carrier_contract_cid: carrier,
      source: {kind: 'logical_output', step_id: producerId, output_port_id: outputId}}]},
  ]}});
  const definitionWire = 'owned original Run';
  const saved = {compiledPlanWire: 'owned original Plan', planViewWire: planWire};
  const original = {definitionWire, ...saved, programDefinitionCid: cid('d')};
  type SampleInstallation = Parameters<typeof installClientRunSample>[0];
  let planOriginal: NonNullable<ReturnType<SampleInstallation['lookupOriginal']>> = original;
  let replacement: typeof original | undefined;
  const source = {run_ref: ref, compiled_plan_cid: compiledPlan, logical_map_cid: logicalMap,
    carrier: 'relation', carrier_contract_cid: carrier, self_cid: cid('5')} as const;
  const relation = {version: 'actql-sample-relation/0.1', kind: 'relation', schema_cid: cid('e'),
    ordering_evidence_cid: null, columns: [{position: 0, name: 'n', value_contract_cid: cid('f'), required: true}],
    rows: [[{presence: 'present', value_contract_cid: cid('f'), value: 7}]]};
  const admissions = new Set<Parameters<SampleInstallation['readWorkspace']['begin']>[0]>();
  const allocations: number[] = [];
  let retainedKind = 'available';
  let authorized = false, probes = 0, reads = 0, planReads = 0, revokeAtEgress = false;
  const runSample = installClientRunSample({
    authorize: () => authorized,
    probeOriginal(run) {probes++; assert.deepEqual(run, ref); return {storedBytes: 1400};},
    lookupOriginal(run) {
      planReads++;
      assert.deepEqual(run, ref);
      if (revokeAtEgress && planReads === 2) authorized = false;
      return replacement !== undefined && planReads === 2 ? replacement : planOriginal;
    },
    control: {
      admit(name, wire) {
        assert.equal(name, 'run_definition'); assert.equal(wire, definitionWire);
        return {identity: ref.runDefinitionCid};
      },
      readStoredRunPlanOriginal(value) {assert.deepEqual(value, saved); return planWire;},
    },
    readRetained(run, output, {current, reserve}) {
      assert.deepEqual(run, ref);
      assert.deepEqual(output, {compiledPlanCid: compiledPlan, logicalMapCid: logicalMap,
        stepId: producerId, outputPortId: outputId, carrierContractCid: carrier, maxBytes: 65536});
      assert.equal(current(), true);
      reserve(2400);
      reads++;
      if (retainedKind === 'expired') return {kind: 'expired', sampleRefCid: cid('8')};
      if (retainedKind === 'unknown') {
        throw Object.assign(new Error('ClientRelationSampleReadUnknown'), {
          code: 'ClientRelationSampleReadUnknown', outcome: 'unknown',
        });
      }
      return {kind: 'available', source, capture: {strategy: 'execution_prefix', self_cid: cid('6')},
        emission: {sampled_items: '1', total: {kind: 'unknown', unit: 'rows', reason: 'count_not_observed'},
          completeness: 'partial', truncation: 'unknown', self_cid: cid('7')},
        reference: {self_cid: cid('8')}, receipt: {receiptCid: cid('9')}, relation};
    },
    readWorkspace: {
      begin(request) {admissions.add(request);},
      metadata(request, bytes) {assert.ok(admissions.has(request)); allocations.push(bytes);},
      close(request) {assert.ok(admissions.delete(request));},
    },
  });
  const port = createNodeInProcessClientHost({authenticate: () => 'caller', authorizeConnection: () => true,
    negotiate: () => profile, maxRowBytes: 1024,
    attach: value => ({ref: value.ref, durability: 'volatile', revision: 0}),
    runSample});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  const run = await client.attach(ref);
  assert.deepEqual(await run.sample(selector), {state: 'forbidden'});
  assert.equal(probes, 0, 'forbidden callers cannot probe the original');
  authorized = true;
  const value = await run.sample(selector);
  assert.equal(value.state, 'available');
  assert.equal(value.source.step_id, consumerId);
  assert.equal(value.source.port_id, inputId);
  assert.deepEqual(value.source.producer, {kind: 'logical_output', step_id: producerId, output_port_id: outputId});
  assert.deepEqual(value.data, relation);
  assert.equal(Object.isFrozen(value.data.rows[0]), true);
  assert.equal(reads, 1);
  assert.deepEqual(allocations, [1024, 2800, 2400]);
  revokeAtEgress = true; planReads = 0;
  assert.deepEqual(await run.sample(selector), {state: 'forbidden'});
  assert.equal(reads, 2);
  revokeAtEgress = false; authorized = true;
  retainedKind = 'expired';
  assert.deepEqual(await run.sample(selector), {state: 'expired'});
  retainedKind = 'unknown';
  assert.deepEqual(await run.sample(selector), {state: 'unknown', reason: 'sample_read_unknown'});
  retainedKind = 'available';
  planReads = 0;
  replacement = {...original, compiledPlanWire: original.compiledPlanWire.replace('owned', 'other')};
  assert.equal(replacement.compiledPlanWire.length, original.compiledPlanWire.length);
  await assert.rejects(run.sample(selector), {code: 'ClientHostFailure'});
  assert.equal(planReads, 2, 'a same-size replacement must be refused during the final original read');
  replacement = undefined;
  planOriginal = {...original, admissionEvidenceWire: JSON.stringify({logicalPlanOriginal: saved})};
  const beforeMixed = reads;
  await assert.rejects(run.sample(selector), {code: 'ClientHostFailure'});
  assert.equal(reads, beforeMixed, 'mixed inline and companion originals cannot select a Sample');
  planOriginal = {definitionWire, admissionEvidenceWire: JSON.stringify({logicalPlanOriginal: saved}),
    programDefinitionCid: original.programDefinitionCid};
  const planOnlySample = await run.sample(selector);
  assert.equal(planOnlySample.state, 'available');
  assert.deepEqual(planOnlySample.data, relation);
  assert.equal(admissions.size, 0);
});

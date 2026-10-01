import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';
import {checked} from '../adapters/host-common/runtime-result.mjs';
import {runCapturedStrategy} from '../adapters/host-node/entry.mjs';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {runInstalledStrategy} from '../adapters/host-common/strategy.mjs';
import {localStrategyContribution} from '../adapters/local-node/strategy-bundle.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
const {evidence_bundle_cid: ignored, ...base} = read('spec/local-check-environment.json');
void ignored;
base.host_policy_profile = {...base.host_policy_profile,
  capacity: {...base.host_policy_profile.capacity,
    max_graph_construction_edges: 1000, max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000}};
const environment = canonicalText({...base, evidence_bundle_cid: cid(base)});
const numericCid = cid(read('spec/contracts/actql-numeric-reduction.json'));
const lawCid = 'sha256:663bbb3096723cb38face189087f79ab37e9b7d34ec994937b3bff8334c405b1';
const args = [environment, cid(base), false, false, true, true, false, false, false, numericCid];
const owner = moon.clientProgramCheckEnvironmentWithPropertyGraphProfile(...args, lawCid);
assert.ok(owner);

// Independently authored constructor/rows. Expected parallel keys are not
// captured from a product run or a second compilation of this Program.
const program = {version: 'actql/0.1', id: 'property-graph-surface', stages: [{
  id: 'source', inputs: {}, steps: [
    {values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'nodes'},
    {values: {schema: {key: {type: 'number', nullable: false}, src: {type: 'number', nullable: false}, dst: {type: 'number', nullable: false}},
      rows: [{key: 10, src: 1, dst: 1}, {key: 11, src: 1, dst: 1}]}, as: 'edges'},
    {property_graph: {version: 'actql-property-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'nodes', key: ['id'], labels: [{name: 'Node', properties: {mode: 'all_columns'}}]}],
      edges: [{name: 'E', from: 'edges', key: ['key'], source: {definition: 'N', key: ['src']}, target: {definition: 'N', key: ['dst']},
        labels: [{name: 'R', properties: {mode: 'all_columns'}}]}]}, as: 'g'},
    {match_edges: {definition: 'E', label: 'R', where: 'key > 0', fields: ['key']}, as: 'matched'},
  ], results: {out: {from: 'matched', fields: ['key']}}}],
results: {answer: {from: {stage: 'source', result: 'out'}}}};
const prepare = environmentOwner => moon.clientProgramPrepareEffectFreeWithParameters(
  canonicalText(program), 'json', environmentOwner, undefined);

test('installed keyed profile requires its exact pin and is not selected by the legacy SGA flag', () => {
  assert.equal(moon.clientProgramCheckEnvironmentWithPropertyGraphProfile(...args, 'sha256:' + '0'.repeat(64)), undefined);
  assert.equal(moon.clientProgramCheckEnvironmentWithPropertyGraphProfile(...args.slice(0, -1), 'sha256:' + '0'.repeat(64), lawCid), undefined);
  const legacy = moon.clientProgramCheckEnvironmentWithNumericProfile(...args);
  assert.ok(legacy);
  const rejected = prepare(legacy);
  assert.equal(moon.clientProgramPreparationReady(rejected), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(rejected), 'check_unsupported');
  assert.ok(moon.clientProgramPreparationReady(prepare(owner)));
});

test('installed JS bridge issues the same four-task Plan with typed Graph handoff and exact definition bindings', () => {
  const ready = moon.clientProgramPreparationReady(prepare(owner));
  assert.ok(ready);
  assert.equal(moon.clientProgramTaskCount(ready), 4);
  const compilation = checked(moon.clientProgramCompileLocalTasks(ready));
  const graph = JSON.parse(moon.clientProgramTaskCompilationPlanWire(compilation));
  assert.equal(graph.nodes.length, 4);
  const construct = graph.nodes[2].pipeline.steps[0];
  assert.equal(construct.op, 'BRIDGE.rows.to_property_graph');
  assert.deepEqual(construct.in, ['input_0', 'input_1']);
  assert.deepEqual(construct.params.nodes, [{definition: 'N', input: 0, keys: [0], properties: [0]}]);
  assert.deepEqual(construct.params.edges, [{element: {definition: 'E', input: 1, keys: [1], properties: [0, 1, 2]}, source: [2], target: [0]}]);
  assert.equal(construct.params.contract.version, 'actql-property-graph-contract/0.1');
  const graphEdges = graph.data_edges.filter(edge => edge.carrier === 'graph');
  assert.equal(graphEdges.length, 1);
  assert.deepEqual(graphEdges[0].from, {node_id: 'task_2', port: construct.id});
  assert.deepEqual(graphEdges[0].to, {node_id: 'task_3', port: 'input_0'});
  assert.equal(graphEdges[0].contract_cid, cid(construct.params.contract));
  assert.equal(graph.nodes[3].input_contracts.input_0, graphEdges[0].contract_cid);
  assert.equal(graph.nodes[3].pipeline.steps[0].params.definition, 'E');
  assert.equal(graph.root_refs[0].name, 'answer');
});

test('existing installed Local providers execute the keyed constructor and MATCH without a fused fallback', async () => {
  const ready = moon.clientProgramPreparationReady(prepare(owner));
  const aoa = read('spec/contracts/actql-aoa.json');
  const setup = moon.clientProgramOpenSourceFreeLocalHost(ready,
    JSON.stringify(read(aoa.pipeline_registry_file)), JSON.stringify(aoa.execution_contracts['REL.values']),
    1n, 0n, 0n, 0n, JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered']));
  assert.ok(setup, 'the existing Local owner admits all four exact selected tasks');
  const execution = await runCapturedStrategy(setup);
  try {
    assert.equal(execution.status, 'host-tasks-completed');
    assert.deepEqual(execution.resultInventory.map(result => result.name), ['answer']);
    // Independent count: both differently keyed self-loop edges survive MATCH.
    assert.equal(execution.completed.length, 4);
    assert.equal(execution.completed[3].outputRows, 2);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(), false);
  }
});

test('keyed constructor Host in-flight cancellation never publishes partial Graph and closes custody', async () => {
  const ready = moon.clientProgramPreparationReady(prepare(owner));
  const aoa = read('spec/contracts/actql-aoa.json');
  const setup = moon.clientProgramOpenSourceFreeLocalHost(ready,
    JSON.stringify(read(aoa.pipeline_registry_file)), JSON.stringify(aoa.execution_contracts['REL.values']),
    1n, 0n, 0n, 0n, JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered']));
  assert.ok(setup);
  assert.equal(moon.strategyHostConfigureManagedIdentity(setup,true,false,false,false),true);
  const cancellation = new AbortController();
  let graphStarted = false, sawPositiveWork = false, graphCompleted = false;
  let starts = 0;
  const observedRuntime = new Proxy(moon,{get(target,name,receiver) {
    if (name !== 'strategyModule_local_ManagedStart') return Reflect.get(target,name,receiver);
    return configuration => {
      const task = target.strategyHostNextTask(setup);
      starts++;
      const result = target.strategyModule_local_ManagedStart(configuration);
      if (task !== 2) return result;
      graphStarted = true;
      const operations = checked(result);
      const observed = new Proxy(operations,{get(operation,member,operationReceiver) {
        if (member !== 'advance') return Reflect.get(operation,member,operationReceiver);
        return () => {
          const polled = operation.advance(1);
          const observation = checked(polled);
          graphCompleted ||= observation.complete;
          if (!sawPositiveWork && !observation.complete && observation.work > 0n) {
            sawPositiveWork = true;
            // A real timer is delivered by the existing Host yield; no sleep
            // or replacement stop owner can make cancellation appear complete.
            setTimeout(()=>cancellation.abort(),0);
          }
          return polled;
        };
      }});
      // Representation of Result::Ok from the pinned MoonBit compiler.
      return {$tag:1,_0:observed};
    };
  }});
  const execution = await runInstalledStrategy(setup,runtimeCore(moon),
    [localStrategyContribution(observedRuntime,setup,checked)],cancellation.signal);
  try {
    assert.equal(graphStarted,true);
    assert.equal(sawPositiveWork,true);
    assert.equal(cancellation.signal.aborted,true);
    assert.equal(graphCompleted,false);
    assert.equal(starts,3); // Only the two VALUES and the constructor start.
    assert.equal(execution.status,'host-tasks-failed');
    assert.equal(execution.failure?.name,'AbortError');
    assert.deepEqual(execution.completed.map(value=>value.task),[0,1]);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(),false);
    await execution.close();
    assert.equal(execution.cleanupPending(),false);
  }
});

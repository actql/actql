import assert from 'node:assert/strict';
import test from 'node:test';
import {bindWorkersFiniteHost} from './finite.mjs';

// ABI-shape tests only. Real compilation/execution is in finite-runtime.test.mjs.
function fixture() {
  const bounds = {max_nodes: 10, max_text_bytes: 100, max_depth: 10, max_work: 1000};
  const configuration = {
    environment: {wire: '{}', cid: 'environment',
      expressions: {text_time: false, veca: false},
      operations: {rela: true, sga: false, tea: false, calendar: false, text_rank: false}},
    contracts: {registry: '{}', values: '{}', grammar: '{}', barriers: '{}'},
    sequence: {max_steps: 10, max_rows: 10, max_cells: 100,
      max_bindings: 10, max_name_bytes: 100,
      expressions: {max_nodes: 10, max_work: 1000, max_depth: 10,
        max_literal_nodes: 10, max_literal_text_bytes: 100}},
    execution: {rows: {max_rows: 10, metadata_entries: 100,
      retained_entries: 100, operation_entries: 100,
      input_values: {...bounds}, output_values: {...bounds}}, max_work: 1000, max_frames: 100},
    measurement: {max_work: 1000, max_bytes: 1000, max_nodes: 100, max_depth: 10},
    capacity: {contract_cid: 'capacity', max_rows: 10, max_value_bytes: 1000},
    search: {max_offers: 10, max_strategies: 10, max_work: 1000, max_revisions: 3},
    ledger: {planning_work: 10000, attempts: 10, holdings: 10, transfer_bytes: 300000n,
      retained_bytes: 32000000n, execution_bytes: 134217728n},
    milliseconds: 1n, max_work: 1000, max_entries: 100,
  };
  const calls = [];
  const ok = value => ({$tag: 1, _0: value});
  const runtime = Object.fromEntries(['Environment', 'Contracts', 'Manifests', 'Prepare', 'Compile', 'Open', 'Ledger', 'AdmitMaterials']
    .map(name => [`workersFinite${name}`, (...args) => {
      calls.push({name, args}); return ok({name});
    }]));
  Object.assign(runtime, {workersFiniteTemplate: () => ({}), workersFiniteCompiledPlan: () => ({}),
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture-only',
    strategyHostAuthorizeActivation() {}, strategyHostRequireActivation() {},
    strategyPublicationContractIdentity: definition => definition.identity ?? definition,
    strategyHostUsage: setup => ({setup}), strategyHostProgramDefinitionCid() {}});
  const authorization = {authorize() {}, cover() {}, isProtectedSite: site => site === 'in-process-default'};
  return {configuration, runtime, calls, authorization};
}

test('finite installation requires explicit complete finite bounds and runtime exports', () => {
  const {configuration, runtime} = fixture();
  for (const mutate of [value => { delete value.capacity; },
    value => { value.capacity.inferred = true; },
    value => { value.milliseconds = 1; },
    value => { value.milliseconds = 9223372036854775808n; },
    value => { value.execution.max_work = NaN; },
    value => { value.search.max_offers = -1; }]) {
    const candidate = structuredClone(configuration); mutate(candidate);
    assert.throws(() => bindWorkersFiniteHost(runtime, candidate), /InvalidWorkersFiniteInstallation/);
  }
  assert.throws(() => bindWorkersFiniteHost({}, configuration), /InvalidWorkersFiniteInstallation/);
});

test('finite installation snapshots trusted configuration and runtime before preparation', () => {
  const {configuration, runtime, calls} = fixture();
  const host = bindWorkersFiniteHost(runtime, configuration);
  assert.deepEqual(calls.map(call => call.name), ['Environment', 'Contracts', 'Manifests']);
  configuration.sequence.max_rows = 999;
  runtime.workersFiniteCompile = () => assert.fail('mutated runtime');
  const prepared = host.prepare('{}');
  assert.ok(Object.isFrozen(prepared));
  assert.equal(calls.find(call => call.name === 'Compile').args[2].max_rows, 10);
  assert.throws(() => host.prepare({}), /InvalidWorkersFiniteDocument/);
});

test('finite Ledger creation uses all six original installation bounds after caller mutation', () => {
  const {configuration, runtime, calls} = fixture();
  const original = {...configuration.ledger};
  const host = bindWorkersFiniteHost(runtime, configuration);
  for (const key of ['planning_work', 'attempts', 'holdings']) configuration.ledger[key] = 0;
  for (const key of ['transfer_bytes', 'retained_bytes', 'execution_bytes']) configuration.ledger[key] = 0n;
  host.createLedger();
  configuration.ledger = {...original, attempts: 2147483647};
  host.createLedger();
  const ledgers = calls.filter(call => call.name === 'Ledger');
  assert.equal(ledgers.length, 2);
  for (const {args} of ledgers) {
    assert.deepEqual(args, [original]);
    assert.ok(Object.isFrozen(args[0]));
  }
  assert.equal(ledgers[0].args[0], ledgers[1].args[0]);
});

test('finite open requires an owned preparation and protected authorization before charging', () => {
  const {configuration, runtime, calls, authorization} = fixture();
  const host = bindWorkersFiniteHost(runtime, configuration);
  const preparation = host.prepare('{}');
  const owner = {admission: {}, definition: {}, ledger: {}};
  for (const gate of [undefined, {}, {...authorization, isProtectedSite: () => false}]) {
    assert.throws(() => host.open(preparation, owner, gate), /WorkersFiniteProtectedAuthorizationRequired/);
  }
  assert.throws(() => host.open({...preparation}, owner, authorization), /InvalidWorkersFiniteInstallation/);
  assert.equal(calls.filter(call => call.name === 'Open').length, 0);
});

test('finite open forwards the original owners exactly once without minting replacements', () => {
  const {configuration, runtime, calls, authorization} = fixture();
  const host = bindWorkersFiniteHost(runtime, configuration);
  const preparation = host.prepare('{}');
  const owner = {admission: {}, definition: {}, ledger: {}};
  const setup = host.open(preparation, owner, authorization);
  const opened = calls.find(call => call.name === 'Open').args;
  assert.equal(opened[2], owner.admission);
  assert.equal(opened[3], owner.definition);
  assert.equal(opened[9], owner.ledger);
  assert.deepEqual(host.usage(setup), {setup});
  assert.throws(() => host.open(preparation, owner, authorization), /WorkersFiniteRunAlreadyOpened/);
  assert.throws(() => host.usage({}), /InvalidWorkersFiniteInstallation/);
  assert.throws(() => host.withExecution(setup, {...authorization}, () => {}), /InvalidWorkersFiniteInstallation/);
  assert.throws(() => host.withExecution({}, authorization, () => {}), /InvalidWorkersFiniteInstallation/);
  assert.throws(() => host.withExecution(setup, authorization, null), /scoped consumer/);
  assert.equal(calls.filter(call => call.name === 'Open').length, 1);
});

test('failed finite open preserves the refusal and never automatically creates another attempt', () => {
  const {configuration, runtime, authorization} = fixture();
  const refusal = {};
  let attempts = 0;
  runtime.workersFiniteOpen = () => { attempts++; return {$tag: 0, _0: refusal}; };
  const host = bindWorkersFiniteHost(runtime, configuration);
  const preparation = host.prepare('{}');
  const owner = {admission: {}, definition: {}, ledger: {}};
  assert.throws(() => host.open(preparation, owner, authorization), error => error.cause === refusal);
  assert.throws(() => host.open(preparation, owner, authorization), /WorkersFiniteRunAlreadyOpened/);
  assert.equal(attempts, 1);
});


test('materials admission uses frozen installation limits and refuses copied preparation or duplicate Run identity', () => {
  const {configuration, runtime, authorization} = fixture();
  const original = {_0: {}, _1: {}, _2: {}, _3: {identity: 'original-run'}};
  let received;
  runtime.workersFiniteAdmitMaterials = (...args) => {
    received = args;
    return {$tag: 1, _0: {...original, _3: {...original._3}}};
  };
  const host = bindWorkersFiniteHost(runtime, configuration);
  configuration.sequence.max_rows = 999;
  const restored = host.admitMaterials('original-body', 'original-run');
  assert.equal(received[0], 'original-body');
  assert.equal(received[1], 'original-run');
  assert.equal(received[5].max_rows, 10);
  assert.equal(restored.admission, original._2);
  assert.equal(restored.preparation.program, original._0);
  const ledger = host.createLedger();
  const second = host.admitMaterials('original-body', 'original-run');
  host.open(restored.preparation, {...restored, ledger}, authorization);
  assert.throws(() => host.open(second.preparation, {...second, ledger}, authorization),
    /WorkersFiniteRunAlreadyOpened/);
  assert.throws(() => host.admitMaterials({}, 'original-run'), /InvalidWorkersFiniteMaterials/);
});

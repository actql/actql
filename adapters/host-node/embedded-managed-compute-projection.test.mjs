import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual namespace function bodies with explicit nominal/current
// ports. These cases do not issue an operational installation or Core Ledger.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
function actual(name, ports) {
  const node = ast.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.type === 'FunctionDeclaration' && node.declaration.id.name === name);
  assert(node, name);
  const helpers = ast.body.flatMap(node => node.type === 'ExportNamedDeclaration' ? [node.declaration] : [node]).filter(node => node?.type === 'FunctionDeclaration' &&
    ['installedManagedRunContracts','prepareInstalledSequenceContractOriginal'].includes(node.id.name) && node.id.name !== name);
  return new Function(...Object.keys(ports),
    helpers.map(node => source.slice(node.start, node.end)).join('\n') + '\n' +
    source.slice(node.declaration.start, node.declaration.end) + `;return ${name};`)(...Object.values(ports));
}
function fixture() {
  const prepared = {}, request = {}, raw = {}, initialControl = {};
  let current = true;
  const calls = [];
  const limits = [7n, 2n, 3n, 0n, 32n, 64n];
  const contractAdmission = {};
  const moon = {
    clientPrepareInstalledSequenceContracts: () => contractAdmission,
    clientProgramInstalledManagedRunRequirements(...args) {calls.push(['requirements', args]); return limits;},
    clientSubmittedIntent(wire, ...bounds) {calls.push(['intent', wire, bounds]); return wire;},
    clientSubmittedIntentCid(intent) {calls.push(['cid', intent]); return 'sha256:' + 'a'.repeat(64);},
  };
  const originals = {host: {}, installation: {initialControl, projectRuntime: moon},
    generation: {}, supplier: {}, moduleLifetime: {}};
  const assets = new Map([
    ['spec/contracts/actql-aoa.json', JSON.stringify({execution_contracts: {
      'REL.values': {kind: 'values'}, 'ACTQL.expression_fragment/0.1': {kind: 'expression'},
      'REL.derive.ordered': {kind: 'derive'}}})],
    ['spec/contracts/actql-query-acquisition.json', 'acquisition-original'],
    ['spec/contracts/actql-query-process-evidence.json', 'process-original'],
    ['spec/dependencies/aoa-pipeline-registry.json', 'registry-original'],
  ]);
  const ports = {
    assertSourceManagedHostPreparation(held) {assert.strictEqual(held, originals); assert(current, 'CurrentRefused');},
    originalSourceManagedHostRequest(held, value) {
      assert.strictEqual(held, originals); assert.strictEqual(value, prepared); assert(current);
      return request;
    },
    assertManagedComputePreparationCurrent(value, held) {
      assert.strictEqual(value, raw); assert.strictEqual(held, originals); assert(current, 'CurrentRefused');
    },
    readInitialControlInstallationAsset(control, held, path) {
      assert.strictEqual(control, initialControl); assert.strictEqual(held, originals); assert(current);
      assert(assets.has(path), path); return assets.get(path);
    },
    checked: value => value,
    runtimeIsError: () => false,
    runtimeField: () => assert.fail('No failed Core result'),
    canonicalValueJson(value, options) {assert.deepEqual(options, {dataKeys: true}); return JSON.stringify(value);},
    clientOperationError: code => Object.assign(new Error(code), {code}),
  };
  return {prepared, request, raw, originals, moon, calls, limits, ports, assets, contractAdmission,
    stop: () => {current = false;},
    requirements: () => actual('readManagedComputeRunRequirements', ports),
    intent: () => actual('managedComputeSubmittedIntentCid', ports)};
}

test('installed managed contract strings are projected once across distinct Host Run requests', () => {
  const f = fixture(), second = {}, requests = new Set([f.prepared, second]);
  let parses = 0, stringifies = 0;
  f.ports.JSON = {
    parse(wire) {parses++; return JSON.parse(wire);},
    stringify(value) {stringifies++; return JSON.stringify(value);},
  };
  f.ports.originalSourceManagedHostRequest = (held, prepared) => {
    assert.strictEqual(held, f.originals); assert(requests.has(prepared)); return f.request;
  };
  const read = f.requirements();
  read(f.originals, f.prepared); read(f.originals, second); read(f.originals, second);
  assert.equal(parses, 1, 'One immutable installed AoA projection, not one per requirement read');
  assert.equal(stringifies, 3, 'Only the original three static contract strings are retained');
  assert.deepEqual(f.calls.map(([, args]) => args[0]), [f.prepared, second, second]);
  for (const [, args] of f.calls) assert.deepEqual(args.slice(-3),
    ['{"kind":"values"}', '{"kind":"expression"}', '{"kind":"derive"}']);
  f.stop();
  assert.throws(() => read(f.originals, second), /CurrentRefused/);
  assert.equal(f.calls.length, 3, 'Static strings cannot supply current Run admission');
});

test('installed contract projection is immutable and cannot cross Host control originals', () => {
  const first = fixture(), second = fixture();
  first.requirements()(first.originals, first.prepared);
  second.requirements()(second.originals, second.prepared);
  const held = first.originals.installation.managedRunContracts;
  assert(Object.isFrozen(held));
  assert.notStrictEqual(held, second.originals.installation.managedRunContracts);
  assert.throws(() => {held.values = '{}';}, TypeError);
  first.originals.installation.initialControl = {};
  assert.throws(() => first.requirements()(first.originals, first.prepared),
    {code: 'ForeignInstalledManagedRunContracts'});
  assert.equal(first.calls.length, 1);

  const broken = fixture(), path = 'spec/contracts/actql-aoa.json';
  const wire = broken.assets.get(path);
  broken.assets.set(path, '{');
  assert.throws(() => broken.requirements()(broken.originals, broken.prepared), SyntaxError);
  assert.equal(broken.originals.installation.managedRunContracts, undefined,
    'Failed construction cannot publish partial contract strings');
  assert.equal(broken.calls.length, 0);
  broken.assets.set(path, wire);
  broken.requirements()(broken.originals, broken.prepared);
  assert.equal(broken.calls.length, 1);
});

test('Mock Model requirement purposes reuse only the same installed static strings', () => {
  const f = fixture(), modelCalls = [], budgets = Array(15).fill(0n);
  f.requirements()(f.originals, f.prepared);
  const held = f.originals.installation.managedRunContracts;
  f.moon.clientProgramAcquisitionCount = () => 0;
  f.moon.clientProgramEffectAcquisitionCount = () => 0;
  f.ports.runtimeCore = runtime => {
    assert.strictEqual(runtime, f.moon);
    return {publicationControl: {
      checkedClientMockModelRunRequirements(...args) {modelCalls.push(['pure', args]); return budgets;},
      checkedClientEffectMockModelRunRequirements(...args) {modelCalls.push(['effect', args]); return budgets;},
    }};
  };
  f.ports.readInitialControlInstallationAsset = (control, original, path) => {
    assert.strictEqual(control, f.originals.installation.initialControl);
    assert.strictEqual(original, f.originals);
    assert.notEqual(path, 'spec/contracts/actql-aoa.json', 'No second static projection');
    return f.assets.get(path);
  };
  const read = actual('readLocalMockModelRunRequirements', f.ports);
  for (const compilation of [undefined, {}]) {
    const model = {compiled: {}, runDefinition: {}, occurrence: 0, graph: {}, compilation};
    read(f.originals, f.prepared, model);
    const [, args] = modelCalls.at(-1);
    assert.strictEqual(args[0], f.prepared); assert.strictEqual(args[1], model.compiled);
    assert.deepEqual(args.slice(-3), [held.values, held.expression, held.ordered]);
    assert.deepEqual(model.budget, {bootstrapRetainedBytes: 0n, bootstrapExecutionBytes: 0n,
      readRetainedBytes: 0n, readExecutionBytes: 0n, modelRetainedBytes: 0n,
      modelExecutionBytes: 0n, maxReservations: 0, maxHoldings: 0, maxDelegations: 0});
  }
  assert.deepEqual(modelCalls.map(([kind]) => kind), ['pure', 'effect']);
});

test('source-free requirements forward the same checked preparation and empty Source inventories', () => {
  const f = fixture();
  const result = f.requirements()(f.originals, f.prepared);
  assert.deepEqual(result, {planningWork: 7, attempts: 2, holdings: 3,
    transferBytes: 0n, retainedBytes: 32n, executionBytes: 64n});
  assert(Object.isFrozen(result));
  assert.equal(f.calls.length, 1);
  const args = f.calls[0][1];
  assert.strictEqual(args[0], f.prepared);
  assert.deepEqual(args.slice(1), [[], 'acquisition-original', 'process-original', [], [],
    f.contractAdmission, '{"kind":"values"}', '{"kind":"expression"}', '{"kind":"derive"}']);
});

test('foreign Host or copied prepared request refuses before any Core requirement call', () => {
  const f = fixture(), read = f.requirements();
  assert.throws(() => read({...f.originals}, f.prepared));
  assert.throws(() => read(f.originals, {...f.prepared}));
  assert.equal(f.calls.length, 0);
});

test('requirements retain the post-Core current and same-request fence', () => {
  const f = fixture();
  f.moon.clientProgramInstalledManagedRunRequirements = () => {f.stop(); return f.limits;};
  assert.throws(() => f.requirements()(f.originals, f.prepared), /CurrentRefused/);
});

test('Core refusal propagates without replacement requirements', () => {
  const f = fixture(), stopped = new Error('OriginalCoreRefusal');
  actual('prepareInstalledSequenceContractOriginal',f.ports)(f.originals);
  f.ports.checked = () => {throw stopped;};
  assert.throws(() => f.requirements()(f.originals, f.prepared), error => error === stopped);
  assert.equal(f.calls.length, 1);
});

test('malformed or overflowing requirement observations are refused', () => {
  for (const value of [[1n], [1n, 2n, 3n, 0n, -1n, 0n],
    [2147483648n, 2n, 3n, 0n, 0n, 0n], [1, 2n, 3n, 0n, 0n, 0n]]) {
    const f = fixture(); f.moon.clientProgramInstalledManagedRunRequirements = () => value;
    assert.throws(() => f.requirements()(f.originals, f.prepared),
      error => error.code === 'InvalidHostRuntimeResult');
  }
});

function preparedRunFixture() {
  const f = fixture(), original = {}, run = {runtime: f.moon, prepared: f.prepared, request: f.request, closed: false};
  f.originals.installation.computeRuns = new Map([[f.prepared, run]]);
  f.moon.clientProgramInstalledManagedRunIssueIsUnsupported = () => false;
  f.moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts = (...args) => {
    f.calls.push(['prepare', args]); return original;
  };
  f.moon.clientProgramPreparedInstalledManagedSourceFreeRequirements = value => {
    assert.strictEqual(value, original); f.calls.push(['project', value]); return f.limits;
  };
  f.moon.clientProgramInstalledManagedRunRequirements = () => assert.fail('No legacy regeneration');
  return {...f, original, run};
}

test('same Host Run retains one typed sequence preparation before repeated scalar projections', () => {
  const f = preparedRunFixture(), read = f.requirements();
  const first = read(f.originals, f.prepared), again = read(f.originals, f.prepared);
  assert.deepEqual(first, again);
  assert.strictEqual(f.run.preparedSequences, f.original);
  assert.equal(f.calls.filter(([name]) => name === 'prepare').length, 1);
  assert.equal(f.calls.filter(([name]) => name === 'project').length, 2);
  assert.deepEqual(f.calls[0][1], [f.prepared, f.contractAdmission,
    '{"kind":"values"}', '{"kind":"expression"}', '{"kind":"derive"}']);
});

test('same typed preparation survives failed projection or current observation without replacement', () => {
  for (const failure of ['projection', 'current']) {
    const f = preparedRunFixture(), marker = new Error('OriginalProjectionFailure');
    f.moon.clientProgramPreparedInstalledManagedSourceFreeRequirements = value => {
      assert.strictEqual(value, f.original);
      if (failure === 'projection') throw marker;
      f.stop(); return f.limits;
    };
    assert.throws(() => f.requirements()(f.originals, f.prepared),
      failure === 'projection' ? error => error === marker : /CurrentRefused/);
    assert.strictEqual(f.run.preparedSequences, f.original);
    assert.equal(f.calls.filter(([name]) => name === 'prepare').length, 1);
  }
});

test('foreign or closed Run and missing typed APIs refuse without legacy regeneration', () => {
  for (const change of [f => {f.run.runtime = {};}, f => {f.run.prepared = {};},
    f => {f.run.closed = true;},
    f => {f.moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts = undefined;},
    f => {f.moon.clientProgramInstalledManagedRunIssueIsUnsupported = undefined;},
    f => {f.moon.clientProgramPreparedInstalledManagedSourceFreeRequirements = undefined;}]) {
    const f = preparedRunFixture(); change(f);
    assert.throws(() => f.requirements()(f.originals, f.prepared),
      error => error.code === 'NodeManagedRunRuntimeUnavailable');
    assert.equal(f.calls.length, 0);
  }
});

test('Compute intent uses the original Common admission and preserves absent optional members', () => {
  const f = fixture(), body = Object.freeze({kind: 'sql', input: 'SELECT 1', parameters: {}});
  assert.equal(f.intent()(f.originals, f.raw, body), 'sha256:' + 'a'.repeat(64));
  assert.deepEqual(f.calls[0], ['intent', '{"kind":"sql","input":"SELECT 1","parameters":{}}',
    [1048576, 65536, 64]]);
  assert.equal(f.calls.length, 2);
});

test('Compute intent preserves both admitted continuation restrictions', () => {
  const f = fixture();
  f.intent()(f.originals, f.raw, Object.freeze({kind: 'aql', input: 'FROM x',
    parameters: {}, stopBefore: 'commit', readOnly: true}));
  assert.equal(f.calls[0][1], '{"kind":"aql","input":"FROM x","parameters":{},"stopBefore":"commit","readOnly":true}');
});

test('copied Compute original or foreign Host refuses before intent admission', () => {
  const f = fixture(), intent = f.intent(), body = {kind: 'sql', input: 'SELECT 1', parameters: {}};
  assert.throws(() => intent(f.originals, {...f.raw}, body));
  assert.throws(() => intent({...f.originals}, f.raw, body));
  assert.equal(f.calls.length, 0);
});

test('intent current changes, missing admission and malformed CID cannot become identity', () => {
  const body = {kind: 'sql', input: 'SELECT 1', parameters: {}};
  const changed = fixture();
  changed.moon.clientSubmittedIntentCid = () => {changed.stop(); return 'sha256:' + 'a'.repeat(64);};
  assert.throws(() => changed.intent()(changed.originals, changed.raw, body), /CurrentRefused/);
  const absent = fixture(); absent.moon.clientSubmittedIntent = () => undefined;
  assert.throws(() => absent.intent()(absent.originals, absent.raw, body),
    error => error.code === 'NodeManagedComputeIntentUnavailable');
  const malformed = fixture(); malformed.moon.clientSubmittedIntentCid = () => 'foreign';
  assert.throws(() => malformed.intent()(malformed.originals, malformed.raw, body),
    error => error.code === 'InvalidHostRuntimeResult');
});


test('only the original pure preparation Unsupported is a typed refusal', () => {
  for (const unsupported of [false, true]) {
    const f = preparedRunFixture(), result = {}, issue = {}, originalFailure = new Error('OriginalCoreFailure');
    f.moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts = () => result;
    f.ports.runtimeIsError = value => {assert.strictEqual(value, result); return true;};
    f.ports.runtimeField = (value, index) => {assert.strictEqual(value, result); assert.equal(index, 0); return issue;};
    f.moon.clientProgramInstalledManagedRunIssueIsUnsupported = value => {
      assert.strictEqual(value, issue); return unsupported;
    };
    actual('prepareInstalledSequenceContractOriginal',f.ports)(f.originals);
    f.ports.checked = value => {assert.strictEqual(value, result); throw originalFailure;};
    assert.throws(() => f.requirements()(f.originals, f.prepared), unsupported
      ? {code: 'ClientProgramUnsupported'} : error => error === originalFailure);
    assert.equal(f.run.preparedSequences, undefined);
    assert.equal(f.calls.length, 0, 'No scalar projection or Resource admission after a failed preparation');
  }
});

test('Unsupported after Resource or a retained failure never issues a new pure refusal', () => {
  for (const field of ['original', 'admission', 'value', 'failure']) {
    const f = preparedRunFixture(), result = {}, issue = {}, failure = new Error('OriginalCoreFailure');
    f.run[field] = {};
    f.moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts = () => result;
    f.ports.runtimeIsError = value => {assert.strictEqual(value, result); return true;};
    f.ports.runtimeField = value => {assert.strictEqual(value, result); return issue;};
    f.moon.clientProgramInstalledManagedRunIssueIsUnsupported = value => {assert.strictEqual(value, issue); return true;};
    actual('prepareInstalledSequenceContractOriginal',f.ports)(f.originals);
    f.ports.checked = value => {assert.strictEqual(value, result); throw failure;};
    assert.throws(() => f.requirements()(f.originals, f.prepared), error => error === failure);
    assert.equal(f.run.preAdmissionRefusal, undefined);
  }
});

test('installed Source demand retains actual checked occurrence capacities before the same Resource admission', () => {
  const f = fixture(), requirements = [{}, {}], capacities = [{}, {}], seen = [];
  f.moon.clientPrepareInstalledCompilationManifests = () => {};
  const adapters = capacities.map((capacity, index) => ({managedCaptureCapacity(requirement) {
    assert.strictEqual(requirement, requirements[index]); seen.push(index);
    return {capacity, transferBytes: BigInt(index + 5), executionBytes: BigInt(index + 9)};
  }}));
  const profile = {sources: adapters};
  const run = {runtime: f.moon, prepared: f.prepared, request: f.request, sourceProfile: profile};
  Object.assign(f.originals.installation, {managedSourceProfile: profile, computeRuns: new WeakMap([[f.prepared, run]])});
  f.moon.clientProgramAcquisitionCount = value => {assert.strictEqual(value, f.prepared); return 2;};
  f.moon.clientProgramPrepareLocalQueryRequirement = (value, stage, input, contracts) => {
    assert.strictEqual(value, f.prepared); assert.equal(input, 0); assert.strictEqual(contracts, f.contractAdmission);
    return requirements[stage];
  };
  f.moon.clientProgramQueryRequirementSourceRef = value => 'source:' + requirements.indexOf(value);
  f.ports.installedSourceFor = (selected, ref) => {
    assert.strictEqual(selected, profile); return adapters[Number(ref.slice(7))];
  };
  let quotes = 0;
  f.moon.clientProgramInstalledManagedCaptureRunRequirements = (value, captures, transfer, workspace, contracts) => {
    assert.strictEqual(value, f.prepared); assert.deepEqual(captures, capacities);
    assert.deepEqual(transfer, [5n, 6n]); assert.deepEqual(workspace, [9n, 10n]);
    assert.strictEqual(contracts, f.contractAdmission); quotes++; return f.limits;
  };
  const read = f.requirements();
  for (let index = 0; index < 2; index++) assert.equal(read(f.originals, f.prepared).executionBytes, 64n);
  assert.deepEqual(seen, [0, 1], 'Each checked occurrence retains its original Source envelope');
  assert.equal(quotes, 2, 'Limits projection is not a full-work recurrence counter');
  assert(Object.isFrozen(run.sourceCapacities));
  assert.strictEqual(run.sourceCapacities[0].adapter, adapters[0]);
  run.sourceProfile = {...profile};
  assert.throws(() => read(f.originals, f.prepared), {code: 'NodeManagedRunRuntimeUnavailable'});
  assert.deepEqual(seen, [0, 1]);
});

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
    ['installedManagedRunContracts','prepareInstalledSequenceContractOriginal','retainedManagedCaptureInventory','installedDirectSourceCoordinates'].includes(node.id.name) && node.id.name !== name);
  return new Function(...Object.keys(ports),
    helpers.map(node => source.slice(node.start, node.end)).join('\n') + '\n' +
    source.slice(node.declaration.start, node.declaration.end) + `;return ${name};`)(...Object.values(ports));
}
function fixture() {
  const prepared = {}, request = {}, raw = {}, initialControl = {};
  let current = true;
  const calls = [];
  const limits = [7n, 2n, 3n, 0n, 32n, 64n];
  const contractAdmission = {}, manifestAdmission = {}, installationCalls = [];
  const moon = {
    clientPrepareInstalledCompilationManifests(...args) {
      assert.strictEqual(this, moon); assert.deepEqual(args, []);
      installationCalls.push('manifests'); return manifestAdmission;
    },
    clientPrepareInstalledSequenceContracts(...args) {
      assert.strictEqual(this, moon);
      assert.equal(installationCalls.at(-1), 'manifests');
      assert.deepEqual(args, ['registry-original', '{"kind":"values"}',
        '{"kind":"expression"}', '{"kind":"derive"}']);
      installationCalls.push('sequence'); return contractAdmission;
    },
    clientProgramInstalledManagedRunRequirements(...args) {calls.push(['requirements', args]); return limits;},
    clientSubmittedIntent(wire, ...bounds) {calls.push(['intent', wire, bounds]); return wire;},
    clientSubmittedIntentCid(intent) {calls.push(['cid', intent]); return 'sha256:' + 'a'.repeat(64);},
  };
  const originals = {host: {}, installation: {initialControl, projectRuntime: moon, retainedRelationOutput: false},
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
    manifestAdmission, installationCalls,
    stop: () => {current = false;},
    requirements: () => actual('readManagedComputeRunRequirements', ports),
    intent: () => actual('managedComputeSubmittedIntentCid', ports)};
}

// Select the existing open-side handoff and preparation method themselves.
// Resource/Core/current replies are explicit fixture ports; parse/stringify
// counts describe these actual bodies, not product timing or physical reads.
function openSequenceContracts(f) {
  const methods = [], blocks = [];
  function walk(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key.name === 'readSequenceContracts') methods.push(node.value);
    if (node.type === 'BlockStatement' && node.body.some(statement =>
      statement.type === 'VariableDeclaration' && statement.declarations.some(declaration =>
        ['registryWire', 'sequenceContracts'].includes(declaration.id.name)))) blocks.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value !== null && typeof value === 'object') walk(value);
    }
  }
  walk(ast);
  assert.equal(methods.length, 1); assert.equal(blocks.length, 1);
  const method = methods[0], block = blocks[0];
  const start = block.body.findIndex(statement => statement.type === 'VariableDeclaration' &&
    statement.declarations.some(declaration => ['registryWire', 'sequenceContracts'].includes(declaration.id.name)));
  const end = block.body.findIndex((statement, index) => index > start &&
    statement.type === 'ExpressionStatement' && statement.expression.type === 'AwaitExpression' &&
    statement.expression.argument.callee.name === 'mkdir');
  assert.ok(start >= 0 && end > start);
  const prepare = actual('prepareInstalledSequenceContractOriginal', f.ports);
  const read = new Function('prepareInstalledSequenceContractOriginal', 'originals',
    `return function()${source.slice(method.body.start, method.body.end)};`)(prepare, f.originals);
  const preparation = {readSequenceContracts: read, readAsset(path) {
    return f.ports.readInitialControlInstallationAsset(f.originals.installation.initialControl, f.originals, path);
  }};
  return new Function('preparation', 'moon', 'JSON', 'readFile', 'join', 'packageRoot', 'checked',
    `return async function(){let registry, values, fragment, ordered;
      ${source.slice(block.body[start].start, block.body[end - 1].end)}
      return {registry, values, fragment, ordered};};`)(preparation, f.moon, f.ports.JSON ?? JSON,
    () => assert.fail('No pathname fallback'), () => assert.fail('No pathname fallback'),
    'unused-package-root', f.ports.checked);
}

test('open borrows the one installed AoA projection through the same sequence original', async () => {
  const f = fixture(); let parses = 0, stringifies = 0;
  f.ports.JSON = {parse(wire) {parses++; return JSON.parse(wire);},
    stringify(body) {stringifies++; return JSON.stringify(body);}};
  const opened = await openSequenceContracts(f)();
  const original = f.originals.installation.sequenceContractOriginal;
  assert.strictEqual(opened.registry, original.admission);
  assert.strictEqual(original.contracts, f.originals.installation.managedRunContracts);
  assert.deepEqual([opened.values, opened.fragment, opened.ordered],
    [original.contracts.values, original.contracts.expression, original.contracts.ordered]);
  f.requirements()(f.originals, f.prepared); f.requirements()(f.originals, f.prepared);
  assert.equal(parses, 1, 'Open and later requirements retain the one actual AoA parse');
  assert.equal(stringifies, 3, 'The three contracts are extracted once');
  assert.deepEqual(f.installationCalls, ['manifests', 'sequence']);
  assert.strictEqual(original.moon, f.moon);
  assert.strictEqual(original.control, f.originals.installation.initialControl);
});

test('open refuses a closed or foreign contract original before parsing another AoA image', async () => {
  for (const changed of ['current', 'runtime', 'control']) {
    const f = fixture(); let parses = 0;
    f.ports.JSON = {parse(wire) {parses++; return JSON.parse(wire);}, stringify: JSON.stringify};
    const open = openSequenceContracts(f);
    await open(); assert.equal(parses, 1);
    if (changed === 'current') f.stop();
    else if (changed === 'runtime') f.originals.installation.projectRuntime = {};
    else f.originals.installation.initialControl = {};
    await assert.rejects(open(), error => changed === 'current' ? /CurrentRefused/u.test(error.message)
      : error.code === 'ForeignInstalledManagedRunContracts');
    assert.equal(parses, 1);
    assert.deepEqual(f.installationCalls, ['manifests', 'sequence']);
  }
});

test('open preserves original manifest and sequence failure without a fallback or partial admission', async () => {
  for (const phase of ['manifests', 'sequence']) {
    const f = fixture(), failure = new Error('OriginalInstalledContractFailure'); let parses = 0;
    f.ports.JSON = {parse(wire) {parses++; return JSON.parse(wire);}, stringify: JSON.stringify};
    const rejected = phase === 'manifests' ? f.manifestAdmission : f.contractAdmission;
    f.ports.checked = value => {if (value === rejected) throw failure; return value;};
    await assert.rejects(openSequenceContracts(f)(), error => error === failure);
    assert.equal(f.originals.installation.sequenceContractOriginal, undefined);
    assert.equal(parses, phase === 'manifests' ? 0 : 1);
    assert.deepEqual(f.installationCalls, phase === 'manifests' ? ['manifests'] : ['manifests', 'sequence']);
  }
});

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
  assert.deepEqual(f.installationCalls, ['manifests', 'sequence'],
    'Fixed installation admission is retained, not repeated for each Run quote');
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

test('Pure Mock Model requirements reuse only the same installed static strings', () => {
  const f = fixture(), modelCalls = [], budgets = Array(15).fill(0n);
  f.requirements()(f.originals, f.prepared);
  const held = f.originals.installation.managedRunContracts;
  f.moon.clientProgramAcquisitionCount = () => 0;
  f.moon.clientProgramEffectAcquisitionCount = () => 0;
  f.ports.runtimeCore = runtime => {
    assert.strictEqual(runtime, f.moon);
    return {publicationControl: {
      checkedClientMockModelRunRequirements(...args) {modelCalls.push(['pure', args]); return budgets;},

    }};
  };
  f.ports.readInitialControlInstallationAsset = (control, original, path) => {
    assert.strictEqual(control, f.originals.installation.initialControl);
    assert.strictEqual(original, f.originals);
    assert.notEqual(path, 'spec/contracts/actql-aoa.json', 'No second static projection');
    return f.assets.get(path);
  };
  const read = actual('readLocalMockModelRunRequirements', f.ports);
  for (const compilation of [undefined]) {
    const model = {compiled: {}, runDefinition: {}, occurrence: 0, graph: {}, compilation};
    read(f.originals, f.prepared, model);
    const [, args] = modelCalls.at(-1);
    assert.strictEqual(args[0], f.prepared); assert.strictEqual(args[1], model.compiled);
    assert.deepEqual(args.slice(-3), [held.values, held.expression, held.ordered]);
    assert.deepEqual(model.budget, {bootstrapRetainedBytes: 0n, bootstrapExecutionBytes: 0n,
      readRetainedBytes: 0n, readExecutionBytes: 0n, modelRetainedBytes: 0n,
      modelExecutionBytes: 0n, maxReservations: 0, maxHoldings: 0, maxDelegations: 0});
  }
  assert.deepEqual(modelCalls.map(([kind]) => kind), ['pure']);
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
  f.originals.installation.computeRuns = new WeakMap([[f.prepared, run]]);
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
    '{"kind":"values"}', '{"kind":"expression"}', '{"kind":"derive"}', false]);
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
  const adapters = capacities.map((capacity, index) => ({managedCaptureCapacity(requirement) {
    assert.strictEqual(requirement, requirements[index]); seen.push(index);
    return {capacity, transferBytes: BigInt(index + 5), executionBytes: BigInt(index + 9)};
  }}));
  const profile = {sources: adapters};
  const run = {runtime: f.moon, prepared: f.prepared, request: f.request, sourceProfile: profile};
  Object.assign(f.originals.installation, {managedSourceProfile: profile, computeRuns: new WeakMap([[f.prepared, run]])});
  f.moon.clientProgramAcquisitionCount = value => {assert.strictEqual(value, f.prepared); return 2;};
  f.moon.clientProgramDirectSourceCoordinates = value => {
    assert.strictEqual(value, f.prepared); return [[0, 0, 0, 0], [1, 0, 1, 1]];
  };
  f.moon.clientProgramSelectInstalledSourceInput = (value, request, stage, input) => {
    assert.strictEqual(value,f.prepared);assert.strictEqual(request,f.request);assert.equal(input,0);
    return requirements[stage];
  };
  f.moon.clientProgramSelectedSourceInputKind = value => {
    assert(requirements.includes(value));return 'query';
  };
  f.moon.clientProgramSelectedSourceInputRef = value => 'source:' + requirements.indexOf(value);
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

test('installed manifest admission precedes sequence preparation and retains the same original', () => {
  const f = fixture(), prepare = actual('prepareInstalledSequenceContractOriginal', f.ports);
  const original = prepare(f.originals);
  assert.deepEqual(f.installationCalls, ['manifests', 'sequence']);
  assert.strictEqual(original.admission, f.contractAdmission);
  assert.strictEqual(original.moon, f.moon);
  assert.strictEqual(original.control, f.originals.installation.initialControl);
  assert.strictEqual(original.contracts, f.originals.installation.managedRunContracts);
  assert.strictEqual(prepare(f.originals), original);
  assert.deepEqual(f.installationCalls, ['manifests', 'sequence'], 'No repeated installed preparation');
  f.originals.installation.projectRuntime = {};
  assert.throws(() => prepare(f.originals), {code: 'ForeignInstalledManagedRunContracts'});
  f.originals.installation.projectRuntime = f.moon;
  f.stop(); assert.throws(() => prepare(f.originals), /CurrentRefused/u);
  assert.deepEqual(f.installationCalls, ['manifests', 'sequence']);
});

test('original manifest or sequence refusal cannot publish a partial installed admission', () => {
  for (const phase of ['manifests', 'sequence']) {
    const f = fixture(), failure = new Error('OriginalInstalledPreparationRefusal');
    const rejected = phase === 'manifests' ? f.manifestAdmission : f.contractAdmission;
    f.ports.checked = value => {if (value === rejected) throw failure; return value;};
    const prepare = actual('prepareInstalledSequenceContractOriginal', f.ports);
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.throws(() => prepare(f.originals), error => error === failure);
      assert.equal(f.originals.installation.sequenceContractOriginal, undefined);
    }
    assert.deepEqual(f.installationCalls, phase === 'manifests'
      ? ['manifests', 'manifests'] : ['manifests', 'sequence', 'manifests', 'sequence']);
    assert.equal(f.originals.installation.managedRunContracts === undefined, phase === 'manifests');
    assert.deepEqual(f.calls, [], 'No Run requirement or Resource replacement after refusal');
  }
});

test('missing installed manifest or sequence port refuses before reading contract assets', () => {
  for (const field of ['clientPrepareInstalledCompilationManifests', 'clientPrepareInstalledSequenceContracts']) {
    const f = fixture(); f.moon[field] = undefined;
    f.ports.readInitialControlInstallationAsset = () => assert.fail('No assets after a missing runtime port');
    assert.throws(() => actual('prepareInstalledSequenceContractOriginal', f.ports)(f.originals),
      {code: 'NodeManagedRunRuntimeUnavailable'});
    assert.deepEqual(f.installationCalls, []);
    assert.equal(f.originals.installation.sequenceContractOriginal, undefined);
  }
});

test('fixed compilation manifest refusal cannot publish a sequence original or quote', () => {
  const f = fixture(), failure = new Error('OriginalCompilationManifestsRefused');
  f.moon.clientPrepareInstalledCompilationManifests = () => {throw failure;};
  f.moon.clientPrepareInstalledSequenceContracts = () => assert.fail('No sequence admission after failed manifests');
  assert.throws(() => f.requirements()(f.originals, f.prepared), error => error === failure);
  assert.equal(f.originals.installation.sequenceContractOriginal, undefined);
  assert.equal(f.calls.length, 0);
});

test('retired raw Effect Model quote refuses before original current or static projection', () => {
  const f = fixture(); let calls = 0;
  f.ports.assertSourceManagedHostPreparation = () => {calls++; assert.fail('No legacy Effect quote');};
  const read = actual('readLocalMockModelRunRequirements', f.ports);
  assert.throws(() => read(f.originals, f.prepared, {compilation: {}}),
    {code: 'InstalledEffectPlanUnavailable'});
  assert.equal(calls, 0); assert.deepEqual(f.installationCalls, []);
});

test('retired positional LocalFiles constructor refuses before a replacement Root or record', () => {
  const text = readFileSync(new URL('../connectors/local/host/installed-project-files.mjs', import.meta.url), 'utf8');
  const tree = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const install = tree.body.find(n => n.type === 'ExportNamedDeclaration' &&
    n.declaration?.id?.name === 'installPreparedProjectLocalFiles').declaration;
  const node = install.body.body.find(n => n.type === 'FunctionDeclaration' && n.id.name === 'prepareRun');
  assert(node);
  const runs = new Map(); let calls = 0;
  const no = () => {calls++; assert.fail('No legacy LocalFiles Effect admission');};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const prepare = new Function('current', 'runs', 'checked', 'moon', 'sourceManaged', 'fail', 'sameRun',
    text.slice(node.start, node.end) + ';return prepareRun;')(
    no, runs, no, {}, {prepareEffectRun: no, prepareRun: no}, fail, no);
  assert.throws(() => prepare({}, {}, true), {code: 'InvalidInstalledManagedRunRequest'});
  assert.equal(calls, 0); assert.equal(runs.size, 0);
});


// Actual Host-delegating Pure constructor and Source-read callee, with explicit
// manager/Core ports only; this does not supply a physical/native parent.
test('LocalFiles Pure admission preserves original identity and Effect read cannot borrow it', () => {
  const text = readFileSync(new URL('../connectors/local/host/installed-project-files.mjs', import.meta.url), 'utf8');
  const tree = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const install = tree.body.find(n => n.type === 'ExportNamedDeclaration' &&
    n.declaration?.id?.name === 'installPreparedProjectLocalFiles').declaration;
  const node = install.body.body.find(n => n.type === 'FunctionDeclaration' && n.id.name === 'prepareRun');
  const prepared = {}, request = {}, parent = {}, sharedRuns = new Map(), calls = [], profile = {};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const current = () => {calls.push('current');};
  const prepareManagedRun = facts => {
    assert.equal(facts.preparedProgram,prepared);assert.equal(facts.requestIdentity,request);
    assert.equal(facts.sourceProfile,profile);assert.equal(Object.isFrozen(facts),true);
    calls.push('original-host');return parent;
  };
  const prepare = new Function('current', 'sharedRuns', 'prepareManagedRun', 'profile', 'fail',
    text.slice(node.start, node.end) + ';return prepareRun;')(
    current, sharedRuns, prepareManagedRun, profile, fail);
  prepare({preparedProgram:prepared,requestIdentity:request});
  const originalRecord=sharedRuns.get(prepared);
  prepare({preparedProgram:prepared,requestIdentity:request});
  assert.equal(sharedRuns.get(prepared),originalRecord);assert.equal(originalRecord.value,parent);
  assert.equal(calls.filter(x => x === 'original-host').length,2,'Both observations use the same Host owner, never a Connector admission');
  const found = [];
  const visit = n => {if (!n || typeof n !== 'object') return;
    if (n.type === 'Property' && n.key?.name === 'prepareSourceRead') found.push(n);
    for (const value of Object.values(n)) {if (Array.isArray(value)) value.forEach(visit); else if (value && typeof value === 'object') visit(value);}};
  visit(install); assert.equal(found.length, 1);
  const declaration={},entry={declaration};
  const read = new Function('current','sharedRuns','entry','fail', 'return ({' + text.slice(found[0].start, found[0].end) + '}).prepareSourceRead;')(
    current,sharedRuns,entry,fail);
  assert.throws(() => read({checkedOwner:prepared,effectful:true,declaration,
    occurrence:{stage:0,input:0},managedRun:parent,originalRead:{},requestIdentity:request}),
    {code:'LocalFilesSourcePreparationMismatch'});
});

// Execute the real Local cleanup owner with explicit typed-read/parent and
// native-child ports. These are retirement ordering counters, not actual Core
// capacity, FileHandle closure, ordinary Host or same-process Saved acceptance.
function localReadCleanupFixture({keyed = false, physical = false} = {}) {
  const text = readFileSync(new URL('../connectors/local/host/installed-project-files.mjs', import.meta.url), 'utf8');
  const tree = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const install = tree.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'installPreparedProjectLocalFiles').declaration;
  const functions = install.body.body.filter(node => node.type === 'FunctionDeclaration' &&
    ['captureClose','closeSharedReadExternal','releaseSharedRead','closeRead','close'].includes(node.id.name));
  assert.equal(functions.length,5);
  const acknowledgment = tree.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'acknowledged'));
  assert(acknowledgment);
  const typedRead = {}, parent = {}, events = [];
  const state = {rawAck: {pending: false}, physicalAck: {pending: false},
    rawCalls: 0, physicalCalls: 0, readRetireCalls: 0, parentRetireCalls: 0,
    rawThrows: false, rawFailure: undefined, retireThrows: false, retireFailure: undefined,
    readReceivers: [], readKinds: []};
  const raw = {close() {
    assert.strictEqual(this, raw); state.rawCalls++; events.push('raw');
    if (state.rawThrows) throw state.rawFailure;
    return state.rawAck;
  }};
  const native = {close() {
    assert.strictEqual(this, native); state.physicalCalls++; events.push('physical');
    return state.physicalAck;
  }};
  const read = {raw, keyed, value: typedRead, physical: physical ? native : undefined,
    close: undefined, closeCaptured: false, closed: false};
  const run = {value: parent, reads: new Map([[0, read]]), retired: false};
  read.owner=run;read.index=0;
  const sharedReads=new Set([read]),reads=new WeakMap([[typedRead,{run,read}]]);
  const runs = new Map([[{}, run]]);
  const retireRead = kind => function(value) {
    assert.strictEqual(value, typedRead); state.readRetireCalls++; state.readReceivers.push(this);
    state.readKinds.push(kind); events.push('typed-read');
    if (state.retireThrows) throw state.retireFailure;
  };
  const moon = {clientProgramInstalledSourceReadRetire: retireRead('ordinary'),
    clientProgramInstalledKeyedSourceReadRetire: retireRead('keyed'),
    clientProgramInstalledManagedRunRetire(value) {
      assert.strictEqual(this, moon); assert.strictEqual(value, parent);
      state.parentRetireCalls++; events.push('parent');
    }, clientProgramNodeManagedRunCleanup() {assert.fail('No replacement parent cleanup');}};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const cleanup = new Function('sharedReads','reads', 'moon', 'checked', 'fail',
    text.slice(acknowledgment.start, acknowledgment.end) + ';let closing=false;\n' +
    functions.map(node => text.slice(node.start, node.end)).join('\n') +
    ';return {close,closeRead};')(sharedReads,reads, moon, value => value, fail);
  return {...cleanup, state, read, raw, run, runs, sharedReads, moon, events};
}

test('Local Source typed read and parent remain live until the original raw child acknowledges', async () => {
  const f = localReadCleanupFixture(); f.state.rawAck = {pending: true};
  await assert.rejects(f.close(), {name: 'AggregateError', message: 'LocalFilesCleanupPending'});
  assert.equal(f.state.rawCalls, 1); assert.equal(f.state.readRetireCalls, 0);
  assert.equal(f.state.parentRetireCalls, 0); assert.equal(f.read.closed, false);
  f.raw.close = () => assert.fail('Replacement close must not be selected');
  f.state.rawAck = {pending: false}; await f.close();
  assert.deepEqual(f.events, ['raw', 'raw', 'typed-read']);
  assert.deepEqual(f.state.readReceivers, [f.moon]);
  assert.equal(f.read.closed,true);assert.equal(f.sharedReads.size,0);assert.equal(f.run.reads.get(0),undefined);
  assert.equal(f.run.retired,false);assert.equal(f.runs.size,1,'Local child cleanup does not retire the Host parent');
});

test('Local keyed cleanup preserves an original thrown undefined before typed retirement', async () => {
  const f = localReadCleanupFixture({keyed: true}); f.state.rawThrows = true;
  await assert.rejects(f.close(), cause => cause instanceof AggregateError &&
    cause.errors.length === 1 && cause.errors[0] === undefined);
  assert.equal(f.state.readRetireCalls, 0); assert.equal(f.state.parentRetireCalls, 0);
  assert.equal(f.read.closed, false); f.state.rawThrows = false; await f.close();
  assert.deepEqual(f.state.readKinds, ['keyed']); assert.deepEqual(f.state.readReceivers, [f.moon]);
  assert.equal(f.state.parentRetireCalls, 0, 'The Host retains its original parent retirement duty');
});

test('Local cleanup waits for physical and raw acknowledgments before typed retirement', async () => {
  const f = localReadCleanupFixture({physical: true}); f.state.physicalAck = {pending: true};
  await assert.rejects(f.close(), {name: 'AggregateError'});
  assert.equal(f.state.rawCalls, 0); assert.equal(f.state.readRetireCalls, 0);
  f.state.physicalAck = {pending: false}; f.state.rawAck = {pending: true};
  await assert.rejects(f.close(), {name: 'AggregateError'});
  assert.equal(f.state.rawCalls, 1); assert.equal(f.state.readRetireCalls, 0);
  f.state.rawAck = {pending: false}; await f.close();
  assert.equal(f.state.readRetireCalls, 1); assert.equal(f.state.parentRetireCalls, 0, 'The Host retains its original parent retirement duty');
});

test('Local cleanup retains the same stopped child while typed retirement fails', async () => {
  const f = localReadCleanupFixture(), failure = new Error('OriginalTypedRetirementPending');
  f.state.retireThrows = true; f.state.retireFailure = failure;
  await assert.rejects(f.close(), cause => cause instanceof AggregateError && cause.errors[0] === failure);
  assert.equal(f.state.rawCalls, 1); assert.equal(f.state.readRetireCalls, 1);
  assert.equal(f.read.closed, false); assert.equal(f.state.parentRetireCalls, 0);
  f.state.retireThrows = false; await f.close();
  assert.equal(f.state.readRetireCalls, 2); assert.equal(f.state.parentRetireCalls, 0, 'The Host retains its original parent retirement duty');
  assert.deepEqual(f.state.readReceivers, [f.moon, f.moon]);
});

test('Local cleanup never treats absent inherited or accessor stop DATA as acknowledgment', async () => {
  let getters = 0;
  for (const ack of [undefined, Object.create({pending: false}),
    Object.defineProperty({}, 'pending', {get() {getters++; return false;}})]) {
    const f = localReadCleanupFixture(); f.state.rawAck = ack;
    await assert.rejects(f.close(), {name: 'AggregateError'});
    assert.equal(f.state.readRetireCalls, 0); assert.equal(f.state.parentRetireCalls, 0);
    f.state.rawAck = {pending: false}; await f.close();
    assert.equal(f.state.readRetireCalls, 1);
  }
  assert.equal(getters, 0);
});

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
  return new Function(...Object.keys(ports),
    source.slice(node.declaration.start, node.declaration.end) + `;return ${name};`)(...Object.values(ports));
}
function fixture() {
  const prepared = {}, request = {}, raw = {}, initialControl = {};
  let current = true;
  const calls = [];
  const limits = [7n, 2n, 3n, 0n, 32n, 64n];
  const moon = {
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
    canonicalValueJson(value, options) {assert.deepEqual(options, {dataKeys: true}); return JSON.stringify(value);},
    clientOperationError: code => Object.assign(new Error(code), {code}),
  };
  return {prepared, request, raw, originals, moon, calls, limits, ports,
    stop: () => {current = false;},
    requirements: () => actual('readManagedComputeRunRequirements', ports),
    intent: () => actual('managedComputeSubmittedIntentCid', ports)};
}

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
    'registry-original', '{"kind":"values"}', '{"kind":"expression"}', '{"kind":"derive"}']);
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
  const f = fixture(), original = {}, run = {runtime: f.moon, prepared: f.prepared, closed: false};
  f.originals.installation.computeRuns = new Map([[f.prepared, run]]);
  f.moon.clientProgramPrepareInstalledManagedSourceFree = (...args) => {
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
  assert.deepEqual(f.calls[0][1], [f.prepared, 'registry-original',
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
    f => {f.moon.clientProgramPrepareInstalledManagedSourceFree = undefined;},
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

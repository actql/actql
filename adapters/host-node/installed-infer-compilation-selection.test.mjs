import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Actual Host planning closure, with explicit compiler ports. This verifies
// compiler selection and original forwarding, not a public execution/permission.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
let initializer;
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' && node.id.name === 'planFor') {
    assert.equal(initializer, undefined);
    initializer = source.slice(node.init.start, node.init.end);
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value !== null && typeof value === 'object') visit(value);
  }
}
visit(tree);
assert.equal(typeof initializer, 'string');
const instantiate = new Function('ports', `
  const {prepareSubmit, earlyMockInferPlans, earlyContentPlans, inferSelections,
    inferTaskRunAdmission, control, moon, authorityScopeCid, namespaceId,
    storeAuthorityCid, now, diagnostic, preparation} = ports;
  return (${initializer});
`);
function fixture({composed = false, multiple = false, modelArtifact} = {}) {
  const prepared = {}, occurrence = {}, one = {}, two = {}, compiled = {};
  const graph = multiple ? [one, two] : one;
  const selection = {graph, ...(composed ? {occurrence} : {})};
  const calls = [];
  const planFor = instantiate({
    prepareSubmit: {assertOwned(value) {assert.strictEqual(value, prepared);}, originalInferRun() {}},
    earlyMockInferPlans: new Map(), earlyContentPlans: new Map(),
    inferSelections: new Map([[prepared, selection]]), control: {}, moon: {},
    preparation: modelArtifact === undefined ? undefined : {
      prepareManagedModelCompilation(_moon, actual, original) {
        assert.equal(actual, prepared); assert.equal(original, graph); return modelArtifact;
      },
    },
    authorityScopeCid: 'original-authority', namespaceId: 'original-namespace',
    storeAuthorityCid: 'original-store', now: () => '2026-10-21T00:00:00.000Z',
    diagnostic() {assert.fail('No failure substitution');},
    inferTaskRunAdmission(options) {
      calls.push(options);
      return Object.freeze({compiled, inferGraph: options.inferGraph});
    },
  });
  return {prepared, graph, compiled, calls, run: () => planFor({preparedProgram: prepared, requestId: 'original-request'})};
}
test('Host selects the composed compiler for its retained single INFER occurrence', () => {
  const f = fixture({composed: true}), plan = f.run();
  assert(Array.isArray(f.calls[0].inferGraph));
  assert.equal(f.calls[0].inferGraph.length, 1);
  assert.strictEqual(f.calls[0].inferGraph[0], f.graph);
  assert.strictEqual(plan.inferGraph, f.graph);
  assert.strictEqual(plan.compiled, f.compiled);
});
test('Host preserves the legacy INFER compiler without a composed occurrence', () => {
  const f = fixture(), plan = f.run();
  assert.strictEqual(f.calls[0].inferGraph, f.graph);
  assert.strictEqual(plan.inferGraph, f.graph);
});
test('Host preserves the original multiple INFER component array', () => {
  const f = fixture({composed: true, multiple: true}), plan = f.run();
  assert.strictEqual(f.calls[0].inferGraph, f.graph);
  assert.strictEqual(plan.inferGraph, f.graph);
});


test('Host Model admission forwards the same original Request artifact into its existing plan consumer', () => {
  const artifact = {}, f = fixture({composed: true, modelArtifact: artifact});
  f.run(); assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].compilationOriginal, artifact);
});

// Actual physical selection statements, explicit immutable occurrence/runtime
// ports. No Common ABI, parent funding, provider IO or normal Host is supplied.
function inputSelectionFixture({acquisitions = 1, managed = true, physical = true, serialized = false} = {}) {
  const nodes = [];
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    nodes.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(tree);
  const declarations = nodes.filter(node => node.type === 'VariableDeclaration');
  const segment = declarations.find(node => node.declarations[0]?.id?.name === 'segments' &&
    source.slice(node.start, node.end).includes('serializationGraph !== undefined'));
  const suffix = declarations.find(node => node.start > segment.start &&
    node.declarations[0]?.id?.name === 'computeSuffix');
  assert(segment); assert(suffix);
  const deferred = declarations.find(node => node.declarations[0]?.id?.name === 'deferredModelInput');
  const body = (deferred ? source.slice(deferred.start, deferred.end) : '') +
    source.slice(segment.start, suffix.end) + ';return {segments, computeSuffix};';
  const prepared = {}, occurrence = {}, prefix = {}, suffixValue = {}, serializationGraph = serialized ? {} : undefined;
  const calls = [], error = new Error('OriginalUnbackedInputSegmentConstructor');
  const moon = {clientProgramAcquisitionCount(p) {assert.equal(p, prepared); return acquisitions;},
    clientProgramPrepareComposedInferSegments(...args) {
      assert.equal(args[0], prepared); assert.equal(args[1], occurrence); calls.push('segments');
      if (acquisitions === 1 && managed && physical && !serialized) throw error;
      return {prefix, suffix: suffixValue};
    },
    clientProgramPrepareComposedInferComputeSuffix(...args) {
      assert.equal(args[0], prepared); assert.equal(args[1], occurrence); calls.push('Content suffix'); return suffixValue;
    }};
  const ports = {preparation: managed ? {} : undefined, physical: physical ? {originalReadInstallation: {}} : {},
    preparedProgram: prepared, occurrence, serializationGraph, effectGraph: undefined, step: 2,
    prepareSubmit: {kindOf: () => 'effect_free'}, moon, registry: {}, values: {}, fragment: {}, ordered: {},
    checked: value => value, runtimeField: (value, index) => index === 1 ? value.suffix : value.prefix,
    runtimeOptionalField: (value, index) => value === undefined ? undefined : index === 0 ? value.prefix : value.suffix};
  const select = Function(...Object.keys(ports), body)(...Object.values(ports));
  return {select, calls, prefix, suffix: suffixValue, error};
}

test('managed acquired Node Model defers input segments to its same Request module before any standalone constructor', () => {
  const f = inputSelectionFixture();
  assert.deepEqual(f.select, {segments: undefined, computeSuffix: undefined});
  assert.deepEqual(f.calls, []);
});

test('existing sourcefree legacy and serialized Model segment selection keep their actual original ports', () => {
  for (const options of [{acquisitions: 0}, {managed: false}, {physical: false}]) {
    const f = inputSelectionFixture(options);
    assert.equal(f.select.segments.prefix, f.prefix); assert.equal(f.select.computeSuffix, f.suffix);
    assert.deepEqual(f.calls, ['segments']);
  }
  const content = inputSelectionFixture({serialized: true});
  assert.equal(content.select.segments, undefined); assert.equal(content.select.computeSuffix, content.suffix);
  assert.deepEqual(content.calls, ['Content suffix']);
});

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

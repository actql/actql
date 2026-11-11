import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// Execute the actual publication caller with explicit Core/plan ports.
// These are routing tests, not a Runtime, Source read or resource ACK.
const text = readFileSync(new URL('./local-values-plan.mjs', import.meta.url), 'utf8');
const tree = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
const body = name => {
  const node = tree.body.find(item => item.declaration?.id?.name === name)?.declaration;
  assert.ok(node);
  return text.slice(node.start, node.end);
};
const limits = {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20};

function fixture({mixed = false, refusal} = {}) {
  const calls = [], sourcePlan = {}, sourceObjects = [{}, {}];
  const originals = sourceObjects.map(() => ({}));
  const sources = sourceObjects.slice(0, mixed ? 2 : 1).map((source, index) => ({
    sourceEvidence: originals[index], sourceEvidenceWire: `original-source-${index}`,
    captured: {identity: {index}, logicalInput: {},
      ...(index === 0 ? {inputKind: 'whole-input', wholeCapacity: {}} : {requirement: {}}),
      capture: {source: () => source}, checkedSource: {sourceDataPolicyCid: `policy-${index}`}},
  }));
  const owner = {}, retention = {wire: '{"effective_data_policy_cid":"joined"}'};
  const acquired = {moon: {
    clientProgramEffectPublicationDataPolicyCid: () => 'joined',
    clientProgramEffectDefinitionCid: () => 'definition',
    clientProgramEffectCompilationResultNames: () => ['result'],
    clientProgramCapturedSourceLogicalCid: identity => `logical-${identity.index}`,
    clientProgramCapturedSourceSchemaCid: identity => `schema-${identity.index}`,
    clientProgramCapturedSourceDependencyBodies: () => ({_0: '{}', _1: '{}'}),
    clientProgramEffectPublicationPolicyBodies: () => ({$tag: 1, _0: []}),
  }, prepared: {}, requestIdentity: {}, compilation: {}, admission: {}, definition: {},
  runDefinition: {wire: '{"created_at":"2026-11-11T00:00:00Z","valid_until":"2026-11-12T00:00:00Z"}'},
  compiledPlan: {identity: 'compiled'}, authorityScopeCid: 'scope',
  namespaceId: 'namespace', storeAuthorityCid: 'store', now: () => '2026-11-11T00:00:00Z'};
  acquired.control = {
    admitRunEvidence(name, wire, bounds) {
      assert.equal(name, 'source_evidence'); assert.strictEqual(bounds, limits);
      calls.push('admit'); return originals[Number(wire.at(-1))];
    },
    issueCheckedClientEffectCapturedInvocation() { assert.fail('Whole never enters the Query-only caller'); },
    issueCheckedClientEffectMultiCapturedInvocation() { assert.fail('Whole never becomes a Query requirement'); },
    issueCheckedInstalledEffectDirectSourcesInvocation(plan, prepared, request, compilation,
      admission, definition, actual, evidence, context, bounds) {
      assert.strictEqual(plan, sourcePlan); assert.strictEqual(prepared, acquired.prepared);
      assert.strictEqual(request, acquired.requestIdentity); assert.strictEqual(compilation, acquired.compilation);
      assert.strictEqual(admission, acquired.admission); assert.strictEqual(definition, acquired.definition);
      for (let index = 0; index < actual.length; index++) {
        assert.strictEqual(actual[index].captured, sources[index].captured);
        assert.strictEqual(evidence[index], originals[index]);
      }
      assert.equal(context.dataPolicyCid, 'joined'); assert.strictEqual(bounds, limits);
      calls.push('original-invocation');
      if (refusal !== undefined) throw refusal;
      return {observation: {}, invocation: {}, owner};
    },
    issueCheckedWholeEffectSourceUnit(plan, prepared, request, slot, source, identity,
      capacity, input, evidence, scope, originalRetention, bounds) {
      assert.strictEqual(plan, sourcePlan); assert.strictEqual(request, acquired.requestIdentity);
      assert.equal(slot, 0); assert.strictEqual(source, sourceObjects[0]);
      assert.strictEqual(identity, sources[0].captured.identity);
      assert.strictEqual(capacity, sources[0].captured.wholeCapacity);
      assert.strictEqual(input, sources[0].captured.logicalInput);
      assert.strictEqual(evidence, originals[0]); assert.strictEqual(originalRetention, retention);
      assert.strictEqual(bounds, limits); calls.push('whole-unit');
      return {catalogBodies: []};
    },
    seal() { calls.push('query-retention'); return {}; },
    issueCheckedAcquiredEffectEvidence(...args) {
      assert.strictEqual(args[3], sources[1].captured.requirement);
      assert.strictEqual(args[5], originals[1]); calls.push('query-unit');
      return {catalogBodies: []};
    },
  };
  const buildLocalPublicationPlan = () => {
    calls.push('plan'); return {plan: {}, retention, retentionDependencies: []};
  };
  const create = Function('runtimeField', 'runtimeOptionalField', 'checked', 'limits',
    'buildLocalPublicationPlan', body('acquiredEffectPublicationPlan') + '\n' +
    body('acquiredMultiEffectPublicationPlan') +
    '\nreturn {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan};');
  const methods = create(runtimeField, runtimeOptionalField, checked, limits, buildLocalPublicationPlan);
  const invoke = () => mixed ? methods.acquiredMultiEffectPublicationPlan({acquired, sources,
    sourcePlan, captureStartedAt: 'start', captureCompletedAt: 'end'})
    : methods.acquiredEffectPublicationPlan({acquired, ...sources[0], sourcePlan,
      captureStartedAt: 'start', captureCompletedAt: 'end'});
  return {invoke, calls, owner, sources, acquired, sourcePlan};
}

test('single Whole Effect uses its original invocation and Whole Unit ports', () => {
  const f = fixture(), plan = f.invoke();
  assert.strictEqual(plan.invocationOwner, f.owner);
  assert.deepEqual(f.calls, ['admit', 'original-invocation', 'plan', 'whole-unit']);
  assert.equal(Object.hasOwn(f.sources[0].captured, 'requirement'), false);
});

test('mixed Effect preserves Query and Whole originals at their respective Unit ports', () => {
  const f = fixture({mixed: true}), plan = f.invoke();
  assert.strictEqual(plan.invocationOwner, f.owner);
  assert.deepEqual(f.calls, ['original-invocation', 'plan', 'whole-unit', 'query-retention', 'query-unit']);
  assert.equal(plan.localEvidenceContext.acquiredEvidenceByUnit.length, 2);
});

test('an original invocation refusal does not fall back or issue producer evidence', () => {
  const original = new Error('OriginalCapturedSourceRefused'), f = fixture({mixed: true, refusal: original});
  assert.throws(f.invoke, error => error === original);
  assert.deepEqual(f.calls, ['original-invocation']);
});

test('direct invocation forwarding preserves the same namespace originals without wire emission', () => {
  const source = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8');
  const parsed = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let property;
  (function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'issueCheckedInstalledEffectDirectSourcesInvocation') property = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  })(parsed);
  assert.ok(property);
  const originals = Array.from({length: 11}, () => ({}));
  const [plan, prepared, request, compilation, admission, definition,
    capture, identity, input, evidence, invocation] = originals;
  const observation = {}, context = {authorityScopeCid: 'scope', dataPolicyCid: 'policy',
    captureStartedAt: 'start', captureCompletedAt: 'end'};
  let calls = 0, reads = 0;
  const moon = {clientProgramIssueInstalledEffectDirectSourcesInvocation(...args) {
    calls++;
    assert.deepEqual(args, [plan, prepared, request, compilation, admission, definition,
      [capture], [identity], [evidence], [input], 'scope', 'policy', 'start', 'end',
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth]);
    return {$tag: 1, _0: {_0: observation, _1: invocation}};
  }};
  const create = Function('issuanceLimits', 'checked', 'moon', 'admissionToken',
    'evidenceToken', 'runtimeField', 'inspectEvidence', 'inspect',
    'return ({' + source.slice(property.start, property.end) + '});');
  const methods = create((actual, label) => {
    assert.strictEqual(actual, limits); assert.equal(label, 'Client original Effect Sources Invocation');
  }, checked, moon, value => value.original, value => value.original, runtimeField,
  original => ({original}), original => ({original}));
  const returned = methods.issueCheckedInstalledEffectDirectSourcesInvocation(
    plan, prepared, request, compilation, {original: admission}, definition,
    [{captured: {capture: {source() { reads++; return capture; }}, identity, logicalInput: input}}],
    [{original: evidence, get wire() { assert.fail('do not emit admitted original evidence'); }}], context, limits);
  assert.strictEqual(returned.owner, invocation);
  assert.strictEqual(returned.observation.original, observation);
  assert.equal(calls, 1); assert.equal(reads, 1);
});

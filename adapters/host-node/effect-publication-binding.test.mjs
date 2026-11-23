import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

// Execute the actual private Runtime forwarding methods with explicit ports.
// Core original authority and cleanup are exercised by the genuine Core tests.
const source = readFileSync(new URL('../host-common/runtime-effect-preparation-control.mjs', import.meta.url), 'utf8');
const properties = new Map();
(function visit(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'Property' && node.key?.name) properties.set(node.key.name, node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  }
})(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
const limits = {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20};
const bounds = Object.values(limits);
function method(name, moon, maps = {}) {
  const property = properties.get(name);
  assert.ok(property, name);
  return Function('moon', 'checked', 'runtimeField', 'issuanceLimits',
    'captureContractLimits', 'admissionToken', 'evidenceToken', 'token',
    'inspect', 'inspectAdmission', 'inspectEvidence', 'inferInvocationTokens',
    'compiledRunTokens', 'serializationGenerationTokens',
    'return ({' + source.slice(property.start, property.end) + '});')(
      moon, checked, runtimeField, () => {}, value => value, value => value.raw,
      value => value.raw, value => value.raw, value => ({raw: value}),
      value => ({raw: value}), value => ({raw: value}),
      maps.infer ?? new WeakMap(), maps.compiled ?? new WeakMap(),
      maps.generation ?? new WeakMap())[name];
}
const ok = value => ({$tag: 1, _0: value});
const tuple = (observation, invocation) => ({_0: observation, _1: invocation});
function originals() {
  const values = Array.from({length: 9}, () => ({}));
  const [parent, prepared, request, plan, host, compilation, admission, definition, original] = values;
  return {parent, prepared, request, plan, host, compilation, admission, definition, original,
    args: values.slice(0, 6).concat({raw: admission}, definition)};
}

test('original Allow and early Values tuple are inspected without a second admission or issuer', () => {
  const allowed = {}, definition = {}, admission = {}, receipt = {}, observation = {}, invocation = {};
  let admits = 0, issues = 0;
  const moon = {
    clientProgramAllowedEffectRunAdmission(value) {assert.equal(value, allowed); admits++; return admission;},
    clientProgramIssueEffectSourceFreeInvocationOriginal(...args) {
      assert.deepEqual(args, ['compiled', 'policy', ...bounds]); issues++; return ok(receipt);
    },
    clientProgramEffectSourceFreeInvocationOriginalInvocation(value) {assert.equal(value, receipt); return invocation;},
    clientProgramEffectSourceFreeInvocationOriginalObservation(value) {assert.equal(value, receipt); return observation;},
  };
  const admitted = method('originalCheckedClientEffectPublication', moon)(allowed, definition, limits);
  assert.equal(admitted.admission.raw, admission); assert.equal(admitted.runDefinition.raw, definition);
  const issued = method('issueCheckedClientEffectSourceFreeInvocationOriginal', moon)('compiled', 'policy', limits);
  assert.equal(issued.original, receipt); assert.equal(issued.owner, invocation);
  assert.equal(issued.observation.raw, observation); assert.equal(issued.invocation.raw, invocation);
  assert.equal(admits, 1); assert.equal(issues, 1);
});

test('late Values binding consumes its exact early receipt once at the closed port', () => {
  const o = originals(), runDefinition = {raw: o.definition}; let calls = 0;
  method('bindCheckedInstalledEffectSourceFreeInvocation', {
    clientProgramBindInstalledEffectSourceFreeInvocation(...args) {
      assert.deepEqual(args, [o.parent, o.prepared, o.request, o.plan, o.host,
        o.admission, o.definition, o.original]); calls++; return ok(undefined);
    },
  })(o.parent, o.prepared, o.request, o.plan, o.host, {raw: o.admission}, runDefinition, o.original);
  assert.equal(calls, 1);
});

test('single Source forwards actual managed host and original source only once', () => {
  const o = originals(), captured = {}, observation = {}, invocation = {};
  const source = {sourceEvidenceWire: 'evidence', inputLogicalWire: 'logical', sourceRef: 'source',
    sourceContractCid: 'contract', authorityScopeCid: 'scope', dataPolicyCid: 'policy',
    captureStartedAt: 'start', captureCompletedAt: 'end'};
  let calls = 0;
  const result = method('issueCheckedInstalledEffectCapturedInvocation', {
    clientProgramIssueInstalledEffectCapturedInvocation(...args) {
      assert.deepEqual(args, [...o.args.slice(0, 6), o.admission, o.definition, captured,
        ...Object.values(source), ...bounds]); calls++; return ok(tuple(observation, invocation));
    },
  })(...o.args, captured, source, limits);
  assert.equal(result.owner, invocation); assert.equal(result.observation.raw, observation); assert.equal(calls, 1);
});

test('plural Source forwards physical occurrences separately at one closed issuer', () => {
  const o = originals(), captured = [{}, {}], identities = [{}, {}], requirements = [{}, {}];
  const sources = captured.map((value, index) => ({sourceEvidenceWire: `e${index}`,
    captured: {capture: {source: () => value}, identity: identities[index],
      requirement: requirements[index], logicalInput: `l${index}`}}));
  const context = {authorityScopeCid: 'scope', dataPolicyCid: 'policy', captureStartedAt: 'start', captureCompletedAt: 'end'};
  let calls = 0;
  method('issueCheckedInstalledEffectMultiCapturedInvocation', {
    strategyRunEvidenceJson: value => value,
    clientProgramIssueInstalledEffectMultiCapturedInvocation(...args) {
      assert.deepEqual(args, [...o.args.slice(0, 6), o.admission, o.definition, captured,
        identities, requirements, ['e0', 'e1'], ['l0', 'l1'], ...Object.values(context), ...bounds]);
      calls++; return ok(tuple({}, {}));
    },
  })(...o.args, sources, context, limits);
  assert.equal(calls, 1);
});

test('Direct Source preserves actual inputs and typed evidence without wire re-admission', () => {
  const o = originals(), captured = {}, identity = {}, input = {}, evidence = {}, invocation = {}, publication = {};
  let calls = 0;
  const context = {authorityScopeCid: 'scope', dataPolicyCid: 'policy', captureStartedAt: 'start', captureCompletedAt: 'end'};
  const result = method('issueCheckedOriginalEffectDirectSourcesInvocation', {
    clientProgramIssueOriginalEffectDirectSourcesInvocation(...args) {
      assert.deepEqual(args, [...o.args.slice(0, 6), o.admission, o.definition, [captured], [identity],
        [evidence], [input], ...Object.values(context), ...bounds]); calls++; return ok(publication);
    },
    clientProgramEffectDirectSourcesPublicationInvocation: value => {assert.equal(value, publication); return invocation;},
    clientProgramEffectDirectSourcesPublicationObservation: () => ({}),
  })(...o.args, [{captured: {capture: {source: () => captured}, identity, logicalInput: input}}],
    [{raw: evidence, get wire() {assert.fail('typed original never emits a replacement wire');}}], context, limits);
  assert.equal(result.owner, invocation); assert.equal(result.sourcePublication, publication); assert.equal(calls, 1);
});

test('Model uses only its opaque original binding and rejects foreign issued DATA before Core', () => {
  const o = originals(), issued = {binding: {}}, compiled = {}, invocation = {}, infer = new WeakMap([[issued, {compiled}]]);
  let calls = 0;
  const bind = method('bindCheckedInstalledEffectModelInvocation', {
    clientProgramBindInstalledEffectModelInvocation(...args) {
      assert.deepEqual(args, [...o.args.slice(0, 6), o.admission, o.definition, compiled, issued.binding]);
      calls++; return ok(tuple({}, invocation));
    },
  }, {infer});
  assert.equal(bind(...o.args, issued).owner, invocation);
  assert.throws(() => bind(...o.args, {binding: issued.binding}), /Foreign Effect Infer Invocation/);
  assert.equal(calls, 1);
});

test('Content forwards original compiled generation and rejects foreign copies before Core', () => {
  const o = originals(), compiled = {}, generation = {}, rawCompiled = {}, rawGeneration = {}, invocation = {};
  const maps = {compiled: new WeakMap([[compiled, rawCompiled]]), generation: new WeakMap([[generation, rawGeneration]])};
  let calls = 0;
  const issue = method('issueCheckedInstalledEffectContentInvocation', {
    clientProgramIssueInstalledEffectContentInvocation(...args) {
      assert.deepEqual(args, [...o.args.slice(0, 6), o.admission, o.definition,
        rawCompiled, rawGeneration, ...bounds]); calls++; return ok(tuple({}, invocation));
    },
  }, maps);
  assert.equal(issue(...o.args, compiled, generation, limits).owner, invocation);
  assert.throws(() => issue(...o.args, compiled, {}, limits), /Foreign Client Content generation/);
  assert.equal(calls, 1);
});

test('closed binding preserves original Core refusal without fallback or reissue', () => {
  const o = originals(), primary = new Error('original Core refusal'); let calls = 0;
  const bind = method('bindCheckedInstalledEffectSourceFreeInvocation', {
    clientProgramBindInstalledEffectSourceFreeInvocation() {calls++; throw primary;},
  });
  assert.throws(() => bind(o.parent, o.prepared, o.request, o.plan, o.host,
    {raw: o.admission}, {raw: o.definition}, o.original), value => value === primary);
  assert.equal(calls, 1);
});

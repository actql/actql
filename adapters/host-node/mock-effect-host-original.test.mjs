import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual private Host functions with explicit Common/Journal and
// physical-owner ports. This covers original binding/order, not a generated
// current Common, ordinary SDK/Host or file UPDATE acceptance.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const host = tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openInstalledHost');
const statements = [];
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (typeof node.type === 'string') statements.push(node);
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child !== null && typeof child === 'object') visit(child);
  }
}
visit(host.body);
const selectedNames = ['assertMockEffectRunOriginal', 'retainMockEffectRunOriginal'];
const functions = statements.filter(node => node.type === 'FunctionDeclaration' &&
  selectedNames.includes(node.id.name)).map(node => source.slice(node.start, node.end)).join('\n');
assert.equal(statements.filter(node => node.type === 'FunctionDeclaration' && selectedNames.includes(node.id.name)).length, 2);
const variable = name => {
  const matches = statements.filter(node => node.type === 'VariableDeclarator' && node.id.name === name);
  assert.equal(matches.length, 1, name);
  return matches[0];
};
const resources = variable('mockEffectResources');
const effectRun = variable('effectRun').init.alternate.arguments[0];
const preparationNode = effectRun.properties.find(node => node.key.name === 'prepareDefinition').value.alternate;

function fixture() {
  const calls = [], prepared = {}, compilation = {}, allowed = {}, definition = {};
  const identity = {request: 'original'}, compiled = {}, runDefinition = {identity: 'actual-run'};
  const facts = {prepared, compilation, allowed, definition, identity, modelCompiled: compiled, runDefinition};
  const mockEffectRuns = new Map(), mockEffectOriginals = new WeakMap(), earlyMockEffectPlans = new WeakMap();
  const inferSelections = new WeakMap();
  let current = true, ownedRecovery = true, physicalFailure;
  const refusal = new Error('OriginalHostNotCurrent');
  const currentHost = () => {if (!current) throw refusal;};
  const clientOperationError = code => Object.assign(new Error(code), {code});
  const actualLimits = Object.freeze({maxFileBytes: 1048576, maxRows: 100});
  let api;
  const mockEffectObservation = {};
  const mockEffectObservationMethods = {limits(original) {
    assert.strictEqual(this, mockEffectObservation);
    calls.push('physical-original');
    api.mockEffectResources.assertCurrent(original);
    if (physicalFailure !== undefined) throw physicalFailure;
    return actualLimits;
  }};
  const moon = {clientProgramBindCompiledEffectRun(p, a, d) {
    assert.strictEqual(p, prepared); assert.strictEqual(a, allowed); assert.strictEqual(d, definition);
    calls.push('typed-run'); return {$tag: 1, _0: {}};
  }, clientRequestCallerId(value) {assert.strictEqual(value, identity); return value.request;}};
  const journal = {lookupOwnedDefinition(key, core, control) {
    assert.strictEqual(core, moon); assert.equal(key.requestId, identity.request);
    calls.push('saved-journal'); return ownedRecovery ? {runDefinition} : undefined;
  }};
  const control = {}, preparation = {assertResultPublicationCurrent: currentHost,
    admitEffectResultPublicationRun(p) {assert.strictEqual(p, prepared); calls.push('result-purpose');},
    modelPublicationCapacity() {return {};}};
  const sourceProfile = {
    prepareManagedEffectRun(p, r) {
      assert.strictEqual(p, prepared); assert.strictEqual(r, identity); calls.push('source-scope');
    },
    prepareManagedEffectMockModelRun(p, r, c, plan, selection, capacity, originalCompilation) {
      assert.strictEqual(p, prepared); assert.strictEqual(r, identity); assert.strictEqual(c, control);
      assert.strictEqual(plan.compiled, compiled); assert.strictEqual(plan.runDefinition, runDefinition);
      assert.strictEqual(originalCompilation, compilation); assert.equal(typeof capacity, 'function');
      calls.push('mock-scope');
    },
  };
  api = new Function('assertProjectRuntime', 'preparation', 'clientOperationError', 'mockEffectOriginals',
    'mockEffectRuns', 'mockEffectObservationMethods', 'mockEffectObservation', 'moon', 'checked',
    'journal', 'namespaceId', 'authorityScopeCid', 'control', 'sourceProfile', 'inferSelections', 'earlyMockEffectPlans',
    functions + '\nconst mockEffectResources=' + source.slice(resources.init.start, resources.init.end) +
    ';const prepareDefinition=' + source.slice(preparationNode.start, preparationNode.end) +
    ';return {mockEffectResources, retainMockEffectRunOriginal, prepareDefinition};')(
      currentHost, preparation, clientOperationError, mockEffectOriginals, mockEffectRuns,
      mockEffectObservationMethods, mockEffectObservation, moon,
      value => {if (value.$tag !== 1) throw value._0; return value._0;},
      journal, 'namespace', 'authority', control, sourceProfile, inferSelections, earlyMockEffectPlans);
  return {...api, calls, facts, originalFacts: facts, actualLimits, inferSelections, earlyMockEffectPlans,
    refusal, revoke() {current = false;}, failPhysical(value) {physicalFailure = value;},
    denyRecovery() {ownedRecovery = false;}};
}

test('winning Effect definition prepares the same Source Scope before actual file-owner binding', () => {
  const f = fixture(); f.prepareDefinition(f.facts);
  assert.deepEqual(f.calls, ['result-purpose', 'source-scope', 'typed-run', 'physical-original']);
  const original = f.mockEffectResources.bindRunOriginal(f.facts);
  assert.strictEqual(f.mockEffectResources.limits(original), f.actualLimits);
  assert.throws(() => f.mockEffectResources.bindRunOriginal({...f.facts, compilation: {}}),
    {code: 'ForeignInstalledMockEffectRun'});
  assert.throws(() => f.mockEffectResources.assertCurrent({...original}), {code: 'ForeignInstalledMockEffectRun'});
});

test('winning Mock Effect definition retains its original compiled Run and Scope before file binding', () => {
  const f = fixture(); f.inferSelections.set(f.facts.prepared, {localMock: true});
  f.prepareDefinition(f.facts);
  assert.deepEqual(f.calls, ['result-purpose', 'mock-scope', 'typed-run', 'physical-original']);
  const plan = f.earlyMockEffectPlans.get(f.facts.prepared);
  assert.strictEqual(plan.compiled, f.facts.modelCompiled);
  assert.strictEqual(plan.runDefinition, f.facts.runDefinition);
});

test('file resource binding survives Source phase retirement but still observes original Host currentness', () => {
  const f = fixture(); f.prepareDefinition(f.facts);
  const original = f.mockEffectResources.bindRunOriginal(f.facts);
  // No Source/Model check is used as a physical FileTarget supplier or ACK.
  f.mockEffectResources.assertCurrent(original);
  f.revoke();
  assert.throws(() => f.mockEffectResources.assertCurrent(original), cause => cause === f.refusal);
});

test('partial physical-original failure remains sticky on the same retained Run', () => {
  const f = fixture(), failure = new Error('OriginalFileServiceRefused');
  f.failPhysical(failure);
  assert.throws(() => f.prepareDefinition(f.facts), cause => cause === failure);
  assert.throws(() => f.retainMockEffectRunOriginal(f.facts), cause => cause === failure);
  assert.equal(f.calls.filter(value => value === 'typed-run').length, 1);
  assert.equal(f.calls.filter(value => value === 'physical-original').length, 1);
});

test('saved Effect binding requires the same Journal original before restoring local handles', () => {
  const f = fixture();
  const recovered = {...f.facts, requestIdentity: f.facts.identity};
  f.denyRecovery();
  assert.throws(() => f.mockEffectResources.bindRunOriginal({recovered}),
    {code: 'ForeignInstalledMockEffectRun'});
  assert.deepEqual(f.calls, ['saved-journal']);
});

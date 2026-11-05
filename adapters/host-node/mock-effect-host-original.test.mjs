import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual private Host functions with explicit Common/Journal and
// shared-Plan and physical-owner ports. This covers original binding/order,
// not generated Common, normal funding, ordinary SDK/Host or file UPDATE acceptance.
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
const selectedNames = ['assertMockEffectRunOriginal', 'retainMockEffectRunOriginal', 'selectedInstalledEffect'];
const functions = statements.filter(node => node.type === 'FunctionDeclaration' &&
  selectedNames.includes(node.id.name)).map(node => source.slice(node.start, node.end)).join('\n');
assert.equal(statements.filter(node => node.type === 'FunctionDeclaration' && selectedNames.includes(node.id.name)).length, 3);
const variable = name => {
  const matches = statements.filter(node => node.type === 'VariableDeclarator' && node.id.name === name);
  assert.equal(matches.length, 1, name);
  return matches[0];
};
const resources = variable('mockEffectResources');
const effectRun = variable('effectRun').init.alternate.arguments[0];
const preparationNode = effectRun.properties.find(node => node.key.name === 'prepareDefinition').value;
assert.equal(preparationNode.type, 'ArrowFunctionExpression');

function fixture({composed = false} = {}) {
  const calls = [], prepared = {}, compilation = {}, allowed = {}, definition = {};
  const identity = {request: 'original'}, readmittedIdentity = {request: 'original'},
    compiled = {}, runDefinition = {identity: 'actual-run'};
  const updateTargetSelections = Object.freeze([]);
  const facts = {prepared, compilation, allowed, definition, identity,
    modelCompiled: compiled, runDefinition, updateTargetSelections};
  const mockEffectRuns = new Map(), mockEffectOriginals = new WeakMap(), effectSelections = new WeakMap();
  const registry = {}, values = {}, fragment = {}, ordered = {};
  const infer = composed ? Object.freeze({graph: {}}) : undefined;
  const inferSelections = new WeakMap(infer === undefined ? [] : [[prepared, infer]]);
  let current = true, ownedRecovery = true, journalIdentity = identity, physicalFailure,
    savedAuthorization = 'saved-authorization';
  const reissuedAllowed = {}, reissuedDefinition = {};
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
  // This original-binding fixture has no Serialize occurrence or Content child.
  const moon = {clientProgramEffectSerializationOccurrences(p) {
    assert.strictEqual(p, prepared); return [];
  }, clientProgramBindCompiledEffectRun(p, a, d) {
    assert.strictEqual(p, prepared);
    assert(a === allowed && d === definition || a === reissuedAllowed && d === reissuedDefinition);
    calls.push('typed-run'); return {$tag: 1, _0: {}};
  },
  // This DATA projection does not establish the nominal request relation.
  clientRequestCallerId(value) {return value?.request;},
  clientRequestRelation(left, right) {
    return [left, right].every(value => value === identity || value === readmittedIdentity) ? 1 : 0;
  },
  strategyPublicationContractJson(value) {
    return value === definition || value === reissuedDefinition ? 'saved-definition' : value?.wire;
  }, clientProgramAllowedEffectRunPrepared(value) {
    assert(value === allowed || value === reissuedAllowed); return 'saved-prepared';
  }, clientProgramAllowedEffectRunAuthorization(value) {
    assert(value === allowed || value === reissuedAllowed); return 'saved-authorization';
  }, strategyRunEvidenceJson(value) {return value;}};
  const selected = Object.freeze({assertPrepared({moon: actualMoon, prepared: p, compilation: c}) {
    assert.strictEqual(this, selected); assert.strictEqual(actualMoon, moon);
    assert.strictEqual(p, prepared); assert.strictEqual(c, compilation); calls.push('selected-prepared');
  }});
  const installedEffect = composed ? Object.freeze({effects: Object.freeze([])}) : selected;
  const descriptors = Object.freeze([]);
  const updateTargetOriginals = Object.freeze({selectionsOf(p) {
    assert.strictEqual(p, prepared); return updateTargetSelections;
  }});
  let descriptorReads = 0, selections = 0, observedPlan, planFailure;
  const installedRowEffectDescriptors = (core, p, c) => {
    assert.strictEqual(core, moon); assert.strictEqual(p, prepared); assert.strictEqual(c, compilation);
    descriptorReads++; return descriptors;
  };
  const installedEffectFor = (catalogue, actualDescriptors) => {
    assert.strictEqual(catalogue, installedEffect); assert.strictEqual(actualDescriptors, descriptors);
    selections++; return selected;
  };
  const validateInstalledUpdateOwnerSelections = (actual, owners, p) => {
    assert.strictEqual(actual, selected); assert.strictEqual(owners, updateTargetSelections);
    assert.strictEqual(p, prepared);
  };
  const journal = {lookupOwnedDefinition(key, core, control) {
    assert.strictEqual(core, moon); assert.equal(key.requestId, identity.request);
    calls.push('saved-journal'); return ownedRecovery ? {runDefinition, requestIdentity: journalIdentity} : undefined;
  }, resolveDefinition(originalIdentity, {namespaceId}, core, owner) {
    assert.strictEqual(originalIdentity, identity); assert.equal(namespaceId, 'namespace');
    assert.strictEqual(core, moon); assert.strictEqual(owner, control);
    calls.push('same-journal');
    return ownedRecovery ? {runDefinition: {wire: 'saved-definition'},
      runAdmissionEvidence: {prepared: 'saved-prepared', authorization: savedAuthorization}} : undefined;
  }};
  const control = {}, preparation = {assertResultPublicationCurrent: currentHost,
    admitEffectResultPublicationRun(p) {assert.strictEqual(p, prepared); calls.push('result-purpose');},
    prepareManagedEffectPlanRun(core, actualFacts, selection, inputs, originalInfer, prepareContent) {
      assert.equal(prepareContent, undefined);
      assert.strictEqual(this, preparation); assert.strictEqual(core, moon);
      assert.strictEqual(actualFacts, facts); assert.strictEqual(selection, selected);
      assert.strictEqual(actualFacts.identity, identity);
      assert.strictEqual(actualFacts.modelCompiled, compiled);
      assert.strictEqual(actualFacts.runDefinition, runDefinition);
      assert.strictEqual(originalInfer, infer);
      assert.deepEqual(Object.keys(inputs).sort(), ['fragment', 'ordered', 'registry', 'sourceProfile', 'values']);
      for (const [name, original] of Object.entries({registry, values, fragment, ordered, sourceProfile})) {
        assert.strictEqual(inputs[name], original);
      }
      observedPlan = {facts: actualFacts, selection, inputs}; calls.push('shared-plan');
      if (planFailure !== undefined) throw planFailure;
    }};
  const sourceProfile = Object.freeze(Object.defineProperties({}, Object.fromEntries(
    ['prepareManagedEffectRun', 'prepareManagedEffectMockModelRun'].map(name => [name,
      {get() {assert.fail(`Retired Source constructor read: ${name}`);}}]))));
  api = new Function('assertProjectRuntime', 'preparation', 'clientOperationError', 'mockEffectOriginals',
    'mockEffectRuns', 'mockEffectObservationMethods', 'mockEffectObservation', 'moon', 'checked',
    'journal', 'namespaceId', 'authorityScopeCid', 'control', 'sourceProfile',
    'registry', 'values', 'fragment', 'ordered', 'installedEffect', 'effectSelections', 'updateTargetOriginals',
    'installedEffectFor', 'installedRowEffectDescriptors', 'validateInstalledUpdateOwnerSelections', 'inferSelections',
    functions + '\nconst mockEffectResources=' + source.slice(resources.init.start, resources.init.end) +
    ';const prepareDefinition=' + source.slice(preparationNode.start, preparationNode.end) +
    ';return {mockEffectResources, retainMockEffectRunOriginal, prepareDefinition};')(
      currentHost, preparation, clientOperationError, mockEffectOriginals, mockEffectRuns,
      mockEffectObservationMethods, mockEffectObservation, moon,
      value => {if (value.$tag !== 1) throw value._0; return value._0;},
      journal, 'namespace', 'authority', control, sourceProfile,
      registry, values, fragment, ordered, installedEffect, effectSelections, updateTargetOriginals,
      installedEffectFor, installedRowEffectDescriptors, validateInstalledUpdateOwnerSelections, inferSelections);
  return {...api, calls, facts, originalFacts: facts, actualLimits,
    plan: () => observedPlan, selected, descriptorReads: () => descriptorReads, selections: () => selections,
    failPlan(value) {planFailure = value;},
    refusal, revoke() {current = false;}, failPhysical(value) {physicalFailure = value;},
    denyRecovery() {ownedRecovery = false;},
    changeSavedAuthorization() {savedAuthorization = 'different-authorization';},
    changeJournalIdentity() {journalIdentity = {};},
    readmittedIdentity,
    readmittedFacts: {...facts, allowed: reissuedAllowed, definition: reissuedDefinition}};
}

test('winning Effect definition prepares the shared original Plan before file-owner binding', () => {
  const f = fixture(); f.prepareDefinition(f.facts);
  assert.deepEqual(f.calls, ['result-purpose', 'selected-prepared', 'shared-plan', 'typed-run', 'physical-original']);
  const original = f.mockEffectResources.bindRunOriginal(f.facts);
  assert.strictEqual(f.mockEffectResources.limits(original), f.actualLimits);
  assert.throws(() => f.mockEffectResources.bindRunOriginal({...f.facts, compilation: {}}),
    {code: 'ForeignInstalledMockEffectRun'});
  assert.throws(() => f.mockEffectResources.assertCurrent({...original}), {code: 'ForeignInstalledMockEffectRun'});
});

test('winning composed Effect definition forwards original selection and model facts to the shared Plan', () => {
  const f = fixture({composed: true});
  f.prepareDefinition(f.facts);
  assert.deepEqual(f.calls, ['result-purpose', 'selected-prepared', 'selected-prepared',
    'shared-plan', 'typed-run', 'physical-original']);
  const plan = f.plan();
  assert.strictEqual(plan.selection, f.selected);
  assert.strictEqual(plan.facts.modelCompiled, f.facts.modelCompiled);
  assert.strictEqual(plan.facts.runDefinition, f.facts.runDefinition);
  assert.equal(f.descriptorReads(), 1); assert.equal(f.selections(), 1);
});

test('shared Effect Plan refusal cannot reach physical binding or a retired Source Root', () => {
  const f = fixture(), refusal = new Error('OriginalPlanRefused');
  f.failPlan(refusal);
  assert.throws(() => f.prepareDefinition(f.facts), cause => cause === refusal);
  assert.deepEqual(f.calls, ['result-purpose', 'selected-prepared', 'shared-plan']);
  assert.throws(() => f.mockEffectResources.bindRunOriginal(f.facts),
    {code: 'ForeignInstalledMockEffectRun'});
});

test('file resource binding observes original Host currentness after shared Plan preparation', () => {
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

test('same winning Journal readmission retains the existing physical Run original once', () => {
  const f = fixture(); f.prepareDefinition(f.facts);
  const original = f.mockEffectResources.bindRunOriginal(f.facts);
  assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.readmittedFacts), original);
  assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.readmittedFacts), original);
  assert.equal(f.calls.filter(call => call === 'same-journal').length, 1);
  assert.equal(f.calls.filter(call => call === 'typed-run').length, 2);
  assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
  assert.equal(f.calls.filter(call => call === 'shared-plan').length, 1);
});

test('readmission refuses missing Journal and changed authorization without replacing original', () => {
  for (const change of ['denyRecovery', 'changeSavedAuthorization']) {
    const f = fixture(); f.prepareDefinition(f.facts); f[change]();
    assert.throws(() => f.mockEffectResources.bindRunOriginal(f.readmittedFacts),
      {code: 'ForeignInstalledMockEffectRun'});
    assert.equal(f.calls.filter(call => call === 'same-journal').length, 1);
    assert.equal(f.calls.filter(call => call === 'typed-run').length, 1);
    assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.facts),
      f.mockEffectResources.bindRunOriginal(f.facts));
  }
});

test('equal definition DATA cannot replace the typed same-Journal readmission', () => {
  const f = fixture(); f.prepareDefinition(f.facts);
  assert.throws(() => f.mockEffectResources.bindRunOriginal({...f.readmittedFacts,
    definition: {wire: 'saved-definition'}}));
  assert.equal(f.calls.filter(call => call === 'same-journal').length, 1);
  assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
  assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.facts),
    f.mockEffectResources.bindRunOriginal(f.facts));
});

test('an empty readmission cache never accepts missing original handles', () => {
  const f = fixture(); f.prepareDefinition(f.facts);
  assert.throws(() => f.mockEffectResources.bindRunOriginal({...f.facts,
    allowed: undefined, definition: undefined}), {code: 'ForeignInstalledMockEffectRun'});
  assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.readmittedFacts),
    f.mockEffectResources.bindRunOriginal(f.facts));
  assert.throws(() => f.mockEffectResources.bindRunOriginal({...f.readmittedFacts,
    identity: {request: 'original'}}), {code: 'ForeignInstalledMockEffectRun'});
});


test('cold saved readmission keeps the same already retained physical Run original', () => {
  const f = fixture({composed: true}); f.prepareDefinition(f.facts);
  const original = f.mockEffectResources.bindRunOriginal(f.facts);
  const recovered = {...f.readmittedFacts, requestIdentity: f.facts.identity};
  assert.strictEqual(f.mockEffectResources.bindRunOriginal({recovered}), original);
  assert.strictEqual(f.mockEffectResources.bindRunOriginal({recovered}), original);
  assert.equal(f.calls.filter(call => call === 'saved-journal').length, 2);
  assert.equal(f.calls.filter(call => call === 'same-journal').length, 1);
  assert.equal(f.calls.filter(call => call === 'typed-run').length, 2);
  assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
  assert.equal(f.calls.filter(call => call === 'shared-plan').length, 1);
  assert.strictEqual(f.mockEffectResources.limits(original), f.actualLimits);
});

test('cold saved readmission refuses lost Journal changed authority and copied typed handles', () => {
  for (const change of ['denyRecovery', 'changeSavedAuthorization', 'copiedDefinition', 'foreignCompilation', 'revoke']) {
    const f = fixture(); f.prepareDefinition(f.facts);
    const original = f.mockEffectResources.bindRunOriginal(f.facts);
    let recovered = {...f.readmittedFacts, requestIdentity: f.facts.identity};
    if (change === 'copiedDefinition') recovered = {...recovered, definition: {wire: 'saved-definition'}};
    else if (change === 'foreignCompilation') recovered = {...recovered, compilation: {}};
    else f[change]();
    assert.throws(() => f.mockEffectResources.bindRunOriginal({recovered}),
      change === 'revoke' ? cause => cause === f.refusal : undefined);
    assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
    assert.equal(f.calls.filter(call => call === 'typed-run').length, 1);
    if (change !== 'revoke') assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.facts), original);
  }
});


test('cold Journal handle cannot replace the already bound physical request original', () => {
  const f = fixture({composed: true}); f.prepareDefinition(f.facts);
  const original = f.mockEffectResources.bindRunOriginal(f.facts);
  const recovered = {...f.readmittedFacts, requestIdentity: f.readmittedIdentity};
  assert.notStrictEqual(recovered.identity, recovered.requestIdentity);
  assert.strictEqual(f.mockEffectResources.bindRunOriginal({recovered}), original);
  assert.strictEqual(f.mockEffectResources.bindRunOriginal({recovered}), original);
  assert.equal(f.calls.filter(call => call === 'same-journal').length, 1);
  assert.equal(f.calls.filter(call => call === 'typed-run').length, 2);
  assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
  // The original pointer fence remains strict outside the saved handoff.
  assert.throws(() => f.mockEffectResources.bindRunOriginal({...f.readmittedFacts,
    identity: f.readmittedIdentity}), {code: 'ForeignInstalledMockEffectRun'});
});

test('cold binding refuses foreign original request, saved handle and current Journal identity', () => {
  for (const change of ['original', 'saved', 'journal']) {
    const f = fixture(); f.prepareDefinition(f.facts);
    const original = f.mockEffectResources.bindRunOriginal(f.facts);
    let recovered = {...f.readmittedFacts, requestIdentity: f.readmittedIdentity};
    if (change === 'original') recovered = {...recovered, identity: {request: 'original'}};
    else if (change === 'saved') recovered = {...recovered, requestIdentity: {request: 'original'}};
    else f.changeJournalIdentity();
    assert.throws(() => f.mockEffectResources.bindRunOriginal({recovered}),
      {code: 'ForeignInstalledMockEffectRun'});
    assert.equal(f.calls.filter(call => call === 'typed-run').length, 1);
    assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
    assert.strictEqual(f.mockEffectResources.bindRunOriginal(f.facts), original);
  }
});


test('cold bound request readmission authenticates the winning evidence before physical reuse', () => {
  for (const change of [undefined, 'changeSavedAuthorization', 'denyRecovery', 'revoke']) {
    const f = fixture({composed: true}); f.prepareDefinition(f.facts);
    const original = f.mockEffectResources.bindRunOriginal(f.facts);
    const recovered = {...f.readmittedFacts, identity: f.readmittedIdentity,
      requestIdentity: f.readmittedIdentity};
    if (change !== undefined) {
      f[change]();
      assert.throws(() => f.mockEffectResources.bindRunOriginal({recovered}));
      assert.equal(f.calls.filter(call => call === 'typed-run').length, 1);
    } else {
      assert.strictEqual(f.mockEffectResources.bindRunOriginal({recovered}), original);
      assert.strictEqual(f.mockEffectResources.bindRunOriginal({recovered}), original);
      assert.equal(f.calls.filter(call => call === 'same-journal').length, 2);
      assert.equal(f.calls.filter(call => call === 'typed-run').length, 3);
      assert.throws(() => f.mockEffectResources.bindRunOriginal({recovered: {...recovered,
        compilation: {}}}), {code: 'ForeignInstalledMockEffectRun'});
      // A matching readmission cache is no substitute for current saved evidence.
      f.changeSavedAuthorization();
      assert.throws(() => f.mockEffectResources.bindRunOriginal({recovered}),
        {code: 'ForeignInstalledMockEffectRun'});
      assert.equal(f.calls.filter(call => call === 'same-journal').length, 3);
      assert.equal(f.calls.filter(call => call === 'typed-run').length, 3);
    }
    assert.equal(f.calls.filter(call => call === 'physical-original').length, 1);
    assert.equal(f.calls.filter(call => call === 'shared-plan').length, 1);
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredKeyedEffectPublicationPlan, checkedLocalOutputLimits, localOutputLimits} from './local-values-plan.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';

function fixture() {
  const prepared = {}, compilation = {}, admission = {}, definition = {}, request = {};
  const parent = {}, plan = {}, host = {}, original = {}, lookup = {}, unit = {};
  const keyedDefinition = {sameCheckedPreparation: true};
  const left = {wire: 'left source'}, right = {wire: 'right source'};
  const invocation = {}, invocationOwner = {}, observation = {wire: JSON.stringify({data_policy_cid: 'policy'})};
  const events = [];
  const outputLimits = Object.freeze({...localOutputLimits, maxRows: 1000,
    maxResultOrderWork: 1000, maxResultWorkspaceEntries: 2000});
  const seal = (name, wire) => ({name, identity: name, wire});
  const acquired = {prepared, compilation, admission, definition, requestIdentity: request,
    runDefinition: {identity: 'run', wire: JSON.stringify({created_at: '2026-11-15T00:00:00Z',
      valid_until: '2026-11-16T00:00:00Z'})},
    compiledPlan: {identity: 'compiled'}, authorityScopeCid: 'authority', namespaceId: 'namespace',
    storeAuthorityCid: 'store', now: () => '2026-11-15T00:00:00Z',
    moon: {clientProgramInstalledEffectPublicationLimits(...args) {
        assert.deepEqual(args.slice(0, 4), [parent, prepared, request, plan]);
        assert(Number.isSafeInteger(args[4]) && args[4] > 0);
        events.push('limits'); return resultOutputLimitFields.map(name => outputLimits[name]);
      },
      clientProgramEffectDefinitionCid: value => {assert.strictEqual(value, prepared); return 'program';},
      clientProgramEffectCompilationResultNames: () => ['rows'],
      clientProgramEffectCompilationResultTransformation: () => ({$tag: 1, _0: undefined}),
      clientProgramCapturedSourceLogicalCid: value => {assert.strictEqual(value, identity); return 'left-relation';}},
    control: {seal, sealRunEvidence: seal,
      issueCheckedInstalledEffectKeyedInvocation(...args) {
        assert.deepEqual(args.slice(0, 9), [parent, prepared, request, plan, host, compilation,
          admission, keyedDefinition, lookup]); events.push('invoke');
        return {observation, invocation, owner: invocationOwner};
      },
      prepareInstalledEffectKeyedSourceUnit(...args) {
        assert.deepEqual(args.slice(0, 7), [parent, prepared, request, plan, host, original, lookup]);
        assert.equal(args[7].name, 'result_retention_policy');
        assert.equal(args[9], true); events.push('unit'); return unit;
      }},
  };
  const identity = {};
  return {events, unit, left, right, invocationOwner, keyedDefinition, outputLimits,
    options: {acquired, sources: [{captured: {identity}, sourceEvidence: left}],
      keyedFamily: {sourceOriginal: original, lookup, evidence: {source: right, logicalRelationCid: 'right-relation'}},
      captureStartedAt: '2026-11-15T00:00:00Z', captureCompletedAt: '2026-11-15T00:00:01Z',
      sourcePlan: plan, managedRun: parent, sourceHost: host, deferCatalogs: true}};
}

test('Source-only keyed publication retains both original Sources and one combined Unit', () => {
  const f = fixture(), result = acquiredKeyedEffectPublicationPlan(f.options, f.keyedDefinition);
  assert.deepEqual(f.events, ['invoke', 'limits', 'unit']);
  assert.deepEqual(result.receiptEvidence.sourceEvidence, [f.left, f.right]);
  assert.deepEqual(result.results[0].evidenceContext.inputRelationCids, ['left-relation', 'right-relation']);
  assert.strictEqual(result.localEvidenceContext.acquiredEvidence, f.unit);
  assert.strictEqual(result.invocationOwner, f.invocationOwner);
  assert.equal(result.localEvidenceContext.catalogDeferred, true);
});

test('Source-only keyed publication consumes the same checked Effect output envelope', () => {
  const f = fixture(), result = acquiredKeyedEffectPublicationPlan(f.options, f.keyedDefinition);
  assert.deepEqual(result.outputLimits, f.outputLimits);
  assert(Object.isFrozen(result.outputLimits));
});

test('Source-only keyed publication preserves a rejected original output envelope', () => {
  const f = fixture(), failure = new Error('ForeignEffectPublicationOriginal');
  f.options.acquired.moon.clientProgramInstalledEffectPublicationLimits = () => {throw failure;};
  assert.throws(() => acquiredKeyedEffectPublicationPlan(f.options, f.keyedDefinition), cause => cause === failure);
  assert.deepEqual(f.events, ['invoke']);
});

test('Source-only publication refuses missing original lookup and preserves actual Unit failure', () => {
  const f = fixture();
  assert.throws(() => acquiredKeyedEffectPublicationPlan({...f.options,
    keyedFamily: {...f.options.keyedFamily, sourceOriginal: undefined}}, f.keyedDefinition), /InvalidOriginalEffectKeyedPublication/);
  assert.deepEqual(f.events, []);
  assert.throws(() => acquiredKeyedEffectPublicationPlan(f.options), /InvalidOriginalEffectKeyedPublication/);
  assert.deepEqual(f.events, []);
  const failure = new Error('OriginalUnitCurrentLost');
  f.options.acquired.control.prepareInstalledEffectKeyedSourceUnit = () => {throw failure;};
  assert.throws(() => acquiredKeyedEffectPublicationPlan(f.options, f.keyedDefinition), cause => cause === failure);
  assert.deepEqual(f.events, ['invoke', 'limits']);
});

test('Source-only keyed publication preserves tighter limits and refuses malformed projections', () => {
  const f = fixture(), tighter = {...f.outputLimits, maxRows: 13, maxResultWorkspaceEntries: 26};
  f.options.acquired.moon.clientProgramInstalledEffectPublicationLimits = () =>
    resultOutputLimitFields.map(name => tighter[name]);
  assert.deepEqual(acquiredKeyedEffectPublicationPlan(f.options, f.keyedDefinition).outputLimits, tighter);
  f.options.acquired.moon.clientProgramInstalledEffectPublicationLimits = () => [];
  assert.throws(() => acquiredKeyedEffectPublicationPlan(f.options, f.keyedDefinition),
    /InvalidCheckedLocalPublicationLimits/u);
});

test('the existing Pure publication projection retains its original checked limits', () => {
  const prepared = {}, original = {}, limits = {...localOutputLimits, maxRows: 121,
    maxResultWorkspaceEntries: 242};
  const moon = {clientProgramPreparedLocalPublicationLimits(...args) {
    assert.strictEqual(args[0], original); assert.strictEqual(args[1], prepared);
    return resultOutputLimitFields.map(name => limits[name]);
  }};
  assert.deepEqual(checkedLocalOutputLimits(moon, prepared,
    {kind: 'preparation', value: original}), limits);
});

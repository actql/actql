import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan} from './local-values-plan.mjs';
import {runtimePair} from '../host-common/compiler-binding.generated.mjs';
test('actual Values and Tasks initial-retention callers forward only their same managed original', async () => {
  const {sourceFreeValuesPlan, sourceFreeTaskPlan, localOutputLimits} = await import('./local-values-plan.mjs');
  const {resultOutputLimitFields} = await import('../host-common/result-output-limits.mjs');
  for (const [kind, create] of [['values', sourceFreeValuesPlan], ['tasks', sourceFreeTaskPlan]]) {
    const prepared = {}, request = {}, owner = {}, foreign = {};
    const retention = {}, initial = [], invocation = {};
    const compiled = {admission: {}, compiledPlan: {identity: cid('4')},
      preparedEvidence: {wire: 'prepared'}, authorization: {wire: 'authorization'}, kind};
    const control = {
      prepareCheckedClientCompiledRun(actual, actualKind) {
        assert.strictEqual(actual, prepared); assert.equal(actualKind, kind); return compiled;
      },
      defineCheckedClientCompiledRun(actual) {
        assert.strictEqual(actual, compiled);
        return {identity: cid('5'), wire: '{"created_at":"2026-11-18T00:00:00.000Z"}'};
      },
      issueCheckedClientCompiledInvocation(actual, definition, policy, limits, actualOwner, actualPrepared) {
        assert.strictEqual(actual, compiled); assert.strictEqual(actualOwner, owner);
        assert.strictEqual(actualPrepared, prepared); return {observation: {}, invocation};
      },
      issueProgramInitialRetention(actualOwner, actualPrepared, actualRequest, policy, selected, contracts) {
        assert.strictEqual(actualOwner, owner); assert.strictEqual(actualPrepared, prepared);
        assert.strictEqual(actualRequest, request); assert.equal(contracts.length, 3);
        assert.equal(selected.availableUntil, '2026-11-18T01:00:00.000Z');
        assert.equal(selected.deleteBy, '2026-11-18T02:00:00.000Z');
        assert.equal(selected.metadataDeleteBy, '2026-11-25T00:00:00.000Z');
        initial.push(selected); return retention;
      },
      seal() { assert.fail('managed constructor cannot fall back to JS seal'); },
      preparedClientNormalizationEvidence: () => ({}),
      preparedClientAuthoringContextEvidence: () => ({}),
      captureOriginalClientRunPlan: () => ({}),
    };
    const moon = {clientProgramDefinitionCid: () => cid('6'), clientProgramResultCount: () => 0,
      clientProgramInstalledManagedPublicationLimits(actualOwner, actualPrepared) {
        assert.strictEqual(actualOwner, owner); assert.strictEqual(actualPrepared, prepared);
        return resultOutputLimitFields.map(name => localOutputLimits[name]);
      }};
    const options = {moon, control, preparedProgram: prepared, requestIdentity: request,
      publicationOriginal: {kind: 'installed_run', value: owner}, publicationPreparation: owner,
      authorityScopeCid: cid('1'), namespaceId: 'fixture', storeAuthorityCid: cid('2'),
      now: () => '2026-11-18T00:00:00.000Z'};
    create(options); assert.equal(initial.length, 1);
    for (const value of [undefined, foreign]) {
      // The invocation port must preserve the bad tuple, then the selected
      // initial caller refuses it instead of silently choosing legacy seal.
      control.issueCheckedClientCompiledInvocation = () => ({observation: {}, invocation});
      assert.throws(() => create({...options, publicationPreparation: value}),
        /OriginalProgramRetentionOwnerRequired/);
      assert.equal(initial.length, 1);
    }
    assert.throws(() => create({...options, publicationOriginal: undefined}),
      /OriginalProgramRetentionOwnerRequired/);
    assert.equal(initial.length, 1);
  }
});

test('actual runtime initial-retention projections preserve all selected fields and original owners', async () => {
  const {runtimeCore} = await import('../host-common/runtime-core.mjs');
  const owner = {}, prepared = {}, request = {}, plan = {}, token = {}, calls = [];
  const contracts = [{cid: cid('1')}, {cid: cid('2')}, {cid: cid('3')}];
  const selection = Object.freeze({availableUntil: '2026-11-18T01:00:00.000Z',
    deleteBy: '2026-11-18T02:00:00.000Z', metadataDeleteBy: '2026-11-25T00:00:00.000Z',
    retentionContractCid: cid('1'), metadataRetentionPolicyCid: cid('2'), clockContractCid: cid('3')});
  const limits = {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 32};
  const expected = [cid('1'), cid('5'), selection.availableUntil, selection.deleteBy,
    selection.metadataDeleteBy, cid('2'), selection.metadataDeleteBy, cid('3'), 10000, 1000, 32];
  const moon = {strategyRemoteManagedOutputEvidenceKind: () => 'fixture',
    strategyPublicationContractName: () => 'result_retention_policy',
    strategyPublicationContractIdentityField: () => 'effective_retention_policy_cid',
    strategyPublicationContractIdentity: () => cid('7'), strategyPublicationContractJson: () => '{}',
    clientProgramIssueProgramInitialRetention(...args) { calls.push(args); return ok(token); },
    clientProgramIssueInstalledEffectInitialRetention(...args) { calls.push(args); return ok(token); }};
  const control = runtimeCore(moon).publicationControl;
  control.issueProgramInitialRetention(owner, prepared, request, cid('5'), selection, contracts, limits);
  control.issueInstalledEffectInitialRetention(owner, prepared, request, plan, cid('5'), selection, limits);
  assert.deepEqual(calls, [[owner, prepared, request, ...expected], [owner, prepared, request, plan, ...expected]]);
  assert.throws(() => control.issueProgramInitialRetention(undefined, prepared, request,
    cid('5'), selection, contracts, limits), /OriginalProgramRetentionOwnerRequired/);
  assert.throws(() => control.issueInstalledEffectInitialRetention(owner, prepared, request,
    undefined, cid('5'), selection, limits), /OriginalEffectRetentionOwnerRequired/);
  assert.equal(calls.length, 2);
});

// Existing pinned Result ABI at explicit fixture ports; no nominal original
// is reconstructed here. Core original/Resource laws have their own tests.
const ok = value => ({$tag: 1, _0: value});
const cid = digit => `sha256:${digit.repeat(64)}`;
function fixture({multi, primary} = {}) {
  const managedRun = {}, sourcePlan = {}, sourceHost = {}, prepared = {}, request = {};
  const retention = Object.freeze({identity: cid('7'),
    get wire() {assert.fail('the actual original retention must not be parsed in JS');}});
  const initial = [], rebound = [], issued = [];
  const sources = Array.from({length: multi ? 2 : 1}, (_, index) => {
    const originalSource = {}, identity = {}, requirement = {}, logicalInput = {};
    return {sourceEvidence: {}, sourceEvidenceWire: 'evidence', captured: {
      inputKind: 'query', occurrence: {stage: index}, identity, requirement, logicalInput,
      checkedSource: {sourceDataPolicyCid: cid(String(index + 5)), sourceRef: `source-${index}`,
        sourceContractCid: cid('1')}, capture: {source: () => originalSource},
    }};
  });
  const moon = {
    clientProgramEffectCapturedSourceMatches: () => true,
    clientProgramCapturedSourceDependencyBodies: () => runtimePair('{}', '{}'),
    clientProgramCapturedSourceLogicalCid: () => cid('2'),
    clientProgramCapturedSourceSchemaCid: () => cid('3'),
    clientProgramEffectPublicationDataPolicyCid: () => cid('9'),
    clientProgramEffectDefinitionCid: () => cid('4'),
    // Result production is outside these explicit caller-port controls.
    clientProgramEffectCompilationResultNames: () => [],
    clientProgramEffectPublicationPolicyBodies: () => ok([]),
    strategyRunEvidenceJson: () => '{}',
  };
  const sourceRetentions = sources.map(() => ({}));
  const invocation = {observation: {wire: JSON.stringify({data_policy_cid: cid('9')})}, invocation: {}, owner: {}};
  const control = {
    issueInstalledEffectInitialRetention(run, owner, originalRequest, plan, policy, selection, limits) {
      assert.strictEqual(run, managedRun); assert.strictEqual(owner, prepared);
      assert.strictEqual(originalRequest, request); assert.strictEqual(plan, sourcePlan);
      assert.equal(initial.length, 0, 'only one initial retention on this owner');
      initial.push({available_until: selection.availableUntil, delete_by: selection.deleteBy,
        extension_ceiling_at: selection.metadataDeleteBy, metadata_delete_by: selection.metadataDeleteBy});
      return retention;
    },
    seal(name, wire) {
      assert.equal(name, 'result_retention_policy');
      initial.push(JSON.parse(wire));
      assert.fail('selected owner must never fall back to the JS retention serializer');
      return retention;
    },
    sealRunEvidence: () => ({}),
    admitRunEvidence: () => ({}),
    issueCheckedInstalledEffectContentInvocation: () => invocation,
    issueCheckedInstalledEffectMultiCapturedInvocation: () => invocation,
    rebindInstalledEffectResultRetention(run, owner, originalRequest, plan, actualRetention, policy, limits) {
      assert.strictEqual(run, managedRun); assert.strictEqual(owner, prepared);
      assert.strictEqual(originalRequest, request); assert.strictEqual(plan, sourcePlan);
      assert.strictEqual(actualRetention, retention);
      assert.deepEqual(limits, {maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64});
      const index = rebound.length;
      assert.equal(policy, sources[index].captured.checkedSource.sourceDataPolicyCid);
      rebound.push(policy);
      if (primary) throw primary;
      return sourceRetentions[index];
    },
    issueCheckedAcquiredEffectEvidence(...args) {
      const index = issued.length;
      assert.strictEqual(args[8], sourceRetentions[index]);
      assert.strictEqual(args[11], retention);
      assert.equal(args[7], sources[index].captured.checkedSource.sourceDataPolicyCid);
      issued.push(args[8]);
      return {invocation: {}, catalogBodies: []};
    },
  };
  const acquired = {moon, control, prepared, requestIdentity: request, compilation: {}, admission: {},
    definition: {}, compiledPlan: {identity: cid('8')}, authorityScopeCid: cid('1'),
    namespaceId: 'local', storeAuthorityCid: cid('2'), now: () => '2026-11-18T00:00:00.000Z',
    runDefinition: {wire: '{"created_at":"2026-11-18T00:00:00.000Z","valid_until":"2026-11-18T03:00:00.000Z"}'}};
  acquired.selectRetention = () => Object.freeze({availableUntil: '2026-11-18T03:00:00.000Z',
    deleteBy: '2026-11-18T04:00:00.000Z', metadataDeleteBy: '2026-11-25T00:00:00.000Z',
    retentionContractCid: cid('1'), metadataRetentionPolicyCid: cid('2'), clockContractCid: cid('3')});
  const common = {acquired, managedRun, sourcePlan, sourceHost,
    captureStartedAt: '2026-11-18T00:00:00.000Z', captureCompletedAt: '2026-11-18T00:01:00.000Z'};
  return {acquired, managedRun, sourcePlan, sourceHost, sources, invocation, initial, rebound, issued, sourceRetentions, retention, invoke: () => multi
    ? acquiredMultiEffectPublicationPlan({...common, sources})
    : acquiredEffectPublicationPlan({...common, ...sources[0], content: {compiled: {}, generation: {}}})};
}

for (const multi of [false, true]) test(`actual ${multi ? 'multi-Source' : 'Content Source'} caller rebinds its same original without JSON reconstruction`, () => {
  const f = fixture({multi}), result = f.invoke();
  assert.strictEqual(result.effectInputRetention, f.retention);
  assert.deepEqual(f.issued, f.sourceRetentions);
  assert.equal(f.rebound.length, multi ? 2 : 1);
  assert.equal(f.initial[0].available_until, '2026-11-18T03:00:00.000Z');
  assert.equal(f.initial[0].delete_by, '2026-11-18T04:00:00.000Z');
  assert.equal(f.initial[0].extension_ceiling_at, '2026-11-25T00:00:00.000Z');
  assert.equal(f.initial[0].metadata_delete_by, '2026-11-25T00:00:00.000Z');
  const primary = new Error('OriginalRetentionReservationRefused'), failed = fixture({multi, primary});
  assert.throws(failed.invoke, error => error === primary);
  assert.equal(failed.rebound.length, 1);
  assert.deepEqual(failed.issued, []);
});

test('actual runtime retention projection preserves the original token and rejects a foreign control', async () => {
  const {runtimeCore} = await import('../host-common/runtime-core.mjs');
  const original = {}, changed = {}, run = {}, prepared = {}, request = {}, plan = {};
  let returned = original, refusal, calls = 0;
  const limits = Object.freeze({maxWireBytes: 10000, maxNodes: 1000, maxDepth: 32});
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'unused explicit fixture metadata',
    strategyPublicationSeal: () => ok(original),
    strategyPublicationContractName: () => 'result_retention_policy',
    strategyPublicationContractIdentityField: () => 'effective_retention_policy_cid',
    strategyPublicationContractIdentity: token => token === original ? cid('5') : cid('6'),
    strategyPublicationContractJson: () => '{}',
    clientProgramRebindInstalledEffectResultRetention(...args) {
      calls++;
      assert.deepEqual(args, [run, prepared, request, plan, original, cid('6'), 10000, 1000, 32]);
      if (refusal) throw refusal;
      return ok(returned);
    },
  };
  const control = runtimeCore(moon).publicationControl;
  const retention = control.seal('result_retention_policy', '{}', limits);
  assert.strictEqual(control.rebindInstalledEffectResultRetention(
    run, prepared, request, plan, retention, cid('6'), limits), retention);
  returned = changed;
  const projected = control.rebindInstalledEffectResultRetention(run, prepared, request, plan, retention, cid('6'), limits);
  assert.equal(projected.identity, cid('6'));
  const beforeMissing = calls;
  for (const index of [0, 1, 2, 3]) {
    const args = [run, prepared, request, plan, retention, cid('6'), limits];
    args[index] = undefined;
    assert.throws(() => control.rebindInstalledEffectResultRetention(...args),
      /OriginalEffectRetentionPreparationRequired/);
  }
  assert.equal(calls, beforeMissing);
  const foreign = runtimeCore({...moon}).publicationControl;
  assert.throws(() => foreign.rebindInstalledEffectResultRetention(
    run, prepared, request, plan, retention, cid('6'), limits), /Foreign publication contract/);
  refusal = new Error('OriginalRetentionGrowRefused');
  assert.throws(() => control.rebindInstalledEffectResultRetention(
    run, prepared, request, plan, retention, cid('6'), limits), error => error === refusal);
});


test('actual plural initial Source-unit caller reuses its original retention at final publication', async () => {
  const {prepareAcquiredEffectSourceUnits} = await import('./local-values-plan.mjs');
  const f = fixture({multi: true}), inputs = {}, unit = {invocation: {}, catalogBodies: []};
  for (const source of f.sources) source.captured.occurrence.stage = 0;
  let preparedUnits = 0;
  f.acquired.control.prepareCheckedInstalledEffectSourceUnits = (plan, prepared, request) => {
    assert.strictEqual(plan, f.sourcePlan); assert.strictEqual(prepared, f.acquired.prepared);
    assert.strictEqual(request, f.acquired.requestIdentity); return inputs;
  };
  f.acquired.control.prepareInstalledEffectModelSourceUnit = (owner, plan, request, actualInputs, index, retention) => {
    assert.strictEqual(owner, f.managedRun); assert.strictEqual(plan, f.sourcePlan);
    assert.strictEqual(request, f.acquired.requestIdentity); assert.strictEqual(actualInputs, inputs);
    assert.equal(index, 0); assert.strictEqual(retention, f.retention); preparedUnits++; return unit;
  };
  const originals = prepareAcquiredEffectSourceUnits({acquired: f.acquired, sources: f.sources,
    managedRun: f.managedRun, sourcePlan: f.sourcePlan, modelUnits: [1]});
  assert.strictEqual(originals.retention, f.retention); assert.equal(preparedUnits, 1);
  f.acquired.control.bindCheckedInstalledEffectModelInvocation = () => f.invocation;
  const result = acquiredMultiEffectPublicationPlan({acquired: f.acquired, sources: f.sources,
    managedRun: f.managedRun, sourcePlan: f.sourcePlan, sourceHost: f.sourceHost,
    sourceUnitsOriginal: originals, issuedModel: {}, modelOriginals: [{unit: 1}]});
  assert.strictEqual(result.effectInputRetention, f.retention);
  assert.strictEqual(result.localEvidenceContext.originalUnitResults, originals.byUnit);
  assert.strictEqual(result.localEvidenceContext.acquiredEvidenceByUnit[0], unit);
  assert.equal(preparedUnits, 1); assert.equal(f.initial.length, 1);
});

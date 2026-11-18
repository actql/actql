import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan} from './local-values-plan.mjs';
import {runtimePair} from '../host-common/compiler-binding.generated.mjs';

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
    seal(name, wire) {
      assert.equal(name, 'result_retention_policy');
      initial.push(JSON.parse(wire));
      assert.equal(initial.length, 1, 'only the initial selected retention is sealed in JS');
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
  const common = {acquired, managedRun, sourcePlan, sourceHost,
    captureStartedAt: '2026-11-18T00:00:00.000Z', captureCompletedAt: '2026-11-18T00:01:00.000Z'};
  return {initial, rebound, issued, sourceRetentions, retention, invoke: () => multi
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

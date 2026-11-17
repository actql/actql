import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';

// Actual runtimeCore consumer with explicit Core ports. The selected compiled
// export returns a boxed Option<Array<Body>>; this is not an installed Run.
function fixture({cached, currentFailure} = {}) {
  const original = {}, lookup = {}, retention = {}, issued = {}, invocation = {};
  const parent = {}, prepared = {}, request = {}, plan = {}, host = {};
  const body = {}, calls = [];
  const core = runtimeCore({
    strategyRemoteManagedOutputEvidenceKind: () => 'component metadata',
    strategyPublicationSeal: () => ({$tag: 1, _0: retention}),
    strategyPublicationContractName: () => 'result_retention_policy',
    strategyPublicationContractIdentityField: () => 'policy_cid',
    strategyPublicationContractIdentity: () => 'retention',
    strategyPublicationContractJson: () => '{}',
    clientProgramPrepareInstalledEffectKeyedSourceUnit(...args) {
      assert.deepEqual(args.slice(0, 7), [parent, prepared, request, plan, host, lookup, retention]);
      calls.push('current-original');
      return currentFailure ? {$tag: 0, _0: currentFailure} : {$tag: 1, _0: issued};
    },
    clientProgramEffectKeyedCachedDependencyBodies(...args) {
      assert.deepEqual(args, [original, lookup, retention]); calls.push('borrow');
      return cached === undefined ? {$tag: 1, _0: [body]} : cached;
    },
    clientProgramEffectDependencyBodyKind(value) {assert.strictEqual(value, body); calls.push('project'); return 'source_contract';},
    clientProgramEffectDependencyBodyCid(value) {assert.strictEqual(value, body); return 'source';},
    clientProgramEffectDependencyBodyJson(value) {assert.strictEqual(value, body); return '{"same":true}';},
    clientProgramEffectKeyedSourceUnitMetadataBodies(value) {assert.strictEqual(value, issued); return [];},
    clientProgramEffectKeyedSourceUnitInvocation(value) {assert.strictEqual(value, issued); return invocation;},
  }).publicationControl;
  const limits = {maxWireBytes: 4096, maxNodes: 1024, maxDepth: 64};
  const view = core.seal('result_retention_policy', '{}', limits);
  return {calls, invocation, run: () => core.prepareInstalledEffectKeyedSourceUnit(
    parent, prepared, request, plan, host, original, lookup, view, limits, true)};
}

test('keyed Source borrows the actual boxed Some inventory after original Core current checks', () => {
  const f = fixture(), value = f.run();
  assert.deepEqual(f.calls, ['current-original', 'borrow', 'project']);
  assert.strictEqual(value.invocation, f.invocation);
  assert.deepEqual(value.bodies, [{kind: 'source_contract', cid: 'source', wire: '{"same":true}'}]);
  assert.equal(Object.isFrozen(value.bodies), true);
  assert.equal(value.catalogDeferred, true);
});

test('keyed Source rejects None malformed Some and an unqualified unboxed inventory', () => {
  for (const cached of [{$tag: 0}, {$tag: 1, _0: 'invalid'}, []]) {
    const f = fixture({cached});
    assert.throws(f.run, /OriginalEffectKeyedInventoryUnavailable/);
    assert.deepEqual(f.calls, ['current-original', 'borrow']);
  }
});

test('keyed Source preserves original Core refusal before borrowing or projecting inventory', () => {
  const currentFailure = {}, f = fixture({currentFailure});
  assert.throws(f.run, error => error.cause === currentFailure);
  assert.deepEqual(f.calls, ['current-original']);
});

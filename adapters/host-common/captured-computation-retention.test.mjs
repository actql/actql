import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from './runtime-core.mjs';

// Exercise the actual Node association and forwarding with explicit Common
// ports. Common's nominal compatibility and traversal are tested in Common;
// these fixtures do not issue a real publication or physical cleanup receipt.
const limits = Object.freeze({maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});
const ok = value => ({$tag: 1, _0: value});
// Distinct from caller metadata limits: the fixture models the existing
// Common port's original-owner projection, not a new extent issuer.
const originalLimits = Object.freeze([131072, 8192, 96]);

function fixture() {
  const calls = {begin: [], finish: [], cancel: [], chain: [], commit: []};
  let serial = 0;
  const preparations = new WeakMap();
  const contract = (name, wire) => Object.freeze({name, wire,
    identity: name === 'captured_run' ? 'same-captured-identity' : `${name}-${++serial}`});
  const begin = (args, effectful) => {
    const preparation = {args, effectful,
      contract: contract('captured_run', '{"captured":"same-visible-body"}')};
    preparations.set(preparation, originalLimits);
    calls.begin.push(preparation);
    return preparation;
  };
  const check = (kind, original, args) => {
    const preparation = Object.freeze({kind, original, args});
    calls[kind].push(preparation);
    return preparation;
  };
  const moon = {
    // runtimeCore also constructs its unrelated Remote facade; no Remote
    // operation or physical capability is exercised by this component fixture.
    strategyRemoteManagedOutputEvidenceKind: () => 'unused-fixture-kind',
    strategyPublicationSeal(name, wire) {return ok(contract(name, wire));},
    strategyPublicationAdmit(name, wire) {return ok(contract(name, wire));},
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
    strategyRunEvidenceAdmit: (name, wire) => ok(contract(name, wire)),
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    strategyPublicationEvidenceWorkspace: value => value * 4,
    strategyBeginOriginalEffectFreeCapturedRun(...args) {
      assert.strictEqual(this, moon); return begin(args, false);
    },
    strategyBeginEffectfulCapturedRun(...args) {
      assert.strictEqual(this, moon); return ok(begin(args, true));
    },
    strategyCapturedRunPreparationLimits(preparation) {
      assert.strictEqual(this, moon);
      const owned = preparations.get(preparation);
      return owned === undefined ? {$tag: 0} : {$tag: 1, _0: owned};
    },
    strategyCapturedRunAdvance() {return ok(true);},
    strategyCapturedRunFinish(preparation) {
      assert.strictEqual(this, moon); calls.finish.push({preparation, retained: false});
      return ok(preparation.contract);
    },
    strategyCapturedRunFinishRetained(preparation) {
      assert.strictEqual(this, moon); calls.finish.push({preparation, retained: true});
      return ok(preparation.contract);
    },
    strategyCapturedRunCancel(preparation) {
      assert.strictEqual(this, moon); calls.cancel.push(preparation);
      preparations.delete(preparation);
    },
    strategyBeginEffectFreeChainCheck(...args) {
      assert.strictEqual(this, moon); return check('chain', undefined, args);
    },
    strategyBeginEffectFreeChainCheckRetained(original, ...args) {
      assert.strictEqual(this, moon); return check('chain', original, args);
    },
    strategyEffectFreeChainCheckAdvance: () => 1,
    strategyEffectFreeChainCheckFinish: () => true,
    strategyEffectFreeChainCheckCancel() {},
    strategyBeginEffectFreeCommitCheck(...args) {
      assert.strictEqual(this, moon); return check('commit', undefined, args);
    },
    strategyBeginEffectFreeCommitCheckRetained(original, ...args) {
      assert.strictEqual(this, moon); return check('commit', original, args);
    },
    strategyEffectFreeCommitCheckAdvance: () => 1,
    strategyEffectFreeCommitCheckFinish: () => true,
    strategyEffectFreeCommitCheckCancel() {},
    strategyAdmitEffectComputationPreview: () => ok(Object.freeze({preview: true})),
  };
  const control = runtimeCore(moon).publicationControl;
  const seal = name => control.seal(name, '{}', limits);
  const chain = Object.freeze({runDefinition: seal('run_definition'),
    invocation: seal('run_invocation'), definitions: Object.freeze([seal('result_definition')]),
    artifacts: Object.freeze([seal('result_artifact')]), manifest: seal('result_manifest'),
    receipt: seal('computation_receipt')});
  const evidence = Object.freeze({snapshots: [], pendingSourceStateAdvances: [],
    modelEvidence: [], authoringContext: control.admitRunEvidence('authoring_context', '{}', limits)});
  const tail = [[], [], [], [], seal('publication_request'),
    seal('publication_attempt'), seal('public_index_entry')];
  const issue = signal => control.issueEffectFreeCapturedRun(chain, evidence, limits, signal);
  const validateChain = (captured, selected = chain, bounds = limits) =>
    control.effectFreeChainValid(selected.runDefinition, selected.invocation,
      selected.definitions, selected.artifacts, selected.manifest, selected.receipt,
      captured, bounds);
  const validateCommit = (captured, selected = chain, bounds = limits) =>
    control.effectFreeCommitValid(selected.runDefinition, selected.invocation,
      selected.definitions, selected.artifacts, ...tail.slice(0, 4), selected.manifest,
      selected.receipt, captured, ...tail.slice(4), bounds);
  return {moon, control, calls, chain, evidence, tail, seal, issue, validateChain, validateCommit};
}

test('the original captured preparation reaches both checks with unchanged argument order', async () => {
  const f = fixture(), captured = await f.issue();
  const original = f.calls.begin[0];
  assert.deepEqual(f.calls.finish, [{preparation: original, retained: true}]);
  assert.equal(await f.validateChain(captured), true);
  assert.equal(await f.validateCommit(captured), true);
  assert.strictEqual(f.calls.chain[0].original, original);
  assert.strictEqual(f.calls.commit[0].original, original);
  const issued = original.args;
  const chain = f.calls.chain[0].args, commit = f.calls.commit[0].args;
  for (const [actual, expected] of [[chain[0], issued[0]], [chain[1], issued[1]],
    [chain[4], issued[4]], [chain[5], issued[5]], [commit[0], issued[0]],
    [commit[1], issued[1]], [commit[8], issued[4]], [commit[9], issued[5]]]) {
    assert.strictEqual(actual, expected);
  }
  assert.deepEqual(chain.slice(2, 4), issued.slice(2, 4));
  assert.deepEqual(commit.slice(2, 4), issued.slice(2, 4));
  assert.strictEqual(chain[6], commit[10]);
  assert.deepEqual(chain.slice(7), [...originalLimits, originalLimits[1] * 4]);
  assert.deepEqual(commit.slice(14), chain.slice(7));
  assert.equal(f.calls.cancel.length, 0, 'checks borrow rather than retire the operation holder');
  f.control.retireCapturedComputation(captured);
  f.control.retireCapturedComputation(captured);
  assert.deepEqual(f.calls.cancel, [original]);
  await f.validateChain(captured);
  await f.validateCommit(captured);
  assert.equal(f.calls.chain[1].original, undefined);
  assert.equal(f.calls.commit[1].original, undefined);
});

test('retirement is exact-wrapper local despite equal visible capture identities', async () => {
  const f = fixture(), first = await f.issue(), second = await f.issue();
  assert.equal(first.identity, second.identity);
  assert.equal(first.wire, second.wire);
  assert.notStrictEqual(first, second);
  f.control.retireCapturedComputation(first);
  await f.validateChain(first);
  await f.validateChain(second);
  assert.equal(f.calls.chain[0].original, undefined);
  assert.strictEqual(f.calls.chain[1].original, f.calls.begin[1]);
  assert.deepEqual(f.calls.cancel, [f.calls.begin[0]]);
  f.control.retireCapturedComputation(second);
  assert.deepEqual(f.calls.cancel, f.calls.begin);
});

test('restored wrappers take full checking and copied or foreign wrappers refuse', async () => {
  const f = fixture(), captured = await f.issue();
  const restored = f.control.admit(captured.name, captured.wire, limits);
  await f.validateChain(restored);
  await f.validateCommit(restored);
  f.control.retireCapturedComputation(restored);
  assert.equal(f.calls.chain[0].original, undefined);
  assert.equal(f.calls.commit[0].original, undefined);
  const foreign = await fixture().issue();
  for (const value of [Object.freeze({...captured}), foreign]) {
    await assert.rejects(f.validateChain(value), /Foreign publication contract/);
    await assert.rejects(f.validateCommit(value), /Foreign publication contract/);
    assert.throws(() => f.control.retireCapturedComputation(value), /Foreign publication contract/);
  }
  assert.equal(f.calls.chain.length, 1);
  assert.equal(f.calls.commit.length, 1);
  assert.equal(f.calls.cancel.length, 0);
  f.control.retireCapturedComputation(captured);
});

test('changed inventories reach Common with the same original envelope, not replacement caller bounds', async () => {
  const f = fixture(), captured = await f.issue();
  const changed = {...f.chain, definitions: [...f.chain.definitions, f.seal('result_definition')],
    receipt: f.seal('computation_receipt')};
  const tighter = {...limits, maxWireBytes: 32768, maxNodes: 2048, maxDepth: 32};
  await f.validateChain(captured, changed, tighter);
  await f.validateCommit(captured, changed, tighter);
  assert.strictEqual(f.calls.chain[0].original, f.calls.begin[0]);
  assert.strictEqual(f.calls.commit[0].original, f.calls.begin[0]);
  assert.equal(f.calls.chain[0].args[2].length, 2);
  assert.deepEqual(f.calls.chain[0].args.slice(7), [...originalLimits, originalLimits[1] * 4]);
  assert.deepEqual(f.calls.commit[0].args.slice(14), [...originalLimits, originalLimits[1] * 4]);
  assert.notStrictEqual(f.calls.chain[0].args[5], f.calls.begin[0].args[5]);
  f.control.retireCapturedComputation(captured);
});

test('retirement failure preserves the same holder for its original retry', async () => {
  const f = fixture(), captured = await f.issue(), failure = new Error('original cancel failure');
  const cancel = f.moon.strategyCapturedRunCancel;
  f.moon.strategyCapturedRunCancel = function(original) {
    assert.strictEqual(this, f.moon); assert.strictEqual(original, f.calls.begin[0]);
    throw failure;
  };
  assert.throws(() => f.control.retireCapturedComputation(captured), error => error === failure);
  await f.validateChain(captured);
  assert.strictEqual(f.calls.chain[0].original, f.calls.begin[0]);
  f.moon.strategyCapturedRunCancel = cancel;
  f.control.retireCapturedComputation(captured);
  await f.validateChain(captured);
  assert.equal(f.calls.chain[1].original, undefined);
  assert.deepEqual(f.calls.cancel, [f.calls.begin[0]]);
});

test('advance, retained finish and wrapper inspection failures cancel the original issuance', async () => {
  for (const method of ['strategyCapturedRunAdvance', 'strategyCapturedRunFinishRetained',
    'strategyPublicationContractJson']) {
    const f = fixture(), failure = new Error(method);
    f.moon[method] = () => {throw failure;};
    await assert.rejects(f.issue(), error => error === failure);
    assert.deepEqual(f.calls.cancel, f.calls.begin);
    assert.equal(f.calls.begin.length, 1);
  }
});

test('cancellation after advance does not publish a retained wrapper', async () => {
  const f = fixture(), abort = new AbortController(), failure = new Error('cancelled issuance');
  f.moon.strategyCapturedRunAdvance = () => {abort.abort(failure); return ok(true);};
  await assert.rejects(f.issue(abort.signal), error => error === failure);
  assert.equal(f.calls.finish.length, 0);
  assert.deepEqual(f.calls.cancel, f.calls.begin);
});

test('Effectful issuance keeps its existing finish and does not retain computation facts', async () => {
  const f = fixture();
  const preview = f.control.admitEffectComputationPreview('{}', f.chain.runDefinition,
    f.evidence.authoringContext, limits);
  const captured = await f.control.issueEffectfulCapturedRun(f.chain,
    {...f.evidence, effectSources: [], localEffectSources: []}, preview, [], limits);
  assert.deepEqual(f.calls.finish, [{preparation: f.calls.begin[0], retained: false}]);
  f.control.retireCapturedComputation(captured);
  assert.equal(f.calls.cancel.length, 0);
});


test('missing or malformed original preparation extents cancel before traversal', async () => {
  for (const projected of [{$tag: 0}, {$tag: 1, _0: [1, 2]},
    {$tag: 1, _0: [1, -1, 3]}, {$tag: 1, _0: [2147483648, 2, 3]}]) {
    const f = fixture();
    f.moon.strategyCapturedRunPreparationLimits = original => {
      assert.strictEqual(original, f.calls.begin[0]);
      return projected;
    };
    f.moon.strategyCapturedRunAdvance = () => assert.fail('No traversal without original limits');
    await assert.rejects(f.issue(), /Invalid original Captured Run preparation limits/);
    assert.deepEqual(f.calls.cancel, f.calls.begin);
    assert.equal(f.calls.finish.length, 0);
  }
});

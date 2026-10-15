import assert from 'node:assert/strict';
import test from 'node:test';
import {preparePinnedEffectSourceSet} from './effect-input-export.mjs';

// Host sequencing fixture only: Moon admission and Store capacity are explicit
// doubles, not evidence of installed or runtime acceptance.
const cidA = 'sha256:' + 'a'.repeat(64);
const cidB = 'sha256:' + 'b'.repeat(64);
const ok = value => ({$tag: 1, _0: value});
const vector = (...cids) => Object.freeze(cids.map((sourceBindingCid, memberIndex) =>
  Object.freeze({memberIndex, sourceBindingCid})));

function fixture({views = [0, 0], extraResults = [], capacity = 20, failAppend, failRelease} = {}) {
  const events = {writers: [], bindings: [], manifests: [], comparisons: 0};
  const inputs = views.map((view, memberIndex) => ({view, memberIndex}));
  const localResults = [...new Set([...views, ...extraResults])].map(view => ({view}));
  const moon = {
    clientProgramEffectInputCount: () => inputs.length,
    clientProgramEffectInputsShareView: (_, left, right) => {
      events.comparisons++;
      return inputs[left].view === inputs[right].view;
    },
    clientProgramEffectInputAt: (_, index) => inputs[index],
    clientProgramEffectInputStage: () => 0,
    clientProgramEffectResultImportCount: () => 0,
    clientProgramEffectLocalResultCount: () => localResults.length,
    clientProgramEffectLocalResultAt: (_, index) => localResults[index],
    clientProgramEffectLocalResultStage: () => 0,
    clientProgramEffectLocalResultTask: input => input,
    clientProgramEffectLocalResultName: input => String(input.view),
    clientProgramEffectLocalResultMatchesMember: (_, result, member) =>
      localResults[result].view === inputs[member].view,
    clientProgramIssueLocalEffectResultDefinition: (_, __, name) => ok({view: Number(name)}),
    clientProgramEffectLocalManagedInputBegin: input => ok({input}),
    clientProgramEffectLocalManagedExportOwner: (_, __, importing) => ok(importing),
    clientProgramEffectInputTask: input => input,
    clientProgramIssueCapturedEffectInputLocalResultDefinition: (_, __, index) =>
      ok({view: inputs[index].view}),
    clientProgramIssueCapturedEffectInputLocalInvocation: () => ok({}),
    clientProgramLocalEffectResultDefinitionCid: value => `definition-${value.view}`,
    clientProgramLocalEffectResultDefinitionJson: value => JSON.stringify(value),
    clientProgramLocalEffectInvocationCid: () => 'invocation',
    clientProgramLocalEffectInvocationJson: () => '{}',
    clientProgramEffectManagedInputBegin: input => ok({input}),
    clientProgramEffectManagedInputAppend: () => ok(undefined),
    clientProgramEffectManagedInputFinish: input => ok(input),
    clientProgramEffectInputExportAdvance: () => ok({_0: true, _1: 1}),
    clientProgramEffectInputExportReady: value => ok(value),
    clientProgramEffectInputExportNext: stream => {
      if (stream.sent) return ok(undefined);
      stream.sent = true;
      return ok('[]');
    },
    clientProgramEffectInputExportFinish: stream => ok({_0: stream, _1: ''}),
    clientProgramEffectInputExportFields: () => [],
    clientProgramEffectInputExportLogicalCid: () => 'logical',
    clientProgramEffectInputExportSchemaCid: () => 'schema',
    clientProgramEffectInputExportRowCount: () => 0,
    clientProgramEffectInputExportReleaseReceipt() {},
    clientProgramEffectInputExportCancel() {},
    clientProgramEffectInputExportCancelPreparation() {},
    clientProgramEffectManagedInputCancel() {},
  };
  const store = {
    storeAuthorityCid: 'store',
    createPreparedObjectWriter(maxBytes) {
      if (events.writers.filter(value => value.pending).length >= capacity) {
        throw new RangeError('FixtureStoreCapacity');
      }
      const state = {maxBytes, bytes: 0, pending: true, released: 0, cancelled: 0};
      events.writers.push(state);
      const prepared = {
        status: () => ({pending: state.pending}),
        async release() {
          state.released++;
          if (failRelease && state === events.writers[0] && state.released === 1) {
            throw new Error('FixtureReleaseFailure');
          }
          state.pending = false;
        },
        async retry() { await prepared.release(); },
      };
      return {
        async append(chunk) {
          if (failAppend === events.writers.length) throw new Error('FixtureAppendFailure');
          state.bytes += Buffer.byteLength(chunk);
          assert.ok(state.bytes <= maxBytes);
        },
        async seal(cid) { return {cid, bytes: state.bytes, prepared}; },
        async cancel() { state.cancelled++; state.pending = false; },
        status: () => ({reservationHeld: state.pending}),
      };
    },
  };
  const control = {
    publicationPreparedReleaseAction(index, count, inspected, pending, attempted) {
      if (index < 0) return 'finished';
      if (!inspected) return 'inspect';
      return pending && !attempted ? 'release' : 'advance';
    },
    publicationCleanupOwnerAction(index, count, inspected, pending, available, attempted) {
      if (index >= count) return 'finished';
      if (!inspected) return 'inspect';
      return pending && available && !attempted ? 'retry' : 'advance';
    },
    issueEffectSourceArtifactFromExport(input, receipt, invocation, retention, binding) {
      events.bindings.push(binding);
      return Object.freeze({identity: binding, wire: JSON.stringify({binding})});
    },
    issueSourceFreeLocalEffectResultArtifact(_, __, index) {
      return Object.freeze({identity: `result-${inputs[index].view}`, wire: '{}'});
    },
    issueSourceFreeExportedLocalEffectResultArtifact(_, __, importing, definition) {
      return Object.freeze({identity: `result-${definition.view}`, wire: '{}'});
    },
    issueLocalEffectResultManifest(_, invocation, artifacts) {
      assert.equal(new Set(artifacts.map(value => value.identity)).size, artifacts.length);
      assert.deepEqual(artifacts.map(value => value.identity).sort(),
        localResults.map(value => `result-${value.view}`).sort(),
        'A Unit Manifest includes declared Results that no Effect consumes');
      events.manifests.push(artifacts);
      return Object.freeze({identity: 'manifest', wire: '{}'});
    },
  };
  const options = {moon, inputs, store, control, checkedOwner: {},
    execution: {effectPhysicalSource: () => ({completed: {}, material: {},
      withRows: async (append, signal, finish) => finish()})},
    maxMembers: inputs.length, maxGroupingWork: 20, maxBytes: 100,
    limits: {}, sourceBindingCid: cidA, invocation: {}, retention: {},
    contractLimits: {maxWireBytes: 1000, maxNodes: 100, maxDepth: 10},
    localEvidenceContext: {admission: {}, runDefinition: {}, runInvocation: {},
      observation: {}, sourceFreeDependencyClosure: true},
  };
  return {options, events};
}

test('ordinary-only Effects complete the Manifest with an earlier unconsumed Result', async () => {
  const {options, events} = fixture({views: [1], extraResults: [0]});
  const sources = await preparePinnedEffectSourceSet(options);
  assert.equal(sources.members.length, 1);
  assert.equal(sources.payloads.length, 1);
  assert.deepEqual(events.manifests[0].map(value => value.identity), ['result-1', 'result-0']);
  assert.deepEqual(events.writers.map(value => value.pending), [true, false],
    'Only temporary Manifest export custody is released before returning the member');
  await sources.payloads[0].prepared.release();
  assert.deepEqual(events.writers.map(value => value.pending), [false, false]);
});

test('same live Result and different original bindings retain separate prepared owners', async () => {
  const {options, events} = fixture();
  const sources = await preparePinnedEffectSourceSet({...options,
    memberSourceBindings: vector(cidA, cidB)});
  assert.equal(sources.payloads.length, 2);
  assert.notEqual(sources.members[0].payload.prepared, sources.members[1].payload.prepared);
  assert.deepEqual(events.bindings, [cidA, cidB]);
  assert.deepEqual(events.writers.map(value => value.maxBytes), [100, 100]);
  assert.equal(events.manifests[0].length, 1);
  await sources.members[0].payload.prepared.release();
  assert.deepEqual(events.writers.map(value => value.pending), [false, true]);
  await sources.members[1].payload.prepared.release();
});

test('same binding shares only when Moon proves the same live Result', async () => {
  for (const [views, expected] of [[[0, 0], 1], [[0, 1], 2]]) {
    const {options, events} = fixture({views});
    const sources = await preparePinnedEffectSourceSet({...options,
      memberSourceBindings: vector(cidA, cidA)});
    assert.equal(sources.payloads.length, expected);
    assert.equal(events.writers.length, expected);
    for (const payload of sources.payloads) await payload.prepared.release();
  }
});

test('nonadjacent original members keep positional bindings and only two physical owners', async () => {
  const {options, events} = fixture({views: [0, 0, 0]});
  const sources = await preparePinnedEffectSourceSet({...options,
    memberSourceBindings: vector(cidA, cidB, cidA)});
  assert.deepEqual(sources.members.map(value => value.memberIndex), [0, 1, 2]);
  assert.equal(sources.members[0].payload, sources.members[2].payload);
  assert.notEqual(sources.members[0].payload, sources.members[1].payload);
  assert.deepEqual(events.bindings, [cidA, cidB]);
  assert.equal(events.manifests[0].length, 1);
  for (const payload of sources.payloads) await payload.prepared.release();
});

test('singular binding keeps the original grouping and identity bytes', async () => {
  const {options, events} = fixture();
  const sources = await preparePinnedEffectSourceSet(options);
  assert.equal(sources.payloads.length, 1);
  assert.deepEqual(events.bindings, [cidA]);
  assert.equal(sources.members[0].payload.summary.artifact.wire, JSON.stringify({binding: cidA}));
  await sources.payloads[0].prepared.release();
});

test('equal artifact CID from different live views never removes a Manifest member', async () => {
  const {options, events} = fixture({views: [0, 1]});
  options.control.issueSourceFreeLocalEffectResultArtifact = () =>
    Object.freeze({identity: 'equal-content', wire: '{}'});
  // The original Manifest owner must see and reject the collision. The Host
  // must not convert equal content into a live-view ownership proof.
  await assert.rejects(preparePinnedEffectSourceSet({...options,
    memberSourceBindings: vector(cidA, cidB)}), {code: 'ERR_ASSERTION'});
  assert.equal(events.writers.length, 2);
  assert.deepEqual(events.writers.map(value => value.pending), [false, false]);
});

test('invalid, mutable, sparse, accessor and misindexed vectors fail before Store I/O', async () => {
  const accessor = Object.freeze(Object.defineProperty([, vector(cidA, cidB)[1]], '0', {
    get() { throw new Error('AccessorMustNotRun'); },
  }));
  const invalid = [[], vector(cidA), Object.freeze([, vector(cidA, cidB)[1]]),
    [...vector(cidA, cidB)], Object.freeze([{memberIndex: 0, sourceBindingCid: cidA}, vector(cidA, cidB)[1]]),
    vector(cidA, 'sha256:no'), vector(cidA, cidB.toUpperCase()), vector(cidA, cidB + '\n'), accessor,
    Object.freeze([...vector(cidA, cidB)].reverse()),
    Object.freeze([Object.freeze({get memberIndex() { throw new Error('AccessorMustNotRun'); },
      sourceBindingCid: cidA}), vector(cidA, cidB)[1]])];
  for (const memberSourceBindings of invalid) {
    const {options, events} = fixture();
    await assert.rejects(preparePinnedEffectSourceSet({...options, memberSourceBindings}),
      /InvalidEffectMemberSourceBindings/);
    assert.equal(events.writers.length, 0);
    assert.equal(events.comparisons, 0);
  }
});

test('the existing grouping and member ceilings apply before any Store reservation', async () => {
  for (const bounds of [{maxGroupingWork: 2}, {maxMembers: 1}]) {
    const {options, events} = fixture();
    await assert.rejects(preparePinnedEffectSourceSet({...options, ...bounds,
      memberSourceBindings: vector(cidA, cidB)}), /EffectSource(Grouping|Member)Limit/);
    assert.equal(events.writers.length, 0);
    assert.ok(events.comparisons <= 2);
  }
});

test('source-free import validation and grouping spend the same existing work budget', async () => {
  const {options, events} = fixture();
  // Two import checks + three live-view checks + one declared Result visit
  // + one retained member match. The former five-work budget now refuses;
  // neither the option nor the refusal ceiling is increased by the adapter.
  const sources = await preparePinnedEffectSourceSet({...options, maxGroupingWork: 7,
    memberSourceBindings: vector(cidA, cidB)});
  assert.equal(events.comparisons, 3);
  for (const payload of sources.payloads) await payload.prepared.release();
  for (const maxGroupingWork of [4, 5]) {
    const refusal = fixture();
    await assert.rejects(preparePinnedEffectSourceSet({...refusal.options, maxGroupingWork,
      memberSourceBindings: vector(cidA, cidB)}), /EffectSourceGroupingLimit/);
    assert.equal(refusal.events.writers.length, 0);
  }
});

test('different bindings charge separate Store capacity and release completed siblings on refusal', async () => {
  const {options, events} = fixture({capacity: 1});
  await assert.rejects(preparePinnedEffectSourceSet({...options,
    memberSourceBindings: vector(cidA, cidB)}), /FixtureStoreCapacity/);
  assert.equal(events.writers.length, 1);
  assert.equal(events.writers[0].released, 1);
  assert.equal(events.writers[0].pending, false);
});

test('failed sibling export cancels its writer and releases already prepared siblings', async () => {
  const {options, events} = fixture({failAppend: 2});
  await assert.rejects(preparePinnedEffectSourceSet({...options,
    memberSourceBindings: vector(cidA, cidB)}), /FixtureAppendFailure/);
  assert.deepEqual(events.writers.map(value => [value.released, value.cancelled, value.pending]),
    [[1, 0, false], [0, 1, false]]);
});

test('failed sibling cleanup keeps the existing retry owner until release succeeds', async () => {
  const {options, events} = fixture({failAppend: 2, failRelease: true});
  const failure = await preparePinnedEffectSourceSet({...options,
    memberSourceBindings: vector(cidA, cidB)}).then(() => assert.fail('expected failure'), error => error);
  assert.equal(failure.cleanupPending, true);
  assert.equal(failure.cleanupHandle.status().pending, true);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.deepEqual(events.writers.map(value => value.pending), [false, false]);
});

test('per-output byte bound stays unchanged and refuses oversized export', async () => {
  const {options, events} = fixture();
  await assert.rejects(preparePinnedEffectSourceSet({...options, maxBytes: 1,
    memberSourceBindings: vector(cidA, cidB)}), /EffectSourceByteLimit/);
  assert.equal(events.writers.length, 1);
  assert.equal(events.writers[0].cancelled, 1);
});

test('acquired and imported source vectors are explicitly unsupported before Store I/O', async () => {
  for (const kind of ['acquired', 'byUnit', 'imported', 'importedWithoutFlag', 'invalidCount']) {
    const {options, events} = fixture();
    if (kind === 'acquired') options.localEvidenceContext.acquiredEvidence = {};
    else if (kind === 'byUnit') options.localEvidenceContext.acquiredEvidenceByUnit = [];
    else options.moon.clientProgramEffectResultImportCount = () => kind === 'invalidCount' ? -1 : 1;
    if (kind === 'importedWithoutFlag') options.localEvidenceContext.sourceFreeDependencyClosure = false;
    await assert.rejects(preparePinnedEffectSourceSet({...options,
      memberSourceBindings: vector(cidA, cidB)}), /UnsupportedDependentEffectMemberSourceBindings/);
    assert.equal(events.writers.length, 0);
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {assertEffectTargetReadBinding, effectTargetReadContinuation,
  isEffectTargetReadRefusal} from './effect-target-read-continuation.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

async function readOwner(gates) {
  return effectTargetReadContinuation({
    checkpoints: {async inspectEffectTargetApprovals() { return []; },
      async effectTargetAuthorization({target}) { return gates[target.index]; }},
    runId: 'cleanup-run', runDefinitionCid: cid('a'), unitId: 'effect',
    declaredResults: ['answer'], principalId: 'owner', submission: {},
    inventory: gates.map((_, index) => ({
      readTuple: {connection: 'crm', resource: `Record${index}`, operation: 'read'},
      physicalBinding: {version: 'cleanup-fixture/0.1', member: index}})),
  });
}

for (const failed of [0, 1, 2]) {
  test(`target-read cleanup retries only failed synchronous gate ${failed}`, async () => {
    const closes = [0, 0, 0];
    const failure = new Error('GateCloseUnavailable');
    const owner = await readOwner(closes.map((_, index) => ({close() {
      closes[index]++;
      if (index === failed && closes[index] === 1) throw failure;
    }})));
    assert.throws(() => owner.close(), error => error === failure);
    assert.deepEqual(closes, [1, 1, 1], 'a failed gate does not skip its siblings');
    await assert.rejects(owner.prepare(), {code: 'EffectTargetReadOwnerClosed'});
    assert.equal(owner.cleanupPending(), true);
    assert.equal(owner.cleanup(), true);
    assert.equal(owner.cleanupPending(), false);
    assert.equal(owner.close(), true);
    assert.deepEqual(closes, closes.map((_, index) => index === failed ? 2 : 1));
  });
}

test('target-read cleanup preserves an existing gate cleanup owner after revocation', async () => {
  let pending = true, closes = 0, cleanups = 0;
  const owner = await readOwner([{close() { closes++; return false; },
    cleanup() { cleanups++; return !pending; }, cleanupPending: () => pending}]);
  assert.equal(owner.close(), false);
  assert.equal(owner.cleanupPending(), true);
  assert.equal(owner.cleanup(), false);
  pending = false;
  assert.equal(owner.cleanup(), true);
  assert.equal(owner.cleanup(), true);
  assert.equal(owner.close(), true);
  assert.equal(closes, 1);
  assert.equal(cleanups, 2);
});

for (const child of ['read', 'inputs', 'physicalClose', 'physical', 'stage']) {
  test(`installed Effect cleanup retains the failed ${child} child only`, async () => {
    const calls = {read: 0, inputs: 0, physicalClose: 0, physical: 0, stage: 0};
    const failure = new Error(`${child}Unavailable`);
    const attempt = name => { calls[name]++; if (name === child && calls[name] === 1) throw failure; };
    let custody, physicalPending = true;
    const targetReads = {async prepare() { return {status: 'ready'}; },
      enterComputation() {}, close() { attempt('read'); }};
    const execution = {async close() { attempt('physicalClose'); },
      async cleanup() { attempt('physical'); physicalPending = false; return true; },
      cleanupPending: () => physicalPending};
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() { return {releaseInputs() { attempt('inputs'); },
        dispose() { attempt('stage'); }}; },
      prepareRecovered() { assert.fail('No replacement execution'); }});
    await assert.rejects(site.execute({targetReads,
      openComputation: () => ({execution, checkedHost: {}}),
      retainExecution: value => { custody = value; }}),
    {code: 'InvalidInstalledEffectCapture'});
    if (['read', 'inputs', 'physicalClose'].includes(child)) {
      await assert.rejects(custody.close(), error => error === failure);
    } else {
      await custody.close();
      await assert.rejects(custody.cleanup(), error => error === failure);
    }
    assert.equal(custody.cleanupPending(), true);
    assert.equal(await custody.cleanup(), true);
    assert.equal(custody.cleanupPending(), false);
    const completedCalls = {...calls};
    await custody.close();
    assert.equal(await custody.cleanup(), true);
    assert.deepEqual(calls, completedCalls, 'completed children are never invoked again');
    assert.deepEqual(calls, {read: child === 'read' ? 2 : 1,
      inputs: child === 'inputs' ? 2 : 1, physicalClose: 1,
      physical: child === 'physical' ? 2 : 1, stage: child === 'stage' ? 2 : 1});
  });
}

test('dispatch retains installed Effect custody until read cleanup confirms completion', async () => {
  const ref = {runDefinitionCid: cid('b')};
  const observations = [];
  let pending = true, closes = 0, cleanups = 0;
  const targetReads = {async prepare() { return {status: 'waiting_checkpoint'}; },
    close() { closes++; return false; },
    cleanup() { cleanups++; return !pending; }, cleanupPending: () => pending};
  const site = createInstalledEffectSite({environmentWire: '{}',
    prepareCaptured() { assert.fail('No Compute before approval'); },
    prepareRecovered() { assert.fail('No replacement execution'); }});
  const dispatch = installNodeClientDispatchOwner({});
  await assert.rejects(dispatch.track(ref, {observeStopped: value => observations.push(value),
    run: context => site.execute({...context, targetReads,
      openComputation() { assert.fail('No Compute before approval'); }})}),
  {message: 'ClientDispatchCleanupPending'});
  assert.deepEqual(observations, []);
  assert.notEqual(dispatch.operation(ref), undefined);
  await assert.rejects(dispatch.drain(), {message: 'ClientDispatchCleanupPending'});
  assert.deepEqual(observations, []);
  assert.notEqual(dispatch.operation(ref), undefined);
  pending = false;
  await dispatch.drain();
  assert.deepEqual(observations, [null]);
  assert.equal(dispatch.operation(ref), undefined);
  assert.equal(closes, 1);
  assert.ok(cleanups >= 2);
});


for (const kind of ['mutable', 'frozen', 'primitive', 'refusal', 'earlier',
  'readonly_handle', 'readonly_pending', 'accessor', 'inherited']) {
  test(`partial target owner construction retains ${kind} failure and unfinished children`, async () => {
    let primary = new Error('FourthTargetUnavailable');
    const hasEarlier = ['earlier', 'readonly_handle', 'readonly_pending', 'accessor', 'inherited'].includes(kind);
    let earlierPending = hasEarlier, earlierRetries = 0;
    if (kind === 'primitive') primary = 'FourthTargetUnavailable';
    if (kind === 'refusal') {
      try { assertEffectTargetReadBinding({}); } catch (error) { primary = error; }
    }
    if (hasEarlier) Object.assign(primary, {cleanupPending: true,
      cleanupHandle: {status: () => ({pending: earlierPending}), async retry() {
        if (++earlierRetries === 1) throw new Error('EarlierCleanupUnavailable');
        earlierPending = false;
      }}});
    if (kind === 'readonly_handle') Object.defineProperty(primary, 'cleanupHandle', {writable: false});
    if (kind === 'readonly_pending') Object.defineProperty(primary, 'cleanupPending', {writable: false});
    if (kind === 'inherited') {
      const handle = primary.cleanupHandle;
      delete primary.cleanupHandle;
      delete primary.cleanupPending;
      Object.setPrototypeOf(primary, Object.create(Error.prototype, {
        cleanupHandle: {value: handle}, cleanupPending: {value: true}}));
    }
    if (kind === 'accessor') {
      const handle = primary.cleanupHandle;
      Object.defineProperty(primary, 'cleanupHandle', {get: () => handle});
    }
    if (['frozen', 'refusal', 'earlier'].includes(kind)) Object.freeze(primary);
    const closes = [0, 0, 0];
    let builds = 0, failure;
    try {
      await effectTargetReadContinuation({
        checkpoints: {async inspectEffectTargetApprovals() { return []; },
          async effectTargetAuthorization() {
            const index = builds++;
            if (index === 3) throw primary;
            return {close() {
              if (++closes[index] === 1 && index === 1) throw new Error('CloseUnavailable');
            }};
          }},
        runId: 'cleanup-run', runDefinitionCid: cid('a'), unitId: 'effect',
        declaredResults: ['answer'], principalId: 'owner', submission: {},
        inventory: [0, 1, 2, 3].map(index => ({
          readTuple: {connection: 'crm', resource: `Record${index}`, operation: 'read'},
          physicalBinding: {version: 'cleanup-fixture/0.1', member: index}})),
      });
      assert.fail('The construction failure must be retained');
    } catch (error) { failure = error; }
    if (['mutable', 'inherited'].includes(kind)) assert.equal(failure, primary);
    else {
      assert.equal(failure.primaryFailure, primary);
      assert.equal(failure.cause, primary);
    }
    assert.equal(isEffectTargetReadRefusal(failure), kind === 'refusal');
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(closes, [1, 1, 1], 'all acquired siblings are attempted');
    assert.equal((await failure.cleanupHandle.retry()).pending, hasEarlier);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(closes, [1, 2, 1]);
    assert.equal(earlierRetries, hasEarlier ? 2 : 0);
    assert.equal(builds, 4, 'cleanup does not reopen authorization');
  });
}

test('recovered Effect custody retains prepared release until its original owner completes', async () => {
  const moon = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  const {runtimeCore} = await import('../host-common/runtime-core.mjs');
  const {storeCompletedRunResultSet} = await import('../host-common/completed-run-publication.mjs');
  const contract = identity => ({name: 'result_definition', identity, wire: '{}'});
  const control = {...runtimeCore(moon).publicationControl,
    effectComputationPreviewSemanticCid: () => cid('a')};
  const limits = {maxWireBytes: 4096, maxNodes: 128, maxDepth: 8};
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'), effective_data_policy_cid: cid('a'),
    available_until: '2026-09-27T01:00:00.000Z',
    delete_by: '2026-09-27T02:00:00.000Z',
    extension_ceiling_at: '2026-09-27T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    metadata_delete_by: '2026-09-27T04:00:00.000Z', clock_contract_cid: cid('d'),
  }), limits);
  let pending = true, releases = 0, retries = 0, custody;
  const prepared = {status: () => ({pending}),
    async release() { releases++; throw new Error('PreparedReleaseUnavailable'); },
    async retry() { retries++; pending = false; }};
  const definition = contract(cid('1'));
  const execution = {status: 'host-tasks-completed', resultInventory: [{name: 'answer'}],
    publicationInventory: {occurrences: [{name: 'answer', task: 0, definitionContract: definition}]},
    async storePublicationResult() { return {occurrence: {name: 'answer', task: 0, definition},
      publication: {artifact: contract(cid('2')), derivation: contract(cid('3')),
        ordering: contract(cid('4')), durableBinding: contract(cid('5')), snapshot: {}}, prepared}; }};
  const storedResults = await storeCompletedRunResultSet({execution, store: {
    async retireEffectCaptureCustody() {}}, control,
    runDefinition: contract(cid('6')), invocation: contract(cid('7')),
    results: [{retention, evidenceContext: {}}], outputLimits: {}, contractLimits: limits});
  const site = createInstalledEffectSite({environmentWire: '{}',
    prepareCaptured() { assert.fail('No new Compute'); },
    prepareRecovered() { assert.fail('The invalidated approval cannot apply'); }});
  assert.deepEqual(await site.resume({control, ref: {runDefinitionCid: cid('6')},
    view: {runId: 'run', subject: {kind: 'run_unit', unit_id: 'effect'}},
    continuation: {version: 'actql-installed-effect-continuation/0.1',
      run_definition_cid: cid('6'), unit_id: 'effect', preview_cid: cid('a')},
    retainExecution: value => { custody = value; },
    recoverCapture: async () => ({computation: {storedResults, computation: {}, preview: {}}}),
    checkpointJournal: {claimResume: () => ({action: 'invalidated'})},
  }), {status: 'failed'});
  await custody.close();
  await assert.rejects(custody.cleanup(), {cleanupPending: true});
  assert.equal(custody.cleanupPending(), true);
  assert.equal(pending, true);
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
  assert.equal(await custody.cleanup(), true);
  assert.equal(releases, 1);
  assert.equal(retries, 1);
});

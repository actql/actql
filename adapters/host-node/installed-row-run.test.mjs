import assert from 'node:assert/strict';
import test from 'node:test';
import {startInstalledRowRun} from './installed-row-run.mjs';

const ok = value => ({$tag: 1, _0: value});
const token = name => Object.freeze({name});

test('keyed original enters only its same Run Ledger and retires after the original capture cleanup', () => {
  const acquisition = {}, originalKeyedRead = {}, ledger = {}, run = {}, calls = [];
  let captureReady = false;
  const moon = {
    clientProgramInstalledKeyedSourceReadCheckLedger(read, actualLedger) {
      assert.strictEqual(read, originalKeyedRead); assert.strictEqual(actualLedger, ledger);
      calls.push('ledger'); return ok(undefined);
    },
    clientProgramInstalledKeyedSourceReadStartRows(read, actualAcquisition, nonce, stopped, transfer, execution, cleanup) {
      assert.strictEqual(read, originalKeyedRead); assert.strictEqual(actualAcquisition, acquisition);
      assert.equal(nonce, 'keyed'); assert.equal(transfer, 1024n); assert.equal(execution, 512n);
      assert.equal(typeof stopped, 'function'); assert.equal(typeof cleanup, 'function');
      calls.push('start'); return ok(run);
    },
    clientProgramRowSourceCloseAccounted(value) {assert.strictEqual(value, run); calls.push('close'); return ok(undefined);},
    clientProgramRowSourceCaptureCleanup(value) {assert.strictEqual(value, run); calls.push('capture'); return ok(captureReady);},
    clientProgramInstalledKeyedSourceReadRetire(value) {assert.strictEqual(value, originalKeyedRead); calls.push('retire'); return ok(undefined);},
  };
  const options = {moon, acquisition, originalKeyedRead, ledger, keyed: true, nonce: 'keyed',
    capacity: {transferBytes: 1024n, executionBytes: 512n}};
  const session = startInstalledRowRun(options);
  assert.deepEqual(calls, ['ledger', 'start']);
  assert.throws(() => session.close(), {code: 'InstalledSourceCleanupPending'});
  assert.equal(calls.includes('retire'), false);
  captureReady = true;
  session.close(); session.close();
  assert.equal(calls.filter(name => name === 'start').length, 1);
  assert.equal(calls.filter(name => name === 'retire').length, 1);
});

test('keyed original foreign Ledger refusal precedes RowRun creation', () => {
  const read = {}, ledger = {}, refusal = new Error('original-Ledger');
  let started = false;
  const moon = {
    clientProgramInstalledKeyedSourceReadCheckLedger(actual, original) {
      assert.strictEqual(actual, read); assert.strictEqual(original, ledger);
      return {$tag: 0, _0: refusal};
    },
    clientProgramInstalledKeyedSourceReadStartRows() {started = true;},
    clientProgramInstalledKeyedSourceReadRetire() {},
  };
  assert.throws(() => startInstalledRowRun({moon, acquisition: {}, originalKeyedRead: read,
    keyed: true, ledger, capacity: {transferBytes: 1024n, executionBytes: 512n}}),
  error => error.code === 'MoonBitHostFailure' && error.cause === refusal);
  assert.equal(started, false);
});

function rowRunFixture({accounted = false, effectful = false, task = 0,
  retainedRelationOutput = false, listingReport = false, typedEvidence = false} = {}) {
  const calls = [];
  const failures = new Map();
  const responses = new Map();
  const acquisition = token('acquisition');
  const run = token('run');
  const capture = token('capture');
  const source = token('source');
  const identity = token('identity');
  const logicalInput = token('logical-input');
  const requirement = token('requirement');
  const checkedOwner = token('checked-owner');
  const checkedSource = token('checked-source');
  const setup = token('host');
  const evidence = token('source-evidence');
  const originalEvidence = token('original-source-evidence');
  const retainedTask = token('retained-task');
  const ledger = accounted ? token('ledger') : undefined;
  const capacity = {transferBytes: 8192n, executionBytes: 1024n};
  const reportCapacity = listingReport ? token('original-report-declaration') : undefined;
  if (listingReport) capacity.listingReport = reportCapacity;
  const occurrence = Object.freeze({stage: task, input: 0, task});
  const owner = Object.freeze({checkedOwner, effectful, requirement, occurrence});
  const prepared = Object.freeze({checkedSource});
  const registry = 'registry-wire';
  const values = 'values-wire';
  const fragment = 'fragment-wire';
  const ordered = 'ordered-wire';
  const nonce = 'run-nonce';
  const attempt = 'physical-attempt';
  const foreignAttempt = 'foreign-physical-attempt';
  let settled;
  let currentRead = async () => true;
  const moon = {};
  const names = () => calls.map(call => call.name);
  const count = name => calls.filter(call => call.name === name).length;
  const exact = (actual, expected) => {
    assert.equal(actual.length, expected.length);
    expected.forEach((value, index) => assert.equal(actual[index], value));
  };
  const method = (name, expected, result, inspect = () => {}) => {
    moon[name] = (...args) => {
      calls.push({name, args});
      if (expected !== undefined) exact(args, expected);
      inspect(args);
      const failure = failures.get(name);
      if (failure !== undefined && failure.remaining > 0) {
        failure.remaining--;
        if (failure.checked) return {$tag: 0, _0: failure.error};
        throw failure.error;
      }
      return responses.has(name) ? responses.get(name) : result;
    };
  };
  const startName = listingReport ? 'clientProgramRowSourceStartListingAccounted'
    : accounted ? 'clientProgramRowSourceStartAccounted'
    : 'clientProgramRowSourceStart';
  method(startName, undefined, ok(run), args => {
    const verifyIndex = listingReport ? 3 : 2;
    assert.equal(typeof args[verifyIndex], 'function');
    settled = args[verifyIndex];
    exact(args, [acquisition, ...(listingReport ? [reportCapacity] : []), nonce, settled,
      ...(accounted ? [ledger, capacity.transferBytes,
        capacity.executionBytes] : [])]);
    assert.equal(settled(attempt), false);
    assert.equal(settled(foreignAttempt), false);
  });
  const closeName = accounted ? 'clientProgramRowSourceCloseAccounted'
    : 'clientProgramRowSourceClose';
  method(closeName, [run], accounted ? ok(undefined) : undefined);
  method('clientProgramRowSourceFinish', [run], ok(undefined), () => {
    assert.equal(settled(attempt), false,
      'the physical attempt is not settled before Finish succeeds');
  });
  method('clientProgramRowSourceAttempt', [run], attempt, () => {
    assert.equal(settled(attempt), false);
  });
  method('clientProgramRowSourceCaptureBegin', [run], ok(undefined), () => {
    assert.equal(settled(attempt), true);
  });
  method('clientProgramRowSourceCaptureAdvance', [run, 64],
    ok({_0: true, _1: 1n}));
  method('clientProgramRowSourceCaptureCleanup', [run], ok(true));
  method('clientProgramRowSourceCaptureCleanupAdvance', [run, 64], ok(true));
  method('clientProgramRowSourceCapture', [run], ok(capture), () => {
    assert.equal(settled(attempt), true,
      'the completed physical attempt is settled before Capture');
    assert.equal(settled(foreignAttempt), false);
  });
  method('clientProgramRowSourceCaptureSource', [capture], ok(source));
  const matchName = effectful
    ? task === 0 ? 'clientProgramEffectCapturedSourceMatches'
      : 'clientProgramEffectCapturedSourceMatchesAt'
    : 'clientProgramCapturedTaskSourceMatches';
  method(matchName, [checkedOwner, source,
    ...(!effectful || task !== 0 ? [task] : [])], true);
  const identifyName = effectful
    ? 'clientProgramIdentifyCapturedEffectSourceRelation'
    : 'clientProgramIdentifyCapturedSourceRelation';
  method(identifyName, [source], ok(identity));
  const logicalName = effectful
    ? task === 0 ? 'clientProgramEffectIssueCapturedSourceLogical'
      : 'clientProgramEffectIssueCapturedSourceLogicalAt'
    : 'clientProgramIssueCapturedTaskSourceLogical';
  method(logicalName, [checkedOwner, source, identity, requirement,
    ...(!effectful || task !== 0 ? [task] : [])], ok(logicalInput));
  method('clientProgramSelectedInferStep', [checkedOwner], undefined);
  method('clientProgramComposedInferOccurrences', [checkedOwner], ok([]));
  const hostName = retainedRelationOutput
    ? 'clientProgramOpenCapturedLocalRetainedHost'
    : 'clientProgramOpenCapturedLocalHost';
  for (const name of ['clientProgramOpenCapturedLocalHost',
    'clientProgramOpenCapturedLocalRetainedHost']) {
    method(name, [checkedOwner, source, registry, values, 1n, 0n, 0n, 0n,
      fragment, ordered], setup, () => {
      assert.equal(accounted || effectful, false,
        'only ordinary unaccounted captures open a local Host');
      assert.equal(name, hostName);
    });
  }
  method('clientProgramRowSourceIssueSourceEvidence', undefined, ok(evidence),
    args => {
      exact(args.slice(0, 6), [acquisition, capture, identity, logicalInput,
        'authority-scope-cid', 'effective-policy-cid']);
      assert.equal(args.length, 7);
      assert.equal(new Date(args[6]).toISOString(), args[6]);
    });
  if (typedEvidence) method('clientProgramRowSourceIssueSourceEvidenceOriginal',
    undefined, ok(originalEvidence), args => {
      exact(args.slice(0, 6), [acquisition, capture, identity, logicalInput,
        'authority-scope-cid', 'effective-policy-cid']);
      assert.equal(args.length, 7);
      assert.equal(new Date(args[6]).toISOString(), args[6]);
    });
  method('clientProgramRowSourceRetainCapturedTask', undefined,
    ok(retainedTask), args => {
      assert.equal(args.length, 3);
      assert.equal(args[0], capture);
    });
  const options = {owner, prepared, registry, values, fragment, ordered,
    retainedRelationOutput,
    currentRead: async () => {
      calls.push({name: 'currentRead', args: []});
      return currentRead();
    }};
  return {run, capture, source, identity, logicalInput, requirement, occurrence,
    prepared, setup, evidence, originalEvidence, retainedTask, calls, names, count, options,
    startName, closeName, matchName, identifyName, logicalName, hostName,
    settled: value => settled(value), attempt, foreignAttempt,
    authorize: read => { currentRead = read; },
    respond: (name, value) => responses.set(name, value),
    fail(name, {times = 1, checked = false} = {}) {
      const error = new Error(`${name}Failed`);
      failures.set(name, {remaining: times, checked, error});
      return error;
    },
    start: () => startInstalledRowRun({moon, acquisition, nonce, ledger,
      capacity: accounted ? capacity : undefined}),
  };
}

test('selected listing declaration enters the original accounted RowRun and capture owner', async () => {
  const f = rowRunFixture({accounted: true, listingReport: true});
  const owner = f.start();
  assert.equal(owner.run, f.run);
  const result = await owner.complete(f.options);
  assert.equal(result.identity, f.identity);
  assert.equal(result.capture.originalRead instanceof Function, true);
  assert.equal(f.count('clientProgramRowSourceStartListingAccounted'), 1);
  assert.equal(f.count('clientProgramRowSourceStartAccounted'), 0);
  assert.equal(f.count('clientProgramRowSourceStart'), 0);
  owner.close();
  owner.close();
  assert.equal(f.count('clientProgramRowSourceCloseAccounted'), 1);
});

test('selected listing Core reservation refusal does not fall back to an ordinary start', () => {
  const f = rowRunFixture({accounted: true, listingReport: true});
  f.fail(f.startName, {checked: true});
  assert.throws(() => f.start(), {code: 'MoonBitHostFailure'});
  assert.deepEqual(f.names(), [f.startName]);
});

test('selected listing pending cleanup retains the same RowRun and original retry', async () => {
  const f = rowRunFixture({accounted: true, listingReport: true});
  const owner = f.start();
  f.fail(f.closeName, {checked: true});
  const state = {};
  owner.closeAfterFailure(state);
  assert.equal(state.closeFailed, true);
  assert.equal(state.recovery.cleanupPending(), true);
  f.respond('clientProgramRowSourceCaptureCleanupAdvance', ok(false));
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.count(f.closeName), 1);
  f.respond('clientProgramRowSourceCaptureCleanupAdvance', ok(true));
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(state.recovery.cleanupPending(), false);
  assert.equal(f.count(f.closeName), 2);
  assert.equal(f.count(f.startName), 1);
});

test('listing report requires the original Ledger and does not enter the keyed owner', () => {
  let starts = 0;
  const moon = new Proxy({}, {get() { return () => { starts++; }; }});
  const options = {moon, acquisition: token('original-acquisition'), nonce: 'original',
    capacity: {transferBytes: 1n, executionBytes: 1n,
      listingReport: token('original-report-declaration')}};
  assert.throws(() => startInstalledRowRun(options),
    {code: 'InstalledListingSourceLedgerRequired'});
  assert.throws(() => startInstalledRowRun({...options, keyed: true, ledger: token('ledger')}),
    {code: 'InstalledListingSourceProgramMismatch'});
  assert.equal(starts, 0);
});

test('selected listing refuses a runtime without the report consumer before starting any RowRun', () => {
  let starts = 0;
  const ordinary = () => { starts++; };
  assert.throws(() => startInstalledRowRun({moon: {
    clientProgramRowSourceStart: ordinary,
    clientProgramRowSourceStartAccounted: ordinary},
  acquisition: token('original-acquisition'), nonce: 'original', ledger: token('ledger'),
  capacity: {transferBytes: 1n, executionBytes: 1n,
    listingReport: token('original-report-declaration')}}),
  {code: 'InstalledListingSourceUnavailable'});
  assert.equal(starts, 0);
});

for (const accounted of [false, true]) {
  for (const effectful of [false, true]) {
    for (const task of [0, 1]) {
      test(`row run completes exact ${accounted ? 'accounted' : 'unaccounted'} ${effectful ? 'Effect' : 'ordinary'} task ${task}`,
        async () => {
          const f = rowRunFixture({accounted, effectful, task});
          const owner = f.start();
          assert.equal(Object.isFrozen(owner), true);
          assert.equal(owner.run, f.run);
          const pending = owner.complete(f.options);
          assert.equal(pending instanceof Promise, true);
          const result = await pending;
          assert.equal(Object.isFrozen(result), true);
          assert.equal(Object.isFrozen(result.capture), true);
          assert.equal(result.checkedSource, f.prepared.checkedSource);
          assert.equal(result.identity, f.identity);
          assert.equal(result.logicalInput, f.logicalInput);
          assert.equal(result.requirement, f.requirement);
          assert.equal(result.occurrence, f.occurrence);
          assert.equal(result.close, owner.close);
          assert.equal(result.setup, accounted || effectful ? undefined
            : f.setup);
          assert.equal(result.capture.source(), f.source);
          assert.equal(typeof result.capture.retainTask,
            accounted ? 'function' : 'undefined');
          assert.deepEqual(f.names().filter(name =>
            name !== 'clientProgramRowSourceCaptureSource'), [f.startName,
            'currentRead', 'clientProgramRowSourceFinish', 'clientProgramRowSourceAttempt',
            'clientProgramRowSourceCaptureBegin', 'currentRead',
            'clientProgramRowSourceCaptureAdvance', 'currentRead',
            'clientProgramRowSourceCapture', f.matchName, f.identifyName,
            f.logicalName, ...(!accounted && !effectful ? [
              'clientProgramSelectedInferStep', 'clientProgramComposedInferOccurrences',
              f.hostName] : [])]);
          assert.equal(f.settled(f.attempt), true);
          assert.equal(f.settled(f.foreignAttempt), false);
          result.close();
          owner.close();
          owner.closeAfterFailure({});
          assert.equal(f.count(f.closeName), 1);
          assert.equal(f.count('clientProgramRowSourceFinish'), 1);
          assert.equal(f.count('clientProgramRowSourceAttempt'), 1);
          assert.equal(f.count('clientProgramRowSourceCapture'), 1);
        });
    }
  }
}

for (const retainedRelationOutput of [false, true]) {
  test(`ordinary unaccounted row run selects ${retainedRelationOutput ? 'retained' : 'ordinary'} Host`,
    async () => {
      const f = rowRunFixture({retainedRelationOutput});
      const owner = f.start();
      assert.equal((await owner.complete(f.options)).setup, f.setup);
      assert.equal(f.count(f.hostName), 1);
      owner.close();
    });
}

test('acquired INFER carries its original Source tuple without opening a pure Host', async () => {
  const f = rowRunFixture();
  f.respond('clientProgramSelectedInferStep', 3);
  const owner = f.start();
  const result = await owner.complete(f.options);
  assert.equal(result.capturedSource, f.source);
  assert.equal(result.inferStep, 3);
  assert.equal(result.composedInfer, false);
  assert.equal(result.setup, undefined);
  assert.equal(result.identity, f.identity);
  assert.equal(result.logicalInput, f.logicalInput);
  assert.equal(result.capture.source(), f.source);
  assert.equal(f.count(f.hostName), 0);
  assert.equal(f.count('clientProgramRowSourceCapture'), 1);
  result.close();
  owner.close();
  assert.equal(f.count(f.closeName), 1);
});

test('acquired composed INFER retains one original capture for the common Model owner', async () => {
  const f = rowRunFixture();
  f.respond('clientProgramComposedInferOccurrences', ok([token('first'), token('second')]));
  const owner = f.start();
  const result = await owner.complete(f.options);
  assert.equal(result.capturedSource, f.source);
  assert.equal(result.composedInfer, true);
  assert.equal(result.setup, undefined);
  assert.equal(f.count(f.hostName), 0);
  assert.equal(f.count('clientProgramRowSourceCapture'), 1);
  owner.close();
  assert.equal(f.count(f.closeName), 1);
});

for (const effectful of [false, true]) {
  for (const task of [0, 1]) {
    test(`row run rejects non-true ${effectful ? 'Effect' : 'ordinary'} task ${task} matches before identity or Host`,
      async () => {
        for (const matched of [false, 1, 'true', undefined]) {
          const f = rowRunFixture({effectful, task});
          f.respond(f.matchName, matched);
          const owner = f.start();
          await assert.rejects(owner.complete(f.options),
            {code: 'InstalledSourceProgramMismatch'});
          assert.equal(f.count(f.identifyName), 0);
          assert.equal(f.count(f.logicalName), 0);
          assert.equal(f.count(f.hostName), 0);
          assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
          owner.close();
        }
      });
  }
}

test('row run rechecks current read before each evidence issue and forwards exact capture',
  async () => {
    const f = rowRunFixture({accounted: true, task: 1});
    const owner = f.start();
    const result = await owner.complete(f.options);
    const baselineReads = f.count('currentRead');
    const baselineCalls = f.calls.length;
    let release;
    const pendingRead = new Promise(resolve => { release = resolve; });
    f.authorize(() => pendingRead);
    const request = {authorityScopeCid: 'authority-scope-cid',
      effectiveDataPolicyCid: 'effective-policy-cid'};
    const issued = result.issueSourceEvidence(request);
    assert.equal(f.count('currentRead'), baselineReads + 1);
    assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
    release(true);
    assert.equal(await issued, f.evidence);
    f.authorize(async () => true);
    assert.equal(await result.issueSourceEvidence(request), f.evidence);
    assert.deepEqual(f.names().slice(baselineCalls).filter(name => name === 'currentRead' ||
      name === 'clientProgramRowSourceIssueSourceEvidence'), ['currentRead',
      'clientProgramRowSourceIssueSourceEvidence', 'currentRead',
      'clientProgramRowSourceIssueSourceEvidence']);
    owner.close();
  });

test('denied current read issues no source evidence and preserves the denial',
  async () => {
    const f = rowRunFixture();
    const owner = f.start();
    const result = await owner.complete(f.options);
    const baselineReads = f.count('currentRead');
    const denial = Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied'});
    f.authorize(async () => { throw denial; });
    await assert.rejects(result.issueSourceEvidence({
      authorityScopeCid: 'authority-scope-cid',
      effectiveDataPolicyCid: 'effective-policy-cid'}), error => error === denial);
    assert.equal(f.count('currentRead'), baselineReads + 1);
    assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
    owner.close();
  });

test('accounted capture retains the exact DAG task through its original capture',
  async () => {
    const f = rowRunFixture({accounted: true, task: 1});
    const owner = f.start();
    const result = await owner.complete(f.options);
    const dag = token('dag');
    const task = token('dag-task');
    assert.equal(result.capture.retainTask(dag, task), f.retainedTask);
    const call = f.calls.find(call =>
      call.name === 'clientProgramRowSourceRetainCapturedTask');
    assert.equal(call.args[0], f.capture);
    assert.equal(call.args[1], dag);
    assert.equal(call.args[2], task);
    f.fail('clientProgramRowSourceRetainCapturedTask', {checked: true});
    assert.throws(() => result.capture.retainTask(dag, task),
      {code: 'MoonBitHostFailure'});
    owner.close();
  });

for (const accounted of [false, true]) {
  test(`${accounted ? 'accounted checked' : 'unaccounted thrown'} close failure remains retryable on the same row run`,
    () => {
      const f = rowRunFixture({accounted});
      const owner = f.start();
      const failure = f.fail(f.closeName, {checked: accounted});
      assert.throws(() => owner.close(), error => accounted
        ? error.code === 'MoonBitHostFailure' && error.cause === failure
        : error === failure);
      assert.equal(f.count(f.closeName), 1);
      owner.close();
      owner.close();
      assert.equal(f.count(f.closeName), 2);
      assert.equal(f.count(f.startName), 1);
      assert.equal(f.count('clientProgramRowSourceFinish'), 0);
    });
}

for (const accounted of [false, true]) {
  test(`post-capture pre-Host failure retries cleanup on the same ${accounted ? 'accounted' : 'unaccounted'} row run`,
    async () => {
      const f = rowRunFixture({accounted});
      const owner = f.start();
      const primary = f.fail(f.logicalName);
      f.fail(f.closeName, {times: 2, checked: accounted});
      await assert.rejects(owner.complete(f.options), error => error === primary);
      assert.equal(f.count('clientProgramRowSourceCapture'), 1);
      assert.equal(f.count(f.hostName), 0);
      const state = {started: true, closeFailed: false, recovery: undefined};
      owner.closeAfterFailure(state);
      assert.equal(state.started, true);
      assert.equal(state.closeFailed, true);
      assert.equal(Object.isFrozen(state.recovery), true);
      assert.equal(state.recovery.cleanupPending(), true);
      state.recovery.close();
      assert.equal(f.count(f.closeName), 1,
        'the recovery close is deliberately a no-op');
      await assert.rejects(state.recovery.cleanup());
      assert.equal(state.recovery.cleanupPending(), true);
      assert.equal(await state.recovery.cleanup(), true);
      assert.equal(state.recovery.cleanupPending(), false);
      assert.equal(await state.recovery.cleanup(), true);
      owner.close();
      assert.equal(f.count(f.closeName), 3);
      assert.equal(f.count(f.startName), 1);
      assert.equal(f.count('clientProgramRowSourceFinish'), 1);
      assert.equal(f.count('clientProgramRowSourceAttempt'), 1);
      assert.equal(f.count('clientProgramRowSourceCapture'), 1);
      assert.equal(f.count(f.logicalName), 1);
      assert.equal(f.count(f.hostName), 0);
    });
}

test('accounted close-after-failure recovery does not finish until checked close succeeds',
  async () => {
    const f = rowRunFixture({accounted: true});
    const owner = f.start();
    f.fail(f.closeName, {times: 2, checked: true});
    const state = {closeFailed: false};
    owner.closeAfterFailure(state);
    assert.equal(state.closeFailed, true);
    assert.equal(state.recovery.cleanupPending(), true);
    state.recovery.close();
    assert.equal(f.count(f.closeName), 1);
    await assert.rejects(state.recovery.cleanup(), {code: 'MoonBitHostFailure'});
    assert.equal(state.recovery.cleanupPending(), true);
    assert.equal(await state.recovery.cleanup(), true);
    assert.equal(state.recovery.cleanupPending(), false);
    owner.close();
    assert.equal(f.count(f.closeName), 3);
    assert.equal(f.count(f.startName), 1);
  });

test('successful failure cleanup closes once without installing recovery', () => {
  const f = rowRunFixture({accounted: true});
  const owner = f.start();
  const state = {started: false, closeFailed: false, recovery: undefined};
  owner.closeAfterFailure(state);
  owner.closeAfterFailure(state);
  owner.close();
  assert.deepEqual(state,
    {started: false, closeFailed: false, recovery: undefined});
  assert.equal(f.count(f.closeName), 1);
});

test('failed Finish cannot settle or capture its physical attempt', async () => {
  const f = rowRunFixture();
  const owner = f.start();
  f.fail('clientProgramRowSourceFinish', {checked: true});
  await assert.rejects(owner.complete(f.options), {code: 'MoonBitHostFailure'});
  assert.equal(f.settled(f.attempt), false);
  assert.equal(f.count('clientProgramRowSourceAttempt'), 0);
  assert.equal(f.count('clientProgramRowSourceCapture'), 0);
  owner.closeAfterFailure({});
  assert.equal(f.count(f.closeName), 1);
});

test('row capture refuses authority revoked after positive child work without another resume', async () => {
  const f = rowRunFixture({accounted: true});
  const owner = f.start();
  const denial = Object.assign(new Error('ExecutionAuthorizationDenied'),
    {code: 'ExecutionAuthorizationDenied'});
  f.respond('clientProgramRowSourceCaptureAdvance', ok({_0: false, _1: 1n}));
  let reads = 0;
  f.authorize(async () => {
    if (++reads === 3) throw denial;
    return true;
  });
  await assert.rejects(owner.complete(f.options), error => error === denial);
  assert.equal(f.count('clientProgramRowSourceCaptureAdvance'), 1);
  assert.equal(f.count('clientProgramRowSourceCapture'), 0);
  assert.equal(f.count(f.logicalName), 0);
  assert.equal(f.count(f.hostName), 0);
  f.fail(f.closeName, {checked: true});
  const state = {closeFailed: false};
  owner.closeAfterFailure(state);
  assert.equal(state.closeFailed, true);
  f.respond('clientProgramRowSourceCaptureCleanupAdvance', ok(false));
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(state.recovery.cleanupPending(), true);
  assert.equal(f.count(f.closeName), 1, 'no reservation retry before child stop');
  f.respond('clientProgramRowSourceCaptureCleanupAdvance', ok(true));
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(state.recovery.cleanupPending(), false);
  assert.equal(f.count(f.closeName), 2);
  assert.equal(f.count(f.startName), 1);
  assert.equal(f.count('clientProgramRowSourceCaptureAdvance'), 1);
  assert.equal(f.count('clientProgramRowSourceCapture'), 0);
});

test('close while current read is awaiting prevents capture setup after the await', async () => {
  const f = rowRunFixture();
  const owner = f.start();
  let release;
  f.authorize(() => new Promise(resolve => { release = resolve; }));
  const pending = owner.complete(f.options);
  owner.close();
  release(true);
  await assert.rejects(pending, {code: 'InstalledSourceClosed'});
  assert.equal(f.count('clientProgramRowSourceFinish'), 0);
  assert.equal(f.count('clientProgramRowSourceCaptureBegin'), 0);
  assert.equal(f.count('clientProgramRowSourceCaptureAdvance'), 0);
  assert.equal(f.count('clientProgramRowSourceCapture'), 0);
});

test('abort during current read prevents setup without declaring successful Source capture', async () => {
  const f = rowRunFixture();
  const owner = f.start();
  const control = new AbortController();
  const reason = new Error('CancelledOriginalAcquisition');
  f.authorize(async () => { control.abort(reason); return true; });
  await assert.rejects(owner.complete({...f.options, signal: control.signal}),
    error => error === reason);
  assert.equal(f.count('clientProgramRowSourceFinish'), 0);
  assert.equal(f.count('clientProgramRowSourceCaptureBegin'), 0);
  assert.equal(f.count('clientProgramRowSourceCapture'), 0);
  owner.closeAfterFailure({});
});

test('missing ordinary Host is rejected after capture and logical issue', async () => {
  const f = rowRunFixture();
  const owner = f.start();
  f.respond(f.hostName, undefined);
  await assert.rejects(owner.complete(f.options),
    {code: 'InstalledSourceHostUnavailable'});
  assert.equal(f.count('clientProgramRowSourceCapture'), 1);
  assert.equal(f.count(f.logicalName), 1);
  assert.equal(f.count(f.hostName), 1);
  owner.closeAfterFailure({});
  assert.equal(f.count(f.closeName), 1);
});

for (const accounted of [false, true]) {
  test(`${accounted ? 'accounted' : 'unaccounted'} row start propagates checked runtime failure`,
    () => {
      const f = rowRunFixture({accounted});
      const failure = f.fail(f.startName, {checked: true});
      assert.throws(() => f.start(), error =>
        error.code === 'MoonBitHostFailure' && error.cause === failure);
      assert.deepEqual(f.names(), [f.startName]);
    });
}


test('cleanup advance refusal retries the original close and preserves its failure until ACK', async () => {
  const f = rowRunFixture({accounted: true});
  const owner = f.start();
  const failure = f.fail(f.closeName, {times: 2, checked: true});
  const state = {};
  owner.closeAfterFailure(state);
  f.respond('clientProgramRowSourceCaptureCleanupAdvance',
    {$tag: 0, _0: token('original-run-not-closed')});
  await assert.rejects(state.recovery.cleanup(), error =>
    error.code === 'MoonBitHostFailure' && error.cause === failure);
  assert.equal(state.recovery.cleanupPending(), true);
  assert.equal(f.count(f.closeName), 2);
  assert.equal(f.count('clientProgramRowSourceCaptureCleanup'), 0);
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(state.recovery.cleanupPending(), false);
  assert.equal(f.count(f.closeName), 3);
  assert.equal(f.count('clientProgramRowSourceCaptureCleanup'), 1);
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(f.count(f.closeName), 3);
  assert.equal(f.count(f.startName), 1);
});


test('original Source evidence is issued once then consumed from the same live capture without wire admission', async () => {
  const f = rowRunFixture({accounted: true, typedEvidence: true});
  const owner = f.start();
  const result = await owner.complete(f.options);
  const request = {authorityScopeCid: 'authority-scope-cid',
    effectiveDataPolicyCid: 'effective-policy-cid'};
  const reads = f.count('currentRead');
  await result.prepareSourceEvidenceOriginal(request);
  assert.equal(f.count('currentRead'), reads + 1);
  assert.equal(f.count('clientProgramRowSourceIssueSourceEvidenceOriginal'), 1);
  assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
  assert.throws(() => Reflect.apply(result.capture.takeSourceEvidenceOriginal,
    {...result.capture}, []), {code: 'ForeignInstalledSourceCapture'});
  assert.equal(result.capture.takeSourceEvidenceOriginal(), f.originalEvidence);
  assert.equal(f.count('currentRead'), reads + 1);
  assert.equal(f.count('clientProgramRowSourceIssueSourceEvidenceOriginal'), 1);
  assert.throws(() => result.capture.takeSourceEvidenceOriginal(),
    {code: 'InstalledSourceEvidenceUnavailable'});
  owner.close();
});

test('original Source evidence preserves current refusal and cannot issue after close during current await', async () => {
  for (const closeDuringCurrent of [false, true]) {
    const f = rowRunFixture({accounted: true, typedEvidence: true});
    const owner = f.start();
    const result = await owner.complete(f.options);
    const denial = new Error('same-original-current-refusal');
    let release;
    f.authorize(() => closeDuringCurrent ? new Promise(resolve => {release = resolve;})
      : Promise.reject(denial));
    const issuing = result.prepareSourceEvidenceOriginal({authorityScopeCid: 'authority-scope-cid',
      effectiveDataPolicyCid: 'effective-policy-cid'});
    if (closeDuringCurrent) {owner.close(); release();}
    await assert.rejects(issuing, error => closeDuringCurrent
      ? error.code === 'InstalledSourceClosed' : error === denial);
    assert.equal(f.count('clientProgramRowSourceIssueSourceEvidenceOriginal'), 0);
    owner.close();
  }
});

test('original Source evidence remains held through pending cleanup and retires only with the original RowRun', async () => {
  const f = rowRunFixture({accounted: true, typedEvidence: true});
  const owner = f.start();
  const result = await owner.complete(f.options);
  const request = {authorityScopeCid: 'authority-scope-cid',
    effectiveDataPolicyCid: 'effective-policy-cid'};
  await result.prepareSourceEvidenceOriginal(request);
  await assert.rejects(result.prepareSourceEvidenceOriginal(request),
    {code: 'InstalledSourceEvidencePending'});
  f.respond('clientProgramRowSourceCaptureCleanup', ok(false));
  assert.throws(() => owner.close(), {code: 'InstalledSourceCleanupPending'});
  assert.equal(result.capture.takeSourceEvidenceOriginal(), f.originalEvidence);
  await result.prepareSourceEvidenceOriginal(request);
  f.respond('clientProgramRowSourceCaptureCleanup', ok(true));
  owner.close();
  assert.throws(() => result.capture.takeSourceEvidenceOriginal(),
    {code: 'InstalledSourceClosed'});
  assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
});


test('accounted Row capture original is retained once and refuses foreign receiver or retired access', async () => {
  const f = rowRunFixture({accounted: true}), owner = f.start();
  const result = await owner.complete(f.options);
  assert.equal(result.capture.originalRowCapture(), f.capture);
  assert.equal(result.capture.originalRowCapture(), f.capture);
  assert.equal(f.count('clientProgramRowSourceCapture'), 1);
  const get = result.capture.originalRowCapture;
  assert.throws(() => Reflect.apply(get, {...result.capture}, []), {code: 'ForeignInstalledSourceCapture'});
  owner.close();
  assert.throws(() => result.capture.originalRowCapture(), {code: 'ForeignInstalledSourceCapture'});
});

// The real session owns the original borrow and cleanup; these explicit Core
// ports inspect only the JS handoff, not a replacement Ledger or admission.
function bodyConstructionFixture({missingConstruction = false, failConstruction,
  reenterStop = false, phase = 'announced-body', chargedOnly = false} = {}) {
  const acquisition = {}, ledger = {}, run = {}, borrow = {}, capacity = {};
  const events = [];
  let cleanup, reserve, stopped = false, constructionReads = 0, chargedReads = 0;
  const originalConstruction = function(actualBorrow, actualCapacity) {
    assert.equal(this, moon);assert.equal(actualBorrow, borrow);assert.equal(actualCapacity, capacity);
    events.push('construct');
    if (failConstruction !== undefined) throw failConstruction;
    if (reenterStop) assert.throws(() => session.close(), {code: 'MoonBitHostFailure'});
    return ok(undefined);
  };
  const originalCharged = function(actualBorrow, actualCapacity) {
    assert.equal(this, moon);assert.equal(actualBorrow, borrow);assert.equal(actualCapacity, capacity);
    events.push('charged');return ok(undefined);
  };
  const moon = {
    clientProgramRowSourceStartProviderAccounted() {return ok(run);},
    clientProgramRowSourceBorrowResponses(actualRun, original) {
      assert.equal(actualRun, run);assert.equal(original, acquisition);return ok(borrow);
    },
    clientProgramRowSourceBindResponseCleanup(original, observe) {
      assert.equal(original, borrow);cleanup = observe;events.push('bind');return ok(undefined);
    },
    get clientProgramRowSourceGrowResponseCapacity() {chargedReads++;return originalCharged;},
    get clientProgramRowSourceGrowResponseConstructionCapacity() {
      constructionReads++;return missingConstruction ? undefined : originalConstruction;
    },
    clientProgramRowSourceRetireResponseWorkspace() {return ok(undefined);},
    clientProgramRowSourceCloseAccounted() {
      if (!cleanup()) return {$tag: 0, _0: 'original reader pending'};
      events.push('close');return ok(undefined);
    },
    clientProgramRowSourceCaptureCleanup() {return ok(true);},
  };
  const signal = new AbortController().signal;
  const options = Object.freeze({signal, verifyRead() {assert.equal(this, options);events.push('verify');}});
  const receiver = {prepare(original, retain, grow) {
    assert.equal(this, receiver);assert.equal(original, options);assert.equal(retain, undefined);
    reserve = grow;
    return Object.freeze({read() {
      // A later namespace mutation must not replace either captured method.
      Object.defineProperties(moon, {
        clientProgramRowSourceGrowResponseCapacity: {value() {assert.fail('reread charged method');}},
        clientProgramRowSourceGrowResponseConstructionCapacity: {value() {assert.fail('reread construction method');}},
      });
      if (chargedOnly) reserve(capacity);else reserve(capacity, phase);events.push('allocate-body');
      reserve(capacity);return 'original-result';
    }, requestStop() {stopped = true;events.push('stop');},
    observe() {return {cleanupConfirmed: stopped};}});
  }};
  const session = startInstalledRowRun({moon, acquisition, ledger, nonce: 'body',
    capacity: {provider: capacity, transferBytes: 100n, executionBytes: 100n}});
  return {session, events, read: () => session.readProvider({prepare: receiver.prepare, receiver, options}),
    reserve: () => reserve(capacity, phase), reads: () => [chargedReads, constructionReads]};
}

test('announced body uses the same cleanup-bound RowRun before allocation and keeps charged response distinct', async () => {
  const f = bodyConstructionFixture();
  assert.equal(await f.read(), 'original-result');
  assert.deepEqual(f.events, ['bind', 'verify', 'construct', 'allocate-body', 'charged']);
  assert.deepEqual(f.reads(), [1, 1]);
  assert.throws(f.reserve, {code: 'InstalledSourceClosed'});
  f.session.close();assert.deepEqual(f.events.slice(-2), ['stop', 'close']);
});

test('announced body refuses absent port invalid phase and original backing failure before allocation', async () => {
  const cause = Object.freeze({original: 'capacity-refusal'});
  for (const options of [{missingConstruction: true}, {phase: 'untrusted'}, {failConstruction: cause}]) {
    const f = bodyConstructionFixture(options);
    await assert.rejects(f.read(), error => options.failConstruction === undefined
      ? error.code === 'InstalledSourceResponseConstructionUnavailable' : error === cause);
    assert.equal(f.events.includes('allocate-body'), false);
    f.session.close();assert.equal(f.events.at(-1), 'close');
  }
  const old = bodyConstructionFixture({missingConstruction: true, chargedOnly: true});
  // The ordinary one-argument charged response keeps its existing ABI.
  assert.equal(await old.read(), 'original-result');old.session.close();
});

test('announced body original-current reentry cannot allocate or use a stopped reader', async () => {
  const f = bodyConstructionFixture({reenterStop: true});
  await assert.rejects(f.read(), {code: 'InstalledSourceClosed'});
  assert.equal(f.events.includes('allocate-body'), false);
  assert.throws(f.reserve, {code: 'InstalledSourceClosed'});
  f.session.close();assert.equal(f.events.at(-1), 'close');
});

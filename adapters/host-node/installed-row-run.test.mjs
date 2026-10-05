import assert from 'node:assert/strict';
import test from 'node:test';
import {startInstalledRowRun} from './installed-row-run.mjs';

const ok = value => ({$tag: 1, _0: value});
const token = name => Object.freeze({name});

function rowRunFixture({accounted = false, effectful = false, task = 0,
  retainedRelationOutput = false} = {}) {
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
  const retainedTask = token('retained-task');
  const ledger = accounted ? token('ledger') : undefined;
  const capacity = {transferBytes: 8192n, executionBytes: 1024n};
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
  const startName = accounted ? 'clientProgramRowSourceStartAccounted'
    : 'clientProgramRowSourceStart';
  method(startName, undefined, ok(run), args => {
    assert.equal(typeof args[2], 'function');
    settled = args[2];
    exact(args, [acquisition, nonce, settled,
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
    prepared, setup, evidence, retainedTask, calls, names, count, options,
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

for (const accounted of [false, true]) {
  for (const effectful of [false, true]) {
    for (const task of [0, 1]) {
      test(`row run completes exact ${accounted ? 'accounted' : 'unaccounted'} ${effectful ? 'Effect' : 'ordinary'} task ${task}`,
        () => {
          const f = rowRunFixture({accounted, effectful, task});
          const owner = f.start();
          assert.equal(Object.isFrozen(owner), true);
          assert.equal(owner.run, f.run);
          const result = owner.complete(f.options);
          assert.equal(result instanceof Promise, false);
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
            'clientProgramRowSourceFinish', 'clientProgramRowSourceAttempt',
            'clientProgramRowSourceCapture', f.matchName, f.identifyName,
            f.logicalName, ...(!accounted && !effectful ? [f.hostName] : [])]);
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
    () => {
      const f = rowRunFixture({retainedRelationOutput});
      const owner = f.start();
      assert.equal(owner.complete(f.options).setup, f.setup);
      assert.equal(f.count(f.hostName), 1);
      owner.close();
    });
}

for (const effectful of [false, true]) {
  for (const task of [0, 1]) {
    test(`row run rejects non-true ${effectful ? 'Effect' : 'ordinary'} task ${task} matches before identity or Host`,
      () => {
        for (const matched of [false, 1, 'true', undefined]) {
          const f = rowRunFixture({effectful, task});
          f.respond(f.matchName, matched);
          const owner = f.start();
          assert.throws(() => owner.complete(f.options),
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
    const result = owner.complete(f.options);
    let release;
    const pendingRead = new Promise(resolve => { release = resolve; });
    f.authorize(() => pendingRead);
    const request = {authorityScopeCid: 'authority-scope-cid',
      effectiveDataPolicyCid: 'effective-policy-cid'};
    const issued = result.issueSourceEvidence(request);
    assert.equal(f.count('currentRead'), 1);
    assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
    release(true);
    assert.equal(await issued, f.evidence);
    f.authorize(async () => true);
    assert.equal(await result.issueSourceEvidence(request), f.evidence);
    assert.deepEqual(f.names().filter(name => name === 'currentRead' ||
      name === 'clientProgramRowSourceIssueSourceEvidence'), ['currentRead',
      'clientProgramRowSourceIssueSourceEvidence', 'currentRead',
      'clientProgramRowSourceIssueSourceEvidence']);
    owner.close();
  });

test('denied current read issues no source evidence and preserves the denial',
  async () => {
    const f = rowRunFixture();
    const owner = f.start();
    const result = owner.complete(f.options);
    const denial = Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied'});
    f.authorize(async () => { throw denial; });
    await assert.rejects(result.issueSourceEvidence({
      authorityScopeCid: 'authority-scope-cid',
      effectiveDataPolicyCid: 'effective-policy-cid'}), error => error === denial);
    assert.equal(f.count('currentRead'), 1);
    assert.equal(f.count('clientProgramRowSourceIssueSourceEvidence'), 0);
    owner.close();
  });

test('accounted capture retains the exact DAG task through its original capture',
  () => {
    const f = rowRunFixture({accounted: true, task: 1});
    const owner = f.start();
    const result = owner.complete(f.options);
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
      assert.throws(() => owner.complete(f.options), error => error === primary);
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

test('failed Finish cannot settle or capture its physical attempt', () => {
  const f = rowRunFixture();
  const owner = f.start();
  f.fail('clientProgramRowSourceFinish', {checked: true});
  assert.throws(() => owner.complete(f.options), {code: 'MoonBitHostFailure'});
  assert.equal(f.settled(f.attempt), false);
  assert.equal(f.count('clientProgramRowSourceAttempt'), 0);
  assert.equal(f.count('clientProgramRowSourceCapture'), 0);
  owner.closeAfterFailure({});
  assert.equal(f.count(f.closeName), 1);
});

test('missing ordinary Host is rejected after capture and logical issue', () => {
  const f = rowRunFixture();
  const owner = f.start();
  f.respond(f.hostName, undefined);
  assert.throws(() => owner.complete(f.options),
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

// Actual installed-consumer/queue modules with explicit Core/Account ports.
// The separate MoonBit tests exercise nominal Request/Compute funding; these
// ports do not qualify a compiled ABI, ordinary Host or physical parent.
import assert from 'node:assert/strict';
import test from 'node:test';
import {localContractLimits} from './local-values-plan.mjs';
import {createLocalReadAuthorizations} from './local-result-authorization.mjs';
import {prepareInstalledLogicalObservation} from './logical-task-observation.mjs';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';
import {installTaskObservation, projectTaskLogicalObservation} from '../host-common/task-observation.mjs';
const ok = value => ({$tag: 1, _0: value});
const bad = issue => ({$tag: 0, _0: issue});
const turn = () => new Promise(resolve => setImmediate(resolve));
const ref = Object.freeze({namespaceId: 'local', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});
const keyWire = '{"version":"actql-logical-step-key/0.1","stage_ordinal":2,"occurrence":{"kind":"operation","operation_ordinal":3},"compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}';
function fixture({deliver = () => {}, projected = true, mutate, captureFailure, recordReturnFailure = () => false} = {}) {
  const calls = [], loans = new Set(), records = [], original = {}, captured = {}, managed = {}, owner = {}, definition = {};
  let closing = false;
  const moon = {
    clientProgramPrepareLogicalObservation() {},
    clientProgramLogicalObservationCleanup: () => undefined,
    clientProgramAttachLogicalObservation(actual, run) {
      assert.equal(actual, original); assert.equal(run, captured); calls.push('attach'); return ok(undefined);
    },
    clientProgramBeginLogicalObservation(actual, phase) {
      assert.equal(actual, original); assert.equal(closing, false);
      const record = {phase, captured: false}; loans.add(record); calls.push('reserve'); return ok(record);
    },
    clientProgramCaptureLogicalObservationRecord(record) {
      assert(loans.has(record)); calls.push('capture');
      if (captureFailure !== undefined) return bad(captureFailure);
      record.captured = true; return ok(undefined);
    },
    clientProgramLogicalObservationRecordState(record) {
      assert(loans.has(record) && record.captured); calls.push('current');
      return ok(projected ? 'projected' : 'not_projected');
    },
    clientProgramLogicalObservationRecordKey(record) {
      assert(projected && loans.has(record)); return ok(keyWire);
    },
    clientProgramLogicalObservationRecordPhase(record) {assert(loans.has(record)); return ok(record.phase);},
    clientProgramReturnLogicalObservationRecord(record) {
      assert(loans.has(record)); calls.push('return-attempt');
      if (recordReturnFailure()) throw new Error('OriginalReturnPending');
      loans.delete(record); calls.push('return');
    },
    clientProgramReturnLogicalObservation(actual) {
      assert.equal(actual, original); closing = true; calls.push('close');
      return loans.size === 0 ? ok(true) : bad({originalPendingCleanup: original});
    },
  };
  const control = {prepareClientLogicalObservation(run, execution, selected, limits) {
    assert.equal(run, managed); assert.equal(execution, owner); assert.equal(selected, definition);
    assert.equal(limits, localContractLimits, 'original normal Plan profile, not an event byte limit');
    calls.push('admit'); mutate?.(moon); return ok(original);
  }};
  const observer = installHostObservation(createHostObservationConnection({include: ['compute'],
    correlation: {include: ['task']}, limits: {shutdownMs: 10},
    async deliver(record) {records.push(record); await deliver(record);},
  }), {journal: {observationStorage: () => ({consume: () => ({accepted: true}), close() {}})}});
  const consumer = prepareInstalledLogicalObservation(moon, control, managed, owner, definition, observer);
  return {consumer, moon, observer, calls, loans, records, captured,
    attach(authorize = () => true) {
      consumer.attach(captured, ref, 'operator', operation => {
        assert.equal(operation.principalId, 'operator'); assert.equal(operation.indexKey, ref);
        assert.equal(operation.purpose, 'run-plan'); assert(Object.isFrozen(operation));
        assert(loans.size > 0, 'Account callback must follow original record admission');
        calls.push('authorize'); return authorize(operation);
      });
    }};
}

test('funded logical queue retains its same original until actual delivery settles', async () => {
  let settle;
  const pending = new Promise(resolve => {settle = resolve;});
  const f = fixture({deliver: () => pending, mutate(moon) {
    // Current/preparation callbacks cannot replace the methods captured before
    // the actual admission. This checks the original installed receiver too.
    moon.clientProgramLogicalObservationRecordKey = () => assert.fail('replacement key getter');
  }});
  f.attach();
  const task = installTaskObservation(() => {}, (phase, ordinal) => f.consumer.project(phase, ordinal));
  assert.equal(projectTaskLogicalObservation(task, 'settled', 19), undefined, 'optional metadata must not add an async task wait');
  assert.deepEqual(f.calls.slice(0, 5), ['admit', 'attach', 'reserve', 'authorize', 'capture']);
  await turn();
  assert.equal(f.records.length, 1);
  assert.equal(f.records[0].attributes['actql.logical_step.key'], keyWire);
  assert.equal(f.records[0].attributes['actql.task.ordinal'], 19);
  assert.equal(f.loans.size, 1);
  assert.throws(() => f.consumer.close(), /MoonBitHostFailure/);
  await f.observer.close();
  assert.equal(f.observer.status().active, 1);
  assert.equal(f.observer.status().cleanupPending, true);
  assert.equal(f.loans.size, 1, 'timeout is not a delivery or resource ACK');
  settle(); await turn();
  assert.equal(f.loans.size, 0); assert.equal(f.calls.filter(x => x === 'return').length, 1);
  f.consumer.close(); f.consumer.close(); await f.observer.close();
  assert.equal(f.observer.status().cleanupPending, false);
});

test('logical read decline precedes capture and queued authority loss releases without disclosure', async () => {
  for (const position of ['before-read', 'queued']) {
    let allowed = position !== 'before-read';
    const f = fixture(); f.attach(() => allowed);
    await f.consumer.project('before', 0);
    if (position === 'before-read') assert.equal(f.calls.includes('capture'), false);
    allowed = false; await turn();
    assert.equal(f.records.length, 0);
    assert.equal(f.loans.size, 0);
    assert.equal(f.calls.filter(x => x === 'return').length, 1);
    f.consumer.close(); await f.observer.close();
  }
});

test('logical fused absence is distinct from an original projection failure', async () => {
  const unprojected = fixture({projected: false}); unprojected.attach();
  await unprojected.consumer.project('settled', 3); await unprojected.observer.close();
  assert.equal(unprojected.records.length, 1);
  assert.equal(unprojected.records[0].event, 'logical_boundary_unavailable');
  assert.equal(unprojected.records[0].attributes['actql.logical_boundary.reason'], 'not_projected');
  assert.equal(unprojected.records[0].attributes['actql.logical_step.key'], undefined);
  unprojected.consumer.close();
  const failed = fixture({captureFailure: {originalCurrentLost: true}}); failed.attach();
  await failed.consumer.project('settled', 3); await failed.observer.close();
  assert.equal(failed.records.length, 0, 'a failure is never fabricated NotProjected');
  assert.equal(failed.loans.size, 0); failed.consumer.close();
});

test('logical queue retries only a declined original return and never redelivers', async () => {
  for (const stage of ['delivery', 'decline-before-capture']) {
    let refuse = true;
    const f = fixture({recordReturnFailure: () => refuse}); f.attach(() => stage === 'delivery');
    await f.consumer.project('settled', 0); await turn();
    assert.equal(f.records.length, stage === 'delivery' ? 1 : 0); assert.equal(f.loans.size, 1);
    assert.throws(() => f.consumer.close(), /MoonBitHostFailure/);
    await f.observer.close();
    assert.equal(f.observer.status().cleanupPending, true);
    refuse = false; await f.observer.close();
    assert.equal(f.records.length, stage === 'delivery' ? 1 : 0); assert.equal(f.loans.size, 0);
    f.consumer.close();
  }
});

test('unarmed logical selection touches no runtime and introduces no async task work', async () => {
  const observer = installHostObservation(createHostObservationConnection({include: ['compute'],
    correlation: false, deliver() {assert.fail('unselected delivery');}}));
  const runtime = new Proxy({}, {get() {assert.fail('unselected runtime access');}});
  assert.equal(prepareInstalledLogicalObservation(runtime, {}, {}, {}, {}, observer), undefined);
  const task = installTaskObservation(() => {});
  assert.equal(projectTaskLogicalObservation(task, 'before', 0), undefined);
  assert.equal(projectTaskLogicalObservation({}, 'settled', 0), undefined);
  await observer.close();
});

// The actual existing Account Owner is imported; its Common evaluation is an
// explicit immutable DATA port here, not a new policy engine or normal proof.
test('immediate metadata authority consumes Common Allow only and never requests a Delegate answer', async () => {
  const outcomes = ['allow', 'deny', 'delegate'];
  for (const outcome of outcomes) {
    let evaluated = 0;
    const authorization = {accountConfiguration: outcome,
      request() {assert.fail('metadata must not invoke an application answer');}};
    const moon = {
      executionAuthorizationAdmit: wire => Object.freeze({wire}),
      executionAuthorizationMissing: () => Object.freeze({wire: 'missing'}),
      executionAuthorizationAccountJson: () => JSON.stringify({state: 'admitted', account_id: 'original-account'}),
      executionAuthorizationEvaluate(account, principal, connection, resource, operation) {
        assert.equal(account.wire, outcome); assert.equal(principal, 'operator');
        assert.equal(resource, 'run'); assert.equal(operation, 'read'); evaluated++;
        return {outcome};
      },
      executionAuthorizationEvaluationJson: value => JSON.stringify(value),
    };
    const authority = createLocalReadAuthorizations({moon, authorization,
      principalId: 'operator', namespaceId: ref.namespaceId, authorityScopeCid: ref.authorityScopeCid});
    const operation = Object.freeze({principalId: 'operator', indexKey: ref, purpose: 'run-plan'});
    assert.equal(authority.runImmediate(operation, operation), outcome === 'allow' ? true : outcome === 'deny' ? false : undefined);
    assert.equal(evaluated, 1);
    if (outcome !== 'delegate') {
      const result = authority.run(operation, operation);
      assert(result instanceof Promise, 'existing public async contract remains a Promise');
      assert.equal(await result, outcome === 'allow');
    }
  }
});

test('queued metadata observes fresh Common authority after the asynchronous boundary', async () => {
  const authorization = {accountConfiguration: 'allow'};
  let evaluated = 0;
  const moon = {
    executionAuthorizationAdmit: wire => Object.freeze({wire}),
    executionAuthorizationMissing: () => Object.freeze({wire: 'missing'}),
    executionAuthorizationAccountJson: () => JSON.stringify({state: 'admitted', account_id: 'original-account'}),
    executionAuthorizationEvaluate(account) {evaluated++; return {outcome: account.wire};},
    executionAuthorizationEvaluationJson: value => JSON.stringify(value),
  };
  const f = fixture();
  const authority = createLocalReadAuthorizations({moon, authorization,
    principalId: 'operator', namespaceId: ref.namespaceId, authorityScopeCid: ref.authorityScopeCid,
    observation: f.observer});
  f.attach(operation => authority.runImmediate(operation, operation));
  assert.equal(f.consumer.project('settled', 0), undefined);
  const beforeDelivery = evaluated; assert(beforeDelivery > 0);
  authorization.accountConfiguration = 'deny';
  await turn();
  assert(evaluated > beforeDelivery, 'delivery must not reuse an earlier allowed decision');
  assert.equal(f.records.length, 0); assert.equal(f.loans.size, 0);
  f.consumer.close(); await f.observer.close();
});

test('existing async read Owner preserves distinct Result permission and rejected Promise semantics', async () => {
  const primary = new Error('original Common evaluation failure');
  let fail = false;
  const moon = {
    executionAuthorizationAdmit: wire => Object.freeze({wire}),
    executionAuthorizationMissing: () => Object.freeze({wire: 'missing'}),
    executionAuthorizationAccountJson: () => JSON.stringify({state: 'admitted', account_id: 'original-account'}),
    executionAuthorizationEvaluate(_account, _principal, _connection, resource) {
      if (fail) throw primary;
      return {outcome: resource === 'run' ? 'allow' : 'deny'};
    },
    executionAuthorizationEvaluationJson: value => JSON.stringify(value),
  };
  const authority = createLocalReadAuthorizations({moon, authorization: {accountConfiguration: 'original'},
    principalId: 'operator', namespaceId: ref.namespaceId, authorityScopeCid: ref.authorityScopeCid});
  const request = {principalId: 'operator', indexKey: ref};
  assert.equal(await authority.run(request), true);
  assert.equal(await authority.result({...request, resultName: 'actual-result'}), false);
  fail = true;
  let returned;
  assert.doesNotThrow(() => {returned = authority.run(request);});
  assert(returned instanceof Promise);
  await assert.rejects(returned, cause => cause === primary);
  assert.throws(() => authority.runImmediate(request), cause => cause === primary);
});

test('logical delivery does not yield between the fresh immediate decision and application entry', async () => {
  let allowed = true, projectionFinished = false, allowedAtDelivery;
  const f = fixture({deliver() {allowedAtDelivery = allowed;}});
  f.attach(() => {
    if (projectionFinished) queueMicrotask(() => {allowed = false;});
    return allowed;
  });
  f.consumer.project('settled', 0);
  projectionFinished = true;
  await turn();
  assert.equal(allowedAtDelivery, true, 'an internal await cannot carry old Allow into a later callback');
  assert.equal(f.records.length, 1);
  assert.equal(f.loans.size, 0);
  f.consumer.close(); await f.observer.close();
});

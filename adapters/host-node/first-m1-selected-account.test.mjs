// Actual Common Account reader and existing Local authorization adapter only.
// No Checkpoint/Model/Entry, physical Provider, funding or live permit is issued
// by this fixture; immediate Host answers below are explicit test doubles.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {createLocalAuthorizationGate, localAuthorizationContext} from './local-account-config.mjs';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {firstM1AccountConfiguration, firstM1ProviderId, firstM1InferEntryId,
  firstM1ReviewerId} from '../../scripts/fixtures/first-m1-selected-account.mjs';

const task = `sha256:${'1'.repeat(64)}`;
const scope = `sha256:${'2'.repeat(64)}`;
const tuple = Object.freeze({connection: firstM1ProviderId, resource: task, operation: 'infer'});
const principal = 'selected-local-principal';
const claim = 'invocation_scope_approved';
const hash = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;

async function installed(t, options = {}) {
  const selected = options.principal ?? principal;
  const accountConfiguration = firstM1AccountConfiguration(selected, task);
  const gate = await createLocalAuthorizationGate({accountConfiguration, principal: selected,
    answeringAuthorities: [firstM1ReviewerId], requiredClaims: [claim], ...options});
  t.after(() => {
    assert.equal(gate.close(), true);
    assert.equal(gate.cleanupPending(), false);
  });
  assert.equal(gate.configurationCid, hash(accountConfiguration));
  assert.equal(gate.accountId, 'first-m1-owner');
  return gate;
}

test('first M1 actual Local Account keeps INFER delegated and raw capture in its separate exact tuple', async t => {
  const gate = await installed(t);
  const infer = await gate.authorize('activation', tuple, {subjectCid: scope});
  assert.equal(infer.action, 'unsupported');
  assert.equal(infer.reason, 'decision_function_not_configured');
  assert.equal(infer.entryId, firstM1InferEntryId);
  assert.equal(authorizationDispatchFacts(infer), undefined);
  const raw = await gate.authorize('activation', {...tuple, operation: 'model_raw_capture'}, {subjectCid: scope});
  assert.equal(raw.action, 'dispatch');
  assert.equal(raw.basis, 'account_allow');
  assert.equal(raw.entryId, 'first-m1-raw');
  assert.equal(authorizationDispatchFacts(raw).configurationCid, gate.configurationCid);
  // No Model owner consumes this Account decision; it is not a raw Store ACK,
  // disclosure grant, physical capacity, INFER dispatch or reconstructed permit.
  for (const changed of [
    {...tuple, connection: 'models/foreign'}, {...tuple, resource: scope},
    {...tuple, operation: 'read'}, {...tuple, operation: 'debug'},
  ]) {
    const refused = await gate.authorize('activation', changed, {subjectCid: scope});
    assert.equal(refused.action, 'deny');
    assert.equal(refused.reason, 'no_match');
    assert.equal(authorizationDispatchFacts(refused), undefined);
  }
  assert.equal(gate.counters().hostDecisionCalls, 0);
});

test('first M1 actual Common HostPermit binds the selected request and required approval claim', async t => {
  let calls = 0;
  const gate = await installed(t, {decide(view) {
    calls++;
    assert.deepEqual(view.answeringAuthorities, [firstM1ReviewerId]);
    assert.deepEqual(view.requiredClaims, [claim]);
    assert.deepEqual(view.tuple, {principal, ...tuple});
    assert.deepEqual(view.subject, {account_id: 'first-m1-owner',
      configuration_cid: gate.configurationCid, entry_id: firstM1InferEntryId,
      principal, connection: firstM1ProviderId, resource: task, operation: 'infer',
      boundary: 'activation', subject_cid: scope,
      context_cid: localAuthorizationContext(principal, 'first-m1-owner').contextCid});
    return {decision: 'permit', subject: view.subject, authority: firstM1ReviewerId, claims: [claim]};
  }});
  const decision = await gate.authorize('activation', tuple, {subjectCid: scope});
  assert.equal(decision.action, 'dispatch');
  assert.equal(decision.basis, 'host_permit');
  assert.equal(decision.authority, firstM1ReviewerId);
  assert.deepEqual(decision.claims, [claim]);
  assert.ok(decision.runtimeDecision, 'Use the original Common decision, not projected DATA');
  assert.equal(calls, 1);
  assert.equal(authorizationDispatchFacts({...decision}), undefined);
});

test('first M1 actual Common refuses changed Host subject authority and missing approval claim', async t => {
  for (const changed of ['subject', 'authority', 'claim']) {
    const gate = await installed(t, {decide(view) {
      return {decision: 'permit',
        subject: changed === 'subject' ? {...view.subject, resource: scope} : view.subject,
        authority: changed === 'authority' ? 'foreign-reviewer' : firstM1ReviewerId,
        claims: changed === 'claim' ? [] : [claim]};
    }});
    const decision = await gate.authorize('activation', tuple, {subjectCid: scope});
    assert.equal(decision.action, 'failure', changed);
    assert.equal(authorizationDispatchFacts(decision), undefined);
    assert.equal(gate.counters().protectedDispatches, 0);
  }
});

test('first M1 actual Account admits the existing UTF16 ceiling and refuses a different principal', async t => {
  const selected = '\u0800'.repeat(512);
  assert.equal(Buffer.byteLength(selected), 1536);
  const gate = await installed(t, {principal: selected});
  const original = await gate.authorize('activation', tuple, {subjectCid: scope});
  assert.equal(original.entryId, firstM1InferEntryId);
  assert.equal(original.action, 'unsupported');
  const foreign = gate.withContext(localAuthorizationContext('foreign-local-principal', 'first-m1-owner'));
  t.after(() => { assert.equal(foreign.close(), true); });
  const refused = await foreign.authorize('activation', tuple, {subjectCid: scope});
  assert.equal(refused.action, 'deny');
  assert.equal(refused.reason, 'no_match');
  assert.equal(authorizationDispatchFacts(refused), undefined);
});

// Exercise installation-owned decision options through the real Checkpoint
// service and compiled authorization runtime, without provider dispatch.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const flush = () => new Promise(setImmediate);
const permit = view => ({decision: 'permit', subject: view.subject, authority: 'reviewer'});
const authorize = (gate, boundary = 'effect_commit', subject = '2') =>
  gate.authorize(boundary, {connection: 'reference', resource: 'records',
    operation: boundary === 'effect_commit' ? 'effect' : 'read'}, {subjectCid: cid(subject)});
const capacityFailure = decision => {
  assert.equal(decision.action, 'failure');
  assert.equal(decision.reason, 'adapter_error');
  assert.equal(decision.detail, 'AuthorizationDecisionCapacity');
};

function pendingDecisions(t) {
  const calls = [];
  const waiters = [];
  t.after(async () => {
    for (const call of calls) call.settle({decision: 'unavailable'});
    await flush();
  });
  return {calls, entered: count => calls.length >= count ? Promise.resolve()
    : new Promise(resolve => { waiters.push({count, resolve}); }),
  decide: (view, {signal}) => new Promise(settle => {
    calls.push({view, signal, settle});
    for (const waiter of waiters) {
      if (calls.length >= waiter.count) waiter.resolve();
    }
  })};
}

async function fixture(t, decide, options) {
  const scratch = new URL('../../_build/effect-authorization-options/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch.pathname, 'host-'));
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  const checkpoints = await installRemoteCheckpoints({root, namespaceId: 'local',
    authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
    realizationKey: 'source-free-values', environmentCid: cid('4'),
    contractControl: runtimeCore(moon).publicationControl,
    authorization: {accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'local',
      entries: [{entry_id: 'records', outcome: 'delegate', principal: {all: true},
        connection: {any_of: ['reference']}, resource: {any_of: ['records']},
        operation: {any_of: ['effect', 'read']}, exclusions: []}]}),
    ...options, decide, resumeAfterAnswer: false,
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
      principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
    reviewReaders: ['reviewer'], hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}});
  const gates = [];
  t.after(async () => {
    for (const gate of gates) gate.close();
    await checkpoints.close();
    await rm(root, {recursive: true, force: true});
  });
  return async runId => {
    const gate = await checkpoints.effectAuthorization({runId,
      runDefinitionCid: cid('1'), unitId: 'effect', declaredResults: ['answer'],
      reviewWire: '{}', continuationWire: '{}',
      beforeDefer() { assert.fail('No deferred answer'); }});
    gates.push(gate);
    return gate;
  };
}

for (const boundary of ['acquisition', 'effect_commit']) {
  test(`Effect ${boundary} uses the installed decision deadline`, async t => {
    const {calls, decide, entered} = pendingDecisions(t);
    const open = await fixture(t, decide, {decisionTimeoutMs: 5});
    const gate = await open('deadline');
    t.mock.timers.enable({apis: ['setTimeout']});
    let result;
    const operation = authorize(gate, boundary).then(value => { result = value; });
    await entered(1);
    assert.equal(calls.length, 1);
    t.mock.timers.tick(4);
    await flush();
    assert.equal(result, undefined, 'the configured deadline has not elapsed');
    t.mock.timers.tick(1);
    await flush();
    assert.equal(result?.reason, 'timeout', 'the installed 5 ms deadline must settle the wait');
    await operation;
    assert.equal(calls[0].signal.aborted, true);
    assert.equal(gate.close(), false, 'timeout does not finish the physical callback');
    assert.equal(gate.cleanup(), false);
    calls[0].settle(permit(calls[0].view));
    await flush();
    assert.equal(gate.cleanup(), true);
    assert.equal(gate.cleanupPending(), false);
    assert.equal(gate.close(), true);
    assert.equal(result.action, 'failure', 'a late permit cannot replace the timeout');
    assert.equal(calls.length, 1);
  });
}

for (const secondBoundary of ['acquisition', 'effect_commit']) {
  test(`Effect commit shares physical capacity with another ${secondBoundary} request`, async t => {
    const {calls, decide, entered} = pendingDecisions(t);
    const open = await fixture(t, decide, {decisionTimeoutMs: 5,
      maxInFlightDecisions: 1, maxRetainedDecisions: 4});
    const first = await open('first');
    const second = await open('second');
    const third = await open('third');
    t.mock.timers.enable({apis: ['setTimeout']});
    const operation = authorize(first);
    await entered(1);
    assert.equal(calls.length, 1);
    let refused;
    const blocked = authorize(second, secondBoundary).then(value => { refused = value; });
    await Promise.race([blocked, entered(2)]);
    assert.equal(calls.length, 1, 'a different request cannot start a second callback');
    capacityFailure(refused);
    await blocked;
    t.mock.timers.tick(5);
    assert.equal((await operation).reason, 'timeout');
    assert.equal(first.close(), false);
    assert.equal(first.cleanup(), false);
    capacityFailure(await authorize(second, secondBoundary));
    assert.equal(calls.length, 1, 'timeout and close must retain physical capacity');
    calls[0].settle({decision: 'unavailable'});
    await flush();
    assert.equal(first.cleanup(), true);
    const replacement = authorize(second, secondBoundary);
    await entered(2);
    assert.equal(calls.length, 2, 'settlement releases the original physical slot');
    assert.equal(first.close(), true);
    assert.equal(first.cleanup(), true);
    capacityFailure(await authorize(third));
    assert.equal(calls.length, 2, 'repeated cleanup cannot release the replacement slot');
    calls[1].settle({decision: 'unavailable'});
    assert.equal((await replacement).reason, 'unavailable');
    assert.equal(second.close(), true);
    const next = authorize(third);
    await entered(3);
    assert.equal(calls.length, 3);
    calls[2].settle({decision: 'unavailable'});
    assert.equal((await next).reason, 'unavailable');
    assert.equal(third.close(), true);
  });
}

test('Effect requests and their read/commit siblings share retained capacity, not judgments', async t => {
  let calls = 0;
  const open = await fixture(t, view => { calls++; return permit(view); },
    {maxInFlightDecisions: 4, maxRetainedDecisions: 1});
  const first = await open('first');
  const second = await open('second');
  const third = await open('third');
  const decision = await authorize(first);
  assert.equal(decision.action, 'dispatch');
  assert.equal(await authorize(first), decision, 'one scope reuses its exact decision');
  assert.equal(calls, 1);
  capacityFailure(await authorize(first, 'acquisition'));
  capacityFailure(await authorize(second));
  assert.equal(calls, 1, 'a retained decision reserves capacity across scopes');
  assert.equal(first.close(), true);
  const secondDecision = await authorize(second);
  assert.equal(secondDecision.action, 'dispatch');
  assert.notEqual(secondDecision, decision, 'judgments are never shared across requests');
  assert.equal(calls, 2);
  assert.equal(first.close(), true);
  assert.equal(first.cleanup(), true);
  capacityFailure(await authorize(third));
  assert.equal(calls, 2, 'repeated cleanup cannot release another scope\'s retained decision');
  assert.equal(second.close(), true);
  assert.equal((await authorize(third)).action, 'dispatch');
  assert.equal(calls, 3);
  assert.equal(third.close(), true);
});

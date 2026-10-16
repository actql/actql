import assert from 'node:assert/strict';
import test from 'node:test';
import {effectTargetReadContinuation} from './effect-target-read-continuation.mjs';
import {EFFECT_TARGET_CONTINUATION, effectTargetReadInventory} from
  './effect-target-read-inventory.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';

// Real continuation with finite Checkpoint ports. These are owner-lifetime and
// await-boundary controls, not compiled account, durable journal or Provider
// acceptance. The inventory helper only constructs a valid resumed fixture;
// no canonical identity or digest is asserted against product output.
const cid = digit => `sha256:${digit.repeat(64)}`;
const accountChanged = () => Object.assign(new Error('AuthorizationCurrentAccountChanged'),
  {code: 'AuthorizationCurrentAccountChanged'});
const closed = {code: 'EffectTargetReadOwnerClosed'};
const changed = {code: 'AuthorizationCurrentAccountChanged'};
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
};
const pause = value => {
  const started = deferred(), released = deferred();
  return {started: started.promise, release: released.resolve,
    async run() { started.resolve(); await released.promise; return value; }};
};

function fixture({selected = true, resumed = false, count = 1} = {}) {
  const inventory = Array.from({length: count}, (_, index) => ({
    readTuple: {connection: 'fixture', resource: `resource-${index}`, operation: 'read'},
    physicalBinding: {version: 'actql-target-current-fixture/0.1', resource: `resource-${index}`},
  }));
  const bound = effectTargetReadInventory(inventory);
  const submission = {request: 'original'};
  const calls = [];
  let originalLive = true, claimLive = true, entries = 0, resumeChecks = 0;
  const states = bound.targets.map(target => {
    const state = {target, live: true, opened: undefined};
    state.gate = {
      scopeCid: cid(String(target.index + 1)),
      configurationCid: cid('a'), contextCid: cid('b'),
      assertCurrent() {
        calls.push(`current-${target.index}`);
        if (!state.live) throw accountChanged();
      },
      async authorize() {
        calls.push(`authorize-${target.index}`);
        return {action: 'dispatch', basis: 'account_allow'};
      },
      async current() {
        calls.push(`authorize-current-${target.index}`);
        return {action: 'dispatch', basis: 'account_allow'};
      },
      async resume() {
        calls.push(`resume-${target.index}`);
        return {action: 'dispatch', basis: 'resumed', admission: {
          enter() { entries++; },
        }};
      },
      close() { calls.push(`close-${target.index}`); state.live = false; return true; },
    };
    return state;
  });
  const checkpoints = {
    journal: {committedApprovalAt: () => ({current: true})},
    async inspectEffectTargetApprovals() { return []; },
    async effectTargetAuthorization(options) {
      const state = states[options.target.index];
      state.opened = options;
      return state.gate;
    },
  };
  const resume = resumed ? {
    view: {checkpointCid: cid('c')}, claim: {generation: 1},
    continuation: {version: EFFECT_TARGET_CONTINUATION,
      run_definition_cid: cid('d'), unit_id: 'unit', submission,
      inventory_cid: bound.inventoryCid, targets: bound.targets, pending_target: 0},
    assertCurrent() {
      resumeChecks++;
      if (!claimLive) throw Object.assign(new Error('PredecessorClaimConsumed'),
        {code: 'PredecessorClaimConsumed'});
    },
  } : undefined;
  const assertOriginalCurrent = () => {
    if (!originalLive) throw Object.assign(new Error('OriginalSelectionChanged'),
      {code: 'OriginalSelectionChanged'});
  };
  const options = {checkpoints, runId: 'run', runDefinitionCid: cid('d'),
    unitId: 'unit', declaredResults: [], submission, inventory,
    principalId: 'principal', resume, assertCurrent: assertOriginalCurrent,
    ...(selected ? {assertOriginalCurrent} : {})};
  return {states, calls, checkpoints, options,
    open: () => effectTargetReadContinuation(options),
    consumeClaim: () => { claimLive = false; },
    revokeOriginal: () => { originalLive = false; },
    entries: () => entries, resumeChecks: () => resumeChecks};
}

async function opened(t, options) {
  const f = fixture(options);
  const owner = await f.open();
  t.after(() => owner.close());
  return {...f, owner};
}

test('a current selected target owner admits preparation and preserves live token fences', async t => {
  const f = await opened(t);
  assert.deepEqual(await f.owner.prepare(), {status: 'ready'});
  const decision = await f.owner.authorize(f.states[0].target.readTuple);
  const facts = checkpointApprovalFacts(decision);
  assert.equal(decision.action, 'dispatch');
  assert.equal(facts.kind, 'effect_target');
  assert.equal(facts.assertCurrent(), undefined);
  assert.equal(facts.enter(), undefined);
  assert.equal(f.owner.enterComputation(), undefined);
  assert.equal(f.entries(), 0);
  assert.equal(f.calls.filter(call => call === 'authorize-0').length, 1);
  assert.equal(f.calls.filter(call => call === 'authorize-current-0').length, 1);
});

test('a live resumed target token and computation share one original admission entry', async t => {
  const f = await opened(t, {resumed: true});
  assert.deepEqual(await f.owner.prepare(), {status: 'ready'});
  const facts = checkpointApprovalFacts(await f.owner.authorize(f.states[0].target.readTuple));
  facts.enter();
  f.owner.enterComputation();
  facts.enter();
  assert.equal(f.entries(), 1);
  assert.equal(f.calls.filter(call => call === 'resume-0').length, 1);
});

for (const [name, value] of [['missing', undefined], ['null', null], ['non-function', true]]) {
  test(`a selected target gate with ${name} assertCurrent refuses before authorization`, async t => {
    const f = await opened(t);
    if (name === 'missing') delete f.states[0].gate.assertCurrent;
    else f.states[0].gate.assertCurrent = value;
    await assert.rejects(f.owner.prepare(), closed);
    assert.equal(f.calls.includes('authorize-0'), false);
    assert.equal(f.entries(), 0);
  });
}

for (const rejected of [false, true]) {
  test(`a selected target gate refuses a ${rejected ? 'rejected' : 'resolved'} Promise currency result`, async t => {
    const f = await opened(t);
    f.states[0].gate.assertCurrent = () => rejected
      ? Promise.reject(accountChanged()) : Promise.resolve();
    await assert.rejects(f.owner.prepare(), closed);
    // Allow the rejection-drain microtask to settle. The Node runner also
    // reports any unhandled rejection as a test failure.
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.calls.includes('authorize-0'), false);
    assert.equal(f.entries(), 0);
  });
}

test('an unselected current preparation does not acquire the selected-owner requirement', async t => {
  const f = await opened(t, {selected: false});
  delete f.states[0].gate.assertCurrent;
  assert.deepEqual(await f.owner.prepare(), {status: 'ready'});
  assert.equal(f.calls.includes('authorize-0'), true);
});

test('account change during initial authorization prevents the ready result', async t => {
  const f = await opened(t);
  const paused = pause({action: 'dispatch', basis: 'host_permit'});
  f.states[0].gate.authorize = paused.run;
  const rejected = assert.rejects(f.owner.prepare(), changed);
  await paused.started;
  f.states[0].live = false;
  paused.release();
  await rejected;
  assert.equal(f.entries(), 0);
});

test('account change during current authorization prevents a retained approval token', async t => {
  const f = await opened(t, {resumed: true});
  await f.owner.prepare();
  const paused = pause({action: 'dispatch', basis: 'account_allow'});
  f.states[0].gate.current = paused.run;
  const rejected = assert.rejects(f.owner.authorize(f.states[0].target.readTuple), changed);
  await paused.started;
  f.states[0].live = false;
  paused.release();
  await rejected;
  assert.equal(f.entries(), 0);
});

test('every opened target owner is fenced after another target authorization awaits', async t => {
  const f = await opened(t, {count: 2});
  const paused = pause({action: 'dispatch', basis: 'account_allow'});
  f.states[0].gate.authorize = paused.run;
  const rejected = assert.rejects(f.owner.prepare(), changed);
  await paused.started;
  f.states[1].live = false;
  paused.release();
  await rejected;
  assert.equal(f.calls.includes('authorize-1'), false);
  assert.equal(f.entries(), 0);
});

test('a retained target token refuses a stale original gate before any admission entry', async t => {
  const f = await opened(t, {resumed: true});
  await f.owner.prepare();
  const facts = checkpointApprovalFacts(await f.owner.authorize(f.states[0].target.readTuple));
  await new Promise(resolve => setImmediate(resolve));
  f.states[0].live = false;
  assert.throws(facts.assertCurrent, changed);
  assert.throws(facts.enter, changed);
  assert.throws(() => f.owner.enterComputation(), changed);
  assert.equal(f.entries(), 0);
});

test('a successor waiting checkpoint returns after consuming the predecessor claim', async t => {
  const f = await opened(t, {resumed: true, count: 2});
  const checkpoint = Object.freeze({checkpointCid: cid('e')});
  let checksAtHandoff;
  f.states[1].gate.authorize = async () => {
    f.states[1].opened.beforeDefer();
    f.consumeClaim();
    checksAtHandoff = f.resumeChecks();
    await Promise.resolve();
    return {action: 'waiting', checkpoint};
  };
  assert.deepEqual(await f.owner.prepare(), {status: 'waiting_checkpoint', checkpoint});
  assert.equal(f.resumeChecks(), checksAtHandoff);
  assert.equal(f.entries(), 0);
  assert.throws(() => f.owner.enterComputation(), {code: 'PredecessorClaimConsumed'});
  assert.equal(f.entries(), 0);
});

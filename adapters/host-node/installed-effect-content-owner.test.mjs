// Actual Effect Site composition with explicit computation/provider ports.
// No Common runtime, physical Content read, approval or file write is issued.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledEffectSite} from './installed-effect-site.mjs';

for (const present of [true, false]) {
  test(`Effect capture ${present ? 'borrows the original' : 'omits an absent'} computation Content owner`, async () => {
    const original = Object.freeze({});
    const unrelated = Object.freeze({});
    const stop = new Error('CapturedOriginalBoundary');
    let captured, retained, ownerReads = 0, closed = 0;
    const execution = {async close() {}, async cleanup() {closed++; return true;},
      cleanupPending: () => false};
    const site = createInstalledEffectSite({environmentWire:'{}',
      prepareCaptured(facts) {captured=facts; throw stop;},
      prepareRecovered() {assert.fail('No restore or second computation');}});
    const opened = {execution,checkedHost:Object.freeze({}),
      get contentOwner() {ownerReads++; return present ? original : undefined;}};
    await assert.rejects(site.execute({
      contentOwner:unrelated,
      openComputation:async () => opened,
      retainExecution(owner) {retained=owner;},
    }),error => error===stop);
    assert.equal(ownerReads,1);
    assert(Object.isFrozen(captured));
    assert.strictEqual(captured.execution,execution);
    if (present) assert.strictEqual(captured.contentOwner,original);
    else assert.equal(Object.hasOwn(captured,'contentOwner'),false);
    assert.equal(closed,0,'failed capture retains its original physical owner');
    assert.equal(await retained.cleanup(),true);
    assert.equal(closed,1);
    assert.equal(retained.cleanupPending(),false);
  });
}

test('Content-owner access failure keeps the already acquired computation under cleanup', async () => {
  const failure = new Error('OriginalContentOwnerUnavailable');
  let retained, closed=0;
  const execution={async close() {},async cleanup() {closed++; return true;},
    cleanupPending:() => false};
  const site=createInstalledEffectSite({environmentWire:'{}',
    prepareCaptured() {assert.fail('No provider after failed original observation');},
    prepareRecovered() {assert.fail('No replacement computation');}});
  await assert.rejects(site.execute({
    openComputation:async () => ({execution,checkedHost:{},
      get contentOwner() {throw failure;}}),
    retainExecution(owner) {retained=owner;},
  }),error => error===failure);
  assert.equal(closed,0);
  assert.equal(await retained.cleanup(),true);
  assert.equal(closed,1);
});

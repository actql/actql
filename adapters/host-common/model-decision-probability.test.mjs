import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from './runtime-core.mjs';

// The forwarding counter uses a nominal-value double. Actual Common selection
// and its existing registered CID are checked separately on the JS backend.
test('installed native probability selection preserves the same runtime original without copying', () => {
  const original = Object.freeze({fixtureOpaqueProbability: true});
  let selections = 0;
  const moon = {clientProgramInitialJevDecisionProfile() {
    assert.equal(this, moon);
    selections++;
    return original;
  }};
  const control = runtimeCore(moon).publicationControl;
  assert.equal(control.selectInstalledInitialJevDecisionProfile(), original);
  assert.equal(selections, 1);
});

test('missing or absent native probability runtime refuses without manufacturing a profile', () => {
  for (const moon of [{}, {clientProgramInitialJevDecisionProfile: null},
    {clientProgramInitialJevDecisionProfile: () => undefined}]) {
    const control = runtimeCore(moon).publicationControl;
    assert.throws(() => control.selectInstalledInitialJevDecisionProfile(),
      {message: 'Installed native Decision probability profile unavailable'});
  }
});

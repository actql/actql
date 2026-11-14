import test from 'node:test';
import assert from 'node:assert/strict';
import {createInferPhysicalObservation} from './infer-physical-observation.mjs';

function fixture() {
  const emitted = [];
  let losses = 0;
  const receipt = {attemptCid: 'attempt-original', runDefinitionCid: 'run-original',
    taskIndex: 2, ordinal: 0, attemptIndex: 1};
  const observe = createInferPhysicalObservation({
    observation: {noteLoss() { losses++; }, emit(...args) { emitted.push(args); }},
    reference: {namespaceId: 'namespace', authorityScopeCid: 'scope'},
    receiptAt: () => receipt});
  return {observe, emitted, losses: () => losses};
}

test('pre-gate diagnostic is unsent and cannot become a completed transport observation', () => {
  const f = fixture();
  f.observe({event: 'before_invoke', slot: 0, attemptCid: 'attempt-original',
    outcome: 'not_started'});
  assert.deepEqual(f.emitted, []);
  assert.equal(f.losses(), 0);
  f.observe({event: 'returned', slot: 0, attemptCid: 'attempt-original', outcome: 'confirmed'});
  assert.deepEqual(f.emitted, []);
  assert.equal(f.losses(), 1);
});

test('actual entry facts correlate the original receipt without fabricated duration or success', () => {
  for (const [event, outcome] of [['returned', 'confirmed'], ['failed', 'failed'],
    ['cancelled', 'cancelled']]) {
    const f = fixture();
    f.observe({event: 'before_invoke', slot: 0, attemptCid: 'attempt-original'});
    f.observe({event: 'started', slot: 0, attemptCid: 'attempt-original'});
    f.observe({event, slot: 0, attemptCid: 'attempt-original', outcome});
    assert.deepEqual(f.emitted, [['infer', 'transport_completed', {
      ref: {namespaceId: 'namespace', authorityScopeCid: 'scope', runDefinitionCid: 'run-original'},
      task: 2, slot: 0, attempt: 1, attemptCid: 'attempt-original', outcome,
    }]]);
    assert.equal(f.losses(), 0);
    f.observe({event, slot: 0, attemptCid: 'attempt-original', outcome});
    assert.equal(f.emitted.length, 1);
    assert.equal(f.losses(), 1);
  }
});

test('foreign attempt and missing entry never acquire original telemetry correlation', () => {
  for (const mutation of [{slot: 1}, {attemptCid: 'foreign-attempt'}, {event: 'unknown'}]) {
    const f = fixture();
    f.observe({event: 'started', slot: 0, attemptCid: 'attempt-original'});
    f.observe({event: 'returned', slot: 0, attemptCid: 'attempt-original',
      outcome: 'confirmed', ...mutation});
    assert.deepEqual(f.emitted, []);
    assert.equal(f.losses(), 1);
  }
});

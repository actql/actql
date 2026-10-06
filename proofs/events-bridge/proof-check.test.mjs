import test from 'node:test';
import assert from 'node:assert/strict';
import {checkEventsBridge, proofInput, runLean} from './check.mjs';

test('ActQL composition laws and the admitted Events instance have exact types and audited axioms', () => {
  assert.equal(checkEventsBridge().theorems.length, 16);
});

test('the common composition claim rejects replacing its conclusion with True', () => {
  const input = proofInput();
  const start = input.indexOf('    observeResult output (composeResult (first value) second) =');
  const end = input.indexOf('\ntheorem failure_short_circuits', start);
  assert.ok(start >= 0 && end > start);
  const result = runLean(input.slice(0, start) + '    True := by\n  trivial\n' + input.slice(end));
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/iu);
});

test('the Events schema/order claim rejects a weakened existing theorem', () => {
  const input = proofInput();
  const original = 'BridgeComposition.composeResult (toEvents rows) toRows = .ok\n      { schema := rows.schema, records := rows.records } := round_trip rows h';
  assert.equal(input.split(original).length, 2);
  const result = runLean(input.replace(original, 'True := by\n  trivial'));
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/iu);
});

test('the instance cannot erase an observable admission failure', () => {
  const input = proofInput();
  const original = 'BridgeComposition.composeResult (toEvents rows) toRows = .error issue := by\n  simp [toEvents, h, BridgeComposition.composeResult]';
  assert.equal(input.split(original).length, 2);
  const result = runLean(input.replace(original, 'True := by\n  trivial'));
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/iu);
});

test('incorrect clock mapping cannot retain the model round-trip proof', () => {
  const input = proofInput();
  const original = '⟨row.identity, row.clock, row.payload⟩';
  assert.equal(input.split(original).length, 2);
  const result = runLean(input.replace(original, '⟨row.identity, .milliseconds row.identity, row.payload⟩'));
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /unsolved goals/iu);
});

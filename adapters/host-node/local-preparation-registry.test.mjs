import test from 'node:test';
import assert from 'node:assert/strict';
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
test('Pure Local frozen submission aliases share a retiring preparation slot', async () => {
  const registry = installLocalPreparationRegistry(value => value.pure === true);
  const prepared = {pure: true};
  const handle = registry.adopt(prepared);
  assert.notEqual(handle, prepared);
  assert.equal(registry.adopt(prepared), handle);
  const candidate = Object.freeze(registry.attach({id: 1}, handle));
  const submission = registry.attach({id: 1}, handle);
  assert.equal(candidate.preparedProgram, prepared);
  assert.equal(Object.hasOwn(Object.getOwnPropertyDescriptor(candidate, 'preparedProgram'), 'value'), false);
  const dispatch = registry.begin(submission);
  await Promise.resolve();
  assert.equal(dispatch.preparedProgram, prepared);
  assert.equal(candidate.preparedProgram, prepared);
  assert.throws(() => registry.begin(submission), /AlreadyDispatched/);
  dispatch.retire(); dispatch.retire();
  assert.throws(() => candidate.preparedProgram, /BorrowReleased|Retired/);
  assert.throws(() => submission.preparedProgram, /BorrowReleased|Retired/);
  assert.throws(() => dispatch.preparedProgram, /BorrowReleased|Retired/);
});
test('generic Source Effect and Model routes are not adopted', () => {
  const registry = installLocalPreparationRegistry(() => false);
  const prepared = {};
  assert.equal(registry.adopt(prepared), prepared);
  const submission = registry.attach({}, prepared);
  assert.equal(submission.preparedProgram, prepared);
  assert.equal(registry.begin(submission), undefined);
});
test('handler and dispatch share input descriptors until both original owners finish', async () => {
  const registry = installLocalPreparationRegistry(() => true);
  const input = Object.freeze({text: 'SELECT 1', format: 'sql'}), parameters = Object.freeze({x: 1});
  const request = registry.capture(Object.freeze({kind: 'aql', input, parameters}));
  assert.throws(() => registry.copy(request, {input: {}}), /SnapshotMutation/);
  assert.throws(() => registry.copy(request, {parameters: {}}), /SnapshotMutation/);
  const derived = registry.copy(request, {requestId: 'original'});
  const handle = registry.adopt({}, derived);
  const submission = Object.freeze(registry.attach(registry.copy(derived), handle));
  const candidate = Object.freeze(registry.attach(registry.copy(derived), handle));
  for (const value of [request, derived, submission, candidate]) {
    assert.equal(value.input, input);
    assert.equal(Object.hasOwn(Object.getOwnPropertyDescriptor(value, 'input'), 'value'), false);
  }
  const dispatch = registry.begin(submission);
  dispatch.retire();
  // Result cleanup may finish before the submitting handler's final await.
  await Promise.resolve();
  assert.equal(request.input, input);
  registry.finishHandler(request);
  registry.finishHandler(request);
  for (const value of [request, derived, submission, candidate]) assert.throws(() => value.input, /Retired/);
  assert.equal(input.text, 'SELECT 1'); // Caller-owned data is never mutated.
});
test('dispatch continues after handler return and later releases all input aliases', () => {
  const registry = installLocalPreparationRegistry(() => true);
  const request = registry.capture({kind: 'program', input: {stages: []}, parameters: null});
  const handle = registry.adopt({}, request);
  const submission = registry.attach(registry.copy(request), handle);
  const dispatch = registry.begin(submission);
  registry.finishHandler(request);
  assert.deepEqual(submission.input, {stages: []});
  assert.ok(dispatch.preparedProgram);
  dispatch.retire();
  assert.throws(() => submission.input, /Retired/);
});
test('handler failure before dispatch preserves original preparation for uncertain setup cleanup', () => {
  const registry = installLocalPreparationRegistry(() => true);
  const request = registry.capture({kind:'aql',input:{text:'SELECT 1'},parameters:null});
  const prepared = {}, handle = registry.adopt(prepared, request);
  const candidate = Object.freeze(registry.attach(registry.copy(request),handle));
  registry.finishHandler(request);
  assert.equal(candidate.preparedProgram,prepared);
  assert.deepEqual(candidate.input,{text:'SELECT 1'});
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';

function fixture(extra = {}) {
  const environment = {};
  const moon = {
    clientProgramPrepareEffectFreeWithParameters() {return {prepared: {}};},
    clientProgramPreparationReady(outcome) {return outcome.prepared;},
    clientProgramPreparationIssue() {},
    clientProgramPreparationIssueCode() {},
  };
  return {environment, prepare: installNodeClientProgramPreparation({moon, environment, ...extra})};
}
const request = () => ({kind: 'program', input: {}, parameters: {p: 'retained'}});

test('private Pure preparation retirement clears only exact metadata and is idempotent', () => {
  const {environment, prepare} = fixture();
  const first = prepare(request());
  const second = prepare(request());
  assert.equal(prepare.originalInputs(first).environment, environment);
  assert.equal(prepare.originalInputs(first).parameters, '{"p":"retained"}');
  prepare.retireOriginal(first);
  prepare.retireOriginal(first);
  assert.throws(() => prepare.originalInputs(first), /ClientProgramPreparationFailure/);
  assert.throws(() => prepare.assertOwned(first), /Foreign Client preparation/);
  assert.throws(() => prepare.kindOf(first), /Foreign Client preparation/);
  assert.equal(prepare.kindOf(second), 'effect_free');
  assert.equal(prepare.originalInputs(second).environment, environment);
  assert.equal(prepare.kindOf(prepare(request())), 'effect_free');
});

test('private Pure preparation retirement rejects foreign and restored Infer owners', () => {
  const definition = {};
  const restored = {prepared: {}, compiled: {}, graph: {}, runDefinition: definition};
  const {prepare} = fixture({restoreInferOriginal: () => restored});
  const other = fixture().prepare(request());
  assert.throws(() => prepare.retireOriginal(other), /Foreign Pure Client preparation/);
  assert.throws(() => prepare.retireOriginal({}), /Foreign Pure Client preparation/);
  const infer = prepare.restoreInferOriginal({}, definition, {}, {});
  assert.throws(() => prepare.retireOriginal(infer), /Foreign Pure Client preparation/);
  assert.equal(prepare.originalInferRun(infer), restored);
});

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

test('fixed funded original bypasses serialization and retains ordinary ownership metadata',()=>{
 const original={},input={toJSON(){throw Error('unexpected second serialization');}};
 let seen;
 const {environment,prepare}=fixture({getFundedPreparation(request,selected){seen=[request,selected];return original;}});
 const request={kind:'program',input,parameters:null};
 assert.equal(prepare(request),original);assert.deepEqual(seen,[request,environment]);
 assert.deepEqual(prepare.originalInputs(original),{environment,parameters:undefined});
 prepare.retireOriginal(original);assert.throws(()=>prepare.assertOwned(original));
});
test('undefined funded original keeps legacy serialization and failure is not silent fallback',()=>{
 const {prepare}=fixture({getFundedPreparation(){return undefined;}});
 assert.ok(prepare({kind:'program',input:{},parameters:null}));
 const broken=fixture({getFundedPreparation(){throw Error('original funding failed');}}).prepare;
 assert.throws(()=>broken({kind:'program',input:{},parameters:null}),/original funding failed/);
});

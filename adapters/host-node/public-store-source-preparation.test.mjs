import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodePublicSourcePreparation} from './public-source-preparation.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const environment = Object.freeze({generation: cid('a')});
const target = () => ({name: 'gcs.objects', targetRef: 'connector://storage/objects',
  installationBindingCid: cid('b'), installationOwnerCid: cid('c')});
const publication = () => ({environmentCid: cid('a'), aliases: [], storeTargets: [target()]});

function ownerDouble() {
  const calls = [], result = Object.freeze({prepared: true});
  const moon = {
    clientProgramCheckingEnvironmentCid: value => value.generation,
    clientProgramSourcePublicationValid: (owner, wire) => {
      calls.push({kind: 'validate', owner, wire}); return true;
    },
    clientProgramPreparePublicSourceComputationWithParameters: (...args) => {
      calls.push({kind: 'source', args}); return {pure: result};
    },
    clientProgramSourceComputationPure: value => value.pure,
    clientProgramSourceComputationEffect: value => value.effect,
    clientProgramPreparePublishedEffectComputationWithParameters: (...args) => {
      calls.push({kind: 'effect', args}); return result;
    },
  };
  return {moon, calls, result};
}

// These are JS-to-Common wiring controls. The actual Common original-pair
// validator has separate source-qualified tests; this double grants no Ref.
test('STORE Source metadata reaches its existing owner unchanged and snapshotted', () => {
  const {moon, calls, result} = ownerDouble(), selected = publication();
  const wire = JSON.stringify(selected), evidence = [Object.freeze({original: true})];
  const prepared = installNodePublicSourcePreparation({moon, environment,
    publication: selected, allowEffects: true, effectEvidence: evidence});
  selected.storeTargets[0].targetRef = 'connector://foreign/changed';
  selected.storeTargets.push(target()); evidence.push({foreign: true});
  assert.deepEqual(prepared.prepare({document: 'SELECT 1', format: 'sql',
    declarations: undefined, supplied: undefined}), {kind: 'effect_free', outcome: result});
  assert.equal(prepared.prepareEffect({document: '{}', format: 'json', supplied: '{}'}), result);
  assert.deepEqual(calls, [
    {kind: 'validate', owner: environment, wire},
    {kind: 'source', args: ['SELECT 1', 'sql', environment, wire, undefined, undefined,
      true, [evidence[0]]]},
    {kind: 'effect', args: ['{}', 'json', environment, wire, '{}', [evidence[0]]]},
  ]);
});

test('STORE Source metadata requires the Common validator even for an unused target', () => {
  for (const absent of [false, true]) {
    const {moon, calls} = ownerDouble();
    if (absent) delete moon.clientProgramSourcePublicationValid;
    else moon.clientProgramSourcePublicationValid = () => false;
    assert.throws(() => installNodePublicSourcePreparation({moon, environment,
      publication: publication()}), {name: 'TypeError', message: 'InvalidPublicSourcePublication'});
    assert.equal(calls.length, 0, 'No lowering or Effect preparation before metadata admission');
  }
});

test('STORE Source metadata retains original bounds and closed outer shape', () => {
  const {moon, calls} = ownerDouble();
  for (const value of [null, {}, 'targets', Array.from({length: 1025}, target)]) {
    assert.throws(() => installNodePublicSourcePreparation({moon, environment,
      publication: {...publication(), storeTargets: value}}), TypeError);
  }
  assert.throws(() => installNodePublicSourcePreparation({moon, environment,
    publication: {...publication(), guessedTarget: target()}}), TypeError);
  assert.equal(calls.length, 0);
});

test('STORE empty publication preserves absence and does not grant Effects', () => {
  const {moon, calls} = ownerDouble();
  const selected = {...publication(), storeTargets: []};
  const prepared = installNodePublicSourcePreparation({moon, environment, publication: selected});
  assert.throws(() => prepared.prepareEffect({document: '{}', format: 'json'}),
    {code: 'ClientProgramUnsupported'});
  assert.deepEqual(calls, [{kind: 'validate', owner: environment, wire: JSON.stringify(selected)}]);
});

test('STORE metadata coexists with existing UPDATE and table publication through one validator', () => {
  const {moon, calls} = ownerDouble();
  const selected = {...publication(), updateTargets: [target()], tableWrites: []};
  installNodePublicSourcePreparation({moon, environment, publication: selected});
  assert.deepEqual(calls, [{kind: 'validate', owner: environment, wire: JSON.stringify(selected)}]);
});

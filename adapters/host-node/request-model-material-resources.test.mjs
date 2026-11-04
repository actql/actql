import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {configuration} from '../../scripts/fixtures/installed-infer-fixture.mjs';
import {readInstalledModelExecution, readInstalledModelDependencies,
  admitInstalledModelProviderBinding} from './installed-model.mjs';

// Actual exported readers with explicit native/current reservation ports.
// The sentinel ends before a Core issuer, Provider, Account or physical IO.
const frozen = (executions, bodies) => Object.freeze({environmentWire: '{}',
  executionContracts: Object.freeze(executions.map(Object.freeze)),
  dependencyBodies: Object.freeze(bodies.map(Object.freeze))});

test('packed Model fixture supplies its original immutable material envelope to the funded reader', () => {
  const base = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url)));
  const {installation, taskCid} = configuration(base);
  const entry = installation.executionContracts[0], prepared = {}, calls = [];
  const original = new Error('original Core execution reader');
  const moon = {
    clientProgramSelectedInferStep(value) {assert.equal(value, prepared); return 3;},
    clientProgramInferModelTaskCid(value, step) {
      assert.equal(value, prepared); assert.equal(step, 3); return taskCid;
    },
    clientProgramReadInferModelExecution(value, step, wire, cid) {
      assert.equal(value, prepared); assert.equal(step, 3);
      assert.equal(wire, entry.bodyWire); assert.equal(cid, entry.cid);
      calls.push('original reader'); throw original;
    },
  };
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, undefined,
    (count, wireAt, containers) => {
      assert.equal(count, 1);
      assert.equal(containers, installation.executionContracts.length + installation.dependencyBodies.length);
      assert.equal(wireAt(0), entry.bodyWire);
      calls.push('same Request reservation');
    }), cause => cause === original);
  assert.deepEqual(calls, ['same Request reservation', 'original reader']);
  assert(Object.isFrozen(installation));
  for (const entries of [installation.executionContracts, installation.dependencyBodies]) {
    assert(Object.isFrozen(entries));
    assert(entries.every(Object.isFrozen));
  }
});

test('Model execution reservation precedes original reader and preserves captured method receiver and wire', () => {
  const prepared = {}, occurrence = {}, primary = new Error('original native execution');
  const installation = frozen([{modelTaskCid: 'task', cid: 'execution', bodyWire: '{"original":true}'}], []);
  const calls = [];
  const moon = {
    clientProgramInferOccurrenceCoordinates(o) {assert.equal(o, occurrence); return {_2: 4};},
    clientProgramInferOccurrenceModelTaskCid(o) {assert.equal(o, occurrence); return 'task';},
    clientProgramReadComposedInferModelExecution(o, wire, cid) {
      assert.equal(this, moon); assert.equal(o, occurrence);
      assert.equal(wire, installation.executionContracts[0].bodyWire); assert.equal(cid, 'execution');
      calls.push('original reader'); throw primary;
    },
  };
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, occurrence,
    (count, wireAt, containers) => {
      calls.push('same Request reservation'); assert.equal(count, 1); assert.equal(containers, 1);
      assert.equal(wireAt(0), installation.executionContracts[0].bodyWire);
      moon.clientProgramReadComposedInferModelExecution = () => assert.fail('replacement reader');
    }), cause => cause === primary);
  assert.deepEqual(calls, ['same Request reservation', 'original reader']);
  const denied = new Error('original capacity refusal'); calls.length = 0;
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, occurrence,
    () => {throw denied;}), cause => cause === denied);
  assert.deepEqual(calls, []);
});

test('Model dependency reservation counts actual selected bodies and preserves absent dependency refusal', () => {
  const execution = {}, primary = new Error('original missing dependency');
  const installation = frozen([], [
    {cid: 'prompt', bodyWire: '{"prompt":1}'},
    {cid: 'retry', bodyWire: '{"retry":2}'},
    {cid: 'media', bodyWire: '{"media":3}'},
    {cid: 'unselected', bodyWire: 'x'.repeat(10000)},
  ]);
  const calls = [], moon = {
    clientProgramInferDependencyReferences(e) {assert.equal(e, execution); return {_0: 'prompt', _1: 'retry', _2: 'absent'};},
    clientProgramInferMediaDependencyReferences(e) {assert.equal(e, execution); return [{_0: 'image', _1: 'media'}];},
    clientProgramReadInferModelDependenciesWithMedia(e, prompt, retry, backoff, media) {
      assert.equal(this, moon); assert.equal(e, execution);
      assert.deepEqual([prompt, retry, backoff], ['{"prompt":1}', '{"retry":2}', undefined]);
      assert.deepEqual(media, [{_0: 'image', _1: '{"media":3}'}]);
      calls.push('original reader'); throw primary;
    },
  };
  assert.throws(() => readInstalledModelDependencies(moon, execution, installation,
    (count, wireAt, containers) => {
      assert.equal(count, 4); assert.equal(containers, 4);
      assert.deepEqual(Array.from({length: count}, (_, index) => wireAt(index)),
        ['{"prompt":1}', '{"retry":2}', '', '{"media":3}']);
      calls.push('same Request reservation');
      moon.clientProgramReadInferModelDependenciesWithMedia = () => assert.fail('replacement reader');
    }), cause => cause === primary);
  assert.deepEqual(calls, ['same Request reservation', 'original reader']);
  let accessed = false;
  const foreign = Object.freeze({environmentWire: '{}', executionContracts: Object.freeze([]),
    get dependencyBodies() {accessed = true; return [];} });
  assert.throws(() => readInstalledModelDependencies(moon, execution, foreign, () => assert.fail('foreign originals')),
    /InstalledModelMaterialOriginalUnavailable/);
  assert.equal(accessed, false);
});

test('Model provider metadata retains same owned issuer result without legacy reissue or mutation fallback', () => {
  const value = {}, originals = Object.freeze({
    installationRevision: Object.freeze({wire: '{"installation":1}', cid: 'installation'}),
    configurationContract: Object.freeze({wire: '{"contract":2}', cid: 'contract'}),
    configuration: Object.freeze({wire: '{"configuration":3}', cid: 'configuration'}),
  });
  const moon = {
    clientProgramModelProviderBinding() {assert.fail('legacy issuer');},
    strategyRunEvidenceJson(actual) {assert.equal(actual, value); return JSON.stringify({provider_id: 'mock', self_cid: 'binding',
      installation_revision_cid: 'installation', configuration_contract_cid: 'contract', configuration_cid: 'configuration'});},
    strategyRunEvidenceIdentity(actual) {assert.equal(actual, value); return 'binding';},
  };
  let calls = 0;
  const result = admitInstalledModelProviderBinding(moon, 'mock', {bindingOriginals: originals},
    (...args) => {
      assert.deepEqual(args, ['mock', originals.installationRevision.wire,
        originals.configurationContract.wire, originals.configuration.wire]);
      calls++; return value;
    });
  assert.equal(result.value, value); assert.equal(result.originals, originals); assert.equal(calls, 1);
  const primary = new Error('original before-binding refusal');
  assert.throws(() => admitInstalledModelProviderBinding(moon, 'mock', {bindingOriginals: originals}, () => {throw primary;}),
    cause => cause === primary);
});

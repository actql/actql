import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {modelConfiguration} from './fixtures/composed-infer-effect-input.mjs';
import {readInstalledModelExecution} from '../adapters/host-node/installed-model.mjs';

// Actual fixture and installed reader; constructor/reservation ports are
// explicit controls, not a compiled ABI, Model grant or provider invocation.
test('packed Salesforce composition retains its original Model materials before the Request read', async () => {
  const base = JSON.parse(readFileSync(new URL(
    '../adapters/host-node/fixtures/two-source/two-source.environment.json', import.meta.url), 'utf8'));
  const model = await modelConfiguration(base);
  const prepared = {}, execution = {}, events = [];
  const original = model.installation.executionContracts[0];
  const moon = {
    clientProgramSelectedInferStep(actual) {
      assert.equal(actual, prepared);return 0;
    },
    clientProgramInferModelTaskCid(actual, step) {
      assert.equal(actual, prepared);assert.equal(step, 0);return model.taskCid;
    },
    clientProgramReadInferModelExecution(actual, step, wire, cid) {
      assert.equal(this, moon);assert.equal(actual, prepared);assert.equal(step, 0);
      assert.equal(wire, original.bodyWire);assert.equal(cid, original.cid);
      assert.deepEqual(events, ['reserve']);events.push('read');
      return {$tag: 1, _0: execution};
    },
  };
  const beforeRead = (count, wireAt, containers) => {
    assert.equal(count, 1);assert.equal(wireAt(0), original.bodyWire);
    assert.equal(containers, model.installation.executionContracts.length +
      model.installation.dependencyBodies.length);
    events.push('reserve');
  };
  assert.equal(readInstalledModelExecution(moon, prepared, model.installation,
    undefined, beforeRead).execution, execution);
  assert.deepEqual(events, ['reserve', 'read']);
  assert(Object.isFrozen(model.installation));
  for (const originals of [model.installation.executionContracts,
    model.installation.dependencyBodies]) {
    assert(Object.isFrozen(originals));
    assert(originals.every(Object.isFrozen));
  }
  assert.throws(() => readInstalledModelExecution(moon, prepared,
    {...model.installation}, undefined, beforeRead), {
    name: 'TypeError', message: 'InstalledModelMaterialOriginalUnavailable',
  });
  assert.deepEqual(events, ['reserve', 'read'], 'Mutable copies never enter either port');
});

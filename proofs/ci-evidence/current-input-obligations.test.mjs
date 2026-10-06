// Controlled edits to the actual Git tree test source invalidation, without
// qualifying a runtime, main origin or physical execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readCatalog} from './actions.mjs';
import {gitTree, actionInputs, compareInputs} from './inputs.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
const original = gitTree(root, revision), catalog = readCatalog();
const runtime = {profile: 'controlled-source-observation', unresolved: ['no physical runtime qualification in this fixture']};
const changedTree = path => {
  assert(original.entries.has(path), 'Expected actual tracked input');
  return {entries: original.entries,
    read: input => input === path ? Buffer.concat([original.read(input), Buffer.from('\n// independently changed input\n')]) : original.read(input)};
};
const inputs = (action, tree = original) => actionInputs({tree, revision, action, runtime});

test('the real 30-action source catalog preserves every key for an unrelated Node Host edit', () => {
  assert.equal(catalog.actions.length, 30);
  const candidate = changedTree('adapters/host-node/client-http.mjs');
  for (const action of catalog.actions) {
    const before = inputs(action), after = inputs(action, candidate);
    assert.equal(after.key, before.key, action.id);
    assert.equal(compareInputs(before, after).equal, true, action.id);
    assert.equal(compareInputs(before, after).eligible, false, 'Equal sources do not qualify an unverified runtime');
  }
});

test('a real Session implementation edit invalidates connected actions while model evidence stays independent', () => {
  const candidate = changedTree('src/bounded_execution/session.mbt');
  for (const id of ['model', 'events-model']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.equal(inputs(action, candidate).key, inputs(action).key, id);
  }
  for (const id of ['session-js', 'session-wasm', 'session-native', 'mutations-js']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.notEqual(inputs(action, candidate).key, inputs(action).key, id);
  }
});

test('a real Events theorem edit invalidates all Bridge obligations without invalidating the shared Session mechanism', () => {
  const candidate = changedTree('proofs/events-bridge/Composition.lean');
  for (const id of ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.notEqual(inputs(action, candidate).key, inputs(action).key, id);
  }
  for (const id of ['model', 'session-js', 'mutations-js']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.equal(inputs(action, candidate).key, inputs(action).key, id);
  }
});

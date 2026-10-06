// Real pinned main catalog, independently of candidate recipes and receipts.
import assert from 'node:assert/strict';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree} from './inputs.mjs';
import {catalogPath, readCatalog, initialRegistrationRevision, protectedRegistrationRevision,
  preserveProtectedActions} from './actions.mjs';
import {checkApplications} from './applications.mjs';
import {checkExecutionRecipes, executionRecipes} from './execution-recipes.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const protectedTree = gitTree(root, protectedRegistrationRevision);
const protectedCatalog = JSON.parse(protectedTree.read(catalogPath));
const current = readCatalog();
const bridge = ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native'];

test('the actual pinned main catalog protects all 30 published descriptors and permits additive obligations', () => {
  assert.equal(protectedCatalog.actions.length, 30);
  assert.deepEqual(preserveProtectedActions(protectedCatalog, current).changed, []);
  const added = structuredClone(current);
  added.actions.push({...added.actions.find(action => action.id === 'session-js'), id: 'additional-session-js'});
  assert.deepEqual(preserveProtectedActions(protectedCatalog, added).changed, ['additional-session-js']);
});

test('an edited recipe/catalog pair cannot delete all four published Bridge obligations', () => {
  const removed = {...current, actions: current.actions.filter(action => !bridge.includes(action.id))};
  const recipes = executionRecipes().filter(recipe => !bridge.includes(recipe.action.id));
  // A matching edited pair is insufficient. The former bootstrap missed this.
  assert.equal(checkExecutionRecipes(removed, recipes).length, 26);
  const initial = JSON.parse(gitTree(root, initialRegistrationRevision).read(catalogPath));
  assert.equal(preserveProtectedActions(initial, removed).required.length, 26);
  assert.throws(() => preserveProtectedActions(protectedCatalog, removed), /Removed required action: events-model/u);
});

test('the actual application entrance rejects omissions and weakened Bridge descriptors before transport or proof', async () => {
  const candidates = bridge.map(id => ({...current, actions: current.actions.filter(action => action.id !== id)}));
  for (const id of bridge) for (const alter of [
    action => {action.minimumUnits = 1;}, action => {action.profile = 'unreviewed wider scope';},
    action => {action.premises = ['weakened premise'];}, action => {action.dependencies = [];},
  ]) {
    const changed = structuredClone(current), action = changed.actions.find(value => value.id === id);
    const before = encode(action); alter(action);
    if (encode(action) !== before) candidates.push(changed);
  }
  const candidate = 'f'.repeat(40);
  let transport = 0, proofs = 0;
  for (const catalog of candidates) {
    const tree = {...protectedTree, read: path => path === catalogPath ? Buffer.from(encode(catalog)) : protectedTree.read(path)};
    await assert.rejects(checkApplications({root, context: {candidateRevision: candidate}, runtime: {},
      protectedRevision: protectedRegistrationRevision, entries: [],
      treeAt: revision => revision === candidate ? tree : protectedTree,
      request: async () => {transport++; assert.fail('No transport for removed/changed obligations');},
      prove: () => {proofs++; assert.fail('No proof for removed/changed obligations');},
    }), /Removed required action|Missing action dependency|Changed protected registration/u);
  }
  assert.equal(transport, 0); assert.equal(proofs, 0);
});

test('collector, final consumer and diagnostic acceptance use the same independent protected revision', () => {
  for (const file of ['collect.mjs', 'final.mjs', 'cli.mjs']) {
    const source = readFileSync(new URL(file, import.meta.url), 'utf8');
    assert(source.includes('protectedRegistrationRevision'), file);
    assert(!source.includes('initialRegistrationRevision'), file);
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {readCatalog, preserveProtectedActions} from './actions.mjs';
import {checkExecutionRecipes, executionRecipes, localExecutionSuites} from './execution-recipes.mjs';

const catalog = readCatalog();
const additional = {id: 'local-correlation', fixture: 'src/execution_relation/correlation_wbtest.mbt',
  package: 'src/execution_relation', minimumTests: 2, profile: 'independent finite correlation fixture',
  premises: ['limited fixture domain; no new derived capacity claim'],
  dependencies: ['session-{target}', 'adapter-{target}']};

test('actual runner recipes retain every initial command, target, scope, minimum and dependency', () => {
  const recipes = checkExecutionRecipes(catalog);
  assert.equal(recipes.length, 26);
  assert.equal(recipes.filter(recipe => recipe.role === 'external').length, 1);
  assert.equal(recipes.find(recipe => recipe.action.id === 'model').runId, 'lean');
  for (const recipe of recipes.filter(value => value.role === 'connection')) {
    assert.equal(recipe.coverage.fixture, recipe.action.command[2]);
    assert(recipe.coverage.scopes.length > 0);
  }
});

test('additive local fixtures use the same target loops while preserving all protected obligations', () => {
  // Controlled registration fixture: this does not claim a new production
  // correlation operation was executed or any runtime closure was proved.
  const recipes = executionRecipes([...localExecutionSuites, additional]);
  const candidate = {...catalog, actions: recipes.map(recipe => recipe.action)};
  const comparison = preserveProtectedActions(catalog, candidate);
  assert.deepEqual(comparison.changed, ['local-correlation-js', 'local-correlation-wasm', 'local-correlation-native']);
  assert.equal(checkExecutionRecipes(candidate, recipes).length, 29);
  for (const target of ['js', 'wasm', 'native']) {
    const recipe = recipes.find(value => value.action.id === `local-correlation-${target}`);
    assert.equal(recipe.role, 'local');
    assert.deepEqual(recipe.action.dependencies, [`session-${target}`, `adapter-${target}`]);
  }
});

test('removing or changing a protected registration is refused even with matching candidate recipes', () => {
  const removed = structuredClone(catalog); removed.actions.splice(1, 1);
  assert.throws(() => preserveProtectedActions(catalog, removed));
  for (const change of [
    action => {action.profile = 'UNCHECKED arbitrary inputs';},
    action => {action.minimumUnits = 1;},
    action => {action.premises = ['weakened assumption'];},
    action => {action.dependencies = ['model'];},
  ]) {
    const changed = structuredClone(catalog); change(changed.actions.find(action => action.id === 'nest-kernel-js'));
    assert.throws(() => preserveProtectedActions(catalog, changed), /Changed protected registration/u);
  }
});

test('unsupported additions and omitted executable recipes cannot become fresh evidence', () => {
  const candidate = structuredClone(catalog);
  candidate.actions.push({...candidate.actions[1], id: 'unexecuted-js'});
  assert.throws(() => checkExecutionRecipes(candidate), /inventory differs/u);
  assert.throws(() => checkExecutionRecipes(catalog, executionRecipes().slice(0, -1)), /inventory differs/u);
  assert.throws(() => checkExecutionRecipes(catalog, [...executionRecipes(), executionRecipes()[0]]), /Duplicate execution recipe/u);
});

for (const [field, mutate] of [
  ['command', action => {action.command[2] = 'src/execution_relation/other_wbtest.mbt';}],
  ['target', action => {action.target = 'native'; action.command[4] = 'native';}],
  ['profile', action => {action.profile = 'unchecked wider domain';}],
  ['premises', action => {action.premises = ['unverified'];}],
  ['minimum', action => {action.minimumUnits = 1;}],
  ['dependencies', action => {action.dependencies = [];}],
]) test(`new local ${field} must match its actual execution recipe`, () => {
  const recipes = executionRecipes([...localExecutionSuites, additional]);
  const candidate = {...catalog, actions: structuredClone(recipes.map(recipe => recipe.action))};
  mutate(candidate.actions.find(action => action.id === 'local-correlation-js'));
  assert.throws(() => checkExecutionRecipes(candidate, recipes), /Registration differs/u);
});

test('invalid local package, filters and duplicate fixture identities are rejected before execution', () => {
  for (const suite of [{...additional, package: 'src/other'}, {...additional, filter: 1},
    {...additional, minimumTests: 0}]) assert.throws(() => executionRecipes([...localExecutionSuites, suite]));
  assert.throws(() => executionRecipes([...localExecutionSuites, additional, additional]), /duplicate action/u);
});

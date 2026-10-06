// These recipes are consumed by the actual existing Session runner. The
// requested catalog is checked against them; it cannot invent an execution.
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {connectionSuites, executedConnectionCoverage, nestLocalSuites, targets} from '../bounded-session/evidence.mjs';
import {validateCatalog} from './actions.mjs';
import {bridgeModelAction, bridgeSuite} from '../events-bridge/evidence.mjs';

// Extend this finite fixture registry for a new local obligation. Keep its
// independent expected values in the fixture; no arbitrary execution callbacks
// or operation-specific branches belong in the common runner.
export const localExecutionSuites = Object.freeze([...nestLocalSuites.map(suite => Object.freeze({
  ...suite, package: 'src/execution_relation',
  profile: `${suite.id} existing Nest-specific obligation`,
  premises: ['limited existing fixture domain; no whole-implementation capacity proof'],
  dependencies: [],
})), bridgeSuite]);
const moonPremises = ['MoonBit compiler/runtime', 'finite correspondence domain; kernel and callback premises remain'];
const connectionProfiles = Object.freeze({
  connection: 'reviewed except/intersect all/distinct checked nullable complete rows',
  'nest-connection': 'reviewed nest correlated-parent-major checked nullable keys and two consumers',
});
const command = (selection, target, filter) => ['moon', 'test', selection, '--target', target, '--deny-warn',
  ...(filter ? ['--filter', filter] : [])];

export function executionRecipes(localSuites = localExecutionSuites) {
  const recipes = [{role: 'model', runId: 'lean', action: {id: 'model', kind: 'formal-model', target: 'model',
    command: ['node', 'proofs/bounded-session/check.mjs'], package: null, minimumUnits: 14,
    profile: 'BoundedSession typed claims and audited foundational axioms',
    premises: ['Lean kernel and permitted foundational axioms'], dependencies: []}}];
  recipes.push({role: 'model', runId: 'events-model', action: bridgeModelAction});
  for (const target of targets) {
    for (const [id, packagePath, profile] of [
      ['session', 'src/bounded_execution', 'finite bounded Session correspondence and retained ownership regressions'],
      ['adapter', 'src/connectors/local', 'finite cumulative-to-delta adapter correspondence and Local provider regressions'],
    ]) recipes.push({role: 'common', runId: `${id}-${target}`, action: {
      id: `${id}-${target}`, kind: 'tested-refinement', target, command: command(packagePath, target),
      package: packagePath, minimumUnits: 1, profile, premises: moonPremises, dependencies: ['model'],
    }});
    for (const suite of connectionSuites) {
      // Unknown fixture scopes fail here, before any requested catalog label
      // can be treated as an independently reviewed connection claim.
      const coverage = executedConnectionCoverage(suite.id);
      assert.equal(coverage.fixture, suite.fixture);
      recipes.push({role: 'connection', runId: `${suite.id}-${target}`, coverage, action: {
        id: `${suite.id}-${target}`, kind: 'tested-refinement', target, command: command(suite.fixture, target),
        package: 'src/query_integration', minimumUnits: suite.minimumTests, profile: connectionProfiles[suite.id],
        premises: ['reviewed fixture coverage independent of requested binding',
          'operation-specific meaning, capacity and ownership obligations remain'],
        dependencies: [`session-${target}`, `adapter-${target}`],
      }});
    }
    for (const suite of localSuites) {
      assert(suite && typeof suite.id === 'string' && suite.fixture?.startsWith(`${suite.package}/`), 'Invalid local fixture');
      recipes.push({role: 'local', runId: `${suite.id}-${target}`, action: {
        id: `${suite.id}-${target}`, kind: 'tested-refinement', target, command: command(suite.fixture, target, suite.filter),
        package: suite.package, minimumUnits: suite.minimumTests, profile: suite.profile, premises: suite.premises,
        dependencies: suite.dependencies.map(id => id.replaceAll('{target}', target)),
      }});
    }
  }
  // This action uses the existing isolated mutation executor, not run.mjs.
  recipes.push({role: 'external', runId: 'mutations-js', action: {
    id: 'mutations-js', kind: 'tested-refinement', target: 'js',
    command: ['node', 'proofs/bounded-session/mutations.mjs'], package: null, minimumUnits: 13,
    profile: '13 existing production mutation assertions and exact source restoration',
    premises: ['JS-only mutation detection; compile failure does not qualify',
      'normal restoration checks remain separate required actions'],
    dependencies: ['model', 'session-js', 'adapter-js', 'connection-js', 'nest-connection-js'],
  }});
  validateCatalog({version: 'actql-verification-action-catalog/0.1', family: 'bounded-session',
    actions: recipes.map(recipe => recipe.action)});
  return recipes;
}

export function checkExecutionRecipes(catalog, recipes = executionRecipes()) {
  validateCatalog(catalog);
  const ids = recipes.map(recipe => recipe.action.id);
  assert.equal(new Set(ids).size, ids.length, 'Duplicate execution recipe');
  assert.deepEqual(catalog.actions.map(action => action.id), ids, 'Registered inventory differs from actual execution recipes');
  for (const [index, action] of catalog.actions.entries()) {
    assert.equal(encode(action), encode(recipes[index].action), `Registration differs from actual execution recipe: ${action.id}`);
  }
  return recipes;
}

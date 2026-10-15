import assert from 'node:assert/strict';
import test from 'node:test';
import {productionDependencyClosure, productionPackageImports} from './source-dependency-closure.mjs';

const imports = (path, scope = '') => `import { "actql/actql/${path}" @renamed, }${scope}`;
const closure = sources => productionDependencyClosure('root', name => {
  assert.ok(Object.hasOwn(sources, name), `Missing manifest ${name}`);
  return sources[name];
});

test('production closure retains direct and transitive concrete dependencies', () => {
  assert.deepEqual(closure({root: imports('common'), common: imports('connectors/example'),
    'connectors/example': ''}), ['common', 'connectors/example']);
});

test('test and wbtest dependency subgraphs are excluded without opening their manifests', () => {
  for (const scope of ['test', 'wbtest']) {
    assert.deepEqual(closure({root: imports('common'), common: imports('fixture', ` for "${scope}"`)}), ['common']);
  }
});

test('production blocks after test blocks and duplicate production edges remain visible', () => {
  const source = imports('fixture', ' for "test"') + imports('concrete') +
    imports('concrete', ' for "wbtest"');
  assert.deepEqual(productionPackageImports(source), ['concrete']);
  assert.deepEqual(closure({root: source, concrete: imports('connectors/example'),
    'connectors/example': ''}), ['concrete', 'connectors/example']);
});

test('scope is local to one block and unscoped imports are always production', () => {
  assert.deepEqual(productionPackageImports(imports('a') + imports('b', ' for "test"') +
    imports('c') + imports('d', ' for "wbtest"')), ['a', 'c']);
});

test('comments, alias names, target metadata and imported string spellings are not dependency edges', () => {
  const source = `supported_targets = "+native"
// import { "actql/actql/forbidden" }
/* import { "actql/actql/other" } */
import { "moonbitlang/core/json", "actql/actql/common" @test, }
formatter(ignore: ["import", "for", "test"])
`;
  assert.deepEqual(productionPackageImports(source), ['common']);
});

test('unknown and malformed import scopes fail instead of hiding dependencies', () => {
  for (const source of [imports('a', ' for "unknown"'), imports('a', ' for 1'),
    imports('a', ' for'), 'import { "actql/actql/a"',
    'import { "actql/actql/a" @ }', 'import nope']) {
    assert.throws(() => productionPackageImports(source));
  }
});

test('production cycles terminate and missing production manifests fail closed', () => {
  assert.deepEqual(closure({root: imports('a'), a: imports('b'), b: imports('a')}), ['a', 'b']);
  assert.throws(() => closure({root: imports('missing')}), /Missing manifest missing/);
});

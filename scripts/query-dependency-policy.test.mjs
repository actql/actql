import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {adapterModuleGraph} from './adapter-module-graph.mjs';
import {assertCommonAdapterGraph, assertOpaqueHandles, assertProductionBoundary,
  assertProductionImports, assertPublicBoundary, concreteDependencies,
  conformanceDependencies} from './query-dependency-policy.mjs';

const imported = (name, scope = '') => `import { "actql/actql/${name}" @renamed, }${scope}`;
const manifests = sources => name => {
  assert.ok(Object.hasOwn(sources, name), `Missing test manifest: ${name}`);
  return sources[name];
};
const intended = message => error => error?.code === 'ERR_ASSERTION' && message.test(error.message);

test('test/wbtest imports never become production violations, including transitive composition', () => {
  for (const scope of ['test', 'wbtest']) {
    const source = imported('common') + imported('connectors/example', ` for "${scope}"`) +
      imported('connector_conformance', ` for "${scope}"`);
    assertProductionBoundary('root', manifests({root: source, common: ''}), concreteDependencies);
    assertProductionImports('root', source, conformanceDependencies);
  }
});

test('neutral extraction and alias/format changes preserve production policies', () => {
  for (const common of ['', imported('extracted_helper')]) {
    const sources = {root: imported('common'), common, extracted_helper: ''};
    assertProductionBoundary('root', manifests(sources), concreteDependencies);
  }
  assertProductionBoundary('root', manifests({root: `/* renamed, not an edge */
    import { "actql/actql/helper" @different_alias }`, helper: ''}), concreteDependencies);
});

test('direct and hidden transitive forbidden dependencies fail the policy assertion', () => {
  for (const sources of [
    {root: imported('connectors/example'), 'connectors/example': ''},
    {root: imported('helper'), helper: imported('connectors/example'), 'connectors/example': ''},
  ]) assert.throws(() => assertProductionBoundary('root', manifests(sources), concreteDependencies),
    intended(/Forbidden production dependency: root -> connectors\/example/u));
  for (const scope of ['', ' for "test"', ' for "wbtest"']) {
    // A later unscoped block must never inherit a previous test scope.
    const source = imported('fixture', scope) + imported('connector_conformance');
    assert.throws(() => assertProductionImports('root', source, conformanceDependencies),
      intended(/Forbidden production import: root -> connector_conformance/u));
  }
});

test('opaque API and provider leakage mutations fail their own assertions', () => {
  assertOpaqueHandles('type Ledger\n', ['Ledger']);
  assert.throws(() => assertOpaqueHandles('type Ledger\npub(all) struct Ledger { value : Int }\n', ['Ledger']),
    intended(/Public representation: Ledger/u));
  assert.throws(() => assertPublicBoundary('common', 'pub fn sql() -> DuckDBQuery', /DuckDB/u),
    intended(/Public responsibility leak: common/u));
});

test('actual adapter import closure accepts extraction but rejects hidden Connector/test authority', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-r2-adapter-'));
  const write = (file, source) => {
    const path = join(root, file);
    mkdirSync(join(path, '..'), {recursive: true});
    writeFileSync(path, source);
  };
  try {
    write('adapters/host-common/entry.mjs', 'export {renamed} from "./helper.mjs";');
    write('adapters/host-common/helper.mjs', 'export function renamed() { return 1; }');
    const check = () => assertCommonAdapterGraph(adapterModuleGraph(root, ['adapters/host-common/entry.mjs']));
    check();
    for (const target of ['adapters/connectors/example/owner.mjs', 'adapters/host-common/control.fixture.mjs']) {
      write(target, 'export const value = 1;');
      write('adapters/host-common/helper.mjs', `export {value as renamed} from ${JSON.stringify('../' + target.slice('adapters/'.length))};`);
      assert.throws(check, intended(/(?:Connector implementation|Test authority) in (?:common|product) adapter graph/u));
    }
  } finally { rmSync(root, {recursive: true, force: true}); }
});


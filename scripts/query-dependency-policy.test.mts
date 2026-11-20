import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, relative} from 'node:path';
import {adapterModuleGraph, localModuleGraphInputs} from './adapter-module-graph.mjs';
import {assertCommonAdapterGraph, assertOpaqueHandles, assertProductionBoundary,
  assertProductionImports, assertPublicBoundary, concreteDependencies,
  conformanceDependencies} from './query-dependency-policy.mjs';

const imported = (name: string, scope = '') => `import { "actql/actql/${name}" @renamed, }${scope}`;
const manifests = (sources: Readonly<Partial<Record<string, string>>>) => (name: string) => {
  assert.ok(Object.hasOwn(sources, name), `Missing test manifest: ${name}`);
  return sources[name]!;
};
type UncheckedAssertion = {readonly code?: unknown; readonly message: string};
const intended = (message: RegExp) => (error: unknown) => (error as UncheckedAssertion | null | undefined)?.code === 'ERR_ASSERTION' && message.test((error as UncheckedAssertion).message);

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
  assert.throws(() => assertOpaqueHandles('pub(all) struct Ledger { value : Int }\n', ['Ledger']),
    intended(/Public representation: Ledger/u));
  assert.throws(() => assertPublicBoundary('common', 'pub fn sql() -> DuckDBQuery', /DuckDB/u),
    intended(/Public responsibility leak: common/u));
});

test('actual adapter import closure accepts extraction but rejects hidden Connector/test authority', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-r2-adapter-'));
  const write = (file: string, source: string) => {
    const path = join(root, file);
    mkdirSync(join(path, '..'), {recursive: true});
    writeFileSync(path, source);
  };
  try {
    write('adapters/host-common/entry.mjs', 'export {renamed} from "./helper.mjs";');
    write('adapters/host-common/helper.mjs', 'export function renamed() { return 1; }');
    const check = () => assertCommonAdapterGraph(localModuleGraphInputs(root, ['adapters/host-common/entry.mjs']));
    check();
    write('packages/shared/neutral.mjs', 'export const value = 1;');
    write('adapters/host-common/helper.mjs', 'export {value as renamed} from "../../packages/shared/neutral.mjs";');
    check();
    for (const target of ['adapters/connectors/example/owner.mjs', 'adapters/host-common/control.fixture.mjs',
      'fixtures/control.fixture.mjs', 'packages/shared/owner.test.mjs']) {
      write(target, 'export const value = 1;');
      let specifier = relative(dirname('adapters/host-common/helper.mjs'), target);
      if (!specifier.startsWith('.')) specifier = './' + specifier;
      write('adapters/host-common/helper.mjs', `export {value as renamed} from ${JSON.stringify(specifier)};`);
      const marker = target.startsWith('adapters/connectors/')
        ? 'Connector implementation in common adapter graph: '
        : 'Test authority in product adapter graph: ';
      assert.throws(check, (error: unknown) => (error as UncheckedAssertion | null | undefined)?.code === 'ERR_ASSERTION' &&
        (error as UncheckedAssertion).message.includes(marker + target));
    }
  } finally { rmSync(root, {recursive: true, force: true}); }
});

test('packaging retains its adapter-only projection while policy sees the complete relative closure', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-r2-module-inputs-'));
  const write = (file: string, source: string) => {
    const path = join(root, file);
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, source);
  };
  try {
    write('adapters/host-common/entry.mjs', 'export {value} from "./helper.mjs";');
    write('adapters/host-common/helper.mjs', 'export {value} from "../../packages/shared/neutral.mjs";');
    write('packages/shared/neutral.mjs', 'export {value} from "./values.mjs";');
    // No attempt to resolve or audit a bare external dependency is introduced.
    write('packages/shared/values.mjs', 'export {value} from "@external/not-installed";');
    const entries = ['adapters/host-common/entry.mjs'];
    const packaging = ['adapters/host-common/entry.mjs', 'adapters/host-common/helper.mjs'];
    const inputs = localModuleGraphInputs(root, entries);
    assert.deepEqual(inputs, [...packaging, 'packages/shared/neutral.mjs', 'packages/shared/values.mjs']);
    assertCommonAdapterGraph(inputs);
    assert.deepEqual(adapterModuleGraph(root, [...entries, ...entries]), packaging);
    assert.throws(() => adapterModuleGraph(root, ['packages/shared/neutral.mjs']),
      /IncompleteLocalNodeAdapterGraph/u);
  } finally { rmSync(root, {recursive: true, force: true}); }
});


test('authored TypeScript adapter graph refuses fixture and test authority', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-r2-ts-authority-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const write = (file: string, source: string) => {
    const path = join(root, file);
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, source);
  };
  const entry = 'adapters/host-common/entry.mts';
  write(entry, 'export {value} from "./owner.mjs";');
  write('adapters/host-common/owner.mts', 'export const value = 1;');
  const ordinary = localModuleGraphInputs(root, [entry]);
  assert.deepEqual(ordinary, [entry, 'adapters/host-common/owner.mts']);
  assertCommonAdapterGraph(ordinary);
  for (const [suffix, extension] of [
    ['mts', 'mjs'], ['cts', 'cjs'], ['ts', 'js'], ['tsx', 'jsx'],
  ] as const) {
    for (const kind of ['fixture', 'test']) {
      const stem = `control-${suffix}.${kind}`;
      const target = `adapters/host-common/${stem}.${suffix}`;
      write(target, 'export const value = 1;');
      write(entry, `export {value} from "./${stem}.${extension}";`);
      const graph = localModuleGraphInputs(root, [entry]);
      assert.ok(graph.includes(target), target);
      assert.throws(() => assertCommonAdapterGraph(graph), intended(/Test authority in product adapter graph/u));
    }
  }
});

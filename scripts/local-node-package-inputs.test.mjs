import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {checkHostBundle, generateInstallations, readHostBundles} from './connector-node-bundles.mjs';
import {localNodeAdapterSourceInputs} from './build-local-node-adapters.mjs';
import {adapterModuleGraph} from './adapter-module-graph.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const put = (root, path, content) => {
  mkdirSync(dirname(join(root, path)), {recursive: true});
  writeFileSync(join(root, path), content);
};
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'local-package-inputs-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const manifest = {installation: {
    registration: 'example', revision: 'example/0.1',
    providerBundle: 'connectors/example/host_node', responseHeaders: [],
    assets: ['src/connectors/example/views.json'],
    source: {profileVersion: 'actql-installed-example-source/0.1',
      module: 'adapters/connectors/example/host/source.mjs',
      exports: {check: 'check', identityParts: 'identity', load: 'load'}},
    effect: {profileVersion: 'actql-installed-example-effect/0.1',
      module: 'adapters/connectors/example/host/effect.mjs',
      exports: {check: 'check', identityParts: 'identity', load: 'load'}},
  }};
  const path = join(root, 'src/connectors/example/host-bundle.json');
  const write = () => put(root, 'src/connectors/example/host-bundle.json', JSON.stringify(manifest));
  write();
  put(root, 'src/connectors/example/host_node/moon.pkg',
    'supported_targets = "js"\npkgtype(kind: "foreign_library")\n');
  put(root, 'src/connectors/example/views.json', '{"independent":"declaration"}\n');
  for (const role of ['source', 'effect']) put(root,
    `adapters/connectors/example/host/${role}.mjs`,
    'export function check() {}\nexport function identity() {}\nexport function load() {}\n');
  const table = join(root, 'adapters/connectors-builtin/installations.generated.mjs');
  const generate = () => put(root, 'adapters/connectors-builtin/installations.generated.mjs',
    generateInstallations(readHostBundles(root), table, root));
  generate();
  return {root, manifest, path, write, generate};
}

test('real declared providers supply runtime, adapter and static asset inventory', () => {
  const inputs = localNodePackageInputs(repository);
  assert.deepEqual(inputs.providerBundles.map(entry => entry.name),
    ['calendar', 'gcs', 'github', 'gmail', 'hubspot', 'notion', 'salesforce', 'sheets', 'slack']);
  for (const provider of inputs.providerBundles) {
    assert.ok(inputs.runtimePackages.includes(provider.package));
    assert.ok(inputs.runtimeFiles.includes(provider.file));
  }
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/github/host/installed-github-source.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/github/host/installed-github-effect.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/local/host/installed-local-table.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/sheets/host/installed-sheets.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/snowflake/host/installed-snowflake-source.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/bigquery/host/installed-bigquery-source.mjs'));
  assert.equal(inputs.providerBundles.some(entry => entry.name === 'bigquery'), false,
    'BigQuery uses its original integrated Common, without a fabricated provider bundle');
  // Root entries and their transitive implementation inputs are distinct.
  const table = readFileSync(join(repository, 'adapters/connectors-builtin/installations.generated.mjs'), 'utf8');
  for (const path of ['adapters/connectors/gcs/site/gcs-file-listing.mjs',
    'adapters/connectors/gcs/host/gcs-collection-target.mjs',
    'adapters/connectors/gcs/host/gcs-upload-declaration.mjs',
    'adapters/connectors/snowflake/site/snowflake-sql-read.mjs']) {
    assert.ok(table.includes(`path: ${JSON.stringify(path)}`));
  }
  assert.ok(inputs.dataFiles.includes('adapters/connectors/local/iceberg/process_worker.py'));
  assert.ok(inputs.dataFiles.includes('spec/contracts/actql-local-table-iceberg.json'));
  assert.ok(inputs.dataFiles.includes('src/connectors/github/source-views.json'));
  assert.ok(inputs.dataFiles.includes('src/connectors/github/writes.json'));
  assert.equal(new Set(inputs.runtimeFiles).size, inputs.runtimeFiles.length);
  const packageManifest = JSON.parse(readFileSync(join(repository, 'packages/local-node/package.json')));
  assert.equal(packageManifest.peerDependenciesMeta['@duckdb/node-api'].optional, true);
  assert.equal(packageManifest.dependencies['@duckdb/node-api'], undefined);
});

test('a physical Host installation needs no artificial MoonBit provider bundle', t => {
  const {root, manifest, write, generate} = fixture(t);
  delete manifest.installation.providerBundle;
  manifest.installation.assets.push('adapters/connectors/example/io/worker.py');
  put(root, 'adapters/connectors/example/io/worker.py', '# independent physical worker\n');
  write(); generate();
  const inputs = localNodePackageInputs(root);
  assert.deepEqual(inputs.providerBundles, []);
  assert.ok(!inputs.runtimePackages.includes(undefined));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/example/host/effect.mjs'));
  assert.ok(inputs.dataFiles.includes('adapters/connectors/example/io/worker.py'));
});

test('implementation inventory includes owned transitive imports and physical contracts', t => {
  const {root, manifest, write, generate} = fixture(t);
  put(root, 'adapters/connectors/example/host/helper.mjs', 'export const helper = 1;\n');
  put(root, 'adapters/connectors/example/host/source.mjs',
    'import {helper} from "./helper.mjs";\n' +
    'export function check() {return helper;}\nexport function identity() {}\nexport function load() {}\n');
  const contract = 'spec/contracts/actql-example-storage.json';
  put(root, contract, '{"physical":"independent"}\n');
  manifest.installation.assets.push(contract);
  write(); generate();
  assert.ok(localNodePackageInputs(root).dataFiles.includes(contract));
  const generated = readFileSync(join(root, 'adapters/connectors-builtin/installations.generated.mjs'), 'utf8');
  assert.match(generated, /path: "adapters\/connectors\/example\/host\/helper\.mjs"/);
  assert.match(generated, /path: "spec\/contracts\/actql-example-storage\.json"/);
  // The actual import graph, not an independently maintained module list,
  // refuses a missing transitive implementation before packaging.
  renameSync(join(root, 'adapters/connectors/example/host/helper.mjs'), join(root, 'helper-backup.mjs'));
  assert.throws(generate, /Could not resolve/);
});

test('physical assets refuse foreign paths, missing files, duplicates and symlink targets', t => {
  const {root, manifest, path, write} = fixture(t);
  const worker = 'adapters/connectors/example/io/worker.py';
  put(root, worker, '# independent physical worker\n');
  put(root, 'adapters/connectors/other/worker.py', '# foreign worker\n');
  put(root, 'outside.py', '# outside sentinel\n');
  symlinkSync(join(root, 'outside.py'), join(root, 'adapters/connectors/example/io/linked.py'));
  for (const assets of [[worker, worker], ['adapters/connectors/other/worker.py'],
    ['adapters/connectors/example/io/missing.py'],
    ['adapters/connectors/example/io/../worker.py'],
    ['adapters/connectors/example/io/linked.py'],
    ['adapters/connectors/example/host/effect.mjs']]) {
    manifest.installation.assets = assets;
    write();
    assert.throws(() => checkHostBundle(root, 'example', path), /manifest \(assets\)/);
  }
  assert.equal(readFileSync(join(root, 'outside.py'), 'utf8'), '# outside sentinel\n');
});

test('another checked Host manifest needs no handwritten provider list or Compute manifest', t => {
  const {root} = fixture(t);
  const inputs = localNodePackageInputs(root);
  assert.deepEqual(inputs.providerBundles, [{name: 'example',
    package: 'connectors/example/host_node', file: 'connectors/example/host_node/host_node.js'}]);
  assert.ok(inputs.runtimePackages.includes('connectors/example/host_node'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/example/host/source.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/example/host/effect.mjs'));
  assert.ok(inputs.dataFiles.includes('src/connectors/example/views.json'));
  assert.ok(Object.isFrozen(inputs.runtimePackages));
});

test('a changed declaration cannot pack with a stale installation table', t => {
  const {root, manifest, write, generate} = fixture(t);
  manifest.installation.revision = 'example/0.2';
  write();
  assert.throws(() => localNodePackageInputs(root), /StaleLocalNodeInstallationTable/);
  generate();
  assert.equal(localNodePackageInputs(root).providerBundles.length, 1);
});

test('static assets stay finite, existing and inside their connector package', t => {
  const {root, manifest, path, write} = fixture(t);
  for (const assets of [null, ['src/connectors/example/missing.json'],
    ['src/connectors/example/../outside.json'],
    ['src/connectors/example/views.json', 'src/connectors/example/views.json'],
    ['src/connectors/other/views.json'], ['src/connectors/example/source.mjs']]) {
    manifest.installation.assets = assets;
    write();
    assert.throws(() => checkHostBundle(root, 'example', path), /manifest \(assets\)/);
  }
  put(root, 'outside.json', '{}');
  symlinkSync(join(root, 'outside.json'), join(root, 'src/connectors/example/linked.json'));
  manifest.installation.assets = ['src/connectors/example/linked.json'];
  write();
  assert.throws(() => checkHostBundle(root, 'example', path), /manifest \(assets\)/);
});

test('a connector directory cannot redirect ownership through a symbolic link', t => {
  const {root, path} = fixture(t);
  renameSync(join(root, 'src/connectors/example'), join(root, 'elsewhere'));
  symlinkSync(join(root, 'elsewhere'), join(root, 'src/connectors/example'), 'dir');
  assert.throws(() => checkHostBundle(root, 'example', path), /manifest \(assets\)/);
});

test('published adapter closure retains concrete Local helpers and their same private runtime Owner', async () => {
  const inputs = localNodePackageInputs(repository);
  const graph = adapterModuleGraph(repository, inputs.adapterEntries);
  const copyInputs = await localNodeAdapterSourceInputs({root: repository, inputs});
  for (const name of ['request-preparation-adapter', 'installed-project-mock',
    'installed-project-mock-answers', 'installed-mock-row-effect',
    'declared-project-catalog', 'declared-file-installation']) {
    const path = `adapters/local-node/${name}.mjs`;
    assert.ok(graph.includes(path), name);
    const copied = copyInputs.filter(entry => entry.path === path);
    assert.equal(copied.length, 1);
    assert.equal(copied[0].source, join(repository, path));
    assert.ok(!graph.includes(`adapters/host-node/${name}.mjs`), name);
  }
  // Installation reads the selected project's admitted catalog through the
  // nominal declared-file inventory; the example DATA is not a runtime input.
  const example = 'adapters/local-node/mock-churn-risk-catalogue.mjs';
  assert.ok(!graph.includes(example));
  assert.ok(!copyInputs.some(entry => entry.path === example));
  assert.equal(graph.filter(path => path.endsWith('/ordinary-node-resource-runtime.cjs')).length, 1);
  assert.ok(graph.includes('adapters/host-node/ordinary-node-resource-runtime.cjs'));
});

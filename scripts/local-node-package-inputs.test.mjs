import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {checkHostBundle, generateInstallations, readHostBundles} from './connector-node-bundles.mjs';
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
  assert.deepEqual(inputs.providerBundles.map(entry => entry.name), ['github', 'salesforce']);
  for (const provider of inputs.providerBundles) {
    assert.ok(inputs.runtimePackages.includes(provider.package));
    assert.ok(inputs.runtimeFiles.includes(provider.file));
  }
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/github/host/installed-github-source.mjs'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/github/host/installed-github-effect.mjs'));
  assert.ok(inputs.dataFiles.includes('src/connectors/github/source-views.json'));
  assert.ok(inputs.dataFiles.includes('src/connectors/github/writes.json'));
  assert.equal(new Set(inputs.runtimeFiles).size, inputs.runtimeFiles.length);
  const packageManifest = JSON.parse(readFileSync(join(repository, 'packages/local-node/package.json')));
  assert.equal(packageManifest.peerDependenciesMeta['@duckdb/node-api'].optional, true);
  assert.equal(packageManifest.dependencies['@duckdb/node-api'], undefined);
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

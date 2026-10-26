import assert from 'node:assert/strict';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {checkNodeAssembly, checkHostBundle, readHostBundles, generateInstallations} from './connector-node-bundles.mjs';
import {checkComputeAssembly} from './connector-compute-bundles.mjs';
import {connectorManifestSelection} from './connector-manifest-selection.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {installedConnectorTable, installedEffectTable, installedConnectorFor,
  loadInstalledConnectorModule, loadInstalledEffectModule} from '../adapters/host-node/installed-connectors.mjs';

const put = (root, path, bytes) => {
  mkdirSync(dirname(join(root, path)), {recursive: true});
  writeFileSync(join(root, path), bytes);
};
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'connector-role-projection-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'src/connectors'), {recursive: true});
  put(root, 'scripts/templates/strategy-node.mbt', readFileSync(
    new URL('./templates/strategy-node.mbt', import.meta.url)));
  put(root, 'src/physical_resources/ledger.mbt', readFileSync(
    new URL('../src/physical_resources/ledger.mbt', import.meta.url)));
  return root;
}
function host(root, name, roles) {
  const installation = {registration: name, revision: `${name}/0.1`,
    providerBundle: `connectors/${name}/host_node`, responseHeaders: []};
  put(root, `src/connectors/${name}/host_node/moon.pkg`,
    'supported_targets = "js"\npkgtype(kind: "foreign_library")\n');
  for (const role of roles) {
    const module = `adapters/connectors/${name}/host/${role}.mjs`;
    installation[role] = {profileVersion: `actql-installed-${name}-${role}/0.1`, module,
      exports: {check: 'check', identityParts: 'identity', load: 'load'}};
    put(root, module, 'export function check(value) { return value; }\n' +
      'export function identity(value) { return [value]; }\n' +
      `export function load() { return ${JSON.stringify(`${name}:${role}`)}; }\n`);
  }
  put(root, `src/connectors/${name}/host-bundle.json`, JSON.stringify({installation}));
  return installation;
}
const options = names => ({names, assembly: 'selected_compute', bridge: 'selected_node',
  adapter: 'selected-node', installations: true, nativeRemoteStandard: false});

test('Read-only and Effect-only selection generates no dummy Compute or opposite Host role', async t => {
  const root = fixture(t);
  host(root, 'reader', ['source']);
  host(root, 'writer', ['effect']);
  put(root, 'src/connectors/unselected/compute-bundle.json', 'invalid unselected declaration');
  assert.equal(checkNodeAssembly(root, true, options(['reader', 'writer'])), 0);
  assert.equal(checkNodeAssembly(root, false, options(['reader', 'writer'])), 0);
  const tablePath = join(root, 'adapters/selected-node/installations.generated.mjs');
  const {installedConnectors} = await import(pathToFileURL(tablePath));
  assert.deepEqual(installedConnectors.map(entry => entry.name), ['reader', 'writer']);
  assert.equal(installedConnectors[0].effect, undefined);
  assert.equal(installedConnectors[1].source, undefined);
  assert.doesNotMatch(readFileSync(join(root, 'src/selected_compute/compute.generated.mbt'), 'utf8'), /with_reader|with_writer/);
  const sources = installedConnectorTable(installedConnectors);
  const effects = installedEffectTable(installedConnectors);
  assert.deepEqual([...sources.keys()], ['actql-installed-reader-source/0.1']);
  assert.deepEqual([...effects.keys()], ['actql-installed-writer-effect/0.1']);
  assert.equal((await loadInstalledConnectorModule(sources.values().next().value)).load(), 'reader:source');
  assert.equal((await loadInstalledEffectModule(effects.values().next().value)).load(), 'writer:effect');
  assert.throws(() => installedConnectorFor(sources,
    {version: 'actql-installed-writer-effect/0.1'}), {code: 'InvalidInstalledSourceProfile'});
});

test('explicit empty selection generates empty role projections without reading other manifests', t => {
  const root = fixture(t);
  put(root, 'src/connectors/broken/compute-bundle.json', 'invalid unselected declaration');
  assert.equal(checkNodeAssembly(root, true, options([])), 0);
  assert.equal(checkNodeAssembly(root, false, options([])), 0);
  assert.deepEqual(readHostBundles(root, {names: []}), []);
  assert.doesNotMatch(readFileSync(join(root, 'src/selected_compute/compute.generated.mbt'), 'utf8'), /let mut count/);
  assert.equal(checkComputeAssembly(root, false, {names: [], directory: 'selected_compute'}), 0);
  assert.equal(installedConnectorTable([]).size, 0);
  assert.equal(installedEffectTable([]).size, 0);
});

test('mixed selection projects a genuine Compute-only member independently', t => {
  const root = fixture(t);
  host(root, 'writer', ['effect']);
  put(root, 'src/connectors/local/compute-bundle.json', readFileSync(
    new URL('../src/connectors/local/compute-bundle.json', import.meta.url)));
  put(root, 'src/connectors/local/driver/moon.pkg', '');
  assert.equal(checkNodeAssembly(root, true, options(['writer', 'local'])), 0);
  assert.match(readFileSync(join(root, 'src/selected_compute/compute.generated.mbt'), 'utf8'), /with_local/);
  assert.doesNotMatch(readFileSync(join(root, 'adapters/selected-node/strategy.generated.mjs'), 'utf8'), /strategy-bundle/);
});

test('Local distribution inventory includes each declared Host role only', t => {
  const root = fixture(t);
  host(root, 'writer', ['effect']);
  const table = join(root, 'adapters/connectors-builtin/installations.generated.mjs');
  put(root, 'adapters/connectors-builtin/installations.generated.mjs',
    generateInstallations(readHostBundles(root), table, root));
  const inputs = localNodePackageInputs(root);
  assert.ok(inputs.runtimePackages.includes('connectors/writer/host_node'));
  assert.ok(inputs.adapterEntries.includes('adapters/connectors/writer/host/effect.mjs'));
  assert.ok(!inputs.adapterEntries.some(path => path.includes('/writer/host/source')));
});

test('unknown names, duplicates and Node strategies without Compute refuse before writing', t => {
  const root = fixture(t);
  host(root, 'reader', ['source']);
  mkdirSync(join(root, 'src/connectors/undeclared'));
  assert.deepEqual(connectorManifestSelection(root).map(entry => entry.name), ['reader']);
  for (const names of [['missing'], ['undeclared'], ['reader', 'reader'], ['../reader'], null]) {
    assert.throws(() => checkNodeAssembly(root, true, options(names)), /Invalid explicit|Missing selected/);
    assert.equal(existsSync(join(root, 'src/selected_compute')), false);
  }
  put(root, 'src/connectors/reader/node-bundle.json', '{}');
  assert.throws(() => checkNodeAssembly(root, true, options(['reader'])),
    /Node strategy requires its Compute manifest: reader/);
  assert.equal(existsSync(join(root, 'src/selected_compute')), false);
});

test('Host declarations require a real role and validate every present role', t => {
  const root = fixture(t);
  const valid = host(root, 'example', ['source', 'effect']);
  const path = join(root, 'src/connectors/example/host-bundle.json');
  const {source, effect, ...shared} = valid;
  for (const installation of [shared, {...shared, source: null}, {...shared, effect: null},
    {...shared, source, effect: {}}, {...shared, effect, source: {}},
    {...valid, effect: {...effect, profileVersion: source.profileVersion}}]) {
    writeFileSync(path, JSON.stringify({installation}));
    assert.throws(() => checkHostBundle(root, 'example', path), /Invalid Host bundle manifest/);
  }
});

test('runtime role projections validate opposite declarations without loading them', async () => {
  let sourceLoads = 0, effectLoads = 0;
  const source = {profileVersion: 'actql-installed-example-source/0.1', load: async () => {
    sourceLoads++; return {check() {}, identityParts() {}, load() {}};
  }};
  const effect = {profileVersion: 'actql-installed-example-effect/0.1', load: async () => {
    effectLoads++; return {check() {}, identityParts() {}, load() {}};
  }};
  for (const entry of [{name: 'example'}, {name: 'example', source, effect: null},
    {name: 'example', source: null, effect}, {name: 'example', source: {}, effect}]) {
    for (const project of [installedConnectorTable, installedEffectTable]) {
      assert.throws(() => project([entry]), {code: 'InvalidInstalledConnectorEntry'});
    }
  }
  const entries = [{name: 'reader', source}, {name: 'writer', effect}];
  const sources = installedConnectorTable(entries), effects = installedEffectTable(entries);
  assert.equal(sourceLoads, 0); assert.equal(effectLoads, 0);
  await loadInstalledEffectModule(effects.values().next().value);
  assert.equal(effectLoads, 1); assert.equal(sourceLoads, 0);
  await loadInstalledConnectorModule(sources.values().next().value);
  assert.equal(sourceLoads, 1);
  for (const project of [installedConnectorTable, installedEffectTable]) {
    assert.throws(() => project([...entries, ...entries]), {code: 'InstalledConnectorVersionAmbiguous'});
  }
});

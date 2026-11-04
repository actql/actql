import assert from 'node:assert/strict';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, isAbsolute, join, relative, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import './local-node-declared-exports.test.mjs';
import './external-installed-helper-types.test.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildLocalNodeAdapters, inspectExternalLocalNodeAdapterGraph} from './build-local-node-adapters.mjs';
import {buildExternalLocalNodeRuntime} from './build-runtime-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
function fixture(t, {collision = false, adapterImport, deferAdapterImport = false} = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-external-inventory-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const host = join(root, 'host'); mkdirSync(join(host, 'src'), {recursive: true});
  writeFileSync(join(host, 'moon.mod'), 'name = "fixture/installed_host"\nversion = "0.0.1"\n' +
    'source = "src"\nimport { "actql/actql@0.0.1", "fixture/external_read@0.0.1", "fixture/external_effect@0.0.1", }\n');
  const providers = ['read', 'effect'].map(role => {
    const source = join(root, role);
    cpSync(join(repository, 'scripts/fixtures/external-installed', `external-${role}`), source, {recursive: true});
    return {role, root: source, name: `external_${role}`};
  });
  if (collision) {
    const reader = providers[0];
    for (const prefix of ['src/connectors', 'adapters/connectors']) {
      renameSync(join(reader.root, prefix, reader.name), join(reader.root, prefix, 'duckdb'));
    }
    const path = join(reader.root, 'src/connectors/duckdb/host-bundle.json');
    writeFileSync(path, readFileSync(path, 'utf8').replaceAll('external_read', 'duckdb'));
    reader.name = 'duckdb';
  }
  const applyAdapterImport = () => {
    if (adapterImport !== undefined) {
      const adapter = join(providers[0].root, 'adapters/connectors/external_read/host/installation.mjs');
      const helper = join(dirname(adapter), 'helper.mjs');
      writeFileSync(helper, 'export const independent = 17;\n');
      const target = adapterImport({providers, helper});
      const specifier = isAbsolute(target) ? relative(dirname(adapter), target).split(sep).join('/') : target;
      const prefix = specifier.startsWith('.') || !isAbsolute(target) ? '' : './';
      writeFileSync(adapter, `import ${JSON.stringify(prefix + specifier)};\n` + readFileSync(adapter, 'utf8'));
    }
  };
  if (!deferAdapterImport) applyAdapterImport();
  const inputs = resolveConnectorBuildInputs({target: 'js',
    modules: [{namespace: 'actql/actql', version: '0.0.1', root: repository},
      {namespace: 'fixture/installed_host', version: '0.0.1', root: host},
      ...providers.map(entry => ({namespace: `fixture/external_${entry.role}`, version: '0.0.1', root: entry.root}))],
    host: 'fixture/installed_host', connectors: providers.map(entry => ({name: entry.name,
      module: `fixture/external_${entry.role}`, directory: `src/connectors/${entry.name}`}))});
  checkNodeAssembly(host, true, {buildInputs: inputs, installations: true});
  return {host, inputs, providers, applyAdapterImport};
}

test('external inventory separates exact provider build owners from stable distribution keys', t => {
  const f = fixture(t), inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
  assert.deepEqual(inputs.providerBundles.map(entry => entry.name), ['external_read', 'external_effect']);
  for (const entry of f.providers) {
    const name = `connectors/${entry.name}/host_node`;
    const runtime = inputs.runtimeInputs.find(value => value.package === name);
    assert.equal(runtime.moduleRoot, entry.root);
    assert.equal(runtime.target, `src/${name}`);
    assert.equal(runtime.qualifiedPackage, `fixture/external_${entry.role}/${name}`);
    assert.equal(runtime.compiledFile, `fixture/external_${entry.role}/${name}/host_node.js`);
    assert.equal(runtime.file, `${name}/host_node.js`);
    assert.ok(inputs.adapterInputs.some(value => value.ownerRoot === entry.root &&
      value.source.startsWith(entry.root) && value.destination.startsWith(`adapters/connectors/${entry.name}/`)));
    assert.ok(inputs.dataInputs.some(value => value.ownerRoot === entry.root &&
      value.destination.startsWith(`src/connectors/${entry.name}/`)));
  }
  const core = inputs.runtimeInputs.find(entry => entry.package === 'connectors_builtin_node');
  assert.equal(core.namespace, 'actql/actql');
  assert.ok(Object.isFrozen(inputs.runtimeInputs));
  const packaged = inputs.installationTable.render(join(f.host, 'package'));
  assert.ok(!packaged.includes(f.host));
  assert.match(packaged, /\.\.\/connectors\/external_read\/host\/installation\.mjs/);
  assert.match(packaged, /\.\.\/connectors\/external_effect\/host\/installation\.mjs/);
  assert.throws(() => inputs.destinationForAdapter(join(f.providers[0].root, 'unlisted.mjs')),
    /UndeclaredLocalNodeAdapterInput/);
});

test('external production cannot reuse a reviewed Core legacy context before compilation', async t => {
  const f = fixture(t), inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
  const inventory = JSON.parse(readFileSync(join(repository, 'scripts/owned-contract-version-legacy.json'), 'utf8'));
  const reviewed = inventory.entries.find(entry => entry.path.startsWith('src/') &&
    entry.path.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/u.test(entry.path));
  assert(reviewed);
  // Identical bytes/context have a different production owner. They cannot
  // inherit Core's reviewed source admission through a compiled token match.
  writeFileSync(join(f.providers[0].root, 'src/connectors/external_read/host_node/copied.mbt'),
    readFileSync(join(repository, reviewed.path)));
  await assert.rejects(buildExternalLocalNodeRuntime({inputs,
    destination: join(f.host, 'distribution'), compiledDirectory: join(f.host, 'compiled')}),
  /Unadmitted external source contract contexts/u);
});

test('external contract checks follow owned adapter helpers without traversing unrelated package caches', async t => {
  const f = fixture(t, {adapterImport: ({helper}) => helper});
  const provider = f.providers[0].root;
  const metadata = join(provider, 'moon.mod');
  writeFileSync(metadata, readFileSync(metadata, 'utf8').replace('source = "src"', 'source = "."'));
  cpSync(join(provider, 'src/connectors'), join(provider, 'connectors'), {recursive: true});
  const packagePath = join(provider, 'connectors/external_read/host_node/moon.pkg');
  writeFileSync(packagePath, readFileSync(packagePath, 'utf8') +
    '\nimport { "fixture/external_read/unavailable_test", } for "test"\n');
  // A source='.' package can coexist with cache/dependency trees and unrelated
  // links. Only the compiler's declared package closure is production input.
  for (const name of ['_build', '.mooncakes', 'node_modules']) symlinkSync('/unselected-cache', join(provider, name));
  const inventory = JSON.parse(readFileSync(join(repository, 'scripts/owned-contract-version-legacy.json'), 'utf8'));
  const token = inventory.entries.find(entry => entry.path.startsWith('src/') &&
    entry.path.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/u.test(entry.path)).token;
  writeFileSync(join(provider, 'adapters/connectors/external_read/host/helper.mjs'),
    `export const originalVersion = ${JSON.stringify(token)};\n`);
  const inputs = localNodePackageInputs(f.host, {buildInputs: resolveConnectorBuildInputs({
    target: 'js', modules: f.inputs.modules.map(({namespace, version, root}) => ({namespace, version, root})),
    host: f.inputs.host.namespace,
    connectors: f.providers.map(entry => ({name: entry.name, module: `fixture/external_${entry.role}`,
      directory: `src/connectors/${entry.name}`})),
  })});
  await assert.rejects(buildExternalLocalNodeRuntime({inputs,
    destination: join(f.host, 'distribution'), compiledDirectory: join(f.host, 'compiled')}),
  /Unadmitted external source contract contexts/u);
});

test('external provider cannot replace an existing common Host runtime destination', t => {
  const f = fixture(t, {collision: true});
  assert.throws(() => localNodePackageInputs(f.host, {buildInputs: f.inputs}),
    /ConflictingLocalNodeRuntime:connectors\/duckdb\/host_node/);
});

test('external distribution refuses a stale table and another composition root', t => {
  const f = fixture(t);
  assert.throws(() => localNodePackageInputs(repository, {buildInputs: f.inputs}), /InvalidLocalNodeBuildRoot/);
  writeFileSync(join(f.host, 'adapters/connectors-builtin/installations.generated.mjs'), 'export const installedConnectors = [];\n');
  assert.throws(() => localNodePackageInputs(f.host, {buildInputs: f.inputs}), /StaleLocalNodeInstallationTable/);
});

test('external adapter graph preserves own helpers and generated installation edges', async t => {
  const f = fixture(t, {adapterImport: ({helper}) => helper});
  const inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
  const graph = await inspectExternalLocalNodeAdapterGraph(inputs);
  assert.ok(Object.keys(graph.metafile.inputs).some(path => path.endsWith('/external_read/host/helper.mjs')));
  assert.ok(Object.keys(graph.metafile.inputs).some(path => path.endsWith('/external_effect/host/installation.mjs')));
});

test('cross-owner adapter and runtime imports refuse before a producer-relative path can be copied', async t => {
  for (const target of [
    () => join(repository, 'adapters/host-common/runtime-result.mjs'),
    () => join(repository, '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'),
    ({providers}) => join(providers[1].root, 'adapters/connectors/external_effect/host/installation.mjs'),
  ]) {
    // Admit the ordinary fixture inventory first. The tested inspector must
    // reject the later foreign edge even when no compiled Core runtime exists;
    // setup graph discovery must not turn this into a missing-file assertion.
    const f = fixture(t, {adapterImport: target, deferAdapterImport: true});
    const inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
    f.applyAdapterImport();
    await assert.rejects(inspectExternalLocalNodeAdapterGraph(inputs), /CrossOwnerLocalNodeAdapterImport/);
  }
});

test('external adapter cannot import a public package absent from the distribution dependency set', async t => {
  const f = fixture(t, {adapterImport: () => '@actql/run-host-core'});
  const inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
  await assert.rejects(inspectExternalLocalNodeAdapterGraph(inputs), /UndeclaredLocalNodeDependency/);
});

test('copying preserves an external author own packages/sdk helper path', async t => {
  const f = fixture(t, {adapterImport: ({providers}) => {
    const helper = join(providers[0].root, 'adapters/connectors/external_read/packages/sdk/index.mjs');
    mkdirSync(dirname(helper), {recursive: true});
    writeFileSync(helper, 'export const independentlyOwned = 19;\n');
    return helper;
  }});
  const inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
  const destination = join(f.host, 'package');
  await buildLocalNodeAdapters({root: f.host, inputs, destination});
  await buildLocalNodeAdapters({root: f.host, inputs, destination, check: true});
  const copied = readFileSync(join(destination,
    'adapters/connectors/external_read/host/installation.mjs'), 'utf8');
  assert.ok(copied.startsWith('import "../packages/sdk/index.mjs";\n'));
  assert.equal(readFileSync(join(destination,
    'adapters/connectors/external_read/packages/sdk/index.mjs'), 'utf8'),
  'export const independentlyOwned = 19;\n');
});


test('external providers cannot import the Core-only source preparation export', async t => {
  const manifest = JSON.parse(readFileSync(join(repository, 'packages/sdk/package.json'), 'utf8'));
  assert.equal(manifest.exports['./_internal/source-preparation'], './internal/private-source-preparation.mjs');
  for (const name of ['@actql/sdk/_internal/source-preparation', '@actql/sdk/_internal/source-preparation/extra']) {
    const f = fixture(t, {adapterImport: () => name});
    const inputs = localNodePackageInputs(f.host, {buildInputs: f.inputs});
    await assert.rejects(inspectExternalLocalNodeAdapterGraph(inputs), /UndeclaredLocalNodeDependency/);
  }
});

// Execute the authored load and its actual local helper bodies. Public helper
// imports are explicit ports here: this checks fixture wiring, not Common,
// Account, Resource, transport or packed Host acceptance.
async function externalFixtureLoader(role, ports) {
  const {parse} = await import('acorn');
  const directory = join(repository, 'scripts/fixtures/external-installed', `external-${role}`);
  const source = readFileSync(join(directory,
    `adapters/connectors/external_${role}/host/installation.mjs`), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const functions = tree.body.map(node => node.type === 'ExportNamedDeclaration'
    ? node.declaration : node).filter(node => node?.type === 'FunctionDeclaration');
  assert.equal(functions.filter(node => node.id.name === 'load').length, 1);
  const values = {registration: `external_${role}`, revision: `external_${role}/0.1`,
    operation: role === 'read' ? 'external_read:records:read' : 'external_effect:events:create',
    origin: `https://external-${role}.fixture.invalid`, isAbsolute,
    viewsUrl: pathToFileURL(join(directory, 'src/connectors/external_read/source-views.json')),
    assets: pathToFileURL(join(directory, 'src/connectors/external_effect') + sep),
    fail: code => {throw Object.assign(new Error(code), {code});},
    text: value => typeof value === 'string' && value.length > 0,
    exact: (value, keys) => value !== null && typeof value === 'object' &&
      !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0'),
    cid: () => 'sha256:' + 'd'.repeat(64), ...ports};
  return Function(...Object.keys(values),
    functions.map(node => source.slice(node.start, node.end)).join('\n') + '\nreturn load;')(
    ...Object.values(values));
}

for (const role of ['read', 'effect']) {
  test(`external ${role} fixture consumes its same bound construction original`, async () => {
    const declared = Object.freeze({catalog_cid: 'sha256:' + 'a'.repeat(64)});
    const declaration = Object.freeze({original: 'declaration'});
    const environment = Object.freeze({wire: '{"original":"environment"}'});
    const authorization = Object.freeze({context: Object.freeze({contextCid: 'sha256:' + 'b'.repeat(64)})});
    const site = Object.freeze({credential: {}, callResource() {}, close() {return true;}});
    const adapter = Object.freeze({original: `${role}-adapter`});
    const mapping = Object.freeze({resource: 'events', target: 'events',
      mappingRef: 'mapping:events.v1', mappingCid: 'sha256:' + 'c'.repeat(64), body: '{}'});
    const specification = Object.freeze({resourceOrigin: `https://external-${role}.fixture.invalid`,
      namespaceId: 'fixture', environment: 'fixture', siteKey: 'fixture', siteGeneration: 1,
      credentialAuthorityId: 'fixture', credentialKeyId: 'fixture',
      credentialPrivateKeyPath: '/fixture/key.pem', journalRoot: '/fixture/journal'});
    const calls = [], legacy = [];
    const prepared = Object.freeze({declaration, declared, environment});
    const construction = Object.freeze({
      configurationReader: Object.freeze({
        async readOriginalText(url) {calls.push('original-text'); return readFileSync(url, 'utf8');},
        async readJson(path, options) {
          assert.equal(path, '/fixture/site.json'); assert.equal(options.maxBytes, 16384);
          calls.push('original-site'); return specification;
        },
      }),
      prepareAuthoredDeclaration(wire) {
        assert.equal(JSON.parse(wire).views[0].resource, role === 'read' ? 'records' : 'events');
        calls.push('declaration'); return prepared;
      },
      prepareMappings(wire, writes) {
        assert.equal(typeof wire, 'string'); assert.equal(writes[0].resource, 'events');
        assert.ok(Object.isFrozen(writes) && Object.isFrozen(writes[0]) &&
          Object.isFrozen(writes[0].sources) && writes[0].sources.every(Object.isFrozen));
        calls.push('mappings'); return Object.freeze({...prepared, mappings: Object.freeze([mapping])});
      },
      async openRowSite(options) {
        assert.equal(options.profile, specification);
        assert.equal(options.accountConfiguration, '{"original":"account"}');
        calls.push('site'); return Object.freeze({site, authorization});
      },
      async createRowSource(options) {
        assert.equal(typeof options.readPages, 'function');
        for (const name of ['moon', 'declaration', 'declared', 'environmentWire', 'site', 'authorization']) {
          assert.equal(Object.hasOwn(options, name), false, name);
        }
        calls.push('source'); return adapter;
      },
      async createRowEffect(options) {
        assert.equal(options.driver.writeOperation(), 'external_effect:events:create');
        for (const name of ['moon', 'environmentWire', 'site', 'authorization', 'mappings']) {
          assert.equal(Object.hasOwn(options, name), false, name);
        }
        calls.push('effect'); return adapter;
      },
    });
    const load = await externalFixtureLoader(role, {
      checked: value => value, rowSourceCheckEnvironment: () => environment,
      rowSourceMapping: () => mapping,
      async readFile(path, encoding) {
        if (typeof path === 'string') return Buffer.from(JSON.stringify(specification));
        return readFileSync(path, encoding);
      },
      async installRowSourceAuthorization() {legacy.push('authorization'); return authorization;},
      async openRowSourceCredentialSite() {legacy.push('site'); return site;},
      async createInstalledRowSource() {legacy.push('source'); return {unbound: true};},
      async createInstalledRowEffect() {legacy.push('effect'); return {unbound: true};},
      async retainInstalledHostInitializationFailure(cause) {return cause;},
    });
    const result = await load({version: role === 'read'
      ? 'actql-installed-external-read-source/0.1' : 'actql-installed-external-effect/0.1',
      connectorId: 'fixture', accountConfigurationWire: '{"original":"account"}',
      siteProfilePath: '/fixture/site.json'}, {
      root: '/fixture', principalId: 'fixture', baseEnvironmentWire: '{}',
      moon: {clientProgramRowSourceRestoreDeclaration: () => declaration,
        clientProgramRowSourceDeclarationJson: () => JSON.stringify(declared)},
      providerMoon: {externalReadRequestJson() {}, externalReadPageJson() {},
        externalEffectRequestJson() {}, externalEffectObservationJson() {}},
      runtimeBundleCid: 'sha256:' + 'e'.repeat(64), construction,
    });
    assert.equal(result, adapter, 'Return only the same bound constructor original');
    assert.deepEqual(legacy, [], 'The installed loader supplies the construction owner');
    assert.deepEqual(calls, role === 'read'
      ? ['original-site', 'original-text', 'declaration', 'site', 'source']
      : ['original-site', 'original-text', 'declaration', 'original-text', 'mappings', 'site', 'effect']);
  });
}

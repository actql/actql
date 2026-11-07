import assert from 'node:assert/strict';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, isAbsolute, join, relative, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {EventEmitter} from 'node:events';
import {Readable, Writable} from 'node:stream';
import {types, types as nodeTypes} from 'node:util';
import {syncBuiltinESMExports} from 'node:module';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import {createHash} from 'node:crypto';
import './local-node-declared-exports.test.mjs';
import './external-installed-helper-types.test.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildLocalNodeAdapters, inspectExternalLocalNodeAdapterGraph} from './build-local-node-adapters.mjs';
import {buildExternalLocalNodeRuntime} from './build-runtime-packages.mjs';
import {ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames} from '../adapters/host-common/http-exchange.mjs';
import {httpsCredentialResponseHeaderByteLimit, httpsCredentialAuthorizationPrefix,
  httpsCredentialResponseReadQuantum} from '../adapters/site-node/https-credential-resource.mjs';
import {canonicalJson} from '../adapters/host-node/local-account-config.mjs';
import {localContractLimits} from '../adapters/host-node/local-values-plan.mjs';
import {invokeScopedCredentialOperation} from '../adapters/host-common/owned-invocation-context.mjs';
import {prepareInstalledStandardCreatePlanRecipe, prepareInstalledEffectManagedPlan}
  from '../adapters/host-node/installed-effect-plan.mjs';

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
    cid: () => 'sha256:' + 'd'.repeat(64), createHash, nodeTypes, ...ports};
  return Function(...Object.keys(values),
    functions.map(node => source.slice(node.start, node.end)).join('\n') + '\nreturn load;')(
    ...Object.values(values));
}

// Source component only: actual standard driver/composer/Plan functions with
// explicit typed Core ports. No Resource, Common ABI or ordinary acceptance.
async function assertExternalStandardPlan(options, profile) {
  const {parse} = await import('acorn');
  const source = readFileSync(join(repository, 'adapters/host-node/installed-row-effect.mjs'), 'utf8');
  const tree = parse(source, {ecmaVersion:'latest',sourceType:'module'});
  const node = tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'deriveInstalledRowWrite');
  const derive = Function('createHash','nodeTypes','canonicalJson','ownHttpRequest','ownRequestHeaders',
    'ownResponseHeaderNames','invokeScopedCredentialOperation','localContractLimits',
    `return (${source.slice(node.start,node.end)});`)(createHash,nodeTypes,canonicalJson,
      ownHttpRequest,ownRequestHeaders,ownResponseHeaderNames,invokeScopedCredentialOperation,localContractLimits);
  const standard = derive(options.write, 'external_effect');
  const quantities = Array.from({length:5},()=>Object.freeze({}));
  const capture = Object.freeze({}), request = Object.freeze({}), write = Object.freeze({});
  const originalPlan = Object.freeze({}), demand = Object.freeze({});
  const ok = value => ({$tag:1,_0:value});
  const moon = {
    clientProgramInstalledStandardCreateRequestRecipeCapacities(original) {
      assert.equal(this,moon); assert.equal(original,profile); return ok(quantities);
    },
    clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare(operation, originals) {
      assert.equal(this,moon);assert.equal(operation,'external_effect:events:create');
      assert.deepEqual(originals,quantities.slice(0,2));return ok(capture);
    },
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, original, transfer, physical) {
      assert.equal(this,moon);assert.equal(operation,'external_effect:events:create');
      if(original===quantities[2]){assert.equal(transfer,0n);assert.equal(physical,false);return ok(request);}
      assert.equal(original,quantities[3]);assert.ok(transfer>0n);assert.equal(physical,true);return ok(write);
    },
    clientProgramEffectAcquisitionCount:()=>0,
    clientProgramInstalledEffectOperationDemandWithControlsPrepare(p, stage, effect, members, rows, controls) {
      assert.equal(p,prepared);assert.equal(stage,0);assert.equal(effect,'create');
      // Capture and cold recovery are distinct constructor occurrences. Both
      // retain the SAME quoted extent; recovery cannot reuse capture's slot.
      assert.equal(members.length,2);
      assert.strictEqual(members[0],capture);assert.strictEqual(members[1],capture);
      assert.deepEqual(rows,[request,write]);
      assert.equal(controls,quantities[4]);return ok(demand);
    },
    clientProgramInstalledEffectManagedPlanPrepare(...args) {
      assert.equal(args[0],prepared);assert.equal(args[1],identity);
      assert.deepEqual(args.at(-1),[demand]);return ok(originalPlan);
    },
  };
  const recipe = prepareInstalledStandardCreatePlanRecipe({moon,providerMoon:options.providerMoon,
    construction:standard.construction,credentialSite:{construction:{limits:{maxSecretBytes:4096},scope:{},issuer:{}}},
    limits:{maxWireBytes:4096,maxNodes:32,maxDepth:4},resourceTextUnits:6});
  assert.deepEqual(recipe.captureConstruction,{operationIndex:0});
  assert.deepEqual(recipe.recoveryConstruction,{operationIndex:1});
  assert.notStrictEqual(recipe.captureConstruction,recipe.recoveryConstruction);
  for(const entry of recipe.memberOperations) assert.strictEqual(entry.extent,capture);
  const prepared = Object.freeze({}),identity = Object.freeze({}),member = Object.freeze({effectId:'create'});
  const plan = prepareInstalledEffectManagedPlan({moon,facts:{prepared,identity},
    inputs:{installedContracts:{},values:'original-values'},unit:{stageIndex:0},members:[member],
    recipeFor(original){assert.equal(original,member);return recipe;}});
  assert.equal(plan,originalPlan);
  const value={key:'original-key',note:'é\r\n😀'};
  const selected=standard.driver.prepareRequest({member:{kind:'create',resource:'events'},value});
  assert.equal(selected.requestCid,`sha256:${createHash('sha256').update('external_effect:POST:/events\0')
    .update(JSON.stringify(value)).digest('hex')}`);
  assert.equal(selected.request.key,value.key);
  assert.deepEqual(standard.driver.requestFacts(selected.request).value,value);
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
    const implementation = Object.freeze({capacity: {}, runAcquisitionLimits: {maxBindings: 2, maxSecretBytes: 4096}});
    const reader = Object.freeze({original: 'reader'});
    const nativeProfile = Object.freeze({original:'native-profile'}), nativeQuantity=Object.freeze({});
    const provider = {
      externalReadRequestJson() {},externalReadPageJson() {},
      externalEffectRequestJson(key,note) {assert.equal(this,provider);return JSON.stringify({body:JSON.stringify({key,note})});},
      externalEffectObservationJson() {assert.equal(this,provider);return '{"kind":"unclassified-response"}';},
      installedStandardCreateConstructionProfile() {assert.equal(this,provider);return nativeProfile;},
      installedStandardCreateHttpLimits() {assert.equal(this,provider);return [4096,4096,16,3];},
      externalEffectDriverConstructionCapacity(units) {assert.equal(this,provider);assert.ok(units>0n);return nativeQuantity;},
    };
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
      sourceReaderImplementation() {calls.push('implementation'); return implementation;},
      createSourceReader(options) {
        assert.equal(options.implementation, implementation);
        assert.equal(typeof options.preparePageReader, 'function');
        calls.push('reader'); return reader;
      },
      async openRowSite(options) {
        assert.equal(options.profile, specification);
        assert.equal(options.accountConfiguration, '{"original":"account"}');
        calls.push('site'); return Object.freeze({site, authorization});
      },
      async createRowSource(options) {
        assert.equal(options.providerReader, reader);
        assert.equal(Object.hasOwn(options, 'readPages'), false);
        for (const name of ['moon', 'declaration', 'declared', 'environmentWire', 'site', 'authorization']) {
          assert.equal(Object.hasOwn(options, name), false, name);
        }
        calls.push('source'); return adapter;
      },
      prepareEffectDriverConstruction(projection) {
        assert.equal(this,construction);assert.equal(projection.capacity(),nativeQuantity);
        calls.push('effect-construction');
        // Original methods/receiver survive reentry before projection.
        provider.externalEffectRequestJson=()=>assert.fail('No late mutable native request lookup');
        provider.installedStandardCreateConstructionProfile=()=>assert.fail('No late native profile lookup');
        return projection.project();
      },
      async createRowEffect(options) {
        assert.equal(options.driver,undefined);
        assert.equal(options.write.operation,'external_effect:events:create');
        await assertExternalStandardPlan(options,nativeProfile);
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
      providerMoon: provider,
      runtimeBundleCid: 'sha256:' + 'e'.repeat(64), construction,
    });
    assert.equal(result, adapter, 'Return only the same bound constructor original');
    assert.deepEqual(legacy, [], 'The installed loader supplies the construction owner');
    assert.deepEqual(calls, role === 'read'
      ? ['original-site', 'original-text', 'declaration', 'implementation', 'site', 'reader', 'source']
      : ['original-site', 'original-text', 'declaration', 'original-text', 'mappings', 'site', 'effect-construction', 'effect']);
  });
}

for (const role of ['read', 'effect']) {
  test(`external ${role} fixture refuses missing construction before any acquisition`, async () => {
    const load = await externalFixtureLoader(role, {
      readFile: () => assert.fail('No configuration or declaration before its construction owner'),
      installRowSourceAuthorization: () => assert.fail('No independent authorization'),
      openRowSourceCredentialSite: () => assert.fail('No independent Site'),
    });
    await assert.rejects(load({}, {}), {code: role === 'read'
      ? 'ExternalReadConstructionUnavailable' : 'ExternalEffectConstructionUnavailable'});
  });
}

test('external read fixture retains its bound managed reader and original page protocol', async () => {
  const declared = Object.freeze({catalog_cid: 'sha256:' + 'a'.repeat(64)});
  const specification = Object.freeze({resourceOrigin: 'https://external-read.fixture.invalid',
    namespaceId: 'fixture', environment: 'fixture', siteKey: 'fixture', siteGeneration: 1,
    credentialAuthorityId: 'fixture', credentialKeyId: 'fixture',
    credentialPrivateKeyPath: '/fixture/key.pem', journalRoot: '/fixture/journal'});
  const authorization = Object.freeze({context: {contextCid: 'sha256:' + 'b'.repeat(64)}});
  const implementation = Object.freeze({capacity: {},
    runAcquisitionLimits: Object.freeze({maxBindings: 2, maxSecretBytes: 4096})});
  const reader = Object.freeze({original: 'managed-reader'}), adapter = Object.freeze({original: 'adapter'});
  const calls = [], bodies = [Buffer.from('first-original'), Buffer.from('second-original')];
  let preparePageReader;
  const construction = {
    configurationReader: {async readJson() {return specification;}, async readOriginalText() {return '{}';}},
    prepareAuthoredDeclaration() {return {declared};},
    sourceReaderImplementation(options) {
      assert.equal(options.columnCount, 2);
      assert.equal(options.limits.maxResponseBytes, 4096);
      assert.equal(options.limits.maxTotalResponseBytes, 8192);
      assert.equal(options.limits.maxPages, 2);
      assert.equal(options.limits.maxRows, 2);
      assert.equal(options.limits.maxTotalRows, 4);
      calls.push('implementation'); return implementation;
    },
    async openRowSite(options) {
      assert.equal(options.runAcquisitionLimits, implementation.runAcquisitionLimits);
      calls.push('site'); return {site: {}, authorization};
    },
    createSourceReader(options) {
      assert.equal(options.implementation, implementation);
      assert.equal(options.operation, 'external_read:records:read');
      preparePageReader = options.preparePageReader;
      calls.push('reader'); return reader;
    },
    async createRowSource(options) {
      assert.equal(options.providerReader, reader);
      assert.equal(Object.hasOwn(options, 'readPages'), false);
      calls.push('source'); return adapter;
    },
  };
  const load = await externalFixtureLoader('read', {});
  const projections = [];
  const providerMoon = {
    externalReadRequestJson(page) {return JSON.stringify({path: `/records?page=${page}`});},
    externalReadPageJson(body, page) {
      assert.equal(body, bodies[page]); projections.push(page);
      return JSON.stringify({rows: [{id: page === 0 ? 'first' : 'second', amount: page + 1}],
        next: page === 0 ? 1 : null});
    },
  };
  assert.equal(await load({version: 'actql-installed-external-read-source/0.1', connectorId: 'fixture',
    accountConfigurationWire: '{}', siteProfilePath: '/fixture/site.json'},
  {construction, providerMoon, installation: {responseHeaders: []}}), adapter);
  assert.deepEqual(calls, ['implementation', 'site', 'reader', 'source']);
  const pages = preparePageReader({resource: 'records', columns: ['id', 'amount']});
  for (const pageIndex of [0, 1]) {
    const request = pages.fetchPage({pageIndex});
    assert.deepEqual(request, {method: 'GET', path: '/records', query: [['page', String(pageIndex)]]});
    assert.equal(ownHttpRequest(request).target, `/records?page=${pageIndex}`);
    assert.deepEqual(pages.decodePage({accepted: true, statusCode: 200, body: bodies[pageIndex]}, {pageIndex}),
      {rows: [{id: pageIndex === 0 ? 'first' : 'second', amount: pageIndex + 1}], done: pageIndex === 1});
  }
  assert.deepEqual(projections, [0, 1]);
  assert.throws(() => preparePageReader({resource: 'foreign'}), {code: 'UndeclaredExternalReadResource'});
  assert.throws(() => pages.decodePage({accepted: false, statusCode: 503, body: bodies[0]}, {pageIndex: 0}),
    {code: 'ExternalReadProviderRejected'});
  providerMoon.externalReadRequestJson = () => JSON.stringify({refused: 'InvalidExternalReadPage'});
  assert.throws(() => pages.fetchPage({pageIndex: 2}), {code: 'InvalidExternalReadPage'});
  providerMoon.externalReadPageJson = () => JSON.stringify({refused: 'InvalidExternalReadPage'});
  assert.throws(() => pages.decodePage({accepted: true, statusCode: 200, body: bodies[0]}, {pageIndex: 0}),
    {code: 'InvalidExternalReadPage'});
});

for (const missing of ['sourceReaderImplementation', 'createSourceReader']) {
  test(`external read fixture refuses missing ${missing} before acquiring its Site`, async () => {
    const load = await externalFixtureLoader('read', {});
    const construction = {prepareAuthoredDeclaration() {assert.fail('No declaration');},
      openRowSite() {assert.fail('No Site');}, createRowSource() {assert.fail('No adapter');},
      sourceReaderImplementation() {assert.fail('No implementation');},
      createSourceReader() {assert.fail('No reader');},
      configurationReader: {readOriginalText() {assert.fail('No text');}, readJson() {assert.fail('No configuration');}}};
    delete construction[missing];
    await assert.rejects(load({}, {construction}), {code: 'ExternalReadConstructionUnavailable'});
  });
}

async function originalExternalTransportReceiver() {
  const {parse} = await import('acorn');
  const fixture = readFileSync(join(repository, 'scripts/fixtures/external-installed/consumer.mjs'), 'utf8');
  const resource = readFileSync(join(repository, 'adapters/site-node/https-credential-resource.mjs'), 'utf8');
  const declaration = (source, name) => parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .find(node => node?.type === 'FunctionDeclaration' && node.id.name === name);
  const transport = declaration(fixture, 'captureFixtureTransport');
  const receiver = declaration(resource, 'receive');
  assert(transport && receiver);
  // Execute both original bodies. Node HTTP/stream ports are explicit here;
  // this does not issue Account, Credential, Common or physical socket ACKs.
  const capture = Function('assert', 'https', 'http', 'net', 'tls', 'EventEmitter',
    'Readable', 'Writable', 'syncBuiltinESMExports',
    `${fixture.slice(transport.start, transport.end)}; return captureFixtureTransport;`)(
    assert, https, http, net, tls, EventEmitter, Readable, Writable, syncBuiltinESMExports);
  const receive = Function('httpsRequest', 'httpsCredentialResponseHeaderByteLimit',
    'httpsCredentialAuthorizationPrefix', 'Buffer', 'types', 'nativePromiseThen',
    'httpsCredentialResponseReadQuantum', 'fail', `${resource.slice(receiver.start, receiver.end)}; return receive;`)(
    (...args) => https.request(...args), httpsCredentialResponseHeaderByteLimit,
    httpsCredentialAuthorizationPrefix, Buffer, types, Promise.prototype.then,
    httpsCredentialResponseReadQuantum, code => {throw Object.assign(new Error(code), {code});});
  return {capture, receive};
}

for (const mode of ['ok', 'hold', 'lost-response']) {
  test(`external fixture original HTTP receiver observes stream close (${mode})`, async t => {
    const {capture, receive} = await originalExternalTransportReceiver();
    const transport = capture(); t.after(() => transport.restore());
    const controller = new AbortController(); t.after(() => controller.abort());
    const effect = mode === 'lost-response';
    transport.state.readMode = mode === 'hold' ? 'hold' : 'ok';
    transport.state.effectMode = mode;
    const binding = {}, charges = [];
    let outcome = {kind: 'pending'};
    const pending = receive({hostname: effect ? 'external-effect.fixture.invalid' : 'external-read.fixture.invalid',
      path: effect ? '/events' : '/records?page=0', method: effect ? 'POST' : 'GET',
      ...(effect ? {body: '{"key":"original","note":"literal note"}'} : {}),
      requestBytes: effect ? Buffer.byteLength('{"key":"original","note":"literal note"}') : 0,
      secret: 'fixture-only-token', headers: [], signal: controller.signal,
      maxResponseBytes: 4096, binding, observeResponseBytes: count => {charges.push(count);}});
    pending.then(value => {outcome = {kind: 'resolved', value};}, error => {outcome = {kind: 'rejected', error};});
    const request = binding.request;
    await new Promise(setImmediate); await new Promise(setImmediate);
    if (mode === 'hold') {
      assert.equal(outcome.kind, 'pending');
      assert.equal(request.destroyed, false);
      controller.abort();
      await new Promise(setImmediate); await new Promise(setImmediate);
      assert.equal(outcome.kind, 'rejected');
      assert.equal(outcome.error.code, 'ABORT_ERR');
    } else if (effect) {
      assert.equal(outcome.kind, 'rejected');
      assert.equal(outcome.error.code, 'ECONNRESET');
      assert.deepEqual(transport.state.events, [{key: 'original', note: 'literal note'}]);
    } else {
      assert.equal(outcome.kind, 'resolved');
      assert.deepEqual(JSON.parse(outcome.value.body.toString()),
        {items: [{key: 'alpha', amount: 7}, {key: 'beta', amount: 2}], next: 1});
      assert.equal(charges.reduce((sum, count) => sum + count, 0), outcome.value.body.byteLength);
    }
    assert.equal(request.closed, true);
    assert.equal(binding.request, undefined);
    assert.equal(transport.state.requests.length, 1);
    assert.equal(transport.state.forbiddenNetworkCalls, 0);
  });
}

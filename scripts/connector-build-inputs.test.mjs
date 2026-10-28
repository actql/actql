import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {readHostBundles} from './connector-node-bundles.mjs';
import {inspectCore} from './portable-core.mjs';

function fixture(t) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'actql-connector-inputs-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const put = (path, contents) => {
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, contents);
  };
  const modules = [
    {namespace: 'actql/actql', version: '0.0.1', root: join(root, 'core')},
    {namespace: 'example/numeric', version: '1.2.3', root: join(root, 'connector')},
    {namespace: 'example/host', version: '0.1.0', root: join(root, 'host')},
  ];
  const mod = (index, imports = [], extra = '') => {
    const module = modules[index];
    put(join(module.root, 'moon.mod'),
      `name = "${module.namespace}"\nversion = "${module.version}"\nsource = "src"\n` +
      'supported_targets = "+js+wasm+native"\n' +
      (imports.length ? `import { ${imports.map(name => JSON.stringify(name)).join(', ')}, }\n` : '') + extra);
    mkdirSync(join(module.root, 'src'), {recursive: true});
  };
  mod(0);
  mod(1, ['actql/actql@0.0.1']);
  mod(2, ['actql/actql@0.0.1', 'example/numeric@1.2.3']);
  const connector = modules[1].root;
  put(join(connector, 'src/driver/moon.pkg'),
    'supported_targets = "js"\nimport { "actql/actql/connector_sdk" @connector, }\n');
  put(join(modules[0].root, 'src/connector_sdk/moon.pkg'), 'supported_targets = "+js+wasm+native"\n');
  const compute = {
    package: 'example/numeric/driver', module: 'NumericModule', configuration: 'NumericSettings',
    configure: 'configure', registration: 'registration', contribution: 'contribution',
    dispatch: 'dispatch', synchronous_dispatch: 'execute', dispatch_result: 'Unit',
    dispatch_error: {package: 'example/numeric/driver', type: 'NumericIssue'},
    estimate_error: {package: 'example/numeric/driver', type: 'NumericIssue'},
    estimate_policy: null, resource_policy: null,
  };
  const manifest = join(connector, 'src/compute-bundle.json');
  put(manifest, JSON.stringify(compute));
  const configuration = {target: 'js', modules, host: 'example/host',
    connectors: [{name: 'numeric', module: 'example/numeric', directory: 'src'}]};
  return {root, put, mod, modules, connector, compute, manifest, configuration};
}

function hostFixture(f, roles = ['source', 'effect'], name = 'numeric') {
  const installation = {registration: name, revision: `${name}/0.1`,
    providerBundle: `connectors/${name}/host_node`, responseHeaders: ['link'],
    assets: [`src/connectors/${name}/views.json`]};
  for (const role of roles) {
    installation[role] = {profileVersion: `actql-installed-${name}-${role}/0.1`,
      module: `adapters/connectors/${name}/host/${role}.mjs`,
      exports: {check: 'check', identityParts: 'identity', load: 'load'}};
    f.put(join(f.connector, installation[role].module),
      'export function check() {}\nexport function identity() {}\nexport function load() {}\n');
  }
  const providerPath = join(f.connector, 'src', installation.providerBundle, 'moon.pkg');
  f.put(providerPath, 'supported_targets = "js"\npkgtype(kind: "foreign_library")\n' +
    'import { "actql/actql/connector_sdk" @connector, }\n');
  f.put(join(f.connector, installation.assets[0]), '{}');
  const directory = `src/connectors/${name}`;
  const path = join(f.connector, directory, 'host-bundle.json');
  const write = (value = installation) => f.put(path, JSON.stringify({installation: value}));
  write();
  const selection = {name, module: 'example/numeric', directory};
  f.configuration.connectors = f.configuration.connectors.filter(entry => entry.name !== name);
  f.configuration.connectors.push(selection);
  return {installation, path, write, providerPath, selection};
}

test('shared reviewed module options preserve both consumers and original module identity', t => {
  const f = fixture(t), core = f.modules[0].root;
  const modulePath = join(core, 'moon.mod'), original = readFileSync(modulePath, 'utf8');
  f.put(join(core, 'src/connector_sdk/main.mbt'), 'pub fn identity(x : Int) -> Int { x }\n');
  const before = resolveConnectorBuildInputs(f.configuration);
  for (const option of [
    'options("link-flags": ["-js-format", "esm"])\n',
    'options(\n  "link-flags": [ "-js-format", "esm" ],\n)\n',
    'options(/* selected module format */ "link-flags": ["-js-format", "esm"],)\n',
  ]) for (const source of [original + option, option + original]) {
    writeFileSync(modulePath, source);
    const after = resolveConnectorBuildInputs(f.configuration);
    assert.deepEqual(after.modules, before.modules);
    assert.deepEqual(after.computeEntries, before.computeEntries);
    assert.deepEqual(inspectCore(core, ['connector_sdk']).packages, ['connector_sdk']);
    assert.equal(readFileSync(modulePath, 'utf8'), source);
  }
});

test('shared module option recognition refuses unknown malformed duplicate and extra flags', t => {
  const f = fixture(t), core = f.modules[0].root;
  const modulePath = join(core, 'moon.mod'), original = readFileSync(modulePath, 'utf8');
  f.put(join(core, 'src/connector_sdk/main.mbt'), 'pub fn identity(x : Int) -> Int { x }\n');
  const valid = 'options("link-flags": ["-js-format", "esm"])';
  for (const invalid of [
    'options("other": ["-js-format", "esm"])',
    'options("pre-build": "node hidden.mjs")',
    'options(deps: {"hidden/dependency": "1.0.0"})',
    'options("link-flags": ["-js-format", "cjs"])',
    'options("link-flags": ["esm", "-js-format"])',
    'options("link-flags": ["-js-format", "esm", "-extra"])',
    'options("link-flags": "esm")',
    'options("link-flags": ["-js-format", "esm",])',
    'options("link-flags": ["-js-format", "esm"],,)',
    'options("link-flags": ["-js-format", "esm"], "link-flags": [])',
    'options("link-flags": ["-js-format", "esm"]',
    valid + '\n' + valid,
    valid + '\nunknown = "hidden"',
  ]) {
    writeFileSync(modulePath, original + invalid);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), undefined, invalid);
    assert.throws(() => inspectCore(core, ['connector_sdk']), undefined, invalid);
  }
});

test('reviewed module options retain dependency target and package metadata refusals', t => {
  const f = fixture(t), core = f.modules[0].root;
  const option = 'options("link-flags": ["-js-format", "esm"],)\n';
  f.mod(0, [], option);
  f.mod(1, ['actql/actql@0.0.1', 'hidden/dependency@1.0.0'], option);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Missing or mismatched declared module dependency/);
  f.mod(1, ['actql/actql@0.0.1'], option);
  const modulePath = join(core, 'moon.mod'), source = readFileSync(modulePath, 'utf8');
  writeFileSync(modulePath, source.replace('supported_targets = "+js+wasm+native"', 'supported_targets = "native"'));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Incompatible JS target/);
  writeFileSync(modulePath, source);
  const resolved = resolveConnectorBuildInputs(f.configuration);
  // Module format DATA is not permission to accept package-level linker data.
  f.put(join(core, 'src/connector_sdk/moon.pkg'), 'supported_targets = "+js+wasm+native"\n' + option);
  assert.throws(() => resolved.resolvePackage('actql/actql/connector_sdk'), /Unsupported package metadata: options/);
  assert.throws(() => inspectCore(core, ['connector_sdk']), /UnknownManifestSyntax/);
});

test('shared module recognition leaves Core source purity and foreign file checks intact', t => {
  const f = fixture(t), core = f.modules[0].root;
  f.mod(0, [], 'options("link-flags": ["-js-format", "esm"],)\n');
  const main = join(core, 'src/connector_sdk/main.mbt');
  for (const source of ['extern "js" fn hidden() -> Int = "Date.now"',
    'pub fn hidden() -> Unit { println("unrequested") }']) {
    f.put(main, source);
    assert.throws(() => inspectCore(core, ['connector_sdk']), /CoreEnvironmentAccess/);
  }
  f.put(main, 'pub fn identity(x : Int) -> Int { x }\n');
  f.put(join(core, 'src/connector_sdk/hidden.c'), 'int hidden(void) { return 1; }\n');
  assert.throws(() => inspectCore(core, ['connector_sdk']), /CoreForeignFile/);
});

test('external package references retain existing manifest ownership and immutable snapshots', t => {
  const f = fixture(t);
  const resolved = resolveConnectorBuildInputs(f.configuration);
  assert.equal(resolved.coreRoot, f.modules[0].root);
  assert.equal(resolved.host.sourceRoot, join(f.modules[2].root, 'src'));
  assert.deepEqual(resolved.computeEntries, [{name: 'numeric', manifest: f.compute,
    packagePrefix: 'example/numeric'}]);
  assert.equal(resolved.entries[0].directory, join(f.connector, 'src'));
  assert.equal(resolved.entries[0].compute, f.manifest);
  assert.equal(resolved.entries[0].revision, undefined);
  assert.equal(resolved.packagePath('example/numeric/driver'), join(f.connector, 'src/driver/moon.pkg'));
  assert.equal(resolved.resolvePackage('actql/actql/connector_sdk', 'example/numeric'),
    join(f.modules[0].root, 'src/connector_sdk/moon.pkg'));
  assert.ok(Object.isFrozen(resolved.computeEntries[0].manifest.dispatch_error));
  assert.throws(() => { resolved.modules[1].dependencies['actql/actql'] = '9.9.9'; }, TypeError);
  writeFileSync(f.manifest, '{}');
  f.configuration.connectors[0].name = 'changed';
  assert.deepEqual(resolved.computeEntries[0].manifest, f.compute);
  assert.equal(resolved.entries[0].name, 'numeric');
});

test('explicit selection ignores unrelated invalid manifests and never imports Node code', t => {
  const f = fixture(t);
  f.put(join(f.connector, 'unselected/compute-bundle.json'), '{ invalid');
  f.put(join(f.connector, 'src/node-bundle.json'), JSON.stringify({strategy: {
    module: 'adapters/numeric.mjs', export: 'numericStrategy',
  }}));
  f.put(join(f.connector, 'adapters/numeric.mjs'), 'throw new Error("This must not run");\n');
  const resolved = resolveConnectorBuildInputs(f.configuration);
  assert.deepEqual(resolved.nodeEntries, [{name: 'numeric',
    modulePath: join(f.connector, 'adapters/numeric.mjs'), symbol: 'numericStrategy', compute: f.compute}]);
  assert.deepEqual(resolveConnectorBuildInputs({...f.configuration, connectors: []}).computeEntries, []);
});

test('module pins and every declared dependency must match explicitly supplied roots', t => {
  const f = fixture(t);
  for (const update of [{namespace: 'elsewhere/numeric'}, {version: '1.2.4'}, {root: 'https://example.com/pkg'}]) {
    assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
      modules: f.modules.map((module, index) => index === 1 ? {...module, ...update} : module)}));
  }
  for (const imports of [['absent/dependency@1.0.0'], ['actql/actql@9.9.9']]) {
    f.mod(1, imports);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Missing or mismatched/);
  }
  f.mod(1, []);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Undeclared module dependency/);
  f.mod(1, ['actql/actql@0.0.1']);
  f.mod(2, ['actql/actql@0.0.1']);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Undeclared module dependency/);
});

test('transitive dependency cycles and Core-to-Connector dependencies are refused', t => {
  const f = fixture(t);
  f.mod(1, ['example/host@0.1.0']);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Cyclic/);
  f.mod(1, []);
  f.mod(0, ['example/numeric@1.2.3']);
  f.put(join(f.connector, 'src/driver/moon.pkg'), 'supported_targets = "js"\n');
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Core cannot depend/);
});

test('a Host root cannot contain or be contained by another module root', t => {
  for (const parent of [0, 1]) {
    const f = fixture(t);
    f.modules[2].root = join(f.modules[parent].root, 'nested-host');
    f.mod(2, ['actql/actql@0.0.1', 'example/numeric@1.2.3']);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /overlapping module ownership/);
  }
  const f = fixture(t);
  f.modules[2].root = f.root;
  f.mod(2, ['actql/actql@0.0.1', 'example/numeric@1.2.3']);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /overlapping module ownership/);
});

test('unsupported or duplicate metadata never hides dependencies in comments or directives', t => {
  const f = fixture(t);
  f.mod(1, ['actql/actql@0.0.1'],
    '// import { "absent/dependency@1.0.0" }\n/* outer /* nested */ comment */\n');
  assert.equal(resolveConnectorBuildInputs(f.configuration).computeEntries.length, 1);
  for (const extra of [
    'options(deps: { "absent/dependency": "1.0.0" })',
    'name = "example/numeric"',
    'import { "actql/actql@0.0.1" }',
    'import { "https://example.com/module@1.0.0" }',
    'import { "actql/actql@^0.0.1" }',
    'import { "actql/actql@0.0.1" } for "test"',
    '/* unclosed',
  ]) {
    f.mod(1, ['actql/actql@0.0.1'], extra);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration));
  }
});

test('module and selected package targets must support the JS composition', t => {
  const f = fixture(t);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration, target: 'native'}), /Invalid Connector/);
  const modulePath = join(f.connector, 'moon.mod');
  const original = readFileSync(modulePath, 'utf8');
  for (const target of ['native', '+wasm+native', '-js', '+js+unknown']) {
    writeFileSync(modulePath, original.replace('+js+wasm+native', target));
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /target/);
  }
  writeFileSync(modulePath, original);
  f.put(join(f.connector, 'src/driver/moon.pkg'), 'supported_targets = "native"\n');
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Incompatible JS target/);
});

test('roots, source directories, package paths and manifest files refuse symlinks and escapes', t => {
  const f = fixture(t);
  const alias = join(f.root, 'alias');
  symlinkSync(f.connector, alias, 'dir');
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    modules: f.modules.map((module, index) => index === 1 ? {...module, root: alias} : module)}), /aliased/);
  for (const directory of ['../connector/src', '/tmp', 'src/../src', 'src\\driver', 'https://example.com']) {
    assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
      connectors: [{...f.configuration.connectors[0], directory}]}), /relative path/);
  }
  f.mod(1, ['actql/actql@0.0.1']);
  const modulePath = join(f.connector, 'moon.mod');
  const original = readFileSync(modulePath, 'utf8');
  writeFileSync(modulePath, original.replace('source = "src"', 'source = "../core/src"'));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /relative path/);
  writeFileSync(modulePath, original);
  const file = join(f.connector, 'src/driver/moon.pkg');
  rmSync(file);
  symlinkSync(join(f.modules[0].root, 'src/connector_sdk/moon.pkg'), file);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /aliased/);
  rmSync(file);
  f.put(file, 'supported_targets = "js"\n');
  const originalManifest = join(f.connector, 'source.json');
  f.put(originalManifest, JSON.stringify(f.compute));
  rmSync(f.manifest);
  symlinkSync(originalManifest, f.manifest);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /aliased/);
});

test('Compute and Node references cannot escape the owning module or add an undeclared dependency', t => {
  const f = fixture(t);
  for (const packageName of ['actql/actql/connector_sdk', 'example/numeric/../driver', 'https://example.com/driver']) {
    f.put(f.manifest, JSON.stringify({...f.compute, package: packageName}));
    assert.throws(() => resolveConnectorBuildInputs(f.configuration));
  }
  f.put(f.manifest, JSON.stringify({...f.compute,
    managed_start_error: {package: 'unavailable/module/issues', type: 'Issue'}}));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Unavailable package namespace/);
  f.put(f.manifest, JSON.stringify(f.compute));
  for (const module of ['../core/adapter.mjs', '/tmp/adapter.mjs', 'https://example.com/adapter.mjs']) {
    f.put(join(f.connector, 'src/node-bundle.json'), JSON.stringify({strategy: {module, export: 'strategy'}}));
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /relative path/);
  }
});

test('existing Host revision keeps its identity and Compute-only entries invent none', t => {
  const f = fixture(t);
  const selected = f.configuration.connectors[0];
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    connectors: [{...selected, revision: 'numeric/0.1'}]}), /requires an existing Host/);
  const h = hostFixture(f);
  const config = {...f.configuration, connectors: [{...h.selection, revision: 'numeric/0.1'}]};
  assert.equal(resolveConnectorBuildInputs(config).entries[0].revision, 'numeric/0.1');
  assert.throws(() => resolveConnectorBuildInputs({...config,
    connectors: [{...h.selection, revision: 'numeric/0.2'}]}), /identity mismatch/);
  h.write({...h.installation, registration: 'other'});
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /registration/);
});

test('Core-owned Compute declarations retain the existing Connector package prefix', t => {
  const f = fixture(t);
  const core = f.modules[0].root;
  f.put(join(core, 'src/connectors/numeric/driver/moon.pkg'), 'supported_targets = "js"\n');
  const manifest = {...f.compute, package: 'actql/actql/connectors/numeric/driver',
    dispatch_error: {package: 'actql/actql/connectors/numeric/driver', type: 'NumericIssue'},
    estimate_error: {package: 'actql/actql/connectors/numeric/driver', type: 'NumericIssue'}};
  const path = join(core, 'src/connectors/numeric/compute-bundle.json');
  f.put(path, JSON.stringify(manifest));
  const config = {...f.configuration,
    connectors: [{name: 'numeric', module: 'actql/actql', directory: 'src/connectors/numeric'}]};
  assert.equal(resolveConnectorBuildInputs(config).computeEntries[0].packagePrefix, 'actql/actql/connectors/numeric');
  f.put(path, JSON.stringify({...manifest, package: 'actql/actql/connector_sdk'}));
  assert.throws(() => resolveConnectorBuildInputs(config), /does not belong/);
});

test('selection and module ownership are explicit and unambiguous', t => {
  const f = fixture(t);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    connectors: [...f.configuration.connectors, ...f.configuration.connectors]}), /duplicate Connector/);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    modules: [...f.modules, f.modules[1]]}), /Duplicate or overlapping/);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration, host: 'actql/actql'}), /separate explicit Host/);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration, program: {url: 'https://example.com'}}), /Invalid Connector/);
  const resolved = resolveConnectorBuildInputs(f.configuration);
  assert.throws(() => resolved.packagePath('example/numeric/missing'), /Missing/);
  assert.throws(() => resolved.resolvePackage('example/numeric/driver', 'actql/actql'), /Undeclared/);
  assert.throws(() => resolved.resolveFile('example/numeric', '../core/moon.mod'), /relative path/);
});

test('Host outputs permit fresh paths and refuse symlink, file-ancestor and traversal redirects', t => {
  const f = fixture(t);
  const resolved = resolveConnectorBuildInputs(f.configuration);
  const host = f.modules[2].root;
  assert.equal(resolved.outputPath('src/composition/compute.generated.mbt'),
    join(host, 'src/composition/compute.generated.mbt'));
  assert.throws(() => resolved.outputPath('../connector/moon.mod'), /relative path/);
  symlinkSync(f.connector, join(host, 'src/link'), 'dir');
  assert.throws(() => resolved.outputPath('src/link/output.mjs'), /invalid Host output/);
  f.put(join(host, 'src/file'), 'ordinary file');
  assert.throws(() => resolved.outputPath('src/file/output.mjs'), /invalid Host output/);
  symlinkSync(f.manifest, join(host, 'src/output.mjs'));
  assert.throws(() => resolved.outputPath('src/output.mjs'), /invalid Host output/);
  assert.equal(resolved.outputPath('src/file'), join(host, 'src/file'));
});

test('external Read-only and Effect-only Host snapshots preserve exact package owners', t => {
  for (const role of ['source', 'effect']) {
    const f = fixture(t), h = hostFixture(f, [role]);
    const resolved = resolveConnectorBuildInputs(f.configuration);
    const [entry] = resolved.hostEntries;
    assert.equal(entry.namespace, 'example/numeric');
    assert.equal(entry.root, f.connector);
    assert.equal(entry.sourceRoot, join(f.connector, 'src'));
    assert.equal(entry.registration, 'numeric');
    assert.equal(entry.revision, 'numeric/0.1');
    assert.equal(entry.providerBundle, 'connectors/numeric/host_node');
    assert.equal(entry.providerPackage, 'example/numeric/connectors/numeric/host_node');
    assert.equal(entry.providerPackagePath, h.providerPath);
    assert.equal(entry[role].module, h.installation[role].module);
    assert.equal(entry[role].modulePath, join(f.connector, h.installation[role].module));
    assert.equal(entry[role === 'source' ? 'effect' : 'source'], undefined);
    assert.deepEqual(entry.assetSources, [{path: 'src/connectors/numeric/views.json',
      sourcePath: join(f.connector, 'src/connectors/numeric/views.json')}]);
    assert.equal(resolved.computeEntries.length, 0);
    assert.equal(resolved.nodeEntries.length, 0);
    assert.equal(readHostBundles(resolved.host.root, {buildInputs: resolved}), resolved.hostEntries);
    assert.ok(Object.isFrozen(entry));
    assert.ok(Object.isFrozen(entry[role].exports));
    assert.ok(Object.isFrozen(entry.assetSources[0]));
    assert.throws(() => { entry[role].exports.load = 'replaced'; }, TypeError);
    h.write({...h.installation, revision: 'numeric/0.2'});
    f.put(join(f.connector, 'src/connectors/broken/host-bundle.json'), '{ invalid');
    assert.equal(readHostBundles(resolved.host.root, {buildInputs: resolved})[0].revision, 'numeric/0.1');
    assert.throws(() => readHostBundles(f.connector, {buildInputs: resolved}), /InvalidResolvedHost/);
    assert.throws(() => readHostBundles(resolved.host.root,
      {buildInputs: resolved, names: ['numeric']}), /InvalidResolvedHost/);
  }
});

test('external Host declarations validate every present role and require at least one', t => {
  const f = fixture(t), h = hostFixture(f);
  const {source, effect, ...shared} = h.installation;
  for (const installation of [shared, {...shared, source: null}, {...shared, effect: null},
    {...shared, source, effect: {}}, {...shared, effect, source: {}},
    {...h.installation, effect: {...effect, profileVersion: source.profileVersion}}]) {
    h.write(installation);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Invalid Host bundle manifest/);
  }
});

test('external Host validation shares profile, header, export and ownership restrictions', t => {
  const f = fixture(t), h = hostFixture(f);
  for (const change of [
    value => { value.extra = 'unrecognized'; },
    value => { value.providerBundle = 'connectors/other/host_node'; },
    value => { value.responseHeaders = ['set-cookie']; },
    value => { value.responseHeaders = ['link', 'link']; },
    value => { value.source.profileVersion = 'unversioned'; },
    value => { value.source.exports.load = 'notExported'; },
    value => { delete value.effect.exports.identityParts; },
    value => { value.effect.identityProfile = {source: 'actql-source/0.1'}; },
    value => { value.source.module = 'adapters/connectors/numeric/host/../source.mjs'; },
    value => { value.effect.module = 'adapters/connectors/other/host/effect.mjs'; },
    value => { value.assets = ['src/connectors/numeric/../views.json']; },
    value => { value.assets.push(value.assets[0]); },
  ]) {
    const value = structuredClone(h.installation);
    change(value); h.write(value);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Invalid Host bundle manifest/);
  }
});

test('external provider packages require the exact path, compatible target, kind and dependency pins', t => {
  const f = fixture(t), h = hostFixture(f);
  const original = readFileSync(h.providerPath, 'utf8');
  rmSync(h.providerPath);
  f.put(join(f.connector, 'src/host_node/moon.pkg'), original);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Missing/);
  for (const text of [original.replace('"js"', '"native"'),
    original.replace('pkgtype(kind: "foreign_library")', ''),
    original.replace('actql/actql/connector_sdk', 'missing/module/provider')]) {
    f.put(h.providerPath, text);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /target|kind|namespace/);
  }
  f.put(h.providerPath, original);
  f.mod(1, []);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Undeclared module dependency/);
  f.mod(1, ['actql/actql@9.9.9']);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Missing or mismatched/);
  f.mod(1, ['actql/actql@0.0.1']);
  f.mod(2, ['actql/actql@0.0.1']);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Undeclared module dependency/);
});

test('external Host adapter, asset and provider package paths refuse symlink aliases', t => {
  for (const role of ['source', 'effect', 'asset', 'provider']) {
    const f = fixture(t), h = hostFixture(f);
    const path = role === 'provider' ? h.providerPath : join(f.connector,
      role === 'asset' ? h.installation.assets[0] : h.installation[role].module);
    const target = join(f.connector, `original-${role}`);
    f.put(target, readFileSync(path));
    rmSync(path); symlinkSync(target, path);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /aliased|Invalid Host/);
  }
  const f = fixture(t), h = hostFixture(f);
  const real = join(f.connector, 'adapters/connectors/numeric/host/actual');
  f.put(join(real, 'source.mjs'), readFileSync(join(f.connector, h.installation.source.module)));
  symlinkSync(real, join(f.connector, 'adapters/connectors/numeric/host/alias'), 'dir');
  h.write({...h.installation, source: {...h.installation.source,
    module: 'adapters/connectors/numeric/host/alias/source.mjs'}});
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /aliased/);
});

test('duplicate installed source and Effect profiles are refused by the shared snapshot', t => {
  for (const role of ['source', 'effect']) {
    const f = fixture(t), first = hostFixture(f, [role]);
    const second = hostFixture(f, [role], 'another');
    second.write({...second.installation, [role]: {...second.installation[role],
      profileVersion: first.installation[role].profileVersion}});
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Duplicate installed/);
  }
});

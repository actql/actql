import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';

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
  f.put(join(f.connector, 'src/host-bundle.json'), JSON.stringify({installation: {
    registration: 'numeric', revision: 'numeric/0.1',
  }}));
  const config = {...f.configuration, connectors: [{...selected, revision: 'numeric/0.1'}]};
  assert.equal(resolveConnectorBuildInputs(config).entries[0].revision, 'numeric/0.1');
  assert.throws(() => resolveConnectorBuildInputs({...config,
    connectors: [{...selected, revision: 'numeric/0.2'}]}), /identity mismatch/);
  f.put(join(f.connector, 'src/host-bundle.json'), JSON.stringify({installation: {
    registration: 'other', revision: 'numeric/0.1',
  }}));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /identity mismatch/);
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

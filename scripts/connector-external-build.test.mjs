import assert from 'node:assert/strict';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkComputeAssembly, generateComputeAssembly} from './connector-compute-bundles.mjs';
import {checkNodeAssembly, generateInstallations, readHostBundles} from './connector-node-bundles.mjs';
import {tokens} from './portable-core.mjs';
import {manifestImports} from './test-packed-external-connector.mjs';

function copiedFixtureImports(manifest) {
  const imports = new Map(manifestImports(manifest).map(({alias, path}) => [alias, path]));
  const original = new Map(manifestImports(readFileSync(
    new URL('../src/node_host_conformance/moon.pkg', import.meta.url), 'utf8'))
    .map(({alias, path}) => [alias, path]));
  const source = tokens(readFileSync(
    new URL('../src/node_host_conformance/fixture.generated.mbt', import.meta.url), 'utf8'), true);
  const missing = new Set();
  for (let index = 0; index < source.length; index++) {
    if (source[index].value !== '@' || source[index + 1]?.kind !== 'word' ||
        source[index + 2]?.value !== '.') continue;
    const alias = source[index + 1].value;
    // The fixture deliberately replaces only the ordinary Compute assembly
    // with its separately compiled external contribution. Other copied Core
    // references keep the exact original package selected by their generator.
    const expected = alias === 'builtin' ? 'fixture/compute_host/compute' : original.get(alias);
    assert.ok(expected, `Undeclared original fixture alias: ${alias}`);
    if (imports.get(alias) !== expected) missing.add(alias);
  }
  return [...missing].sort();
}

test('external Compute fixture retains imports of its copied generated Core source', () => {
  const manifest = readFileSync(new URL(
    './fixtures/external-compute/compute-host/src/scenario/moon.pkg', import.meta.url), 'utf8');
  assert.deepEqual(copiedFixtureImports(manifest), []);
  // Independent regression for the real packed-build failure: the generated
  // fixture's pipeline Step match must not lose its package during the copy.
  const withoutPipeline = manifest.replace('  "actql/actql/pipeline_typing" @pipeline,\n', '');
  assert.notEqual(withoutPipeline, manifest);
  assert.deepEqual(copiedFixtureImports(withoutPipeline), ['pipeline']);
  const wrongOwner = manifest.replace('"actql/actql/pipeline_typing" @pipeline',
    '"actql/actql/pipeline_check_context" @pipeline');
  assert.deepEqual(copiedFixtureImports(wrongOwner), ['pipeline']);
});

function fixture(t) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'external-connector-build-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const put = (path, contents) => {
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, contents);
  };
  const modules = [
    {namespace: 'actql/actql', version: '0.0.1', root: join(root, 'core')},
    {namespace: 'fixture/portable', version: '1.0.0', root: join(root, "connector's root#?%")},
    {namespace: 'fixture/host', version: '1.0.0', root: join(root, 'host')},
  ];
  const dependencies = [[], ['actql/actql@0.0.1'], ['actql/actql@0.0.1', 'fixture/portable@1.0.0']];
  for (const [index, module] of modules.entries()) {
    put(join(module.root, 'moon.mod'), `name = "${module.namespace}"\nversion = "${module.version}"\n` +
      'source = "src"\nsupported_targets = "js"\n' +
      (dependencies[index].length ? `import {${dependencies[index].map(JSON.stringify).join(',')}}\n` : ''));
    mkdirSync(join(module.root, 'src'), {recursive: true});
  }
  // The pinned compiler supplies its standard library; external module inputs
  // neither replace it nor need a synthetic package to validate generated imports.
  // These are generation fixtures only, not replacement runtime Owners.
  // Actual external execution uses a separately compiled packed fixture.
  for (const path of ['connector_sdk', 'physical_host', 'physical_host_dispatch', 'execution_relation',
    'physical_strategy', 'physical_strategy_host', 'physical_resources', 'encode_core', 'run_publication',
    'run_publication_host', 'publication_payload', 'execution_site', 'remote_site_protocol',
    'remote_credential', 'remote_bundle', 'physical_manifest', 'effect_application', 'remote_transfer']) {
    put(join(modules[0].root, 'src', path, 'moon.pkg'), 'supported_targets = "js"\n');
  }
  put(join(modules[0].root, 'scripts/templates/strategy-node.mbt'), readFileSync(
    new URL('./templates/strategy-node.mbt', import.meta.url)));
  put(join(modules[0].root, 'src/physical_resources/ledger.mbt'), readFileSync(
    new URL('../src/physical_resources/ledger.mbt', import.meta.url)));
  put(join(modules[1].root, 'src/driver/moon.pkg'),
    'supported_targets = "js"\nimport { "actql/actql/physical_host_dispatch" @host, }\n');
  const manifest = {package: 'fixture/portable/driver', module: 'Contribution',
    configuration: 'Configuration', configure: 'configure', registration: 'registration',
    validate_binding: 'validate_binding', contribution: 'contribution', dispatch: 'dispatch', completion_dispatch: 'complete_dispatch',
    dispatch_result: 'Unit', dispatch_error: {package: 'actql/actql/physical_strategy_host', type: 'RunIssue'},
    estimate_error: {package: 'actql/actql/physical_strategy_host', type: 'RunIssue'},
    estimate_policy: null, resource_policy: null};
  put(join(modules[1].root, 'declarations/compute-bundle.json'), JSON.stringify(manifest));
  put(join(modules[1].root, 'declarations/node-bundle.json'), JSON.stringify({strategy: {
    module: 'node/strategy.mjs', export: 'installPortable'}}));
  put(join(modules[1].root, 'node/strategy.mjs'), 'export function installPortable() {}\nthrow new Error("NoBuildTimeImport");\n');
  const configuration = {target: 'js', modules, host: 'fixture/host',
    connectors: [{name: 'portable', module: 'fixture/portable', directory: 'declarations'}]};
  return {root, modules, put, configuration, resolved: resolveConnectorBuildInputs(configuration)};
}

test('strategy usage generation follows the selected Core fields and primitive widths', t => {
  const f = fixture(t);
  const ledger = join(f.modules[0].root, 'src/physical_resources/ledger.mbt');
  const original = readFileSync(ledger, 'utf8');
  f.put(ledger, original.replace('pub(all) struct LedgerUsage {',
    'pub(all) struct LedgerUsage {\n  future_count : Int\n  future_bytes : Int64'));
  const inputs = resolveConnectorBuildInputs(f.configuration);
  checkNodeAssembly(f.modules[2].root, true, {buildInputs: inputs});
  const bridgePath = join(f.modules[2].root, 'src/connectors_builtin_node/bridge.generated.mbt');
  const bridge = readFileSync(bridgePath, 'utf8');
  const usage = bridge.slice(bridge.indexOf('#export_name("strategyHostUsage")'),
    bridge.indexOf('#export_name("strategyHostTransferBegin")'));
  assert.match(usage, /usage\.future_count\.to_int64\(\)/u);
  assert.match(usage, /usage\.future_bytes,/u);
  assert.doesNotMatch(usage, /usage\.future_bytes\.to_int64/u);
  for (const field of ['reserved_attempts', 'live_reservations', 'live_delegations',
    'uncertain_transfer_bytes', 'peak_retention_bytes']) assert.match(usage,
      new RegExp(`usage\\.${field}(?:\\.to_int64\\(\\))?,`, 'u'));
  assert(usage.indexOf('usage.future_count') < usage.indexOf('usage.planning_work'));
  f.put(ledger, original.replace('reserved_attempts : Int', 'reserved_attempts : String'));
  assert.throws(() => checkNodeAssembly(f.modules[2].root, true,
    {buildInputs: resolveConnectorBuildInputs(f.configuration)}), /Unsupported Core ledger field/u);
  assert.equal(readFileSync(bridgePath, 'utf8'), bridge);
});

function hostFixture(f, name, role) {
  const root = f.modules[1].root;
  const installation = {registration: name, revision: `${name}/0.1`,
    providerBundle: `connectors/${name}/host_node`, responseHeaders: [],
    [role]: {profileVersion: `actql-installed-${name}-${role}/0.1`,
      module: `adapters/connectors/${name}/host/${role}.mjs`,
      exports: {check: 'check', identityParts: 'identity', load: 'load'}}};
  f.put(join(root, 'src', installation.providerBundle, 'moon.pkg'),
    'supported_targets = "js"\npkgtype(kind: "foreign_library")\n');
  f.put(join(root, installation[role].module),
    'export function check() {}\nexport function identity() {}\n' +
    `export function load() { return ${JSON.stringify(`${name}:${role}`)}; }\n`);
  const directory = `src/connectors/${name}`;
  const path = join(root, directory, 'host-bundle.json');
  const write = (value = installation) => f.put(path, JSON.stringify({installation: value}));
  write();
  f.configuration.connectors.push({name, module: 'fixture/portable', directory});
  return {installation, path, write};
}
const installedOptions = buildInputs => ({buildInputs, assembly: 'compute', bridge: 'bridge',
  adapter: 'portable', installations: true});

test('existing generators emit external ownership into a separate Host namespace', async t => {
  const f = fixture(t), root = f.modules[2].root;
  const options = {buildInputs: f.resolved, assembly: 'compute', bridge: 'bridge', adapter: 'portable'};
  assert.equal(checkNodeAssembly(root, true, options), 1);
  assert.equal(checkNodeAssembly(root, false, options), 1);
  assert.equal(checkComputeAssembly(root, false, {buildInputs: f.resolved, directory: 'compute'}), 1);
  const assembly = readFileSync(join(root, 'src/compute/moon.pkg'), 'utf8');
  const bridge = readFileSync(join(root, 'src/bridge/moon.pkg'), 'utf8');
  const adapter = readFileSync(join(root, 'adapters/portable/strategy.generated.mjs'), 'utf8');
  assert.match(assembly, /"fixture\/portable\/driver"/);
  assert.match(bridge, /"fixture\/host\/compute" @builtin/);
  assert.doesNotMatch(bridge, /actql\/actql\/compute"/);
  assert.match(adapter, /from ".*connector's%20root%23%3F%25\/node\/strategy.mjs";/);
  await assert.rejects(import(pathToFileURL(join(root, 'adapters/portable/strategy.generated.mjs')).href),
    /NoBuildTimeImport/);
  assert.doesNotMatch(readFileSync(join(f.modules[0].root, 'moon.mod'), 'utf8'), /fixture\//);
});

test('resolved ownership cannot be replaced by another declaration or widened namespace', t => {
  const f = fixture(t), [entry] = f.resolved.computeEntries;
  assert.throws(() => generateComputeAssembly([{...entry, manifest: {...entry.manifest}}],
    {buildInputs: f.resolved}), /UnresolvedComputeBuildEntry/);
  const file = join(f.modules[1].root, 'declarations/compute-bundle.json');
  writeFileSync(file, JSON.stringify({...entry.manifest, package: 'actql/actql/physical_host_dispatch'}));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /owned|belong|Compute/);
  assert.throws(() => checkNodeAssembly(f.modules[2].root, true,
    {buildInputs: f.resolved, names: ['portable']}), /InvalidResolvedNodeBuildSelection/);
  assert.throws(() => checkNodeAssembly(f.modules[0].root, true,
    {buildInputs: f.resolved}), /InvalidResolvedNodeBuildSelection/);
});

test('generated outputs refuse symlinks before writing another file or outside sentinel', t => {
  const f = fixture(t), host = f.modules[2].root;
  const sentinel = join(f.root, 'sentinel.mbt');
  writeFileSync(sentinel, 'outside bytes\n');
  mkdirSync(join(host, 'src/bridge'));
  symlinkSync(sentinel, join(host, 'src/bridge/bridge.generated.mbt'));
  assert.throws(() => checkNodeAssembly(host, true,
    {buildInputs: f.resolved, assembly: 'compute', bridge: 'bridge', adapter: 'portable'}),
  /Aliased or invalid Host output/);
  assert.equal(readFileSync(sentinel, 'utf8'), 'outside bytes\n');
  assert.throws(() => readFileSync(join(host, 'src/compute/moon.pkg')), {code: 'ENOENT'});
});

test('external dynamic runtime discovery remains refused with or without installations', t => {
  const f = fixture(t), root = f.modules[2].root;
  for (const installations of [false, true]) {
    assert.throws(() => checkNodeAssembly(root, true,
      {buildInputs: f.resolved, loading: 'selected', installations}), /UnsupportedExternalNodeBuildProfile/);
  }
  assert.equal(existsSync(join(root, 'adapters')), false);
});

test('unsupported handwritten Client bridge metadata is refused without following its link', t => {
  const f = fixture(t), root = f.modules[2].root;
  const sentinel = join(f.root, 'outside.json');
  writeFileSync(sentinel, 'not a metadata document\n');
  mkdirSync(join(root, 'src/bridge'));
  symlinkSync(sentinel, join(root, 'src/bridge/client-execution-dependencies.json'));
  assert.throws(() => checkNodeAssembly(root, true,
    {buildInputs: f.resolved, assembly: 'compute', bridge: 'bridge'}),
  /UnsupportedExternalNodeBridgeExtension/);
  assert.equal(readFileSync(sentinel, 'utf8'), 'not a metadata document\n');
});

test('external Read-only and Effect-only installations load from the checked owner snapshot', async t => {
  const f = fixture(t), root = f.modules[2].root;
  f.configuration.connectors = [];
  const reader = hostFixture(f, 'reader', 'source');
  const writer = hostFixture(f, 'writer', 'effect');
  const resolved = resolveConnectorBuildInputs(f.configuration);
  reader.write({...reader.installation, source: null});
  writer.write({...writer.installation, revision: 'writer/9.9'});
  f.put(join(f.modules[1].root, 'src/connectors/unselected/host-bundle.json'), '{ invalid');
  const options = installedOptions(resolved);
  assert.equal(checkNodeAssembly(root, true, options), 0);
  assert.equal(checkNodeAssembly(root, false, options), 0);
  assert.equal(readHostBundles(root, {buildInputs: resolved}), resolved.hostEntries);
  const path = join(root, 'adapters/portable/installations.generated.mjs');
  const generated = readFileSync(path, 'utf8');
  assert.match(generated, /connector's%20root%23%3F%25\/adapters\/connectors\/reader\/host\/source.mjs/);
  const {installedConnectors} = await import(pathToFileURL(path));
  assert.deepEqual(installedConnectors.map(entry => [entry.name, entry.revision]),
    [['reader', 'reader/0.1'], ['writer', 'writer/0.1']]);
  assert.equal(installedConnectors[0].effect, undefined);
  assert.equal(installedConnectors[1].source, undefined);
  assert.equal((await installedConnectors[0].source.load()).load(), 'reader:source');
  assert.equal((await installedConnectors[1].effect.load()).load(), 'writer:effect');
  assert.doesNotMatch(readFileSync(join(root, 'src/compute/compute.generated.mbt'), 'utf8'),
    /with_reader|with_writer/);
  assert.equal(resolveConnectorBuildInputs({...f.configuration, connectors: []}).hostEntries.length, 0);
});

test('installation generation maps packaged module destinations without changing checked ownership', t => {
  const f = fixture(t), root = f.modules[2].root;
  hostFixture(f, 'reader', 'source');
  const resolved = resolveConnectorBuildInputs(f.configuration);
  const output = join(f.root, 'package/adapters/portable/installations.generated.mjs');
  const calls = [];
  const generated = generateInstallations(resolved.hostEntries, output, root, {
    resolveModule(entry, section, label) {
      calls.push([entry.namespace, label, section.modulePath]);
      return join(f.root, 'package', section.module);
    },
  });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], ['fixture/portable', 'source',
    join(f.modules[1].root, 'adapters/connectors/reader/host/source.mjs')]);
  assert.match(generated, /import\("\.\.\/connectors\/reader\/host\/source.mjs"\)/);
  for (const module of generated.matchAll(/import\(("[^"\n]+")\)/gu)) {
    assert.doesNotMatch(JSON.parse(module[1]), /connector's|fixture\/portable/);
  }
  assert.equal(resolved.hostEntries[0].root, f.modules[1].root);
});

test('installation output aliases and colliding assembly paths fail before any write', t => {
  for (const conflict of ['symlink', 'directory', 'assembly']) {
    const f = fixture(t), root = f.modules[2].root;
    hostFixture(f, 'reader', 'source');
    const resolved = resolveConnectorBuildInputs(f.configuration);
    const sentinel = join(f.root, 'sentinel.mjs');
    writeFileSync(sentinel, 'unchanged outside bytes\n');
    const output = join(root, 'adapters/portable/installations.generated.mjs');
    if (conflict !== 'assembly') {
      mkdirSync(dirname(output), {recursive: true});
      if (conflict === 'symlink') symlinkSync(sentinel, output);
      else mkdirSync(output);
    }
    assert.throws(() => checkNodeAssembly(root, true,
      {...installedOptions(resolved), ...(conflict === 'assembly' ? {bridge: 'compute'} : {})}),
    /Aliased or invalid Host output|CollidingConnectorAssemblyOutput/);
    assert.equal(readFileSync(sentinel, 'utf8'), 'unchanged outside bytes\n');
    assert.equal(existsSync(join(root, 'src/compute/moon.pkg')), false);
    assert.equal(existsSync(join(root, 'adapters/portable/strategy.generated.mjs')), false);
  }
});

test('invalid Host roles and duplicate profiles refuse before the default Compute generator writes', t => {
  for (const conflict of ['role', 'profile']) {
    const f = fixture(t), root = f.modules[1].root;
    const first = hostFixture(f, 'reader', 'source');
    const second = hostFixture(f, 'another', 'source');
    if (conflict === 'role') first.write({...first.installation, effect: null});
    else second.write({...second.installation, source: {...second.installation.source,
      profileVersion: first.installation.source.profileVersion}});
    assert.throws(() => checkNodeAssembly(root, true, {names: ['reader', 'another'],
      assembly: 'compute', bridge: 'bridge', adapter: 'portable', installations: true,
      nativeRemoteStandard: false}), /Invalid Host bundle manifest|Duplicate installed/);
    assert.equal(existsSync(join(root, 'src/compute/moon.pkg')), false);
    assert.equal(existsSync(join(root, 'adapters/portable/strategy.generated.mjs')), false);
    assert.equal(existsSync(join(root, 'adapters/portable/installations.generated.mjs')), false);
  }
});

test('missing bridge dependency refuses before Compute or installation files are written', t => {
  const f = fixture(t), root = f.modules[2].root;
  hostFixture(f, 'reader', 'source');
  const resolved = resolveConnectorBuildInputs(f.configuration);
  rmSync(join(f.modules[0].root, 'src/physical_manifest/moon.pkg'));
  assert.throws(() => checkNodeAssembly(root, true, installedOptions(resolved)), /Missing/);
  assert.equal(existsSync(join(root, 'src/compute/moon.pkg')), false);
  assert.equal(existsSync(join(root, 'adapters/portable/installations.generated.mjs')), false);
});

test('default installation outputs also refuse symlink aliases before Compute writes', t => {
  const f = fixture(t), root = f.modules[1].root;
  hostFixture(f, 'reader', 'source');
  const sentinel = join(f.root, 'sentinel.mjs');
  writeFileSync(sentinel, 'unchanged outside bytes\n');
  const output = join(root, 'adapters/portable/installations.generated.mjs');
  mkdirSync(dirname(output), {recursive: true});
  symlinkSync(sentinel, output);
  assert.throws(() => checkNodeAssembly(root, true, {names: ['reader'],
    assembly: 'compute', bridge: 'bridge', adapter: 'portable', installations: true,
    nativeRemoteStandard: false}), /Aliased or invalid Host output/);
  assert.equal(readFileSync(sentinel, 'utf8'), 'unchanged outside bytes\n');
  assert.equal(existsSync(join(root, 'src/compute/moon.pkg')), false);
  assert.equal(existsSync(join(root, 'adapters/portable/strategy.generated.mjs')), false);
});

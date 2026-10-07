import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkComputeAssembly, generateComputeAssembly} from './connector-compute-bundles.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';

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
  // These are generation fixtures only, not replacement runtime Owners.
  // Actual external execution uses a separately compiled packed fixture.
  for (const path of ['connector_sdk', 'physical_host', 'execution_relation',
    'physical_strategy', 'physical_resources', 'encode_core', 'run_publication',
    'run_publication_host', 'publication_payload', 'execution_site', 'remote_site_protocol',
    'remote_credential', 'remote_bundle', 'physical_manifest', 'effect_application', 'remote_transfer']) {
    put(join(modules[0].root, 'src', path, 'moon.pkg'), 'supported_targets = "js"\n');
  }
  put(join(modules[0].root, 'scripts/templates/strategy-node.mbt'), readFileSync(
    new URL('./templates/strategy-node.mbt', import.meta.url)));
  put(join(modules[1].root, 'src/driver/moon.pkg'),
    'supported_targets = "js"\nimport { "actql/actql/physical_host" @host, }\n');
  const manifest = {package: 'fixture/portable/driver', module: 'Contribution',
    configuration: 'Configuration', configure: 'configure', registration: 'registration',
    contribution: 'contribution', dispatch: 'dispatch', completion_dispatch: 'complete_dispatch',
    dispatch_result: 'Unit', dispatch_error: {package: 'actql/actql/physical_strategy', type: 'RunIssue'},
    estimate_error: {package: 'actql/actql/physical_strategy', type: 'RunIssue'},
    estimate_policy: null, resource_policy: null};
  put(join(modules[1].root, 'declarations/compute-bundle.json'), JSON.stringify(manifest));
  put(join(modules[1].root, 'declarations/node-bundle.json'), JSON.stringify({strategy: {
    module: 'node/strategy.mjs', export: 'installPortable'}}));
  put(join(modules[1].root, 'node/strategy.mjs'), 'export function installPortable() {}\nthrow new Error("NoBuildTimeImport");\n');
  const configuration = {target: 'js', modules, host: 'fixture/host',
    connectors: [{name: 'portable', module: 'fixture/portable', directory: 'declarations'}]};
  return {root, modules, put, configuration, resolved: resolveConnectorBuildInputs(configuration)};
}

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
  writeFileSync(file, JSON.stringify({...entry.manifest, package: 'actql/actql/physical_host'}));
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

test('external Read/Effect loading and dynamic runtime discovery are not implied by Compute assembly', t => {
  const f = fixture(t), root = f.modules[2].root;
  for (const options of [{installations: true}, {loading: 'selected'}]) {
    assert.throws(() => checkNodeAssembly(root, true, {buildInputs: f.resolved, ...options}),
      /UnsupportedExternalNodeBuildProfile/);
  }
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

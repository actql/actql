import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {readHostBundles} from './connector-node-bundles.mjs';
import {inspectCore, copyProductionCore, tokens, readPackageTargetOptions} from './portable-core.mjs';

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
    validate_binding: 'validate_binding',
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

function npmFixture(t) {
  const f = fixture(t);
  f.configuration.modules = [f.modules[0], f.modules[2]];
  f.mod(2, ['actql/actql@0.0.1']);
  f.connector = join(f.root, 'npm-connector');
  const h = hostFixture(f, ['source']);
  delete h.installation.providerBundle;
  rmSync(dirname(h.providerPath), {recursive: true});
  h.write();
  const pin = {name: '@actql-connectors/numeric', version: '1.2.3', root: f.connector};
  const metadata = {name: pin.name, version: pin.version, type: 'module',
    peerDependencies: {'@actql/local-node': '0.0.1'}};
  const packagePath = join(f.connector, 'package.json');
  const writePackage = (value = metadata) => f.put(packagePath, JSON.stringify(value));
  f.put(join(f.modules[0].root, 'packages/local-node/package.json'),
    JSON.stringify({name: '@actql/local-node', version: '0.0.1'}));
  writePackage();
  f.configuration.packages = [pin];
  f.configuration.connectors = [{name: 'numeric', package: pin.name,
    directory: 'src/connectors/numeric'}];
  return {...f, h, pin, metadata, packagePath, writePackage};
}

test('npm-only Source resolves exact pinned ownership without a MoonBit contribution', t => {
  const f = npmFixture(t), resolved = resolveConnectorBuildInputs(f.configuration);
  const owner = resolved.modules.find(value => value.namespace === f.pin.name);
  assert.deepEqual(owner, {namespace: f.pin.name, version: '1.2.3', root: f.connector,
    source: '.', sourceRoot: f.connector, dependencies: {}, kind: 'npm'});
  assert.deepEqual(resolved.modules.map(value => value.namespace),
    ['actql/actql', 'example/host', f.pin.name]);
  const [entry] = resolved.hostEntries;
  assert.equal(entry.namespace, f.pin.name);
  assert.equal(entry.root, f.connector);
  assert.equal(entry.sourceRoot, f.connector);
  assert.equal(entry.revision, 'numeric/0.1');
  assert.equal(entry.source.modulePath, join(f.connector, f.h.installation.source.module));
  assert.equal(entry.effect, undefined);
  assert.equal(entry.providerBundle, undefined);
  assert.equal(entry.providerPackagePath, undefined);
  assert.deepEqual(resolved.computeEntries, []);
  assert.deepEqual(resolved.nodeEntries, []);
  assert.equal(readHostBundles(resolved.host.root, {buildInputs: resolved}), resolved.hostEntries);
  assert.ok(Object.isFrozen(owner.dependencies));
  assert.ok(Object.isFrozen(entry.source.exports));
  f.writePackage({...f.metadata, version: '9.9.9'});
  f.h.write({...f.h.installation, revision: 'numeric/0.2'});
  assert.equal(owner.version, '1.2.3');
  assert.equal(entry.revision, 'numeric/0.1');
});

test('npm-only pins require exact package and sole original Host peer identities', t => {
  const f = npmFixture(t);
  for (const change of [
    {name: '@actql-connectors/other'}, {version: '1.2.4'}, {type: 'commonjs'},
    {peerDependencies: {}}, {peerDependencies: {'@actql/local-node': '^0.0.1'}},
    {peerDependencies: {'@actql/local-node': '0.0.1', hidden: '1.0.0'}},
    {dependencies: {}}, {scripts: {}},
  ]) {
    f.writePackage({...f.metadata, ...change});
    assert.throws(() => resolveConnectorBuildInputs(f.configuration),
      /npm Connector identity or Host dependency mismatch/, JSON.stringify(change));
  }
  f.writePackage();
  for (const change of [{name: 'unscoped'}, {version: '^1.2.3'}, {root: './relative'}]) {
    assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
      packages: [{...f.pin, ...change}]}), /Invalid explicit npm Connector pin/);
  }
  f.put(join(f.modules[0].root, 'packages/local-node/package.json'),
    JSON.stringify({name: '@actql/local-node', version: '0.0.2'}));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Host dependency mismatch/);
});

test('npm-only ownership refuses overlapping roots ambiguous selectors and npm Hosts', t => {
  const f = npmFixture(t), selection = f.configuration.connectors[0];
  for (const root of [f.modules[0].root, f.modules[2].root,
    join(f.modules[2].root, 'nested'), f.root]) {
    assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
      packages: [{...f.pin, root}]}), /overlapping npm Connector ownership/);
  }
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    packages: [f.pin, f.pin]}), /overlapping npm Connector ownership/);
  for (const selected of [
    {...selection, module: 'example/numeric'},
    {name: 'numeric', module: f.pin.name, directory: selection.directory},
    {...selection, package: 'example/host'}, {...selection, package: '@absent/connector'},
  ]) assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    connectors: [selected]}), /Invalid or duplicate Connector selection/);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration, host: f.pin.name}),
    /separate explicit Host module and Core/);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    connectors: [{...selection, revision: 'numeric/0.2'}]}), /Host Connector identity mismatch/);
});

test('npm-only Source refuses MoonBit metadata and Compute Node or provider contributions', t => {
  const f = npmFixture(t);
  for (const name of ['moon.mod', 'moon.mod.json']) {
    const path = join(f.connector, name);
    f.put(path, '{}');
    assert.throws(() => resolveConnectorBuildInputs(f.configuration),
      /Ambiguous npm and MoonBit Connector ownership/);
    rmSync(path);
  }
  for (const name of ['compute', 'node']) {
    const path = join(f.connector, 'src/connectors/numeric', `${name}-bundle.json`);
    f.put(path, '{}');
    assert.throws(() => resolveConnectorBuildInputs(f.configuration),
      /npm-only Connector cannot select a MoonBit contribution/);
    rmSync(path);
  }
  f.h.write({...f.h.installation, providerBundle: 'connectors/numeric/host_node'});
  assert.throws(() => resolveConnectorBuildInputs(f.configuration),
    /npm-only Connector cannot select a MoonBit contribution/);
});

test('npm-only package roots metadata and adapter paths retain alias and escape refusals', t => {
  const f = npmFixture(t), rootAlias = join(f.root, 'npm-alias');
  symlinkSync(f.connector, rootAlias, 'dir');
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    packages: [{...f.pin, root: rootAlias}]}), /aliased or nonregular build input/);
  const originalPackage = join(f.root, 'original-package.json');
  f.put(originalPackage, readFileSync(f.packagePath));
  rmSync(f.packagePath); symlinkSync(originalPackage, f.packagePath);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /aliased or nonregular build input/);
  rmSync(f.packagePath); f.writePackage();
  const adapter = join(f.connector, f.h.installation.source.module);
  const originalAdapter = join(f.root, 'original-source.mjs');
  f.put(originalAdapter, readFileSync(adapter));
  rmSync(adapter); symlinkSync(originalAdapter, adapter);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /aliased or nonregular build input/);
  rmSync(adapter); f.put(adapter, readFileSync(originalAdapter));
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    connectors: [{...f.configuration.connectors[0], directory: '../host'}]}), /relative path/);
});

test('compiler standard-library imports remain toolchain-owned and explicit shadow pins refuse', t => {
  const f = fixture(t), path = join(f.connector, 'src/driver/moon.pkg');
  f.put(path, 'supported_targets = "js"\nimport { "actql/actql/connector_sdk", ' +
    '"moonbitlang/core/array", }\n');
  assert.equal(resolveConnectorBuildInputs(f.configuration)
    .resolvePackage('example/numeric/driver'), path);
  for (const namespace of ['moonbitlang/core', 'moonbitlang/core/array']) {
    const root = join(f.root, 'compiler-shadow');
    f.put(join(root, 'moon.mod'), `name = "${namespace}"\nversion = "0.0.1"\n`);
    assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
      modules: [...f.modules, {namespace, version: '0.0.1', root}]}),
    /Compiler standard library cannot be supplied or shadowed/);
  }
});

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
  assert.throws(() => resolved.resolvePackage('actql/actql/connector_sdk'), /Unsupported build metadata syntax/);
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

function targetClause(source) {
  const list = tokens(source);
  let index = 0;
  const take = (kind, value) => {
    const token = list[index++];
    assert.equal(token?.kind, kind);
    if (value !== undefined) assert.equal(token.value, value);
    return token.value;
  };
  take('word', 'options');
  const result = readPackageTargetOptions({take, peek: value => list[index]?.value === value});
  assert.equal(index, list.length);
  return result;
}

test('shared target reader retains both actual selected Core package target clauses', () => {
  for (const [name, expected] of [
    ['physical_resources', [
      ['original_inventory_index_js_wbtest.mbt', ['js']],
      ['preparation_inventory_backing_nonjs_wbtest.mbt', ['not', 'js']],
      ['node_managed_run_admission.mbt', ['js']],
      ['node_preparation_admission.mbt', ['js']],
      ['node_preparation_cleanup.mbt', ['js']],
      ['node_managed_run_bootstrap_wbtest.mbt', ['js']],
      ['node_managed_run_cleanup_wbtest.mbt', ['js']],
      ['node_managed_run_admission_wbtest.mbt', ['js']],
      ['node_managed_run_current_wbtest.mbt', ['js']],
      ['node_managed_run_continuation_wbtest.mbt', ['js']],
      ['node_managed_run_preparation_lifetime_wbtest.mbt', ['js']],
      ['node_managed_run_unsupported.mbt', ['not', 'js']],
      ['node_original_source_child_js.mbt', ['js']],
      ['node_managed_run_admission_js.mbt', ['js']],
      ['node_preparation_admission_js.mbt', ['js']],
      ['node_preparation_lifecycle_js.mbt', ['js']],
      ['node_preparation_lifecycle_unsupported.mbt', ['not', 'js']],
      ['node_preparation_admission_wbtest.mbt', ['js']],
      ['node_preparation_cleanup_wbtest.mbt', ['js']],
      ['node_managed_run_admission_js_wbtest.mbt', ['js']],
      ['node_original_source_child_js_wbtest.mbt', ['js']],
      ['ledger_usage_js_boundary_wbtest.mbt', ['js']],
      ['imported_child_ledger_wasm.mbt', ['wasm']],
      ['platform_vm_capacity_wasm.mbt', ['wasm']],
      ['platform_vm_capacity_unsupported.mbt', ['not', 'wasm']],
      ['imported_child_ledger_unsupported.mbt', ['not', 'wasm']],
      ['imported_child_ledger_unsupported_wbtest.mbt', ['not', 'wasm']],
    ]],
    ['client_local_host', [
      ['collection_request_finalization_js_wbtest.mbt', ['js']],
      ['managed_import_reentry_js_wbtest.mbt', ['js']],
      ['original_values_text_working_js_wbtest.mbt', ['js']],
      ['preparation_request_native_document_js_wbtest.mbt', ['js']],
      ['preparation_request_native_intake_js_wbtest.mbt', ['js']],
      ['preparation_request_native_intake_retirement_js_wbtest.mbt', ['js']],
      ['preparation_request_acquired_graph_js_wbtest.mbt', ['js']],
      ['preparation_request_model_graph_js_wbtest.mbt', ['js']],
      ['request_native_keyed_plan_js_wbtest.mbt', ['js']],
      ['preparation_request_model_materials_js_wbtest.mbt', ['js']],
      ['preparation_request_model_recovery_js_wbtest.mbt', ['js']],
      ['preparation_request_model_module_js_wbtest.mbt', ['js']],
      ['preparation_request_serialization_graph_js_wbtest.mbt', ['js']],
      ['preparation_effect_capture_recovery_js_wbtest.mbt', ['js']],
      ['installed_effect_definition_capacity_js_wbtest.mbt', ['js']],
      ['installed_effect_empty_headers_js_wbtest.mbt', ['js']],
      ['installed_whole_source_publication_js_wbtest.mbt', ['js']],
      ['installed_whole_source_result_js_wbtest.mbt', ['js']],
      ['installed_whole_source_query_time_js_wbtest.mbt', ['js']],
      ['preparation_request_check_boundary_js_wbtest.mbt', ['js']],
      ['preparation_request_check_observation_js_wbtest.mbt', ['js']],
      ['preparation_request_supplied_observation_js_wbtest.mbt', ['js']],
      ['preparation_request_policy_fixture_js_wbtest.mbt', ['js']],
      ['preparation_request_policy_check_js_wbtest.mbt', ['js']],
      ['installed_whole_source_plan_js_wbtest.mbt', ['js']],
      ['installed_whole_source_dispatch_js_wbtest.mbt', ['js']],
      ['installed_kintone_create_plan_js_wbtest.mbt', ['js']],
      ['installed_kintone_whole_source_js_wbtest.mbt', ['js']],
      ['installed_effect_operation_borrow_js_wbtest.mbt', ['js']],
      ['installed_effect_host_preview_input_js_wbtest.mbt', ['js']],
      ['installed_effect_staged_input_js_wbtest.mbt', ['js']],
      ['installed_effect_header_lifetime_js_wbtest.mbt', ['js']],
      ['installed_effect_native_control_js_wbtest.mbt', ['js']],
      ['installed_effect_discarded_projection_js_wbtest.mbt', ['js']],
      ['installed_effect_operation_index_js_wbtest.mbt', ['js']],
      ['preparation_parameter_source_current_wbtest.mbt', ['js']],
      ['preparation_program_check_context_input_js_wbtest.mbt', ['js']],
      ['preparation_program_check_core_js_wbtest.mbt', ['js']],
      ['preparation_program_check_delta_binding_js_wbtest.mbt', ['js']],
      ['preparation_program_check_evidence_work_js_wbtest.mbt', ['js']],
      ['preparation_program_check_imported_js_wbtest.mbt', ['js']],
      ['preparation_program_check_inputs_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_tail_js_wbtest.mbt', ['js']],
      ['preparation_program_check_pipeline_entry_js_wbtest.mbt', ['js']],
      ['preparation_program_check_topology_entry_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_snapshot_batch_js_wbtest.mbt', ['js']],
      ['preparation_program_check_parameters_js_wbtest.mbt', ['js']],
      ['preparation_program_check_topology_locals_js_wbtest.mbt', ['js']],
      ['preparation_program_check_current_js_wbtest.mbt', ['js']],
      ['preparation_program_check_finish_js_wbtest.mbt', ['js']],
      ['preparation_program_compile_js_wbtest.mbt', ['js']],
      ['preparation_request_program_body_js_wbtest.mbt', ['js']],
      ['preparation_request_effect_body_js_wbtest.mbt', ['js']],
      ['preparation_request_effect_original_js_wbtest.mbt', ['js']],
      ['preparation_request_effect_model_js_wbtest.mbt', ['js']],
      ['preparation_request_capture_body_js_wbtest.mbt', ['js']],
      ['preparation_request_model_js_wbtest.mbt', ['js']],
      ['model_scope_demand_js_wbtest.mbt', ['js']],
      ['content_original_execution_demand_js_wbtest.mbt', ['js']],
      ['preparation_request_same_stage_model_js_wbtest.mbt', ['js']],
      ['preparation_request_content_body_js_wbtest.mbt', ['js']],
      ['preparation_request_keyed_content_js_wbtest.mbt', ['js']],
      ['preparation_request_keyed_prefix_js_wbtest.mbt', ['js']],
      ['preparation_request_serialization_compilation_js_wbtest.mbt', ['js']],
      ['installed_keyed_content_originals_js_wbtest.mbt', ['js']],
      ['installed_capture_original_row_js_wbtest.mbt', ['js']],
      ['installed_keyed_capture_parent_js_wbtest.mbt', ['js']],
      ['installed_capture_provider_source_js_wbtest.mbt', ['js']],
      ['preparation_request_query_syntax_js_wbtest.mbt', ['js']],
      ['preparation_request_large_literal_js_wbtest.mbt', ['js']],
      ['preparation_request_query_selection_js_wbtest.mbt', ['js']],
      ['preparation_request_query_lowering_js_wbtest.mbt', ['js']],
      ['preparation_request_snapshot_js_wbtest.mbt', ['js']],
      ['preparation_request_native_input_js_wbtest.mbt', ['js']],
      ['preparation_request_parent_js_wbtest.mbt', ['js']],
      ['preparation_request_work_calls_js_wbtest.mbt', ['js']],
      ['preparation_host_initial_js_wbtest.mbt', ['js']],
      ['preparation_request_terminal_js_wbtest.mbt', ['js']],
      ['preparation_request_parameters_js_wbtest.mbt', ['js']],
      ['preparation_request_intent_js_wbtest.mbt', ['js']],
      ['preparation_request_plan_input_js_wbtest.mbt', ['js']],
      ['preparation_request_compilation_handoff_js_wbtest.mbt', ['js']],
      ['preparation_request_artifact_retention_js_wbtest.mbt', ['js']],
      ['native_publication_workspace_js_wbtest.mbt', ['js']],
      ['preparation_request_model_query_time_js_wbtest.mbt', ['js']],
      ['preparation_request_invocation_js_wbtest.mbt', ['js']],
      ['preparation_request_document_js_wbtest.mbt', ['js']],
      ['preparation_recursive_snapshot_layout_js_wbtest.mbt', ['js']],
      ['preparation_request_native_computation_js_wbtest.mbt', ['js']],
      ['preparation_managed_publication_js_wbtest.mbt', ['js']],
      ['preparation_request_program_json_js_wbtest.mbt', ['js']],
      ['preparation_request_handoff_js_wbtest.mbt', ['js']],
      ['preparation_request_check_parent_js_wbtest.mbt', ['js']],
      ['preparation_program_check_source_js_wbtest.mbt', ['js']],
      ['preparation_program_check_collection_js_wbtest.mbt', ['js']],
      ['preparation_program_check_resolution_js_wbtest.mbt', ['js']],
      ['preparation_program_check_pipeline_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_entry_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_index_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_groups_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_snapshot_js_wbtest.mbt', ['js']],
      ['preparation_program_check_local_snapshot_reference_js_wbtest.mbt', ['js']],
      ['preparation_module_call_js.mbt', ['js']],
      ['preparation_module_call_portable.mbt', ['wasm', 'wasm-gc', 'native']],
      ['preparation_closed_values_module_wbtest.mbt', ['js']],
      ['preparation_closed_values_module_fault_wbtest.mbt', ['js']],
      ['preparation_closed_values_module_controls_wbtest.mbt', ['js']],
      ['preparation_closed_values_module_adoption_wbtest.mbt', ['js']],
      ['preparation_publication_custody_wbtest.mbt', ['js']],
      ['preparation_publication_snapshot_wbtest.mbt', ['js']],
      ['preparation_publication_start_custody_wbtest.mbt', ['js']],
      ['preparation_publication_validation_custody_wbtest.mbt', ['js']],
      ['installed_direct_occurrences_js_wbtest.mbt', ['js']],
      ['installed_effect_content_model_js_wbtest.mbt', ['js']],
      ['installed_effect_operation_parent_js_wbtest.mbt', ['js']],
      ['installed_effect_provider_plan_js_wbtest.mbt', ['js']],
      ['installed_capture_parent_js_wbtest.mbt', ['js']],
      ['managed_source_free_preparation_js_wbtest.mbt', ['js']],
    ]],
  ]) {
    const source = readFileSync(new URL(`../src/${name}/moon.pkg`, import.meta.url), 'utf8');
    const start = source.indexOf('\noptions(');
    assert(start >= 0);
    assert.deepEqual(targetClause(source.slice(start + 1)), expected);
  }
});

test('package target DATA survives original path resolution and isolated production copying', t => {
  const f = fixture(t), core = f.modules[0].root;
  const path = join(core, 'src/connector_sdk/moon.pkg');
  const data = [
    ['first.mbt', ['js']], ['second.mbt', ['not', 'wasm']],
    ['unlisted.mbt', ['future-compiler-data']], ['ignored_wbtest.mbt', ['js']],
  ];
  const source = 'supported_targets = "+js+wasm+native"\noptions(targets: {\n' +
    data.map(([file, value]) => `${JSON.stringify(file)}: ${JSON.stringify(value)},`).join('\n') + '\n},)\n';
  f.put(path, source);
  for (const name of ['first.mbt', 'second.mbt']) f.put(join(dirname(path), name),
    'pub fn identity(x : Int) -> Int { x }\n');
  f.put(join(dirname(path), 'ignored_wbtest.mbt'), 'test { }\n');
  const resolved = resolveConnectorBuildInputs(f.configuration);
  assert.equal(resolved.resolvePackage('actql/actql/connector_sdk'), path);
  assert.equal(readFileSync(path, 'utf8'), source);
  const isolated = join(f.root, 'isolated');
  copyProductionCore(core, isolated, ['connector_sdk']);
  const copied = readFileSync(join(isolated, 'src/connector_sdk/moon.pkg'), 'utf8');
  assert.deepEqual(targetClause(copied.slice(copied.indexOf('\noptions(') + 1)), data.slice(0, 3));
  assert.equal(readFileSync(path, 'utf8'), source);
});

test('shared package target reader refuses unknown duplicate malformed and nonliteral options', t => {
  const f = fixture(t), core = f.modules[0].root, path = join(core, 'src/connector_sdk/moon.pkg');
  const valid = 'options(targets: {"main.mbt": ["js"]})';
  for (const invalid of [
    'options(link: ["socket"])', 'options(targets: {"main.mbt": [js]})',
    'options(targets: {"main.mbt": "js"})', 'options(targets: {"main.mbt": [["js"]]})',
    'options(targets: {"main.mbt": ["js"], "main.mbt": ["wasm"]})',
    'options(targets: {"main.mbt": ["js"]}, link: ["socket"])',
    'options(targets: {"main.mbt": ["js"]},,)',
    'options(targets: {"main.mbt": ["js"]}', valid + '\n' + valid,
    'options(targets: {})\noptions(targets: {})', valid + '\nunknown = "hidden"',
  ]) {
    f.put(path, 'supported_targets = "+js+wasm+native"\n' + invalid);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration)
      .resolvePackage('actql/actql/connector_sdk'), undefined, invalid);
    assert.throws(() => inspectCore(core, ['connector_sdk']), undefined, invalid);
  }
});

test('literal package targets never hide imports source FFI foreign files or JS incompatibility', t => {
  const f = fixture(t), core = f.modules[0].root, path = join(core, 'src/connector_sdk/moon.pkg');
  const targets = '\noptions(targets: {"hidden.mbt": ["wasm"]})\n';
  const base = 'supported_targets = "+js+wasm+native"\n';
  f.put(path, base + 'import {"unavailable/driver" @pure}\n' + targets);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration)
    .resolvePackage('actql/actql/connector_sdk'), /Unavailable package namespace/);
  assert.throws(() => inspectCore(core, ['connector_sdk']), /UnreviewedExternal/);
  f.put(path, base + targets);
  f.put(join(dirname(path), 'hidden.mbt'), 'extern "js" fn hidden() -> Int = "Date.now"');
  assert.throws(() => inspectCore(core, ['connector_sdk']), /CoreEnvironmentAccess/);
  f.put(join(dirname(path), 'hidden.mbt'), 'pub fn identity(x : Int) -> Int { x }\n');
  f.put(join(dirname(path), 'hidden.c'), 'int hidden(void) { return 1; }\n');
  assert.throws(() => inspectCore(core, ['connector_sdk']), /CoreForeignFile/);
  f.put(path, 'supported_targets = "native"\n' + targets);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration)
    .resolvePackage('actql/actql/connector_sdk'), /Incompatible JS target/);
  f.put(path, base + 'pkgtype(kind: "unreviewed")\n' + targets);
  assert.throws(() => resolveConnectorBuildInputs(f.configuration)
    .resolvePackage('actql/actql/connector_sdk'), /Unsupported package kind/);
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

test('reviewed ESM linker format preserves the original module and dependency inputs', t => {
  const f = fixture(t);
  const esm = 'options("link-flags": ["-js-format", "esm"])\n';
  for (const selected of [esm, 'options(\n  "link-flags": [ "-js-format", "esm" ],\n)\n']) for (const index of [0, 1, 2]) {
    const path = join(f.modules[index].root, 'moon.mod');
    const original = readFileSync(path, 'utf8');
    f.put(path, original + selected);
    assert.equal(resolveConnectorBuildInputs(f.configuration).computeEntries.length, 1);
    assert.equal(readFileSync(path, 'utf8'), original + selected);
    f.put(path, original);
  }
});

test('module format review refuses extra flags, hooks and duplicate options', t => {
  const f = fixture(t);
  const esm = 'options("link-flags": ["-js-format", "esm"])';
  for (const extra of [
    'options("link-flags": ["-js-format", "esm",,],)',
    'options("link-flags": ["-js-format", "esm"],,)',
    'options("link-flags": ["-js-format", "cjs"])',
    'options("link-flags": ["-js-format", "esm", "-other"])',
    'options("link-flags": ["esm", "-js-format"])',
    'options("pre-build": ["-js-format", "esm"])',
    'options("link-flags": ["-js-format", "esm"], deps: {})',
    esm + '\n' + esm, esm.slice(0, -1),
  ]) {
    f.mod(1, ['actql/actql@0.0.1'], extra);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration),
      {message: 'Unsupported or duplicate module metadata: options'});
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

test('selected packages preserve compiler-owned literal targets and refuse structural options', t => {
  const f = fixture(t);
  const path = join(f.connector, 'src/driver/moon.pkg');
  const original = readFileSync(path, 'utf8');
  for (const source of [
    'options(targets: {"local_file.mbt": ["js"], "fallback.mbt": ["not", "wasm"],})',
    // Literal target DATA is retained for the pinned compiler, not resolved as file I/O.
    'options(targets: {"../outside.mbt": ["js"]})',
    'options(targets: {"/outside.mbt": ["js"]})',
    'options(targets: {"sub/file.mbt": ["js"]})',
    'options(targets: {"file.js": ["js"]})',
    'options(targets: {"file.mbt": []})',
    'options(targets: {"file.mbt": ["not"]})',
    'options(targets: {"file.mbt": ["unknown"]})',
    'options(targets: {"file.mbt": ["not", "unknown"]})',
    'options(targets: {"file.mbt": ["js", "native"]})',
    ...['physical_resources', 'client_local_host'].map(name => {
      const source = readFileSync(new URL(`../src/${name}/moon.pkg`, import.meta.url), 'utf8');
      return source.slice(source.indexOf('options('));
    }),
  ]) {
    f.put(path, original + source);
    assert.equal(resolveConnectorBuildInputs(f.configuration).computeEntries.length, 1);
    assert.equal(readFileSync(path, 'utf8'), original + source);
  }
  for (const option of [
    'options(targets: {"file.mbt": ["js"], "file.mbt": ["js"]})',
    'options(targets: {}) options(targets: {})',
    'options(targets: {}, deps: {"absent/dependency": "1.0.0"})',
    'options(targets: {}, "native-stub": ["outside.c"])',
    'options(targets: {}, link: {"js": {"flags": "unsafe"}})',
    'options(targets: {}) import {"absent/dependency/hidden"}',
    'options(targets: {"file.mbt": ["js"]} ',
  ]) {
    f.put(path, original + option);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), undefined, option);
  }
});

test('compiler standard library cannot be shadowed and lookalikes require declared owners', t => {
  for (const namespace of ['moonbitlang/core', 'moonbitlang/core/encoding']) {
    const f = fixture(t);
    assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
      modules: [...f.configuration.modules, {namespace, version: '0.0.1', root: join(f.root, 'shadow')}],
    }), /standard library cannot be supplied or shadowed/);
  }
  for (const imported of ['moonbitlang/core_evil/encoding', 'moonbitlang/coreevil/encoding']) {
    const f = fixture(t);
    const path = join(f.connector, 'src/driver/moon.pkg');
    f.put(path, readFileSync(path, 'utf8') + `import {${JSON.stringify(imported)}}`);
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Unavailable package namespace/);
  }
});

// Rebuild-time assembly only. Concrete module references come from manifests
// owned by connector packages; the common Host has no provider imports.
import {readFileSync, existsSync, writeFileSync, mkdirSync, lstatSync} from 'node:fs';
import {dirname, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {stop} from 'esbuild';
import {checkComputeAssembly} from './connector-compute-bundles.mjs';
import {checkRelaClientBridges} from './client-bridge-mirrors.mjs';
export {checkRelaClientBridges} from './client-bridge-mirrors.mjs';
import {connectorManifestSelection} from './connector-manifest-selection.mjs';
import {readHostBundles, generateInstallations, moduleSpecifier} from './connector-host-bundles.mjs';
import {projectCoreLedger} from './generate-ledger-transport-contract.mjs';
export {checkHostBundle, readHostBundles, generateInstallations} from './connector-host-bundles.mjs';

// The Core record owns both field order and primitive width. This is only
// its generated Int64 bridge projection, not another usage schema.
function renderStrategyLedgerUsage(source) {
  return projectCoreLedger(source).usage.map(({name, bits}) =>
    `    usage.${name}${bits === 32 ? '.to_int64()' : ''},`).join('\n');
}

export function checkNodeAssembly(root, write = false, options = {}) {
const buildInputs = options.buildInputs;
if (buildInputs !== undefined && (options.names !== undefined ||
    resolve(root) !== buildInputs.host.root)) {
  throw new Error('InvalidResolvedNodeBuildSelection');
}
const sourceRoot = buildInputs?.host.sourceRoot ?? join(root, 'src');
const coreRoot = buildInputs?.coreRoot ?? root;
const assembly = options.assembly ?? 'connectors_builtin';
const bridgePackage = options.bridge ?? 'connectors_builtin_node';
const adapter = options.adapter ?? 'connectors-builtin';
const loading = options.loading ?? (buildInputs === undefined ? 'selected' : 'static');
const nativeRemoteStandard = options.nativeRemoteStandard ?? (buildInputs === undefined);
const selectedFamilies = options.selectedFamilies ??
  (buildInputs === undefined && bridgePackage === 'connectors_builtin_node');
if (!['selected', 'static'].includes(loading)) throw new Error('Invalid module loading profile');
if (![assembly, bridgePackage].every(value => /^[a-z][a-z0-9_]*$/.test(value)) ||
    !/^[a-z][a-z0-9_-]*$/.test(adapter)) throw new Error('Invalid bridge output');
const withInstallations = options.installations ??
  (buildInputs === undefined && adapter === 'connectors-builtin');
if (buildInputs !== undefined && loading !== 'static') {
  throw new Error('UnsupportedExternalNodeBuildProfile');
}
if (buildInputs !== undefined) {
  // External compositions use a generated bridge. Product Client extensions
  // have their own inputs and are not inferred from files.
  for (const name of ['local_carrier_bridge.mbt', 'client_program_bridge.mbt',
    'client_infer_bridge.mbt', 'authorization_bridge.mbt', 'client_check.mbt',
    'client_update_target_bridge.mbt', 'client_effect_content_bridge.mbt',
    'client_recovered_content_bridge.mbt',
    'client-program-dependencies.json', 'client-execution-dependencies.json']) {
    const path = join(sourceRoot, bridgePackage, name);
    try { lstatSync(path); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    throw new Error('UnsupportedExternalNodeBridgeExtension');
  }
}
const selected = buildInputs?.entries ?? connectorManifestSelection(root, {names: options.names});
for (const entry of selected) {
  if (entry.node !== undefined && entry.compute === undefined) {
    throw new Error(`Node strategy requires its Compute manifest: ${entry.name}`);
  }
}
const output = join(root, 'adapters', adapter, 'strategy.generated.mjs');
const installationOutput = join(root, 'adapters', adapter, 'installations.generated.mjs');
const outputs = [output, ...(withInstallations ? [installationOutput] : []),
  join(sourceRoot, assembly, 'moon.pkg'),
  join(sourceRoot, assembly, 'compute.generated.mbt'),
  join(sourceRoot, bridgePackage, 'bridge.generated.mbt'),
  join(sourceRoot, bridgePackage, 'moon.pkg')].map(path => resolve(path));
// Check the complete write set before the Compute generator can write anything.
for (let index = 0; index < outputs.length; index++) {
  const path = outputs[index];
  if (outputs.some((other, otherIndex) => otherIndex !== index &&
      (other === path || other.startsWith(path + sep)))) {
    throw new Error('CollidingConnectorAssemblyOutput');
  }
  if (buildInputs !== undefined) buildInputs.outputPath(relative(buildInputs.host.root, path));
  else {
    let current = resolve(root);
    const parts = relative(current, path).split(sep);
    for (let index = 0; index <= parts.length; index++) {
      if (index) current = join(current, parts[index - 1]);
      let info;
      try { info = lstatSync(current); }
      catch (error) { if (error.code === 'ENOENT') break; throw error; }
      if (info.isSymbolicLink() ||
          !(index === parts.length ? info.isFile() : info.isDirectory())) {
        throw new Error(`Aliased or invalid Host output: ${current}`);
      }
    }
  }
}
const installations = withInstallations
  ? readHostBundles(root, {names: options.names, buildInputs}) : [];
const installationSource = withInstallations
  ? generateInstallations(installations, installationOutput, root) : undefined;
const externalModuleSpecifier = path => moduleSpecifier(output, path);
const entries = buildInputs === undefined ? [] : buildInputs.nodeEntries.map(entry => ({
  name: entry.name, module: externalModuleSpecifier(entry.modulePath),
  symbol: entry.symbol, compute: entry.compute,
}));
for (const {name, node: path, compute: computePath} of buildInputs === undefined ? selected : []) {
  if (path === undefined) continue;
  const manifest = JSON.parse(readFileSync(path, 'utf8'));
  if (Object.keys(manifest).join() !== 'strategy' ||
      Object.keys(manifest.strategy).sort().join() !== 'export,module') {
    throw new Error(`Invalid Node bundle manifest: ${path}`);
  }
  const entry = manifest.strategy;
  const connectorOwnedModule =
    `adapters/connectors/${name}/node/strategy-bundle.mjs`;
  const legacyModule =
    /^adapters\/[a-z0-9_-]+\/strategy-bundle\.mjs$/.test(entry.module);
  if (!(entry.module === connectorOwnedModule || legacyModule) ||
      !/^[A-Za-z_]\w*$/.test(entry.export) || !existsSync(join(root, entry.module))) {
    throw new Error(`Invalid strategy contribution: ${path}`);
  }
  const compute = JSON.parse(readFileSync(computePath, 'utf8'));
  entries.push({name, module: relative(dirname(output), join(root, entry.module)), symbol: entry.export, compute});
}
const moduleLiteral = entry => buildInputs === undefined ? `'${entry.module}'` : JSON.stringify(entry.module);
const source = `// Generated by scripts/connector-node-bundles.mjs; edit connector manifests.\n` + (loading === 'static' ?
  entries.map((entry, index) => `import {${entry.symbol} as contribution${index}} from ${moduleLiteral(entry)};\n`).join('') +
  `\nexport function installStrategyContributions(moon, setup, checked, options) {\n` +
  `  const factories = new Map([\n` +
  entries.map((entry, index) => `    ['${entry.name}', contribution${index}],\n`).join('') +
  `  ]);\n` +
  `  const keys = moon.strategyHostModules(setup);\n` +
  `  if (!Array.isArray(keys) || new Set(keys).size !== keys.length ||\n` +
  `      keys.some(key => !factories.has(key))) {\n` +
  `    throw new Error('Configured module has no unique Node implementation');\n` +
  `  }\n` +
  `  return Object.freeze(keys.map(key => factories.get(key)(moon, setup, checked, options?.[key])));\n}\n` :
  `import {installSelectedContributions} from '../host-node/installation.mjs';\n\n` +
  `const loaders = new Map([\n` +
  entries.map(entry => `  ['${entry.name}', () => import(${moduleLiteral(entry)}).then(module => module.${entry.symbol})],\n`).join('') +
  `]);\n\nexport async function installStrategyContributions(moon, setup, checked, options, signal) {\n` +
  `  return installSelectedContributions(loaders, moon, setup, checked, options, signal);\n}\n`);
const dependencies = new Map([
  [`${buildInputs?.host.namespace ?? 'actql/actql'}/${assembly}`, 'builtin'],
  ['actql/actql/physical_host_dispatch', 'host_driver'],
  ['actql/actql/physical_strategy_host', 'strategy'],
  ['actql/actql/physical_resources', 'resources'],
  ['actql/actql/execution_relation', 'execution'],
  ['actql/actql/connector_sdk', 'connector'],
  ['actql/actql/encode_core', 'encode'],
  ['actql/actql/run_publication', 'publication'],
  ['actql/actql/run_publication_host', 'publication_host'],
  ['actql/actql/publication_payload', 'payload'],
  ['actql/actql/execution_site', 'site'],
  ['actql/actql/remote_site_protocol', 'remote'],
  ['actql/actql/remote_credential', 'credential'],
  ['actql/actql/remote_bundle', 'bundle'],
  ['actql/actql/physical_manifest', 'manifest'],
  ...(nativeRemoteStandard ? [
    ['actql/actql/execution_query', 'query'],
    ['actql/actql/pipeline_check_context', 'context'],
    [
    'actql/actql/platform_native/remote_standard_host',
    'remote_standard',
    ],
  ] : []),
]);
const hasLocalCarrierBridge = existsSync(
  join(sourceRoot, bridgePackage, 'local_carrier_bridge.mbt'),
);
const hasClientProgramBridge = existsSync(
  join(sourceRoot, bridgePackage, 'client_program_bridge.mbt'),
);
if (hasLocalCarrierBridge || hasClientProgramBridge) {
  dependencies.set('actql/actql/connectors/local/driver', 'local_driver');
}
const type = value => {
  if (!dependencies.has(value.package)) dependencies.set(value.package, `binding${dependencies.size}`);
  return `@${dependencies.get(value.package)}.${value.type}`;
};
const host = '@builtin.ConfiguredComputeHost[@strategy.RunIssue]';
let template = readFileSync(buildInputs === undefined
  ? join(coreRoot, 'scripts/templates/strategy-node.mbt')
  : buildInputs.resolveFile('actql/actql', 'scripts/templates/strategy-node.mbt'), 'utf8');
const usageMarker = '    // CORE_LEDGER_USAGE_VALUES';
if (template.split(usageMarker).length !== 2) throw Error('Invalid Core ledger usage projection marker');
template = template.replace(usageMarker, renderStrategyLedgerUsage(readFileSync(
  buildInputs === undefined ? join(coreRoot, 'src/physical_resources/ledger.mbt')
    : buildInputs.resolveFile('actql/actql', 'src/physical_resources/ledger.mbt'), 'utf8')));
// Only a selected Local module can project its sealed producer metadata.
// Keep unrelated backend assemblies independent and explicitly legacy.
const publicationPolicyBlock = /  \/\/ LOCAL_PUBLICATION_BRIDGE_POLICY_BEGIN[\s\S]*?  \/\/ LOCAL_PUBLICATION_BRIDGE_POLICY_END\n/;
if (entries.some(({name}) => name === 'local')) {
  const path = 'actql/actql/connectors/local/driver';
  if (!dependencies.has(path)) dependencies.set(path, `binding${dependencies.size}`);
  template = template.replaceAll('@publication_local_driver', `@${dependencies.get(path)}`)
    .replace('  // LOCAL_PUBLICATION_BRIDGE_POLICY_BEGIN\n', '')
    .replace('  // LOCAL_PUBLICATION_BRIDGE_POLICY_END\n', '');
} else {
  template = template.replace(publicationPolicyBlock,
    '  let bridge_limits : @execution.ManagedPublicationBridgeLimits? = None\n');
}
if (!nativeRemoteStandard) {
  template = template.replace(
    /\/\/ NATIVE_REMOTE_STANDARD_BEGIN[\s\S]*?\/\/ NATIVE_REMOTE_STANDARD_END\n?/,
    '',
  );
} else {
  template = template
    .replace('// NATIVE_REMOTE_STANDARD_BEGIN\n', '')
    .replace('// NATIVE_REMOTE_STANDARD_END\n', '');
}
let bridge = '// Generated by scripts/connector-node-bundles.mjs; edit the common template or manifests.\n' +
  template;
const managedStartIssues = [];
for (const {name, compute: c} of entries) {
  // These fields are validated by the Compute assembly generator. No code,
  // module names or payload rules are inferred from runtime connector IDs.
  if (!/^[a-z][a-z0-9_]*$/.test(name) || !/^[a-z][a-z0-9_]*$/.test(c.registration)) throw new Error('Invalid bridge declaration');
  const moduleType = type({package:c.package, type:c.module});
  const pkg = moduleType.slice(0, moduleType.lastIndexOf('.'));
  const result = c.dispatch_result === 'Unit' ? 'Unit' : Array.isArray(c.dispatch_result)
    ? `(${c.dispatch_result.map(type).join(', ')})` : type(c.dispatch_result);
  bridge += `
///|
#export_name("strategyModule_${name}_Registration")
pub fn ${name}_registration(setup : ${host}) -> @connector.CapabilityRegistration {
  ${pkg}.${c.registration}(@builtin.configured_${name}_module(@builtin.configured_host_modules(setup)).unwrap())
}

///|
#export_name("strategyModule_${name}_Dispatch")
pub fn ${name}_dispatch(
  setup : ${host},
  task : @host_driver.PreparedTaskDispatch,${c.completion_dispatch ? '\n  completion_ready : () -> Bool,' : ''}
) -> ${result} raise NodeHostFailure {
  match @builtin.dispatch_${name}${c.completion_dispatch ? '_with_completion_admission' : ''}(@builtin.configured_host_modules(setup),
    @host_driver.compute_host_dispatch(@builtin.configured_host_runtime(setup)), task${c.completion_dispatch ? ', completion_ready' : ''}) {
    Ok(value) => value
    Err(MissingImplementation) => raise InvalidCommand
    Err(Implementation(issue)) => raise Execution(issue)
  }
}
`;
  if (c.managed_dispatch) {
    const managedResult = `${type(c.managed_dispatch_result)}[Int]${c.managed_dispatch_optional === true ? '?' : ''}`;
    bridge += `
///|
#export_name("strategyModule_${name}_ManagedDispatch")
pub fn ${name}_managed_dispatch(
  setup : ${host},
  completed : Array[@execution.ManagedCompletedOutput[Int]],
  output_file_bytes : Int64,
) -> ${managedResult} raise NodeHostFailure {
  let obligations = match @strategy.captured_next_managed_obligations(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
    @host_driver.compute_host_max_entries(
      @builtin.configured_host_runtime(setup),
    ),
  ) {
    Ok(value) => value
    Err(_) => raise InvalidCommand
  }
  match @builtin.dispatch_managed_${name}(
    @builtin.configured_host_modules(setup), completed, obligations,
    output_file_bytes,
  ) {
    Ok(value) => value
    Err(MissingImplementation) => raise InvalidCommand
    Err(Implementation(issue)) => raise Execution(issue)
  }
}
`;
    if (c.managed_duration) {
      bridge += `
///|
#export_name("strategyModule_${name}_ManagedDuration")
pub fn ${name}_managed_duration(
  setup : ${type(c.managed_dispatch_result)}[Int],
) -> Int64? {
  ${pkg}.${c.managed_duration}(setup)
}
`;
    }
    if (c.managed_capacity) {
      bridge += `
///|
#export_name("strategyModule_${name}_ManagedCapacity")
pub fn ${name}_managed_capacity(
  setup : ${type(c.managed_dispatch_result)}[Int],
) -> (Int64, Int64)? {
  ${pkg}.${c.managed_capacity}(setup)
}
`;
    }
    if (c.managed_start) {
      const managedStart = `${type(c.managed_start_result)}[Int]`;
      const managedIssue = name.split('_').map(part =>
        part[0].toUpperCase() + part.slice(1)).join('') + 'ManagedStart';
      managedStartIssues.push(`  ${managedIssue}(${type(c.managed_start_error)})`);
      bridge += `
///|
#export_name("strategyModule_${name}_ManagedStart")
pub fn ${name}_managed_start(
  setup : ${type(c.managed_dispatch_result)}[Int],
) -> ${managedStart} raise NodeHostFailure {
  match ${pkg}.${c.managed_start}(setup) {
    Ok(value) => value
    Err(issue) => raise ${managedIssue}(issue)
  }
}
`;
    }
  }
}
bridge = bridge.replace('  // MANAGED_START_ISSUES', managedStartIssues.join('\n'));
dependencies.set('actql/actql/effect_application', 'effect');
dependencies.set('actql/actql/remote_transfer', 'transfer');
// The common output receipt bridge projects canonical UTF-8 payload bytes.
dependencies.set('moonbitlang/core/encoding/utf8', 'utf8');
if (existsSync(join(sourceRoot, bridgePackage, 'client_infer_bridge.mbt'))) {
  dependencies.set('actql/actql/model_execution', 'model');
  dependencies.set('actql/actql/client_infer_host', 'infer_host');
  dependencies.set('actql/actql/value_admission', 'admitted');
}
if (existsSync(join(sourceRoot, bridgePackage,
  'client_program_bridge.mbt'))) {
  dependencies.set('actql/actql/client_local_host', 'client_local_host');
  dependencies.set('actql/actql/canonical_json', 'identity');
  dependencies.set('actql/actql/physical_cost', 'cost');
  dependencies.set('moonbitlang/core/json', 'json');
  dependencies.set('actql/actql/connectors/local', 'local');
  dependencies.set('actql/actql/lowering_relation', 'lower');
  dependencies.set('actql/actql/check_environment', 'check_environment');
  dependencies.set('actql/actql/value_admission', 'admitted');
  dependencies.set('actql/actql/program_check', 'program_check');
  dependencies.set('actql/actql/effect_program_binding', 'effect_binding');
  dependencies.set('actql/actql/stage_syntax', 'stage_syntax');
  dependencies.set('actql/actql/source_value', 'source');
  dependencies.set('actql/actql/decode_core', 'decode');
  dependencies.set('moonbitlang/core/encoding/utf8', 'utf8');
}
// Request construction and its shared typed-failure projection borrow the
// existing Source DATA. Other bridge packages do not gain an unused import.
if (existsSync(join(sourceRoot, bridgePackage,
  'client_preparation_root_bridge.mbt')) || existsSync(join(sourceRoot,
  bridgePackage, 'client_program_bridge.mbt'))) {
  dependencies.set('actql/actql/stage_parameters', 'stage_parameters');
  dependencies.set('actql/actql/client_infer_host', 'infer_host');
}
// A bridge package may also contain the handwritten Carrier adapter. Keep its
// runtime dependency after generated connector aliases so their stable names
// continue to match that adapter. Other generated bridge packages do not gain
// the dependency.
if (existsSync(join(sourceRoot, bridgePackage,
  'client_program_bridge.mbt'))) {
  dependencies.set('actql/actql/sourceview_resolution', 'acquisition');
  dependencies.set('actql/actql/query_planning', 'planning');
  const manifestPath = join(sourceRoot,
    bridgePackage === 'connectors_builtin_node_rela'
      ? 'connectors_builtin_node' : bridgePackage,
    'client-program-dependencies.json');
  if (existsSync(manifestPath)) {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    if (Object.keys(manifest).join() !== 'imports' ||
        !Array.isArray(manifest.imports)) {
      throw new Error(`Invalid Client bridge dependencies: ${manifestPath}`);
    }
    for (const entry of manifest.imports) {
      if (entry === null || typeof entry !== 'object' ||
          Object.keys(entry).sort().join() !== 'alias,path' ||
          typeof entry.path !== 'string' ||
          !/^actql\/actql\/[a-z0-9_/]+$/.test(entry.path) ||
          typeof entry.alias !== 'string' ||
          !/^[a-z][a-z0-9_]*$/.test(entry.alias) ||
          dependencies.has(entry.path) ||
          [...dependencies.values()].includes(entry.alias)) {
        throw new Error(`Invalid Client bridge dependency: ${manifestPath}`);
      }
      dependencies.set(entry.path, entry.alias);
    }
  }
  if (selectedFamilies) {
    dependencies.set('actql/actql/local_sga_provider', 'local_sga_provider');
    dependencies.set('actql/actql/managed_graph_storage', 'graph_storage');
    dependencies.set('actql/actql/local_tea_provider', 'local_tea_provider');
    dependencies.set('actql/actql/local_veca_provider', 'local_veca_provider');
    dependencies.set('actql/actql/managed_record_storage', 'record_storage');
  }
}
if (hasLocalCarrierBridge) {
  dependencies.set(
    'actql/actql/managed_carrier_runtime',
    'carrier_runtime',
  );
}
const executionDependencies = join(sourceRoot, bridgePackage,
  'client-execution-dependencies.json');
if (existsSync(executionDependencies)) {
  const manifest = JSON.parse(readFileSync(executionDependencies, 'utf8'));
  if (Object.keys(manifest).join() !== 'imports' ||
      !Array.isArray(manifest.imports)) {
    throw new Error(`Invalid Client execution dependencies: ${executionDependencies}`);
  }
  for (const entry of manifest.imports) {
    if (entry === null || typeof entry !== 'object' ||
        Object.keys(entry).sort().join() !== 'alias,path' ||
        typeof entry.path !== 'string' ||
        !/^actql\/actql\/[a-z0-9_/]+$/.test(entry.path) ||
        typeof entry.alias !== 'string' ||
        !/^[a-z][a-z0-9_]*$/.test(entry.alias) ||
        dependencies.has(entry.path) ||
        [...dependencies.values()].includes(entry.alias)) {
      throw new Error(`Invalid Client execution dependency: ${executionDependencies}`);
    }
    dependencies.set(entry.path, entry.alias);
  }
}
// The handwritten execution-authorization adapter lets the Host gate and the
// activation grant share one runtime, so an evaluated dispatch action reaches
// the captured Run without a second evaluation.
if (existsSync(join(sourceRoot, bridgePackage, 'authorization_bridge.mbt'))) {
  dependencies.set('actql/actql/execution_authorization', 'authorization');
  dependencies.set('moonbitlang/core/debug', 'debug');
}
if (hasClientProgramBridge) {
  dependencies.set('actql/actql/stage_results', 'effect_results');
  dependencies.set('actql/actql/source_frontend', 'source_frontend');
  dependencies.set('actql/actql/query_program', 'query_program');
  dependencies.set('actql/actql/query_syntax', 'query_syntax');
}
if (buildInputs !== undefined) {
  for (const path of dependencies.keys()) {
    if (path === `${buildInputs.host.namespace}/${assembly}`) continue;
    // As in resolvePackage's import walk, the pinned compiler supplies its
    // standard library; it is not another external module to acquire.
    if (path.startsWith('moonbitlang/core/')) continue;
    buildInputs.packagePath(path);
  }
}
const manifest = '// Generated by scripts/connector-node-bundles.mjs.\n' +
  'supported_targets = "js"\n\npkgtype(kind: "foreign_library")\n\nimport {\n' +
  [...dependencies].map(([path, name]) => `  "${path}" @${name},\n`).join('') + '}\n' +
  (bridgePackage === 'connectors_builtin_node' && hasClientProgramBridge
    ? '\nimport {\n  "actql/actql/frontend_source_map" @source_origin,\n} for "wbtest"\n'
    : '');
const formatter = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt') : 'moonfmt';
bridge = execFileSync(formatter, ['-'], {input: bridge, encoding: 'utf8'});
const formattedManifest = execFileSync(formatter, ['-', '-file-type', 'pkg'], {input:manifest, encoding:'utf8'});
checkComputeAssembly(root, write, {names:options.names, directory:assembly, buildInputs});
for (const [path, text] of [[output, source],
  ...(installationSource === undefined ? [] : [[installationOutput, installationSource]]),
  [join(sourceRoot, bridgePackage, 'bridge.generated.mbt'), bridge],
  [join(sourceRoot, bridgePackage, 'moon.pkg'), formattedManifest]]) {
  if (write) { mkdirSync(dirname(path), {recursive:true}); writeFileSync(path, text); }
  else if (!existsSync(path) || readFileSync(path, 'utf8') !== text) throw new Error(`Node connector assembly is stale: ${path}`);
}
return entries.length;
}


export function checkRelaNodeAssembly(root, write = false) {
  checkRelaClientBridges(root, write);
  return checkNodeAssembly(root, write, {
    bridge: 'connectors_builtin_node_rela',
    adapter: 'connectors-builtin-rela',
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const write = process.argv.includes('--write');
  try {
    console.log(`${checkNodeAssembly(root, write)} selected Node strategy contributions verified.`);
    console.log(`${checkRelaNodeAssembly(root, write)} RelA-only Node strategy contributions verified.`);
  } finally {
    await stop();
  }
}

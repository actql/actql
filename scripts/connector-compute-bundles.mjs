// Rebuild-time typed composition. Concrete imports are generated exclusively
// from connector-owned declarations, never interpreted by a runtime planner.
import {readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const keys = (value, expected) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).sort().join() === [...expected].sort().join();
const identifier = value => typeof value === 'string' && /^[a-z][a-z0-9_]*$/.test(value);
const typeName = value => typeof value === 'string' && /^[A-Z][A-Za-z0-9]*$/.test(value);
const packageName = value => typeof value === 'string' && /^actql\/actql\/[a-z][a-z0-9_]*(?:\/[a-z][a-z0-9_]*)*$/.test(value);

export function generateComputeAssembly(entries) {
  const names = new Set();
  const dependencies = new Map([
    ['actql/actql/connector_sdk', 'connector'],
    ['actql/actql/physical_host', 'host'],
    ['actql/actql/execution_relation', 'execution'],
  ]);
  const alias = path => {
    if (!dependencies.has(path)) dependencies.set(path, `binding${dependencies.size}`);
    return dependencies.get(path);
  };
  const typed = value => `@${alias(value.package)}.${value.type}`;
  const resultType = value => value === 'Unit' ? 'Unit'
    : Array.isArray(value) ? `(${value.map(typed).join(', ')})` : typed(value);
  for (const {name, manifest: m} of entries) {
    const managed = Object.hasOwn(m, 'managed_dispatch') ||
      Object.hasOwn(m, 'managed_dispatch_result');
    const managedStart = Object.hasOwn(m, 'managed_start') ||
      Object.hasOwn(m, 'managed_start_result');
    if (!identifier(name) || names.has(name) ||
        !keys(m, ['package', 'module', 'configuration', 'configure', 'registration', 'contribution', 'dispatch', 'dispatch_result', 'dispatch_error', 'estimate_error', 'estimate_policy', 'resource_policy', ...(Object.hasOwn(m, 'synchronous_dispatch') ? ['synchronous_dispatch'] : []), ...(managed ? ['managed_dispatch', 'managed_dispatch_result'] : []), ...(managedStart ? ['managed_start', 'managed_start_result'] : [])]) ||
        (Object.hasOwn(m, 'synchronous_dispatch') && !identifier(m.synchronous_dispatch)) ||
        (managed && (!identifier(m.managed_dispatch) ||
          !keys(m.managed_dispatch_result, ['package', 'type']) ||
          !packageName(m.managed_dispatch_result.package) ||
          !typeName(m.managed_dispatch_result.type))) ||
        (managedStart && (!managed || !identifier(m.managed_start) ||
          !keys(m.managed_start_result, ['package', 'type']) ||
          !packageName(m.managed_start_result.package) ||
          !typeName(m.managed_start_result.type))) ||
        !packageName(m.package) || !(m.package === `actql/actql/connectors/${name}` || m.package.startsWith(`actql/actql/connectors/${name}/`)) ||
        !typeName(m.module) || !typeName(m.configuration) || !identifier(m.configure) ||
        !identifier(m.registration) || !identifier(m.contribution) || !identifier(m.dispatch)) {
      throw new Error('Invalid Compute bundle declaration');
    }
    names.add(name);
    for (const policy of [m.estimate_policy, m.resource_policy]) {
      if (policy !== null &&
          (!keys(policy, ['configuration', 'prepare', 'install', 'work_slots']) ||
           !typeName(policy.configuration) ||
           !identifier(policy.prepare) || !identifier(policy.install) ||
           !identifier(policy.work_slots))) {
        throw new Error('Invalid Compute estimate policy');
      }
    }
    alias(m.package);
    const results = m.dispatch_result === 'Unit' ? []
      : Array.isArray(m.dispatch_result) ? m.dispatch_result : [m.dispatch_result];
    if (Array.isArray(m.dispatch_result) && (results.length < 2 || results.length > 8)) {
      throw new Error('Invalid Compute result tuple');
    }
    for (const result of results) {
      if (!keys(result, ['package', 'type']) || !packageName(result.package) || !typeName(result.type)) {
        throw new Error('Invalid Compute result type');
      }
      alias(result.package);
    }
    if (managed) alias(m.managed_dispatch_result.package);
    if (managedStart) alias(m.managed_start_result.package);
    for (const error of [m.dispatch_error, m.estimate_error]) {
      if (!keys(error, ['package', 'type']) || !packageName(error.package) || !typeName(error.type)) {
        throw new Error('Invalid Compute error projection');
      }
      alias(error.package);
    }
  }
  const parameters = entries.map(({name, manifest: m}) =>
    `  with_${name}? : (@${alias(m.package)}.${m.module}, (${typed(m.dispatch_error)}) -> E, (${typed(m.estimate_error)}) -> E)? = None,\n`).join('');
  const count = entries.map(({name}) => `  if with_${name} is Some(_) { count += 1 }\n`).join('');
  const collect = entries.map(({name, manifest: m}) =>
    `  if with_${name} is Some((installed, dispatch_issue, estimate_issue)) {\n` +
    `    entries.push((@${alias(m.package)}.${m.registration}(installed),\n` +
    `      @${alias(m.package)}.${m.contribution}(installed, dispatch_issue, estimate_issue)))\n` +
    `  }\n`).join('');
  const banner = '// Generated by scripts/connector-compute-bundles.mjs; edit connector manifests.\n';
  return {
    manifest: banner + 'supported_targets = "+js+wasm+native"\n\nimport {\n' +
      [...dependencies].map(([path, name]) => `  "${path}" @${name},\n`).join('') + '}\n',
    source: banner + '///|\n' +
      '/// Pure assembly of an explicit Host implementation subset. Omitted modules\n' +
      '/// remain absent; registration/ownership checks use the shared SDK.\n' +
      'pub fn[E] assemble_compute_contributions(\n' +
      '  registry : @connector.CapabilityRegistry,\n  max_entries : Int,\n' + parameters +
      ') -> Result[@connector.CapabilityImplementations[@host.ComputeContribution[Unit, E]], @connector.CapabilityInstallationIssue] {\n' +
      '  if max_entries < 0 { return Err(InvalidLimits) }\n  let mut count = 0\n' + count +
      '  if count > max_entries { return Err(EntryLimit) }\n' +
      '  let entries : Array[(@connector.CapabilityRegistration, @host.ComputeContribution[Unit, E])] = []\n' + collect +
      '  @connector.install_capability_implementations(registry, entries, max_entries, registry_order=true)\n}\n' + configurationAssembly(entries, alias, typed, resultType),
  };
}

function configurationAssembly(entries, alias, typed, resultType) {
  const fields = entries.map(({name, manifest: m}) =>
    `  installed_${name} : (@${alias(m.package)}.${m.module}, (${typed(m.dispatch_error)}) -> E, (${typed(m.estimate_error)}) -> E)?\n`).join('');
  const parameters = entries.map(({name, manifest: m}) =>
    `  with_${name}? : (@connector.CapabilityRegistration, @${alias(m.package)}.${m.configuration}, (${typed(m.dispatch_error)}) -> E, (${typed(m.estimate_error)}) -> E)? = None,\n`).join('');
  const registrations = entries.map(({name}) =>
    `  if with_${name} is Some((registration, _, _, _)) { registrations.push((registration, ())) }\n`).join('');
  const prepare = entries.map(({name, manifest: m}) =>
    `  let installed_${name} = match with_${name} {\n` +
    `    None => None\n` +
    `    Some((registration, configuration, dispatch_issue, estimate_issue)) => {\n` +
    `      match @${alias(m.package)}.${m.configure}(driver, registry, registration, configuration) {\n` +
    `        Ok(installed) => Some((installed, dispatch_issue, estimate_issue))\n` +
    `        Err(issue) => return Err(dispatch_issue(issue))\n` +
    `      }\n    }\n  }\n`).join('');
  const passed = entries.map(({name}) => `    with_${name}=installed_${name},\n`).join('');
  const stored = entries.map(({name}) => `    installed_${name},\n`).join('');
  const getters = entries.map(({name, manifest: m}) =>
    `\n///|\npub fn[E] configured_${name}_module(value : ConfiguredComputeModules[E]) -> @${alias(m.package)}.${m.module}? {\n  value.installed_${name}.map(value => value.0)\n}\n`).join('');
  const installedKeys = '\n///|\n/// Composition keys only; not capability IDs, resource bindings or dispatch authority.\n' +
    'pub fn[E] configured_compute_module_keys(value : ConfiguredComputeModules[E]) -> Array[String] {\n  let keys = []\n' +
    entries.map(({name}) => `  if value.installed_${name} is Some(_) { keys.push("${name}") }\n`).join('') +
    '  keys\n}\n';
  const dispatches = entries.map(({name, manifest: m}) =>
    `\n///|\n/// Invoke the configured implementation; the connector verifies the exact dispatch ownership.\n` +
    `pub fn[C, E] dispatch_${name}(value : ConfiguredComputeModules[E], host : @host.DispatchHost[C, E], task : @host.PreparedTaskDispatch) -> Result[${resultType(m.dispatch_result)}, ConfiguredDispatchIssue[E]] {\n` +
    `  match value.installed_${name} {\n` +
    `    None => Err(MissingImplementation)\n` +
    `    Some((installed, project, _)) => @${alias(m.package)}.${m.dispatch}(installed, host, task).map_err(issue => Implementation(project(issue)))\n` +
    `  }\n}\n`).join('');
  const managedDispatches = entries.filter(({manifest:m}) => m.managed_dispatch)
    .map(({name, manifest:m}) =>
      `\n///|\n/// Prepare one managed task through the configured implementation.\n` +
    `pub fn[E] dispatch_managed_${name}(value : ConfiguredComputeModules[E], completed : Array[@execution.ManagedCompletedOutput[Int]], obligations : @execution.ManagedObligations, output_file_bytes : Int64) -> Result[${typed(m.managed_dispatch_result)}[Int], ConfiguredDispatchIssue[E]] {\n` +
    `  match value.installed_${name} {\n` +
    `    None => Err(MissingImplementation)\n` +
    `    Some((installed, project, _)) => @${alias(m.package)}.${m.managed_dispatch}(installed, completed, obligations, output_file_bytes).map_err(issue => Implementation(project(issue)))\n` +
    `  }\n}\n`).join('');
  return '\n///|\nstruct ConfiguredComputeModules[E] {\n  driver : @host.DispatchDriver\n' + fields +
    '  contributions : @connector.CapabilityImplementations[@host.ComputeContribution[Unit, E]]\n}\n' +
    '\n///|\n/// Validate the complete registration subset before invoking any connector factory.\n' +
    '/// Configuration is synchronous and cannot authorize provider I/O or task start.\n' +
    'pub fn[E] configure_compute_modules(\n' +
    '  driver : @host.DispatchDriver,\n  registry : @connector.CapabilityRegistry,\n' +
    '  max_entries : Int,\n  installation_issue : (@connector.CapabilityInstallationIssue) -> E,\n' +
    parameters + ') -> Result[ConfiguredComputeModules[E], E] {\n' +
    '  let registrations : Array[(@connector.CapabilityRegistration, Unit)] = []\n' + registrations +
    '  match @connector.install_capability_implementations(registry, registrations, max_entries) {\n' +
    '    Err(issue) => return Err(installation_issue(issue))\n    Ok(_) => ()\n  }\n' +
    prepare +
    '  let contributions = match assemble_compute_contributions(registry, max_entries,\n' + passed +
    '  ) {\n    Ok(value) => value\n    Err(issue) => return Err(installation_issue(issue))\n  }\n' +
    '  Ok({\n    driver,\n' + stored + '    contributions,\n  })\n}\n' +
    '\n///|\npub fn[E] configured_compute_contributions(value : ConfiguredComputeModules[E]) -> @connector.CapabilityImplementations[@host.ComputeContribution[Unit, E]] {\n  value.contributions\n}\n' +
    getters + installedKeys + '\n///|\npub(all) enum ConfiguredDispatchIssue[E] {\n  MissingImplementation\n  Implementation(E)\n}\n' + dispatches + managedDispatches + estimateAssembly(entries, alias) + hostAssembly() + synchronousAssembly(entries, alias);
}

function synchronousAssembly(entries, alias) {
  return `
///|
/// Invoke an installed in-process implementation by exact registration. External
/// transport modules are not coerced into this synchronous execution contract.
pub fn[E] execute_configured_in_process(value : ConfiguredComputeHost[E], task : @host.PreparedTaskDispatch) -> Result[Unit, ConfiguredDispatchIssue[E]] {
  let selected = @host.prepared_task_registration(task)
` + entries.filter(({manifest:m})=>m.dispatch_result === 'Unit' || m.synchronous_dispatch).map(({name, manifest:m})=>`
  if value.modules.installed_${name} is Some((installed, project, _)) &&
    physical_equal(selected, @${alias(m.package)}.${m.registration}(installed)) {
    return @${alias(m.package)}.${m.synchronous_dispatch ?? m.dispatch}(installed, @host.compute_host_dispatch(value.runtime), task).map_err(issue => Implementation(project(issue)))
  }
`).join('') + '  Err(MissingImplementation)\n}\n';
}

function hostAssembly() {
  return `
///|
/// Standard composition: only an already configured installation and common
/// limits. Connector configuration and typed execution remain in the modules.
struct ConfiguredComputeHost[E] {
  modules : ConfiguredComputeModules[E]
  runtime : @host.ComputeHost[Unit, E]
}

///|
pub fn[E] open_configured_compute_host(
  modules : ConfiguredComputeModules[E],
  registry : @connector.CapabilityRegistry,
  capacity : @connector.FixedComputeCapacity,
  max_entries : Int,
  max_name_bytes : Int,
  max_implementations : Int,
) -> Result[ConfiguredComputeHost[E], @host.ComputeHostIssue[E]] {
  @host.open_compute_host(modules.driver, registry, modules.contributions,
    capacity, max_entries, max_name_bytes, max_implementations).map(runtime => { modules, runtime, })
}

///|
pub fn[E] configured_host_runtime(value : ConfiguredComputeHost[E]) -> @host.ComputeHost[Unit, E] { value.runtime }

///|
pub fn[E] configured_host_modules(value : ConfiguredComputeHost[E]) -> ConfiguredComputeModules[E] { value.modules }

///|
pub fn[E] configured_host_driver(value : ConfiguredComputeHost[E]) -> @host.DispatchDriver { value.modules.driver }
`;
}

function estimateAssembly(entries, alias) {
  if (!entries.some(({manifest}) => manifest.estimate_policy || manifest.resource_policy)) return '';
  return '\n///|\nstruct ConfiguredEstimatePolicy[E] {\n  install : () -> Result[Unit, E]\n}\n' +
    '\n///|\npub fn[E] install_configured_estimate_policy(policy : ConfiguredEstimatePolicy[E]) -> Result[Unit, E] {\n  (policy.install)()\n}\n' +
    entries.flatMap(({name, manifest: m}) => ['estimate', 'resource'].flatMap(kind => {
      const p = m[`${kind}_policy`];
      if (p === null) return [];
      const pkg = `@${alias(m.package)}`;
      return `\n///|\npub fn ${name}_${kind}_work_slots() -> Int {\n  ${pkg}.${p.work_slots}()\n}\n` +
        `\n///|\n/// Prepare without installing; installation retains the exact module and policy.\n` +
        `pub fn[E] prepare_${name}_${kind}_policy(value : ConfiguredComputeModules[E], settings : ${pkg}.${p.configuration}) -> Result[ConfiguredEstimatePolicy[E], ConfiguredDispatchIssue[E]] {\n` +
        `  guard value.installed_${name} is Some((installed, _, project)) else { return Err(MissingImplementation) }\n` +
        `  match ${pkg}.${p.prepare}(installed, settings) {\n` +
        `    Err(issue) => Err(Implementation(project(issue)))\n` +
        `    Ok(policy) => Ok({ install: () => ${pkg}.${p.install}(installed, policy).map_err(project) })\n` +
        `  }\n}\n`;
    })).join('');
}

export function checkComputeAssembly(root, write = false, options = {}) {
  const selected = options.names;
  if (selected !== undefined && (!Array.isArray(selected) || selected.length === 0 ||
      new Set(selected).size !== selected.length || !selected.every(identifier))) {
    throw new Error('Invalid explicit Compute composition');
  }
  const entries = [];
  for (const name of readdirSync(join(root, 'src/connectors')).sort()) {
    if (selected && !selected.includes(name)) continue;
    const path = join(root, 'src/connectors', name, 'compute-bundle.json');
    if (existsSync(path)) entries.push({name, manifest: JSON.parse(readFileSync(path, 'utf8'))});
  }
  if (selected && entries.length !== selected.length) throw new Error('Missing selected Compute manifest');
  const generated = generateComputeAssembly(entries);
  // Use the pinned formatter as a pure stdin/stdout transformation. Check mode
  // never edits the source tree or invokes contribution factories.
  const formatter = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt') : 'moonfmt';
  generated.source = execFileSync(formatter, ['-'], {input: generated.source, encoding: 'utf8'});
  generated.manifest = execFileSync(formatter, ['-', '-file-type', 'pkg'], {input: generated.manifest, encoding: 'utf8'});
  for (const {manifest} of entries) {
    const results = manifest.dispatch_result === 'Unit' ? []
      : Array.isArray(manifest.dispatch_result) ? manifest.dispatch_result : [manifest.dispatch_result];
    for (const pkg of [manifest.package, manifest.dispatch_error.package, manifest.estimate_error.package, ...results.map(value => value.package)]) {
      if (!existsSync(join(root, 'src', pkg.slice('actql/actql/'.length), 'moon.pkg'))) {
        throw new Error(`Missing declared Compute dependency: ${pkg}`);
      }
    }
  }
  const output = options.directory ?? 'connectors_builtin';
  if (!identifier(output)) throw new Error('Invalid Compute composition output');
  const directory = join(root, 'src', output);
  if (write) mkdirSync(directory, {recursive: true});
  for (const [file, source] of [['moon.pkg', generated.manifest], ['compute.generated.mbt', generated.source]]) {
    const path = join(directory, file);
    if (write) writeFileSync(path, source);
    else if (!existsSync(path) || readFileSync(path, 'utf8') !== source) {
      throw new Error(`Typed Compute bundle assembly is stale: ${file}`);
    }
  }
  return entries.length;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  console.log(`${checkComputeAssembly(root, process.argv.includes('--write'))} rebuild-time Compute contributions verified.`);
}

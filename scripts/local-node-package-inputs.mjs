// One resolved distribution inventory for the standard installed Node Host.
// Provider runtimes, adapters and static declarations come from the same
// checked host manifests that generate the installed connector table.
import {readFileSync} from 'node:fs';
import {basename, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {generateInstallations, readHostBundles} from './connector-node-bundles.mjs';

// These are Host infrastructure, not a second list of provider manifests.
// DuckDB is still an explicit built-in binding (installed-source.mjs); its
// JS bridge does not install or load the optional native transport.
const hostRuntimes = [
  'connectors_builtin_node', 'connectors/duckdb/host_node',
  'retained_host_bridge', 'process_host_bridge', 'checkpoint_runtime_node',
];
const hostAdapters = [
  'adapters/host-node/infer-trusted-node-preload.cjs',
  'adapters/host-node/node-public-initial-control-bootstrap.cjs',
  'adapters/host-node/entry.mjs',
  'adapters/host-node/embedded-local.mjs',
  'adapters/host-node/captured-duckdb-source.mjs',
  'adapters/host-node/installed-source.mjs',
  'adapters/host-node/installed-effect.mjs',
  'adapters/host-node/local-account-config.mjs',
  'adapters/host-node/in-process-client.mjs',
  'adapters/host-node/client-request-journal.mjs',
  'adapters/host-node/client-request-lookup.mjs',
  'adapters/host-node/client-run-start.mjs',
  'adapters/host-node/client-effect-run.mjs',
  'adapters/host-node/installed-effect-site.mjs',
  'adapters/host-node/client-run-attach.mjs',
  'adapters/host-node/client-program-preparation.mjs',
  'adapters/host-node/result-access.mjs',
  'adapters/host-common/run-state-access.mjs',
  'adapters/store-local/publication-store.mjs',
  'adapters/host-node/installed-row-source.mjs',
  'adapters/host-node/ordinary-source-binding.mjs',
  'adapters/host-node/installed-row-effect.mjs',
  'adapters/host-node/installed-host-cleanup.mjs',
  'adapters/host-common/runtime-result.mjs',
  'adapters/host-common/owned-invocation-context.mjs',
  'adapters/host-common/credential-scope-fields.generated.mjs',
];
const hostContracts = [
  'spec/dependencies/aoa-pipeline-registry.json',
  'spec/dependencies/actql-graph-laws.json',
  'spec/contracts/actql-aoa.json',
  'spec/contracts/actql-numeric-reduction.json',
  'spec/contracts/actql-capacity-host-policy.json',
  'spec/contracts/actql-check-environment.json',
  'spec/local-check-environment.json',
  'spec/contracts/actql-query-acquisition.json',
  'spec/contracts/actql-query-process-evidence.json',
  'spec/contracts/actql-query-two-receipt.json',
];
const unique = values => Object.freeze([...new Set(values)]);

const inside = (root, path) => {
  const value = relative(root, path);
  return value === '' || !isAbsolute(value) && value !== '..' && !value.startsWith('..' + sep);
};
const descriptors = entries => {
  const byDestination = new Map();
  for (const entry of entries) {
    const prior = byDestination.get(entry.destination);
    if (prior && prior.source !== entry.source) {
      throw new Error(`ConflictingLocalNodeDestination:${entry.destination}`);
    }
    byDestination.set(entry.destination, Object.freeze(entry));
  }
  return Object.freeze([...byDestination.values()]);
};

// The default inventory retains its established package-relative shape. An
// external composition carries concrete source owners separately from those
// same destination names; callers never reinterpret a destination as a path
// in the Core checkout.
export function localNodePackageInputs(root, {buildInputs} = {}) {
  if (buildInputs !== undefined) return externalInputs(root, buildInputs);
  const installations = readHostBundles(root);
  const table = join(root, 'adapters/connectors-builtin/installations.generated.mjs');
  if (readFileSync(table, 'utf8') !== generateInstallations(installations, table, root)) {
    throw new Error('StaleLocalNodeInstallationTable');
  }
  const runtimePackages = unique([...hostRuntimes,
    ...installations.map(entry => entry.providerBundle).filter(Boolean)]);
  return Object.freeze({
    runtimePackages,
    runtimeFiles: Object.freeze(runtimePackages.map(path =>
      `${path}/${basename(path)}.js`)),
    adapterEntries: unique([...hostAdapters, ...installations.flatMap(entry =>
      [entry.source, entry.effect].filter(Boolean).map(role => role.module))]),
    dataFiles: unique([...hostContracts, ...installations.flatMap(entry => entry.assets)]),
    providerBundles: Object.freeze(installations.filter(entry => entry.providerBundle !== undefined)
      .map(entry => Object.freeze({
      name: entry.name, package: entry.providerBundle,
      file: `${entry.providerBundle}/${basename(entry.providerBundle)}.js`,
    }))),
  });
}

function externalInputs(root, buildInputs) {
  if (resolve(root) !== buildInputs.host.root) throw new Error('InvalidLocalNodeBuildRoot');
  const installations = readHostBundles(root, {buildInputs});
  const tablePath = 'adapters/connectors-builtin/installations.generated.mjs';
  const table = buildInputs.resolveFile(buildInputs.host.namespace, tablePath);
  if (readFileSync(table, 'utf8') !== generateInstallations(installations, table, root)) {
    throw new Error('StaleLocalNodeInstallationTable');
  }
  const core = buildInputs.modules.find(module => module.namespace === 'actql/actql');
  const runtimeInputs = [];
  const runtimes = new Set();
  const addRuntime = (name, module, packageName, packagePath) => {
    if (runtimes.has(name)) throw new Error(`ConflictingLocalNodeRuntime:${name}`);
    runtimes.add(name);
    runtimeInputs.push(Object.freeze({package: name, moduleRoot: module.root,
      namespace: module.namespace, qualifiedPackage: packageName,
      target: relative(module.root, dirname(packagePath)),
      compiledFile: `${packageName}/${basename(name)}.js`,
      file: `${name}/${basename(name)}.js`}));
  };
  for (const name of hostRuntimes) {
    const packageName = `${core.namespace}/${name}`;
    addRuntime(name, core, packageName, buildInputs.resolvePackage(packageName));
  }
  for (const entry of installations.filter(entry => entry.providerBundle !== undefined)) {
    addRuntime(entry.providerBundle, entry, entry.providerPackage, entry.providerPackagePath);
  }
  const coreFile = path => ({source: buildInputs.resolveFile(core.namespace, path),
    destination: path, ownerRoot: core.root});
  const adapterInputs = descriptors([...hostAdapters.map(coreFile),
    ...installations.flatMap(entry => [entry.source, entry.effect].filter(Boolean)
      .map(role => ({source: role.modulePath, destination: role.module, ownerRoot: entry.root}))),
    {source: table, destination: tablePath, ownerRoot: buildInputs.host.root}]);
  const dataInputs = descriptors([...hostContracts.map(coreFile),
    ...installations.flatMap(entry => entry.assetSources.map(asset =>
      ({source: asset.sourcePath, destination: asset.path, ownerRoot: entry.root})))]);
  const assetPaths = new Map(dataInputs.map(entry => [entry.source, entry.destination]));
  const destinationForAdapter = source => {
    if (source === table) return tablePath;
    if (inside(join(core.root, 'adapters'), source)) return relative(core.root, source).split(sep).join('/');
    for (const entry of installations) {
      if (inside(join(entry.root, 'adapters/connectors', entry.name), source)) {
        return relative(entry.root, source).split(sep).join('/');
      }
    }
    if (assetPaths.has(source)) return assetPaths.get(source);
    throw new Error(`UndeclaredLocalNodeAdapterInput:${source}`);
  };
  return Object.freeze({
    coreRoot: core.root, buildInputs, installations,
    roots: Object.freeze(buildInputs.modules.map(module => module.root)),
    runtimeInputs: Object.freeze(runtimeInputs), adapterInputs, dataInputs,
    runtimePackages: Object.freeze(runtimeInputs.map(entry => entry.package)),
    runtimeFiles: Object.freeze(runtimeInputs.map(entry => entry.file)),
    adapterEntries: Object.freeze(adapterInputs.map(entry => entry.destination)),
    dataFiles: Object.freeze(dataInputs.map(entry => entry.destination)),
    providerBundles: Object.freeze(installations.filter(entry => entry.providerBundle !== undefined)
      .map(entry => Object.freeze({
      name: entry.name, package: entry.providerBundle,
      file: `${entry.providerBundle}/${basename(entry.providerBundle)}.js`,
    }))),
    destinationForAdapter,
    installationTable: Object.freeze({source: table, destination: tablePath,
      render: destination => generateInstallations(installations, join(destination, tablePath), root,
        {resolveModule: (_entry, section) => join(destination, section.module),
          resolveImplementationFile: (_entry, path) => join(destination, path)})}),
  });
}

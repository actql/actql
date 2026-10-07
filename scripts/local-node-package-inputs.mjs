// One resolved distribution inventory for the standard installed Node Host.
// Provider runtimes, adapters and static declarations come from the same
// checked host manifests that generate the installed connector table.
import {readFileSync} from 'node:fs';
import {basename, join} from 'node:path';
import {generateInstallations, readHostBundles} from './connector-node-bundles.mjs';

// These are Host infrastructure, not a second list of provider manifests.
// DuckDB is still an explicit built-in binding (installed-source.mjs); its
// JS bridge does not install or load the optional native transport.
const hostRuntimes = [
  'connectors_builtin_node', 'connectors/duckdb/host_node',
  'retained_host_bridge', 'process_host_bridge', 'checkpoint_runtime_node',
];
const hostAdapters = [
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
];
const hostContracts = [
  'spec/dependencies/aoa-pipeline-registry.json',
  'spec/dependencies/actql-graph-laws.json',
  'spec/contracts/actql-aoa.json',
  'spec/contracts/actql-numeric-reduction.json',
  'spec/contracts/actql-capacity-host-policy.json',
  'spec/local-check-environment.json',
  'spec/contracts/actql-query-acquisition.json',
  'spec/contracts/actql-query-process-evidence.json',
  'spec/contracts/actql-query-two-receipt.json',
];
const unique = values => Object.freeze([...new Set(values)]);

export function localNodePackageInputs(root) {
  const installations = readHostBundles(root);
  const table = join(root, 'adapters/connectors-builtin/installations.generated.mjs');
  if (readFileSync(table, 'utf8') !== generateInstallations(installations, table, root)) {
    throw new Error('StaleLocalNodeInstallationTable');
  }
  const runtimePackages = unique([...hostRuntimes,
    ...installations.map(entry => entry.providerBundle)]);
  return Object.freeze({
    runtimePackages,
    runtimeFiles: Object.freeze(runtimePackages.map(path =>
      `${path}/${basename(path)}.js`)),
    adapterEntries: unique([...hostAdapters, ...installations.flatMap(entry =>
      [entry.source, entry.effect].filter(Boolean).map(role => role.module))]),
    dataFiles: unique([...hostContracts, ...installations.flatMap(entry => entry.assets)]),
    providerBundles: Object.freeze(installations.map(entry => Object.freeze({
      name: entry.name, package: entry.providerBundle,
      file: `${entry.providerBundle}/${basename(entry.providerBundle)}.js`,
    }))),
  });
}

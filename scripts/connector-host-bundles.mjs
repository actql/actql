// Checkout tools resolve implementation graphs before using the shared renderer.
import {resolve} from 'node:path';
import {connectorManifestSelection} from './connector-manifest-selection.mjs';
import {adapterModuleGraph} from './adapter-module-graph.mjs';
import {checkHostBundle, renderHostInstallations} from './connector-host-bundle-contract.mjs';

export {checkHostBundle, checkHostProfiles, moduleSpecifier} from './connector-host-bundle-contract.mjs';

// Generation and distribution read exactly the same checked declarations.
// Selecting installed Host contributions does not require Compute support.
export function readHostBundles(root, {names, buildInputs} = {}) {
  if (buildInputs !== undefined) {
    if (names !== undefined || resolve(root) !== buildInputs.host.root) {
      throw new Error('InvalidResolvedHostBuildSelection');
    }
    return buildInputs.hostEntries;
  }
  return connectorManifestSelection(root, {names})
    .filter(entry => entry.host !== undefined)
    .map(entry => checkHostBundle(root, entry.name, entry.host));
}

export function generateInstallations(installations, output, root, options = {}) {
  return renderHostInstallations(installations, output, root, {
    ...options,
    implementationModules(entry, ownerRoot) {
      const modules = [entry.source, entry.effect].filter(Boolean).map(role => role.module);
      return adapterModuleGraph(ownerRoot, modules)
        .filter(path => path.startsWith(`adapters/connectors/${entry.name}/`));
    },
  });
}

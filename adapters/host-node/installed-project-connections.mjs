import {open} from 'node:fs/promises';
import {resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {installedProjectOriginalsForRuntime} from './installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };

// Same-project declaration acquisition only. Connector readers still admit the
// exact selected entry before installation; this does not create an installed
// Source, credential use, current authority, capacity or durable publication.
export async function loadInstalledProjectConnections(moon, project,
  {assertCurrent, openFile = open, installationInventory} = {}) {
  const projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  const directory = project.directory;
  if (typeof directory !== 'string' || !directory ||
      typeof assertCurrent !== 'function' || typeof openFile !== 'function') {
    fail('InvalidInstalledProjectConnectionsInstallation');
  }
  const select = moon?.clientProjectConfigurationConnectorsFile;
  const admit = moon?.clientProjectConnectionsAdmit;
  if (typeof select !== 'function' || typeof admit !== 'function') {
    fail('InstalledProjectRuntimeUnavailable');
  }
  const check = () => {
    assertCurrent();
    if (installedProjectOriginalsForRuntime(project, moon) !== projectOriginal) {
      fail('ForeignInstalledProjectOriginal');
    }
  };
  check();
  const selected = Reflect.apply(select, moon, [projectOriginal.configuration]);
  if (selected != null && (typeof selected !== 'string' || !selected)) {
    fail('InvalidInstalledProjectConnectionsSelection');
  }
  const path = selected == null ? undefined : resolve(directory, selected);
  const wire = path === undefined ? undefined : installationInventory === undefined
    ? await readBoundedConfigurationUtf8(path, {maxBytes: 65536, openFile})
    : await installationInventory.readMetadataUtf8(path, 65536);
  // No second parse or file read can replace this exact acquisition. Close
  // failures retain the original FD on the existing reader's cleanup carrier.
  check();
  const admission = () => checked(Reflect.apply(admit, moon, [wire]));
  const connections = wire === undefined ? undefined : installationInventory === undefined
    ? admission() : installationInventory.prepareMetadataInput(Object.freeze({
      capacity() {
        const quote = moon.clientProjectConnectionsAdmissionConstructionCapacity;
        if (typeof quote !== 'function') fail('InstalledProjectRuntimeUnavailable');
        const quantity = Reflect.apply(quote, moon, [wire]);
        if (quantity == null) fail('InstalledProjectMetadataCapacityUnavailable');
        return quantity;
      }, project: admission,
    }));
  check();
  const original = Object.freeze({project: projectOriginal, path, wire, connections});
  return Object.freeze({originalsForRuntime(runtime) {
    if (runtime !== moon) fail('ForeignInstalledProjectRuntime');
    check();
    return original;
  }});
}

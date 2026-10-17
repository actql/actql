import {checked} from '../host-common/runtime-result.mjs';
import {dirname, join, resolve} from 'node:path';
import {open} from 'node:fs/promises';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };

function readConfiguration(moon, configurationWire, readers) {
  const admitConfiguration = readers === undefined
    ? moon?.clientProjectConfigurationAdmit : readers.admitConfiguration;
  const modelTasksFile = readers === undefined
    ? moon?.clientProjectConfigurationModelTasksFile : readers.modelTasksFile;
  if (typeof admitConfiguration !== 'function' ||
      typeof modelTasksFile !== 'function') fail('InstalledProjectRuntimeUnavailable');
  const configuration = checked(Reflect.apply(admitConfiguration, moon,
    [configurationWire]));
  const selected = Reflect.apply(modelTasksFile, moon, [configuration]);
  if (selected != null && (typeof selected !== 'string' || selected.length === 0)) {
    fail('InvalidInstalledProjectRegistrySelection');
  }
  return {configuration, selected};
}

function retainConfiguration(moon, configurationWire, modelRegistryWire,
  {configuration, selected}, readers) {
  let modelRegistry;
  if (selected == null) {
    if (modelRegistryWire !== undefined) fail('UnexpectedInstalledProjectRegistry');
  } else {
    if (modelRegistryWire === undefined) fail('InstalledProjectRegistryUnavailable');
    const admitRegistry = readers === undefined
      ? moon?.clientProjectModelRegistryAdmit : readers.admitRegistry;
    if (typeof admitRegistry !== 'function') fail('InstalledProjectRuntimeUnavailable');
    modelRegistry = checked(Reflect.apply(admitRegistry, moon, [modelRegistryWire]));
  }
  // Retain the exact admitted pair and original text. No JSON reserialization,
  // equal-CID reconstruction, fallback runtime or new preparation is used.
  const original = Object.freeze({configuration, modelRegistry,
    configurationWire, modelRegistryWire});
  return Object.freeze({originalsForRuntime(runtime) {
    if (runtime !== moon) fail('ForeignInstalledProjectRuntime');
    return original;
  }});
}

// Private Host assembly, not a public wire/authority/registry factory. The
// original runtime supplies every parser and semantic projection. File access,
// containment, physical generation/currentness and funding stay with the
// caller's existing installation Owner; this operation performs no I/O.
export function admitInstalledProjectConfiguration(moon, configurationWire,
  modelRegistryWire) {
  if (typeof configurationWire !== 'string' ||
      modelRegistryWire !== undefined && typeof modelRegistryWire !== 'string') {
    fail('InvalidInstalledProjectMaterials');
  }
  return retainConfiguration(moon, configurationWire, modelRegistryWire,
    readConfiguration(moon, configurationWire));
}

// Physical discovery inside the existing installed Host. Only an open's
// acknowledged ENOENT may advance to a parent; read/decode/close failures never
// turn a nearer selected original into an absent project. This is not an
// execution assembler, currentness proof, numerical envelope or permission.
export async function loadInstalledProjectConfiguration(moon,
  {directory = process.cwd(), openFile = open} = {}) {
  if (typeof directory !== 'string' || !directory ||
      typeof openFile !== 'function') fail('InvalidInstalledProjectLocation');
  // These original callbacks and their receiver remain fixed across file I/O.
  const readers = {admitConfiguration: moon?.clientProjectConfigurationAdmit,
    modelTasksFile: moon?.clientProjectConfigurationModelTasksFile,
    admitRegistry: moon?.clientProjectModelRegistryAdmit};
  const stateDirectory = moon?.clientProjectConfigurationStateDirectory;
  if (typeof stateDirectory !== 'function' ||
      typeof readers.admitConfiguration !== 'function' ||
      typeof readers.modelTasksFile !== 'function') {
    fail('InstalledProjectRuntimeUnavailable');
  }
  let selectedDirectory = resolve(directory);
  for (;;) {
    const configurationPath = join(selectedDirectory, 'actql.config.json');
    let opened = false, configurationWire;
    try {
      configurationWire = await readBoundedConfigurationUtf8(configurationPath,
        {maxBytes: 65536, openFile: async (...args) => {
          const handle = await openFile(...args);
          opened = true;
          return handle;
        }});
    } catch (error) {
      if (opened || error?.code !== 'ENOENT') throw error;
      const parent = dirname(selectedDirectory);
      if (parent === selectedDirectory) return undefined;
      selectedDirectory = parent;
      continue;
    }
    const admitted = readConfiguration(moon, configurationWire, readers);
    const state = Reflect.apply(stateDirectory, moon, [admitted.configuration]);
    if (typeof state !== 'string' || !state) fail('InvalidInstalledProjectLocation');
    const registryPath = admitted.selected == null ? undefined :
      resolve(selectedDirectory, admitted.selected);
    const registryWire = registryPath === undefined ? undefined :
      await readBoundedConfigurationUtf8(registryPath,
        {maxBytes: 65536, openFile});
    const retained = retainConfiguration(moon, configurationWire, registryWire, admitted, readers);
    return Object.freeze({configurationPath, directory: selectedDirectory,
      stateDirectory: resolve(selectedDirectory, state), registryPath,
      originalsForRuntime: retained.originalsForRuntime});
  }
}

import {checked} from '../host-common/runtime-result.mjs';
import {dirname, join, resolve} from 'node:path';
import {open} from 'node:fs/promises';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {assertInitialControlInstallationCurrent}
  from './node-initial-control-installation.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const retainedProjects = new WeakMap();

function originalForRuntime(retained, moon) {
  if (retained.retired) fail('InstalledProjectOriginalRetired');
  if (retained.moon !== moon) fail('ForeignInstalledProjectRuntime');
  return retained.original;
}

// A private issued-project lookup, not a DATA or equal-wire reconstruction.
// Consumers keep the original callback runtime through every file read.
export function installedProjectOriginalsForRuntime(project, moon) {
  const retained = retainedProjects.get(project);
  if (retained === undefined) fail('ForeignInstalledProjectOriginal');
  return originalForRuntime(retained, moon);
}

// Task locators are relative to the selected registry, never the project root.
// This shared interpretation performs no I/O and preserves the caller's existing
// locator/containment policy. Only a live issued project supplies the base.
export function resolveInstalledProjectTaskPath(project, moon, file) {
  installedProjectOriginalsForRuntime(project, moon);
  if (typeof project.registryPath !== 'string' || !project.registryPath ||
      typeof file !== 'string' || !file) fail('InvalidInstalledProjectTaskSelection');
  return resolve(dirname(project.registryPath), file);
}

// Managed original-reference retirement only, after the existing Host's child
// cleanup or for an unadopted preparation. It does not acknowledge any file,
// body, Store, startup envelope, escaped alias, garbage collection or capacity.
export function retireInstalledProjectConfiguration(project, moon) {
  const retained = retainedProjects.get(project);
  if (retained === undefined) fail('ForeignInstalledProjectOriginal');
  originalForRuntime(retained, moon);
  retained.retired = true;
  retained.original = undefined;
  retained.moon = undefined;
}

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
  const retained = {moon, original, retired: false};
  const project = Object.freeze({originalsForRuntime(runtime) {
    return originalForRuntime(retained, runtime);
  }});
  retainedProjects.set(project, retained);
  return project;
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
  {directory = process.cwd(), openFile = open,
    initialControl, initialControlOriginals} = {}) {
  const check = () => {
    if (initialControl !== undefined || initialControlOriginals !== undefined) {
      assertInitialControlInstallationCurrent(initialControl, initialControlOriginals);
    }
  };
  // A supplied scope is checked by the SAME preload's nominal operation, not
  // by a caller's assertCurrent method. Legacy standalone DATA/read callers
  // do not acquire an operational admission by omitting these private inputs.
  check();
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
    check();
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
      check();
      const parent = dirname(selectedDirectory);
      if (parent === selectedDirectory) return undefined;
      selectedDirectory = parent;
      continue;
    }
    // The original file Owner has closed or retained its FD before this
    // refusal can occur; do not lose an acquired handle before its custody.
    check();
    const admitted = readConfiguration(moon, configurationWire, readers);
    check();
    const state = Reflect.apply(stateDirectory, moon, [admitted.configuration]);
    if (typeof state !== 'string' || !state) fail('InvalidInstalledProjectLocation');
    const registryPath = admitted.selected == null ? undefined :
      resolve(selectedDirectory, admitted.selected);
    const registryWire = registryPath === undefined ? undefined :
      await readBoundedConfigurationUtf8(registryPath,
        {maxBytes: 65536, openFile});
    check();
    const retained = retainConfiguration(moon, configurationWire, registryWire, admitted, readers);
    // Register the returned view before the caller's next current check. A
    // refused current phase still owns this exact same retained record.
    const project = Object.freeze({configurationPath, directory: selectedDirectory,
      stateDirectory: resolve(selectedDirectory, state), registryPath,
      originalsForRuntime: retained.originalsForRuntime});
    // Both views share this same retirement record. Copying the getter must
    // not leave its earlier closure able to recover retired original DATA.
    retainedProjects.set(project, retainedProjects.get(retained));
    return project;
  }
}

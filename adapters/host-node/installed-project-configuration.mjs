import {checked} from '../host-common/runtime-result.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };

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
  const admitConfiguration = moon?.clientProjectConfigurationAdmit;
  const modelTasksFile = moon?.clientProjectConfigurationModelTasksFile;
  if (typeof admitConfiguration !== 'function' ||
      typeof modelTasksFile !== 'function') fail('InstalledProjectRuntimeUnavailable');
  const configuration = checked(Reflect.apply(admitConfiguration, moon,
    [configurationWire]));
  const selected = Reflect.apply(modelTasksFile, moon, [configuration]);
  let modelRegistry;
  if (selected == null) {
    if (modelRegistryWire !== undefined) fail('UnexpectedInstalledProjectRegistry');
  } else {
    if (modelRegistryWire === undefined) fail('InstalledProjectRegistryUnavailable');
    const admitRegistry = moon?.clientProjectModelRegistryAdmit;
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

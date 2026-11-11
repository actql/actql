import {open} from 'node:fs/promises';
import {extname} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime, resolveInstalledProjectTaskPath} from './installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {assertInstalledModelDefaultsPreparation,
  assertInstalledModelDefaultsAdoption} from './installed-model.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const boundFields = Object.freeze(['contractDepth', 'contractNodes', 'contractTextBytes',
  'maxBytes', 'maxDepth', 'maxMembers', 'maxNodes', 'maxTasks', 'maxWork']);

function snapshotLimits(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail('InvalidInstalledProjectTaskLimits');
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== boundFields.length ||
      keys.some((key, index) => key !== boundFields[index])) {
    fail('InvalidInstalledProjectTaskLimits');
  }
  const retained = {};
  for (const key of boundFields) {
    const amount = value[key];
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > 2147483647) {
      fail('InvalidInstalledProjectTaskLimits');
    }
    retained[key] = amount;
  }
  return Object.freeze(retained);
}

// Physical project intake in the existing installation, not another Task
// registry, execution assembler or capacity issuer. Common owns the closed
// declaration, original selection, policy, canonical Task/prompt and identity.
// Per-document bounds and a finite task count bound traversal, not heap/RSS:
// the Host still funds all retained originals and read/decode/hash overlap.
export async function loadInstalledProjectModelTasks(moon, project, providers,
  {limits, assertCurrent, openFile = open} = {}) {
  return loadProjectModelTasks(moon, project, providers, {limits, assertCurrent, openFile}, false);
}

// Candidate Task DATA can precede the physical assembler that needs its exact
// Common-issued Task/prompt identities. It cannot project a Run environment
// until the same original defaults are adopted by actual installed Providers.
export async function prepareInstalledProjectModelTasks(moon, project, defaults,
  {limits, assertCurrent, openFile = open} = {}) {
  return loadProjectModelTasks(moon, project, defaults, {limits, assertCurrent, openFile}, true);
}

async function loadProjectModelTasks(moon, project, providers,
  {limits, assertCurrent, openFile}, candidate) {
  const original = installedProjectOriginalsForRuntime(project, moon);
  if (typeof project.directory !== 'string' || !project.directory ||
      typeof assertCurrent !== 'function' || typeof openFile !== 'function' ||
      !(providers instanceof Map)) fail('InvalidInstalledProjectTaskInstallation');
  const bounds = snapshotLimits(limits);
  const callbacks = Object.freeze({
    count: moon?.clientProjectModelRegistryTaskCount,
    name: moon?.clientProjectModelRegistryTaskName,
    file: moon?.clientProjectModelRegistryTaskFile,
    read: moon?.clientProgramReadPublicModelTask,
    select: moon?.clientProgramSelectProjectModelTask,
    pair: moon?.clientProgramProjectModelTaskSelectionFor,
    normalize: moon?.clientProgramNormalizeProjectModelTask,
    materials: moon?.clientProgramNormalizedPublicModelTaskMaterials,
    environment: moon?.clientProgramProjectPublicModelTaskEnvironment,
  });
  if (!Object.values(callbacks).every(value => typeof value === 'function')) {
    fail('InstalledProjectRuntimeUnavailable');
  }
  const call = (name, ...args) => Reflect.apply(callbacks[name], moon, args);
  const check = () => {
    assertCurrent();
    if (installedProjectOriginalsForRuntime(project, moon) !== original) {
      fail('ForeignInstalledProjectOriginal');
    }
  };
  check();
  const count = original.modelRegistry === undefined ? 0 : call('count', original.modelRegistry);
  if (!Number.isSafeInteger(count) || count < 0 || count > bounds.maxTasks) {
    fail('InstalledProjectTaskCountLimit');
  }
  const readerBounds = Object.freeze({maxBytes: bounds.maxBytes, maxNodes: bounds.maxNodes,
    maxDepth: bounds.maxDepth, maxMembers: bounds.maxMembers, maxWork: bounds.maxWork});
  const coreBounds = [bounds.maxBytes, bounds.maxNodes, bounds.maxDepth, bounds.maxMembers,
    bounds.contractNodes, bounds.contractDepth, bounds.contractTextBytes, bounds.maxWork];
  const tasks = [];
  for (let index = 0; index < count; index++) {
    check();
    const name = call('name', original.modelRegistry, index);
    const file = call('file', original.modelRegistry, index);
    if (typeof name !== 'string' || !name || typeof file !== 'string' || !file) {
      fail('InvalidInstalledProjectTaskSelection');
    }
    const extension = extname(file);
    const format = extension === '.json' ? 'json' :
      extension === '.yaml' || extension === '.yml' ? 'yaml' : undefined;
    if (format === undefined) fail('InstalledProjectTaskFormatUnavailable');
    const path = resolveInstalledProjectTaskPath(project, moon, file);
    const wire = await readBoundedConfigurationUtf8(path,
      {maxBytes: bounds.maxBytes, openFile});
    // Read/close success is not current installation, funding or send admission.
    // A pending close's original FD remains on the existing error carrier.
    check();
    const task = checked(call('read', wire, format, ...coreBounds));
    const selection = checked(call('select', original.modelRegistry, task, bounds.maxWork));
    const pair = runtimeUnboxedReferenceOption(call('pair', selection, original.modelRegistry, task));
    if (pair == null || runtimeField(pair, 2) !== file) {
      fail('InvalidInstalledProjectTaskSelection');
    }
    // The same registry occurrence must select the file just read. In
    // particular a file for A cannot silently declare a different registered B.
    const providerId = runtimeField(pair, 0), model = runtimeField(pair, 1);
    const provider = Map.prototype.get.call(providers, providerId);
    if (provider === undefined || typeof provider.resolveTaskDefaults !== 'function') {
      fail('InstalledModelDefaultsUnavailable');
    }
    if (candidate) assertInstalledModelDefaultsPreparation(provider, moon, providerId);
    const defaults = provider.resolveTaskDefaults(model, undefined, readerBounds);
    // Common reuses the declaration's own token override; this preliminary
    // default read supplies only the retained original configuration profile.
    const normalized = checked(call('normalize', selection, original.modelRegistry,
      task, defaults.value, ...coreBounds));
    const material = call('materials', normalized);
    const taskWire = runtimeField(material, 0), taskCid = runtimeField(material, 1);
    const promptWire = runtimeField(material, 2), promptCid = runtimeField(material, 3);
    if ([taskWire, taskCid, promptWire, promptCid].some(value => typeof value !== 'string')) {
      fail('InvalidHostRuntimeResult');
    }
    // Inspect the already checked public material, not compiler fields or a
    // second parser of the original Task. The filename may occur more than
    // once in a registry; that does not permit substituting its declared name.
    if (JSON.parse(taskWire).task_id !== name) {
      fail('InvalidInstalledProjectTaskSelection');
    }
    check();
    if (Map.prototype.get.call(providers, providerId) !== provider) {
      fail('InstalledModelDefaultsForeignOriginal');
    }
    if (candidate) assertInstalledModelDefaultsPreparation(provider, moon, providerId);
    else provider.assertNewTrustedRuntime?.();
    tasks.push(Object.freeze({name, file, path, wire, task, selection, providerId,
      ...(candidate ? {providerDefaults: provider} : {provider}),
      defaults, normalized, taskWire, taskCid, promptWire, promptCid}));
  }
  const retained = Object.freeze(tasks);
  function originalsForRuntime(runtime) {
    if (runtime !== moon) fail('ForeignInstalledProjectRuntime');
    check();
    for (const task of retained) {
      const originalProvider = candidate ? task.providerDefaults : task.provider;
      if (Map.prototype.get.call(providers, task.providerId) !== originalProvider) {
        fail('InstalledModelDefaultsForeignOriginal');
      }
      if (candidate) assertInstalledModelDefaultsPreparation(originalProvider, moon, task.providerId);
      else originalProvider.assertNewTrustedRuntime?.();
    }
    return retained;
  }
  function installedView(installedTasks, assertOriginals) {
    return Object.freeze({originalsForRuntime: assertOriginals,
      projectEnvironmentForRuntime(runtime, wire, evidenceCid) {
        assertOriginals(runtime);
        if (typeof wire !== 'string' || typeof evidenceCid !== 'string') {
          fail('InvalidInstalledProjectEnvironment');
        }
        const projection = checked(call('environment', wire, evidenceCid,
          installedTasks.map(task => task.normalized), ...coreBounds));
        const environmentWire = runtimeField(projection, 0), identity = runtimeField(projection, 1);
        const work = runtimeField(projection, 2);
        if (typeof environmentWire !== 'string' || typeof identity !== 'string' ||
            !Number.isSafeInteger(work) || work < 0) fail('InvalidHostRuntimeResult');
        assertOriginals(runtime);
        return Object.freeze({environmentWire, evidenceCid: identity, work});
      }});
  }
  if (!candidate) return installedView(retained, originalsForRuntime);
  return Object.freeze({originalsForRuntime,
    bindInstalledProviders(installed) {
      originalsForRuntime(moon);
      if (!(installed instanceof Map)) fail('InvalidInstalledProjectTaskInstallation');
      const bound = Object.freeze(retained.map(task => {
        const provider = Map.prototype.get.call(installed, task.providerId);
        assertInstalledModelDefaultsAdoption(provider, task.providerDefaults, moon, task.providerId);
        return Object.freeze({...task, provider});
      }));
      const assertBound = runtime => {
        originalsForRuntime(runtime);
        for (const task of bound) {
          if (Map.prototype.get.call(installed, task.providerId) !== task.provider) {
            fail('InstalledModelDefaultsForeignOriginal');
          }
          assertInstalledModelDefaultsAdoption(task.provider, task.providerDefaults, moon, task.providerId);
        }
        return bound;
      };
      return installedView(bound, assertBound);
    }});
}

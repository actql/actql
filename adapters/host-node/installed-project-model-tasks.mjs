import {open} from 'node:fs/promises';
import {extname} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsBoxedSome, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime, resolveInstalledProjectTaskPath} from './installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';
import {assertInstalledModelDefaultsPreparation,
  assertInstalledModelDefaultsAdoption} from './installed-model.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const boundFields = Object.freeze(['contractDepth', 'contractNodes', 'contractTextBytes',
  'maxBytes', 'maxDepth', 'maxMembers', 'maxNodes', 'maxTasks', 'maxWork']);

function snapshotLimits(value, funded) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail('InvalidInstalledProjectTaskLimits');
  }
  const keys = Object.keys(value).sort();
  const expected = funded && !Object.hasOwn(value, 'maxTasks')
    ? boundFields.filter(key => key !== 'maxTasks') : boundFields;
  if (keys.length !== expected.length ||
      keys.some((key, index) => key !== expected[index])) {
    fail('InvalidInstalledProjectTaskLimits');
  }
  const retained = {};
  for (const key of expected) {
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
  {limits, assertCurrent, openFile = open, installationServices} = {}) {
  return loadProjectModelTasks(moon, project, providers, {limits, assertCurrent, openFile, installationServices}, false);
}

// Candidate Task DATA can precede the physical assembler that needs its exact
// Common-issued Task/prompt identities. It cannot project a Run environment
// until the same original defaults are adopted by actual installed Providers.
export async function prepareInstalledProjectModelTasks(moon, project, defaults,
  {limits, assertCurrent, openFile = open, installationServices} = {}) {
  return loadProjectModelTasks(moon, project, defaults, {limits, assertCurrent, openFile, installationServices}, true);
}

async function loadProjectModelTasks(moon, project, providers,
  {limits, assertCurrent, openFile, installationServices}, candidate) {
  const original = installedProjectOriginalsForRuntime(project, moon);
  if (typeof project.directory !== 'string' || !project.directory ||
      typeof assertCurrent !== 'function' || typeof openFile !== 'function' ||
      !(providers instanceof Map)) fail('InvalidInstalledProjectTaskInstallation');
  const construction = installationServices === undefined ? undefined : installedSourceConfigurationReader(installationServices);
  if (installationServices !== undefined && construction === undefined) fail('InstalledModelTaskConstructionUnavailable');
  if (construction !== undefined && openFile !== open) fail('InstalledModelTaskReaderChanged');
  const bounds = snapshotLimits(limits, construction !== undefined);
  const construct = (capacity, project, retained = () => capacity()) => construction === undefined
    ? project() : construction.prepareModelTaskInput(Object.freeze({capacity, project, retained}));
  const jsCapacity = (retained, workspace = 0n, text = 0n) => checked(moon.clientProgramInstalledSourceConstructionCapacity(
    retained, text, 0n, workspace, 0n, 0n));
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
    identity: moon?.clientProgramPublicModelTaskName,
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
  if (!Number.isSafeInteger(count) || count < 0 || (bounds.maxTasks !== undefined && count > bounds.maxTasks)) {
    fail('InstalledProjectTaskCountLimit');
  }
  const readerBounds = Object.freeze({maxBytes: bounds.maxBytes, maxNodes: bounds.maxNodes,
    maxDepth: bounds.maxDepth, maxMembers: bounds.maxMembers, maxWork: bounds.maxWork});
  const coreBounds = [bounds.maxBytes, bounds.maxNodes, bounds.maxDepth, bounds.maxMembers,
    bounds.contractNodes, bounds.contractDepth, bounds.contractTextBytes, bounds.maxWork];
  const tasks = construct(() => jsCapacity(2n), () => []);
  const inventory = []; // Original scalar cells only; no earlier Task is re-parsed or normalized.
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
    // Path segments are actual slash-delimited slots. Locator text is priced
    // independently; source bytes never become Task value-node credit.
    const locatorUnits = BigInt(project.registryPath.length + file.length + 2);
    let separators = 1n;
    for (const value of [project.registryPath, file]) {
      for (let offset = 0; offset < value.length; offset++) if (value.charCodeAt(offset) === 47) separators++;
    }
    const {path} = construct(() => jsCapacity(6n, 4n * separators, 12n * locatorUnits),
      () => Object.freeze({path: resolveInstalledProjectTaskPath(project, moon, file)}));
    const wire = construction === undefined
      ? await readBoundedConfigurationUtf8(path, {maxBytes: bounds.maxBytes, openFile})
      : await construction.readUtf8(path, {maxBytes: bounds.maxBytes});
    // Read/close success is not current installation, funding or send admission.
    // A pending close's original FD remains on the existing error carrier.
    check();
    const task = construct(
      () => moon.clientProgramPublicModelTaskReadConstructionCapacity(wire, format, ...coreBounds),
      () => checked(call('read', wire, format, ...coreBounds)),
      value => moon.clientProgramPublicModelTaskRetainedCapacity(value));
    if (call('identity', task) !== name) fail('InvalidInstalledProjectTaskSelection');
    const selected = construct(
      () => moon.clientProgramProjectModelTaskSelectionConstructionCapacity(original.modelRegistry),
      () => {
        const selection = checked(call('select', original.modelRegistry, task, bounds.maxWork));
        return Object.freeze({selection, pair: runtimeUnboxedReferenceOption(
          call('pair', selection, original.modelRegistry, task))});
      }, () => moon.clientProgramProjectModelTaskSelectionRetainedCapacity());
    const {selection, pair} = selected;
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
    const defaults = provider.resolveTaskDefaults(model, undefined, readerBounds, construction);
    // Common reuses the declaration's own token override; this preliminary
    // default read supplies only the retained original configuration profile.
    const normalized = construct(
      () => moon.clientProgramPublicModelTaskNormalizationConstructionCapacity(task, defaults.value, ...coreBounds),
      () => checked(call('normalize', selection, original.modelRegistry, task, defaults.value, ...coreBounds)),
      value => moon.clientProgramPublicModelTaskNormalizedRetainedCapacity(value));
    const material = construct(() => jsCapacity(5n), () => call('materials', normalized));
    const taskWire = runtimeField(material, 0), taskCid = runtimeField(material, 1);
    const promptWire = runtimeField(material, 2), promptCid = runtimeField(material, 3);
    if ([taskWire, taskCid, promptWire, promptCid].some(value => typeof value !== 'string')) {
      fail('InvalidHostRuntimeResult');
    }
    // The declaration identity above belongs to this exact normalized original;
    // no second JSON parser is needed to inspect its public material.
    check();
    if (Map.prototype.get.call(providers, providerId) !== provider) {
      fail('InstalledModelDefaultsForeignOriginal');
    }
    if (candidate) assertInstalledModelDefaultsPreparation(provider, moon, providerId);
    else provider.assertNewTrustedRuntime?.();
    // Current entry fields, two ordered vector slots and the original parent
    // input references. Earlier entries stay in the accumulated retained sum.
    construct(() => jsCapacity(24n), () => {
      tasks.push(Object.freeze({name, file, path, wire, task, selection, providerId,
        ...(candidate ? {providerDefaults: provider} : {provider}),
        defaults, normalized, taskWire, taskCid, promptWire, promptCid}));
      inventory.push(normalized);
      return tasks[tasks.length - 1];
    });
  }
  const retained = Object.freeze(tasks);
  Object.freeze(inventory);
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
      projectEnvironmentForRuntime(runtime, wire, evidenceCid, environmentBody) {
        assertOriginals(runtime);
        if (typeof wire !== 'string' || typeof evidenceCid !== 'string') {
          fail('InvalidInstalledProjectEnvironment');
        }
        let environmentBounds = coreBounds, geometry, baseMembers = 0, baseTasks = 0;
        if (construction !== undefined) {
          if (environmentBody === null || typeof environmentBody !== 'object' || nodeTypes.isProxy(environmentBody)) {
            fail('InstalledModelTaskEnvironmentInventoryUnavailable');
          }
          for (const section of ['command_contracts', 'connector_capabilities', 'connector_catalogs',
            'contract_registry', 'mapping_contracts', 'model_task_contracts', 'schema_snapshots', 'source_views']) {
            const field = Object.getOwnPropertyDescriptor(environmentBody, section);
            const entries = field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
            if (!Array.isArray(entries) || nodeTypes.isProxy(entries)) fail('InstalledModelTaskEnvironmentInventoryUnavailable');
            baseMembers += entries.length;
            if (section === 'model_task_contracts') baseTasks = entries.length;
          }
          geometry = sourceJsonWireGeometry(wire);
          const selectedBounds = moon.clientProgramPublicModelTaskEnvironmentLimits(
            Buffer.byteLength(wire), Number(geometry.nodes), Number(geometry.depth + 1n), baseMembers, baseTasks, inventory);
          // This compiled Array[Int] Option uses boxed Some, unlike the
          // unboxed reference Options returned by the capacity exports.
          environmentBounds = runtimeIsBoxedSome(selectedBounds) ? runtimeField(selectedBounds, 0) : undefined;
          if (!Array.isArray(environmentBounds) || environmentBounds.length !== 8) {
            fail('InstalledModelTaskEnvironmentCapacityUnavailable');
          }
        }
        const projection = construct(
          () => moon.clientProgramPublicModelTaskEnvironmentConstructionCapacity(
            Buffer.byteLength(wire), Number(geometry.nodes),
            Number(geometry.depth + 1n), baseMembers, baseTasks, inventory),
          () => checked(call('environment', wire, evidenceCid, inventory, ...environmentBounds)));
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
      const bound = construct(() => jsCapacity(3n + 24n * BigInt(retained.length)), () => Object.freeze(retained.map(task => {
        const provider = Map.prototype.get.call(installed, task.providerId);
        assertInstalledModelDefaultsAdoption(provider, task.providerDefaults, moon, task.providerId);
        return Object.freeze({...task, provider});
      })));
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

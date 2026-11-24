import {open} from 'node:fs/promises';
import {extname} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsBoxedSome, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import type {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {installedProjectOriginalsForRuntime, resolveInstalledProjectTaskPath} from './installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';
import {assertInstalledModelDefaultsPreparation, assertInstalledModelDefaultsAdoption} from './installed-model.mjs';

type Project = NonNullable<Awaited<ReturnType<typeof loadInstalledProjectConfiguration>>>;
type ModelReader = NonNullable<ReturnType<typeof installedSourceConfigurationReader>>;
type CoreBounds = [maxBytes: number, maxNodes: number, maxDepth: number, maxMembers: number,
  contractNodes: number, contractDepth: number, contractTextBytes: number, maxWork: number];
type ReaderBounds = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxMembers: number; maxWork: number}>;
type TaskMaterial = object & Readonly<{then?: never}>;
type TaskDefaults = Readonly<{value: unknown; resolved: unknown; binding: unknown; readUsage: unknown}>;
type TaskProvider = Readonly<{
  resolveTaskDefaults(model: string | undefined, tokens: bigint | undefined,
    bounds: ReaderBounds, construction: ModelReader | undefined): TaskDefaults;
  assertNewTrustedRuntime?(): void;
}>;
type LoadOptions = Readonly<{
  limits?: unknown;
  assertCurrent?: () => unknown;
  openFile?: (path: string, flags: string) => unknown;
  installationServices?: object;
}>;
type TaskEntry = Readonly<{
  name: string;
  file: string;
  path: string;
  wire: string;
  task: TaskMaterial;
  selection: unknown;
  providerId: string;
  defaults: TaskDefaults;
  normalized: TaskMaterial;
  taskWire: string;
  taskCid: string;
  promptWire: string;
  promptCid: string;
}>;
type CandidateTask = TaskEntry & Readonly<{providerDefaults: TaskProvider; provider?: never}>;
type InstalledTask = TaskEntry & Readonly<{provider: TaskProvider; providerDefaults?: TaskProvider}>;
type InstalledTasks = Readonly<{
  originalsForRuntime(runtime: unknown): readonly InstalledTask[];
  projectEnvironmentForRuntime(runtime: unknown, wire: string, evidenceCid: string, environmentBody?: unknown):
    Readonly<{environmentWire: string; evidenceCid: string; work: number}>;
}>;
type CandidateTasks = Readonly<{
  originalsForRuntime(runtime: unknown): readonly CandidateTask[];
  bindInstalledProviders(installed: ReadonlyMap<string, TaskProvider>): InstalledTasks;
}>;
type TaskGeometryPort = (bytes: number, nodes: number, depth: number, members: number, existingTasks: number,
  tasks: readonly TaskMaterial[]) => unknown;
type ModelTaskRuntime = Readonly<{
  clientProjectModelRegistryTaskCount(registry: unknown): number;
  clientProjectModelRegistryTaskName(registry: unknown, index: number): string | undefined;
  clientProjectModelRegistryTaskFile(registry: unknown, index: number): string | undefined;
  clientProgramReadPublicModelTask(wire: string, format: string, ...bounds: CoreBounds): unknown;
  clientProgramSelectProjectModelTask(registry: unknown, task: unknown, maxWork: number): unknown;
  clientProgramProjectModelTaskSelectionFor(selection: unknown, registry: unknown, task: unknown): unknown;
  clientProgramNormalizeProjectModelTask(selection: unknown, registry: unknown, task: unknown,
    defaults: unknown, ...bounds: CoreBounds): unknown;
  clientProgramNormalizedPublicModelTaskMaterials(normalized: unknown): TaskMaterial;
  clientProgramProjectPublicModelTaskEnvironment(wire: string, evidenceCid: string, tasks: readonly TaskMaterial[],
    ...bounds: CoreBounds): unknown;
  clientProgramPublicModelTaskName(task: unknown): string;
  clientProgramInstalledSourceConstructionCapacity(retainedNodes: bigint, retainedText: bigint, retainedWire: bigint,
    workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint): unknown;
  clientProgramPublicModelTaskReadConstructionCapacity(wire: string, format: string, ...bounds: CoreBounds): unknown;
  clientProgramPublicModelTaskRetainedCapacity(task: TaskMaterial): unknown;
  clientProgramProjectModelTaskSelectionConstructionCapacity(registry: unknown): unknown;
  clientProgramProjectModelTaskSelectionRetainedCapacity(): unknown;
  clientProgramPublicModelTaskNormalizationConstructionCapacity(task: TaskMaterial, defaults: unknown,
    ...bounds: CoreBounds): unknown;
  clientProgramPublicModelTaskNormalizedRetainedCapacity(task: TaskMaterial): unknown;
  clientProgramPublicModelTaskEnvironmentLimits: TaskGeometryPort;
  clientProgramPublicModelTaskEnvironmentConstructionCapacity: TaskGeometryPort;
}>;

const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const boundFields = Object.freeze(['contractDepth', 'contractNodes', 'contractTextBytes',
  'maxBytes', 'maxDepth', 'maxMembers', 'maxNodes', 'maxTasks', 'maxWork'] as const);

type LimitName = typeof boundFields[number];
type Limits = Readonly<Record<Exclude<LimitName, 'maxTasks'>, number> & {maxTasks?: number}>;

function snapshotLimits(value: unknown, funded: boolean): Limits {
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
  const retained: Partial<Record<LimitName, number>> = {};
  for (const key of expected) {
    const amount = (value as Record<LimitName, number>)[key];
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > 2147483647) {
      fail('InvalidInstalledProjectTaskLimits');
    }
    retained[key] = amount;
  }
  return Object.freeze(retained) as Limits;
}

// Physical project intake in the existing installation, not another Task
// registry, execution assembler or capacity issuer. Common owns the closed
// declaration, original selection, policy, canonical Task/prompt and identity.
// Per-document bounds and a finite task count bound traversal, not heap/RSS:
// the Host still funds all retained originals and read/decode/hash overlap.
export async function loadInstalledProjectModelTasks(moon: ModelTaskRuntime, project: Project, providers: ReadonlyMap<string, TaskProvider>,
  {limits, assertCurrent, openFile = open, installationServices}: LoadOptions = {}) {
  return loadProjectModelTasks(moon, project, providers, {limits, assertCurrent, openFile, installationServices}, false) as Promise<InstalledTasks>;
}

// Candidate Task DATA can precede the physical assembler that needs its exact
// Common-issued Task/prompt identities. It cannot project a Run environment
// until the same original defaults are adopted by actual installed Providers.
export async function prepareInstalledProjectModelTasks(moon: ModelTaskRuntime, project: Project, defaults: ReadonlyMap<string, TaskProvider>,
  {limits, assertCurrent, openFile = open, installationServices}: LoadOptions = {}) {
  return loadProjectModelTasks(moon, project, defaults, {limits, assertCurrent, openFile, installationServices}, true) as Promise<CandidateTasks>;
}

async function loadProjectModelTasks(moon: ModelTaskRuntime, project: Project, providers: ReadonlyMap<string, TaskProvider>,
  {limits, assertCurrent, openFile, installationServices}: LoadOptions, candidate: boolean) {
  const original = installedProjectOriginalsForRuntime(project, moon);
  if (typeof project.directory !== 'string' || !project.directory ||
      typeof assertCurrent !== 'function' || typeof openFile !== 'function' ||
      !(providers instanceof Map)) fail('InvalidInstalledProjectTaskInstallation');
  const construction = installationServices === undefined ? undefined : installedSourceConfigurationReader(installationServices);
  if (installationServices !== undefined && construction === undefined) fail('InstalledModelTaskConstructionUnavailable');
  if (construction !== undefined && openFile !== open) fail('InstalledModelTaskReaderChanged');
  const bounds = snapshotLimits(limits, construction !== undefined);
  const construct = <Value extends TaskMaterial>(capacity: () => unknown, project: () => Value,
    retained: (value: Value) => unknown = () => capacity()) => construction === undefined
    ? project() : construction.prepareModelTaskInput(Object.freeze({capacity, project, retained})) as Value;
  const jsCapacity = (retained: bigint, workspace = 0n, text = 0n) => checked(moon.clientProgramInstalledSourceConstructionCapacity(
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
  const call = <Name extends keyof typeof callbacks>(name: Name, ...args: Parameters<(typeof callbacks)[Name]>) =>
    Reflect.apply(callbacks[name] as (...args: Parameters<(typeof callbacks)[Name]>) => ReturnType<(typeof callbacks)[Name]>, moon, args);
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
  const coreBounds: CoreBounds = [bounds.maxBytes, bounds.maxNodes, bounds.maxDepth, bounds.maxMembers,
    bounds.contractNodes, bounds.contractDepth, bounds.contractTextBytes, bounds.maxWork];
  const tasks = construct<(CandidateTask | InstalledTask)[]>(() => jsCapacity(2n), () => []);
  const inventory: TaskMaterial[] = []; // Original scalar cells only; no earlier Task is re-parsed or normalized.
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
    const locatorUnits = BigInt(project.registryPath!.length + file.length + 2);
    let separators = 1n;
    for (const value of [project.registryPath!, file]) {
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
      () => checked(call('read', wire, format, ...coreBounds)) as TaskMaterial,
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
    const providerId = runtimeField(pair, 0) as string, model = runtimeField(pair, 1) as string | undefined;
    const provider = Map.prototype.get.call(providers, providerId) as TaskProvider | undefined;
    if (provider === undefined || typeof provider.resolveTaskDefaults !== 'function') {
      fail('InstalledModelDefaultsUnavailable');
    }
    if (candidate) assertInstalledModelDefaultsPreparation(provider, moon, providerId);
    const defaults = provider.resolveTaskDefaults(model, undefined, readerBounds, construction);
    // Common reuses the declaration's own token override; this preliminary
    // default read supplies only the retained original configuration profile.
    const normalized = construct(
      () => moon.clientProgramPublicModelTaskNormalizationConstructionCapacity(task, defaults.value, ...coreBounds),
      () => checked(call('normalize', selection, original.modelRegistry, task, defaults.value, ...coreBounds)) as TaskMaterial,
      value => moon.clientProgramPublicModelTaskNormalizedRetainedCapacity(value));
    const material = construct(() => jsCapacity(5n), () => call('materials', normalized));
    const taskWire = runtimeField(material, 0) as string, taskCid = runtimeField(material, 1) as string;
    const promptWire = runtimeField(material, 2) as string, promptCid = runtimeField(material, 3) as string;
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
  function originalsForRuntime(runtime: unknown) {
    if (runtime !== moon) fail('ForeignInstalledProjectRuntime');
    check();
    for (const task of retained) {
      const originalProvider = candidate ? task.providerDefaults : task.provider;
      if (Map.prototype.get.call(providers, task.providerId) !== originalProvider) {
        fail('InstalledModelDefaultsForeignOriginal');
      }
      if (candidate) assertInstalledModelDefaultsPreparation(originalProvider, moon, task.providerId);
      else originalProvider!.assertNewTrustedRuntime?.();
    }
    return retained;
  }
  function installedView(installedTasks: readonly TaskEntry[], assertOriginals: (runtime: unknown) => readonly TaskEntry[]) {
    return Object.freeze({originalsForRuntime: assertOriginals,
      projectEnvironmentForRuntime(runtime: unknown, wire: string, evidenceCid: string, environmentBody?: unknown) {
        assertOriginals(runtime);
        if (typeof wire !== 'string' || typeof evidenceCid !== 'string') {
          fail('InvalidInstalledProjectEnvironment');
        }
        let environmentBounds: CoreBounds | undefined = coreBounds,
          geometry: ReturnType<typeof sourceJsonWireGeometry> | undefined, baseMembers = 0, baseTasks = 0;
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
          environmentBounds = runtimeIsBoxedSome(selectedBounds) ? runtimeField(selectedBounds, 0) as CoreBounds : undefined;
          if (!Array.isArray(environmentBounds) || environmentBounds.length !== 8) {
            fail('InstalledModelTaskEnvironmentCapacityUnavailable');
          }
        }
        const projection = construct(
          () => moon.clientProgramPublicModelTaskEnvironmentConstructionCapacity(
            Buffer.byteLength(wire), Number(geometry!.nodes),
            Number(geometry!.depth + 1n), baseMembers, baseTasks, inventory),
          () => checked(call('environment', wire, evidenceCid, inventory, ...environmentBounds)) as TaskMaterial);
        const environmentWire = runtimeField(projection, 0), identity = runtimeField(projection, 1);
        const work = runtimeField(projection, 2) as number;
        if (typeof environmentWire !== 'string' || typeof identity !== 'string' ||
            !Number.isSafeInteger(work) || work < 0) fail('InvalidHostRuntimeResult');
        assertOriginals(runtime);
        return Object.freeze({environmentWire, evidenceCid: identity, work});
      }});
  }
  if (!candidate) return installedView(retained, originalsForRuntime);
  return Object.freeze({originalsForRuntime,
    bindInstalledProviders(installed: ReadonlyMap<string, TaskProvider>) {
      originalsForRuntime(moon);
      if (!(installed instanceof Map)) fail('InvalidInstalledProjectTaskInstallation');
      const bound = construct(() => jsCapacity(3n + 24n * BigInt(retained.length)), () => Object.freeze(retained.map(task => {
        const provider = Map.prototype.get.call(installed, task.providerId) as TaskProvider;
        assertInstalledModelDefaultsAdoption(provider, task.providerDefaults, moon, task.providerId);
        return Object.freeze({...task, provider});
      })));
      const assertBound = (runtime: unknown) => {
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

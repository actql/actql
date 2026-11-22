// Static ModelTask registration shares the installed checker composition.
// This metadata is neither a provider registration nor an egress grant. The
// common execution owner must separately admit dependencies and authority.
import {runtimeField, runtimePair} from '../host-common/compiler-binding.generated.mjs';
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {checked} from '../host-common/runtime-result.mjs';
// @ts-expect-error TS7016: the original-read installer is still authored in JavaScript.
import {retainInferOriginalReadInstallation, retainInferOriginalReadRecipe} from './infer-original-installation.mjs';
import {snapshotModelRawCaptureSelection} from './infer-raw-selection.mjs';
import {types as nodeTypes} from 'node:util';
import {runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
import {modelDefaultsCallbacks, modelDefaultsResolver, retainAdmittedProviderBinding,
  retainModelQuantityCapacity, retainProviderBindingOriginals} from './installed-model-defaults.mjs';

type DefaultsRuntime = Parameters<typeof modelDefaultsResolver>[0];
type BindingOriginals = NonNullable<ReturnType<typeof retainProviderBindingOriginals>>;
type ResolveDefaults = ReturnType<typeof modelDefaultsResolver>;
type Current = () => unknown;
type Callback = (...args: unknown[]) => unknown;
type Prompt = (...args: unknown[]) => boolean;
type RawSelection = NonNullable<ReturnType<typeof snapshotModelRawCaptureSelection>>;
type QuantityCapacity = NonNullable<ReturnType<typeof retainModelQuantityCapacity>>;
type InstalledTaskOriginal = Readonly<{providerId: string; taskCid: string}>;
type SdkCapability = Readonly<{opaque: unknown; installation: unknown}>;
type ProviderRuntime = DefaultsRuntime & Readonly<{
  clientProgramInstallModelProvider(providerId: string, invoke: Callback): unknown;
  clientProgramInstallAsyncModelProvider?(providerId: string): unknown;
  clientProgramAdmitInstalledStructuredSdkCapability?(capability: unknown, acquisition: unknown, installation: unknown): unknown;
}>;
type PrepareSdkCapability = (registration: unknown, providerId: string, taskCid: string,
  provider: unknown, selection: RawSelection) => SdkCapability;
type ProviderEntry = Readonly<{
  providerId?: unknown; entryPersistence?: unknown; bindingOriginals?: unknown; quantityCapacity?: unknown;
  invoke?: Callback; validatePrompt?: Callback; reconcileResponse?: Callback;
  physicalPreflight?: Callback; observeEgress?: Callback;
  originalReadInstallation?: unknown; originalReadRecipe?: unknown;
  rawCaptureSelection?: Record<string, unknown>; taskInstallations?: unknown;
  sdkStaticOriginals?: unknown; registeredSdk?: unknown;
}>;
type TaskData = Readonly<{
  originalReadInstallation: unknown; originalReadRecipe: unknown;
  rawCaptureSelection: RawSelection; quantityCapacity: QuantityCapacity;
  physicalPreflight: Callback; reconcileResponse: Callback | undefined;
  observeEgress: () => unknown; validatePrompt: Prompt;
}>;
type InstalledProvider = Readonly<{
  provider: unknown; originalReadInstallation: unknown; originalReadRecipe: unknown;
  rawCaptureSelection: RawSelection | undefined; bindingOriginals: BindingOriginals | undefined;
  assertTrustedRuntime: (() => void) | undefined; assertNewTrustedRuntime: (() => void) | undefined;
  requireEagerSdkStartup: (() => void) | undefined;
  physicalPreflight: Callback | undefined; entryPersistence: 'async' | undefined;
  reconcileResponse: Callback | undefined; quantityCapacity: QuantityCapacity | undefined;
  observeEgress: (() => unknown) | undefined; validatePrompt: Prompt; resolveTaskDefaults: ResolveDefaults;
  selectTaskOriginals?(taskCid: string): InstalledProvider;
  taskOriginals?(): readonly InstalledProvider[] | undefined;
}>;
type PreparedDefaults = Readonly<{
  bindingOriginals: BindingOriginals;
  resolveTaskDefaults: ResolveDefaults;
  bindRegistration<Entry extends object>(entry: Entry): Entry;
}>;
type DefaultsPreparation = Readonly<{
  moon: DefaultsRuntime; providerId: string; originals: BindingOriginals; check(): void;
  adopt(runtime: unknown, id: unknown, source: unknown, current: Current, installationCurrent: unknown): void;
}>;
type DependencyBody = Readonly<{cid: string; bodyWire: string}>;
type ExecutionBody = DependencyBody & Readonly<{modelTaskCid: string}>;
type ModelInstallation = Readonly<{
  environmentWire: string;
  executionContracts?: readonly ExecutionBody[] | null;
  dependencyBodies?: readonly DependencyBody[] | null;
}>;
type BodyWires = [prompt: string | undefined, retry: string | undefined, backoff: string | undefined];
type DependenciesRuntime = Readonly<{
  clientProgramInferDependencyReferences(execution: unknown): unknown;
  clientProgramInferMediaDependencyReferences(execution: unknown): readonly unknown[];
  clientProgramReadInferModelDependencies(execution: unknown, ...wires: BodyWires): unknown;
  clientProgramReadInferModelDependenciesWithMedia(execution: unknown, ...rest: [...BodyWires, media: readonly unknown[]]): unknown;
  clientProgramReadOriginalMockModelDependencies(mock: unknown, execution: unknown, ...wires: BodyWires): unknown;
}>;
type ExecutionRuntime = Readonly<{
  clientProgramSelectedInferStep(prepared: unknown): number | undefined;
  clientProgramInferOccurrenceCoordinates(occurrence: unknown): unknown;
  clientProgramInferModelTaskCid(prepared: unknown, step: number): string | undefined;
  clientProgramInferOccurrenceModelTaskCid(occurrence: unknown): string | undefined;
  clientProgramReadInferModelExecution(prepared: unknown, step: number, wire: string, cid: string): unknown;
  clientProgramReadComposedInferModelExecution(occurrence: unknown, wire: string, cid: string): unknown;
}>;
type BeforeRead = (count: number, wireAt: (index: number) => string, containers: number) => unknown;
type MetadataWitness = Readonly<{
  prepared: unknown; installation: unknown; occurrence: unknown; beforeRead?: BeforeRead; execution?: unknown;
}>;
type ConstructBinding = (providerId: string, revision: string, contract: string, configuration: string) => unknown;
type BindingRuntime = Parameters<typeof retainAdmittedProviderBinding>[0] & Readonly<{
  clientProgramModelProviderBinding?: ConstructBinding;
}>;

const modelMetadataRefusals = new WeakMap<object, MetadataWitness>();
const originalArrayIterator = Array.prototype[Symbol.iterator];
const originalArrayFind = Array.prototype.find;
const originalArrayMap = Array.prototype.map;
const originalArrayFilter = Array.prototype.filter;

// Consume this reader's exact synchronous absence once. A copied exception,
// another Prepared/installation/occurrence or a callback throw is no proof.
export function consumeInstalledModelExecutionAbsence(error: unknown, prepared: unknown, installation: unknown, occurrence?: unknown) {
  return consumeInstalledModelPreparationRefusal(error, prepared, installation, occurrence);
}

export function consumeInstalledModelPreparationRefusal(error: unknown, prepared: unknown, installation: unknown, occurrence?: unknown,
  beforeRead?: BeforeRead, execution?: unknown) {
  const original = modelMetadataRefusals.get(error as object);
  modelMetadataRefusals.delete(error as object);
  return original !== undefined && original.prepared === prepared &&
    original.installation === installation && original.occurrence === occurrence &&
    (original.beforeRead === undefined || original.beforeRead === beforeRead) &&
    (original.execution === undefined || original.execution === execution);
}

function originalModelMaterialIntrinsics() {
  return Object.getOwnPropertyDescriptor(Array.prototype, Symbol.iterator)?.value === originalArrayIterator &&
    Object.getOwnPropertyDescriptor(Array.prototype, 'find')?.value === originalArrayFind &&
    Object.getOwnPropertyDescriptor(Array.prototype, 'map')?.value === originalArrayMap &&
    Object.getOwnPropertyDescriptor(Array.prototype, 'filter')?.value === originalArrayFilter;
}

function checkedModelMetadata(result: unknown, original: MetadataWitness | undefined) {
  // Only this original native RETURN, after successful synchronous material
  // funding, supplies the witness. Callback/native throws never enter here.
  if (original === undefined || !runtimeIsError(result)) return checked(result);
  try {return checked(result);}
  catch (error) {modelMetadataRefusals.set(error as object, original); throw error;}
}

// These are aliases in the existing installation, not another Provider
// registry. A candidate supplies configuration DATA only; the physical entry
// must later adopt that same original through installModelProviders.
const defaultsPreparations = new WeakMap<object, DefaultsPreparation>();
const preparedRegistrations = new WeakMap<object, PreparedDefaults>();
const installedDefaults = new WeakMap<object, PreparedDefaults>();

function checkInstallation(installation: ModelInstallation): readonly ExecutionBody[] {
  if (installation === null || typeof installation !== 'object' ||
      Array.isArray(installation) ||
      Object.keys(installation).some(key =>
        !['environmentWire', 'executionContracts', 'dependencyBodies'].includes(key)) ||
      typeof installation.environmentWire !== 'string') {
    throw new TypeError('InvalidInstalledModelConfiguration');
  }
  const entries = installation.executionContracts ?? [];
  if (!Array.isArray(entries)) {
    throw new TypeError('InvalidInstalledModelExecutionConfiguration');
  }
  const tasks = new Set();
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'bodyWire,cid,modelTaskCid' ||
        typeof entry.bodyWire !== 'string' ||
        typeof entry.cid !== 'string' ||
        typeof entry.modelTaskCid !== 'string' ||
        tasks.has(entry.modelTaskCid)) {
      throw new TypeError('InvalidInstalledModelExecutionConfiguration');
    }
    tasks.add(entry.modelTaskCid);
  }
  const bodies = installation.dependencyBodies ?? [];
  if (!Array.isArray(bodies)) {
    throw new TypeError('InvalidInstalledModelDependencyConfiguration');
  }
  const references = new Set();
  for (const entry of bodies) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'bodyWire,cid' ||
        typeof entry.bodyWire !== 'string' || typeof entry.cid !== 'string' ||
        references.has(entry.cid)) {
      throw new TypeError('InvalidInstalledModelDependencyConfiguration');
    }
    references.add(entry.cid);
  }
  return entries;
}

// Prepare Task DATA before a Task-specific physical assembler needs its CID.
// No Provider, dummy invoke, resource profile, permission or send is issued.
// The Host supplies the actual original configuration and current predicate.
export function prepareInstalledModelProviderDefaults(moon: DefaultsRuntime, providerId: unknown, bindingOriginals: unknown,
  {assertCurrent}: Readonly<{assertCurrent?: Current}> = {}): PreparedDefaults {
  if (typeof providerId !== 'string' || !providerId || typeof assertCurrent !== 'function') {
    throw new TypeError('InvalidInstalledModelDefaultsPreparation');
  }
  const originals = retainProviderBindingOriginals(bindingOriginals);
  if (originals === undefined) {
    throw Object.assign(new Error('InstalledModelDefaultsUnavailable'),
      {code: 'InstalledModelDefaultsUnavailable'});
  }
  let view: PreparedDefaults;
  let adoptedCurrent: Current | undefined;
  let spent = false;
  const check = () => {
    if (assertCurrent() !== undefined) {
      throw new TypeError('InvalidInstalledModelDefaultsCurrentPredicate');
    }
    adoptedCurrent?.();
  };
  check();
  const resolveTaskDefaults = modelDefaultsResolver(moon, providerId, originals, check, () => view);
  const state: DefaultsPreparation = {moon, providerId, originals, check,
    adopt(runtime, id, source, current, installationCurrent) {
      check();
      if (runtime !== moon || id !== providerId || source !== originals || spent ||
          typeof current !== 'function' || installationCurrent !== assertCurrent) {
        throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
          {code: 'InstalledModelDefaultsForeignOriginal'});
      }
      // One preparation cannot migrate to another installation after a failed
      // registration. No physical child has been acquired by this DATA stage.
      spent = true;
      adoptedCurrent = current;
    }};
  view = Object.freeze({bindingOriginals: originals, resolveTaskDefaults,
    bindRegistration<Entry extends object>(entry: Entry) {
      if (this !== view || entry === null || typeof entry !== 'object' ||
          (entry as ProviderEntry).providerId !== providerId || (entry as ProviderEntry).bindingOriginals !== originals ||
          preparedRegistrations.has(entry)) {
        throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
          {code: 'InstalledModelDefaultsForeignOriginal'});
      }
      check();
      preparedRegistrations.set(entry, view);
      return entry;
    }});
  defaultsPreparations.set(view, state);
  return view;
}

export function assertInstalledModelDefaultsPreparation(view: unknown, moon: unknown, providerId: string) {
  const original = defaultsPreparations.get(view as object);
  if (original === undefined || original.moon !== moon || original.providerId !== providerId) {
    throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
      {code: 'InstalledModelDefaultsForeignOriginal'});
  }
  original.check();
}

export function assertInstalledModelDefaultsAdoption(provider: unknown, view: unknown, moon: unknown, providerId: string) {
  assertInstalledModelDefaultsPreparation(view, moon, providerId);
  if (installedDefaults.get(provider as object) !== view) {
    throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
      {code: 'InstalledModelDefaultsForeignOriginal'});
  }
  (provider as {assertNewTrustedRuntime(): void}).assertNewTrustedRuntime();
}

// Closed physical metadata views of the SAME installed Provider. This is not
// another Provider registry or a Task/authority issuer. Actual Request binding
// still checks each selected profile, recipe, prompt and schema in Common.
function snapshotTaskInstallations(source: unknown, providerId: string, bindings: unknown, sdkOriginals: unknown,
  taskOriginals: readonly InstalledTaskOriginal[] | undefined, registeredSdk: unknown) {
  if (source === undefined) return undefined;
  const owned = taskOriginals?.filter(value => value.providerId === providerId);
  if (!Array.isArray(source) || nodeTypes.isProxy(source) || source.length === 0 ||
      !Array.isArray(owned) || source.length !== owned.length || !Object.isFrozen(source) ||
      Reflect.ownKeys(source).length !== source.length + 1) {
    throw new TypeError('InvalidInstalledModelTaskInstallations');
  }
  const result = new Map<string, TaskData>();
  for (let index = 0; index < source.length; index++) {
    const slot = Object.getOwnPropertyDescriptor(source, String(index));
    const row = slot?.value;
    if (slot === undefined || !Object.hasOwn(slot, 'value') || row === null ||
        typeof row !== 'object' || nodeTypes.isProxy(row)) {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    const fields = Object.getOwnPropertyDescriptors(row);
    if (Reflect.ownKeys(fields).length !== 2 || ['taskCid', 'entry'].some(key =>
      !fields[key]?.enumerable || !Object.hasOwn(fields[key], 'value'))) {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    const taskCid = fields.taskCid.value, entry = fields.entry.value;
    if (typeof taskCid !== 'string' || taskCid.length !== 71 || result.has(taskCid) ||
        !owned.some(value => value.taskCid === taskCid) ||
        entry === null || typeof entry !== 'object' || Array.isArray(entry) || nodeTypes.isProxy(entry)) {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    const selected = Object.getOwnPropertyDescriptors(entry);
    const allowed = ['providerId', 'entryPersistence', 'sdkStaticOriginals', 'bindingOriginals',
      'originalReadInstallation', 'originalReadRecipe', 'rawCaptureSelection', 'quantityCapacity',
      'observeEgress', 'validatePrompt', 'physicalPreflight', 'reconcileResponse', 'registeredSdk'];
    if (Reflect.ownKeys(selected).some(key => !allowed.includes(key as string) ||
        !selected[key as string].enumerable || !Object.hasOwn(selected[key as string], 'value'))) {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    const value = (key: string): unknown => selected[key]?.value;
    const originalReadSource = value('originalReadInstallation'), recipeSource = value('originalReadRecipe');
    const physicalPreflight = value('physicalPreflight'), validatePrompt = value('validatePrompt');
    const observeEgress = value('observeEgress'), reconcileResponse = value('reconcileResponse');
    if (value('providerId') !== providerId || value('entryPersistence') !== 'async' ||
        value('bindingOriginals') !== bindings || value('sdkStaticOriginals') !== sdkOriginals ||
        value('registeredSdk') !== registeredSdk ||
        (originalReadSource === undefined) === (recipeSource === undefined) ||
        typeof physicalPreflight !== 'function' || typeof validatePrompt !== 'function' ||
        typeof observeEgress !== 'function' ||
        reconcileResponse !== undefined && typeof reconcileResponse !== 'function') {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    const originalReadInstallation: unknown = retainInferOriginalReadInstallation(originalReadSource);
    const originalReadRecipe: unknown = retainInferOriginalReadRecipe(recipeSource);
    const rawCaptureSelection = snapshotModelRawCaptureSelection(value('rawCaptureSelection') as ProviderEntry['rawCaptureSelection']);
    const quantityCapacity = retainModelQuantityCapacity(value('quantityCapacity'));
    if (rawCaptureSelection === undefined || quantityCapacity === undefined) {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    result.set(taskCid, Object.freeze({originalReadInstallation, originalReadRecipe,
      rawCaptureSelection, quantityCapacity, physicalPreflight: physicalPreflight as Callback,
      reconcileResponse: reconcileResponse as Callback | undefined,
      observeEgress() {try {return Reflect.apply(observeEgress, entry, []);} catch {return undefined;}},
      validatePrompt: (...args: unknown[]) => validatePrompt(...args) === true}));
  }
  return result;
}

// Registration remains physical Host capability. The common admission owner
// subsequently binds the selected callback to its exact Task and prompt.
export function installModelProviders(moon: ProviderRuntime, register?: (runtime: ProviderRuntime) => unknown,
  assertHostRuntime?: Current, assertNewHostRuntime = assertHostRuntime, bindSdkStaticOriginals?: (original: unknown) => unknown,
  taskOriginals?: readonly InstalledTaskOriginal[], prepareSdkCapability?: PrepareSdkCapability): Map<string, InstalledProvider> {
  if (register === undefined) return new Map();
  if (typeof register !== 'function') {
    throw new TypeError('InvalidInstalledModelProviderRegistration');
  }
  if (assertHostRuntime !== undefined) {
    if (typeof assertHostRuntime !== 'function') {
      throw new TypeError('InferTrustedRuntimeViewUnavailable');
    }
    assertHostRuntime();
  }
  const entries = register(moon);
  assertHostRuntime?.();
  // This is the embedding Host's original registration inventory, not checked
  // Run demand or a physical execution grant. Keep every actual entry and its
  // original callbacks; the selected Run still admits its own material/limits.
  if (!Array.isArray(entries)) {
    throw new TypeError('InvalidInstalledModelProviderRegistration');
  }
  const result = new Map<string, InstalledProvider>();
  for (const entry of entries as ProviderEntry[]) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).some(key => !['invoke', 'providerId', 'validatePrompt',
          'physicalPreflight', 'quantityCapacity', 'observeEgress',
          'bindingOriginals', 'reconcileResponse', 'entryPersistence',
          'originalReadInstallation', 'originalReadRecipe', 'rawCaptureSelection', 'sdkStaticOriginals',
          'taskInstallations', 'registeredSdk'].includes(key))) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    // Static registration values are read once before retention/Core calls.
    // Dynamic current facts still come from the SAME selected callback later.
    const providerId = entry.providerId, entryPersistence = entry.entryPersistence;
    if (entryPersistence !== undefined && entryPersistence !== 'async' ||
        typeof providerId !== 'string' || result.has(providerId) ||
        entryPersistence === 'async' && Object.hasOwn(entry, 'invoke')) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    const invoke = entryPersistence === 'async' ? undefined : entry.invoke;
    const validatePrompt = entry.validatePrompt, reconcileResponse = entry.reconcileResponse;
    const physicalPreflight = entry.physicalPreflight, observeEgress = entry.observeEgress;
    const originalReadSource = entry.originalReadInstallation, originalRecipeSource = entry.originalReadRecipe,
      rawSource = entry.rawCaptureSelection;
    const bindingSource = entry.bindingOriginals, quantitySource = entry.quantityCapacity;
    const sdkStaticOriginals = entry.sdkStaticOriginals;
    const taskSources = entry.taskInstallations, registeredSdk = entry.registeredSdk;
    if (taskSources !== undefined && entryPersistence !== 'async') {
      throw new TypeError('InvalidInstalledModelTaskInstallations');
    }
    const tasks = snapshotTaskInstallations(taskSources, providerId, bindingSource, sdkStaticOriginals, taskOriginals, registeredSdk);
    if (registeredSdk !== undefined && (tasks === undefined || typeof prepareSdkCapability !== 'function')) {
      throw new TypeError('InvalidInstalledModelSdkInstallation');
    }
    const defaultsCallbacks = modelDefaultsCallbacks(moon);
    let requireOriginalEagerStartup: (() => unknown) | undefined;
    // The Host supplies this private same-installation/current connection,
    // not registration DATA or a packet flag. Ordinary platform trust does
    // not imply the optional explicit recipe's eager-startup responsibility.
    if (sdkStaticOriginals !== undefined) {
      if (typeof bindSdkStaticOriginals !== 'function') {
        throw Object.assign(new TypeError('InferTrustedSdkStaticUnavailable'),
          {code: 'InferTrustedSdkStaticUnavailable'});
      }
      const requireEager = bindSdkStaticOriginals(sdkStaticOriginals);
      if (typeof requireEager === 'function') requireOriginalEagerStartup = requireEager as () => unknown;
    }
    if (entryPersistence !== 'async' && typeof invoke !== 'function' ||
        typeof validatePrompt !== 'function' ||
        reconcileResponse !== undefined && typeof reconcileResponse !== 'function') {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    // Installation-time snapshot precedes any provider or original Run start.
    // No default numerical profile is supplied when this declaration is absent.
    if (originalReadSource !== undefined && originalRecipeSource !== undefined) {
      throw new TypeError('InvalidInstalledInferOriginalReadInstallation');
    }
    const originalReadInstallation: unknown = retainInferOriginalReadInstallation(originalReadSource);
    const originalReadRecipe: unknown = retainInferOriginalReadRecipe(originalRecipeSource);
    const rawCaptureSelection = snapshotModelRawCaptureSelection(rawSource);
    // This installation profile connects raw custody only to the existing
    // durable asynchronous caller. It grants no raw capture or send authority.
    if (rawCaptureSelection !== undefined &&
        (entryPersistence !== 'async' || typeof physicalPreflight !== 'function')) {
      throw new TypeError('InstalledInferRawCaptureRequiresAsyncPhysicalPreflight');
    }
    const preparedDefaults = preparedRegistrations.get(entry);
    const preparedState = preparedDefaults === undefined ? undefined : defaultsPreparations.get(preparedDefaults);
    if (preparedState !== undefined && (preparedState.moon !== moon ||
        preparedState.providerId !== providerId || preparedState.originals !== bindingSource ||
        typeof assertNewHostRuntime !== 'function')) {
      throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
        {code: 'InstalledModelDefaultsForeignOriginal'});
    }
    const bindingOriginals = preparedState === undefined
      ? retainProviderBindingOriginals(bindingSource) : preparedState.originals;
    const quantityCapacity = retainModelQuantityCapacity(quantitySource);
    if (entryPersistence === 'async' &&
        (typeof physicalPreflight !== 'function' || quantityCapacity === undefined ||
          bindingOriginals === undefined || rawCaptureSelection === undefined)) {
      throw new TypeError('InvalidInstalledModelAsyncProviderRegistration');
    }
    if (entryPersistence === 'async' &&
        typeof moon.clientProgramInstallAsyncModelProvider !== 'function') {
      throw new TypeError('InstalledModelAsyncProviderRuntimeUnavailable');
    }
    // Reserve the same candidate for this one actual installation, before
    // creating its Core Provider. Its current closure is used only after the
    // existing map has retained the physical record below.
    let retained: InstalledProvider | undefined;
    if (preparedState !== undefined) {
      preparedState.adopt(moon, providerId, bindingSource, () => {
        if (retained === undefined) {
          throw Object.assign(new Error('InstalledModelDefaultsUnavailable'),
            {code: 'InstalledModelDefaultsUnavailable'});
        }
        retained.assertNewTrustedRuntime!();
      }, assertNewHostRuntime);
    }
    const provider = entryPersistence === 'async'
      ? moon.clientProgramInstallAsyncModelProvider!(providerId)
      : moon.clientProgramInstallModelProvider(providerId, invoke!);
    if (provider === undefined) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    const assertTrustedRuntime = assertHostRuntime === undefined ? undefined : () => {
      assertHostRuntime();
      if (sdkStaticOriginals !== undefined) bindSdkStaticOriginals!(sdkStaticOriginals);
      if (result.get(providerId) !== retained || retained!.provider !== provider) {
        throw Object.assign(new Error('InferTrustedRuntimeOriginalChanged'),
          {code: 'InferTrustedRuntimeOriginalChanged'});
      }
    };
    const assertNewTrustedRuntime = assertNewHostRuntime === undefined ? undefined : () => {
      assertNewHostRuntime();
      assertTrustedRuntime!();
    };
    // The existing Host binder supplies this same-original check, not entry
    // fields or a caller-authored Bool/CID. Preserve static-only registrations.
    const requireEagerSdkStartup = requireOriginalEagerStartup === undefined ||
      assertTrustedRuntime === undefined ? undefined : () => {
      assertTrustedRuntime();
      requireOriginalEagerStartup!();
      assertTrustedRuntime();
    };
    const resolveTaskDefaults: ResolveDefaults = preparedDefaults === undefined
      ? modelDefaultsResolver(moon, providerId, bindingOriginals, assertNewTrustedRuntime,
        () => retained, defaultsCallbacks)
      : function (this: unknown, selectedModel, taskMaxOutputTokens, limits, construction) {
        if (this !== retained) {
          throw Object.assign(new Error('InstalledModelDefaultsForeignOriginal'),
            {code: 'InstalledModelDefaultsForeignOriginal'});
        }
        return preparedDefaults.resolveTaskDefaults(selectedModel, taskMaxOutputTokens, limits, construction);
      };
    const taskViews = tasks === undefined ? undefined : new Map<string, InstalledProvider>();
    let taskInventory: readonly InstalledProvider[] | undefined;
    const selectTaskOriginals = tasks === undefined ? undefined : (taskCid: string) => {
      assertTrustedRuntime?.();
      const view = taskViews!.get(taskCid);
      if (view === undefined) throw Object.assign(new Error('InstalledModelTaskProfileUnavailable'),
        {code: 'InstalledModelTaskProfileUnavailable'});
      return view;
    };
    retained = Object.freeze({provider, originalReadInstallation, originalReadRecipe, rawCaptureSelection,
      assertTrustedRuntime, assertNewTrustedRuntime, requireEagerSdkStartup,
      bindingOriginals,
      physicalPreflight,
      entryPersistence,
      reconcileResponse,
      quantityCapacity,
      resolveTaskDefaults,
      ...(tasks === undefined ? {} : {selectTaskOriginals,
        taskOriginals() {assertTrustedRuntime?.(); return taskInventory;}}),
      observeEgress: typeof observeEgress !== 'function' ? undefined : () => {
        try { return Reflect.apply(observeEgress, entry, []); }
        catch { return undefined; }
      },
      validatePrompt: (...args: unknown[]) => validatePrompt(...args) === true});
    result.set(providerId, retained);
    if (preparedDefaults !== undefined) installedDefaults.set(retained, preparedDefaults);
    if (tasks !== undefined) {
      for (const [taskCid, data] of tasks) {
        const capability = registeredSdk === undefined ? undefined : prepareSdkCapability!(
          registeredSdk, providerId, taskCid, provider, data.rawCaptureSelection);
        let view: InstalledProvider;
        const current = () => {
          assertTrustedRuntime?.();
          if (result.get(providerId) !== retained || taskViews!.get(taskCid) !== view) {
            throw Object.assign(new Error('InferTrustedRuntimeOriginalChanged'),
              {code: 'InferTrustedRuntimeOriginalChanged'});
          }
        };
        const guarded = <Args extends unknown[], Value>(callback: (...args: Args) => Value) => (...args: Args) => {
          current();
          const value = callback(...args);
          current();
          return value;
        };
        view = Object.freeze({...retained, ...data,
          assertTrustedRuntime: current,
          assertNewTrustedRuntime() {assertNewTrustedRuntime?.(); current();},
          validatePrompt: guarded(data.validatePrompt),
          observeEgress: guarded(data.observeEgress),
          // Common registers the acquired cursor before its existing current
          // guard can refuse advance. Do not lose cleanup by throwing after
          // this factory has already returned an owned physical cursor.
          physicalPreflight(...args: unknown[]) {
            current();
            if (capability === undefined) return data.physicalPreflight(...args);
            const admitted = checked(moon.clientProgramAdmitInstalledStructuredSdkCapability!(
              capability.opaque, args[3], capability.installation));
            return data.physicalPreflight(...args, admitted);
          },
          resolveTaskDefaults(...args: Parameters<ResolveDefaults>) {current(); return retained!.resolveTaskDefaults(...args);}});
        taskViews!.set(taskCid, view);
      }
      taskInventory = Object.freeze([...taskViews!.values()]);
    }
  }
  return result;
}

export function readInstalledModelDependencies(moon: DependenciesRuntime, execution: unknown, installation: ModelInstallation,
  beforeRead?: BeforeRead, prepared?: unknown, occurrence?: unknown, originalMock?: unknown) {
  if (beforeRead !== undefined) {
    const original = originalModelMaterialArrays(installation);
    const references = moon.clientProgramInferDependencyReferences(execution);
    const media = moon.clientProgramInferMediaDependencyReferences(execution);
    const read = media.length !== 0 ? moon.clientProgramReadInferModelDependenciesWithMedia
      : moon.clientProgramReadInferModelDependencies;
    const funded = beforeRead(3 + media.length, index => {
      const cid = index < 3 ? runtimeField(references, index) : runtimeField(media[index - 3], 1);
      // Empty is sizing DATA for an absent body only. The actual reader below
      // still receives undefined and keeps its original missing-body refusal.
      return original.bodies.find(entry => entry.cid === cid)?.bodyWire ?? '';
    }, original.executions.length + original.bodies.length);
    const witness = funded === undefined && prepared !== undefined &&
      original.ordinaryOriginal && originalModelMaterialIntrinsics()
      ? {prepared, installation, occurrence, beforeRead, execution} : undefined;
    checkInstallation(installation);
    const bodies = new Map<unknown, string>(original.bodies.map(entry => [entry.cid, entry.bodyWire]));
    if (originalMock !== undefined) {
      return checkedModelMetadata(moon.clientProgramReadOriginalMockModelDependencies(originalMock, execution,
        bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)),
        bodies.get(runtimeField(references, 2))), witness);
    }
    if (media.length !== 0) {
      return checkedModelMetadata(Reflect.apply(read, moon, [execution,
        bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)), bodies.get(runtimeField(references, 2)),
        media.filter(entry => bodies.has(runtimeField(entry, 1))).map(entry =>
          runtimePair(runtimeField(entry, 0), bodies.get(runtimeField(entry, 1))))]), witness);
    }
    return checkedModelMetadata(Reflect.apply(read, moon, [execution,
      bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)),
      bodies.get(runtimeField(references, 2))]), witness);
  }
  return readInstalledModelDependenciesLegacy(moon, execution, installation, originalMock);
}

function readInstalledModelDependenciesLegacy(moon: DependenciesRuntime, execution: unknown,
  installation: ModelInstallation, originalMock: unknown) {
  checkInstallation(installation);
  const references = moon.clientProgramInferDependencyReferences(execution);
  const bodies = new Map<unknown, string>((installation.dependencyBodies ?? [])
    .map(entry => [entry.cid, entry.bodyWire]));
  const media = moon.clientProgramInferMediaDependencyReferences(execution);
  if (originalMock !== undefined) {
    return checked(moon.clientProgramReadOriginalMockModelDependencies(originalMock, execution,
      bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)),
      bodies.get(runtimeField(references, 2))));
  }
  if (media.length !== 0) {
    // Preserve the checked role-to-CID relation. Missing bodies are reported
    // by the common dependency owner; another role or a provider callback
    // cannot manufacture admission from a symbolic contract reference.
    return checked(moon.clientProgramReadInferModelDependenciesWithMedia(execution,
      bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)), bodies.get(runtimeField(references, 2)),
      media.filter(entry => bodies.has(runtimeField(entry, 1))).map(entry =>
        (runtimePair(runtimeField(entry, 0), bodies.get(runtimeField(entry, 1)))))));
  }
  return checked(moon.clientProgramReadInferModelDependencies(execution,
    bodies.get(runtimeField(references, 0)), bodies.get(runtimeField(references, 1)),
    bodies.get(runtimeField(references, 2))));
}

export function admitInstalledModelProvider(moon: Readonly<{
  clientProgramInferProviderId(execution: unknown): string;
  clientProgramAdmitModelProvider(provider: unknown, execution: unknown, dependencies: unknown, validate: Prompt): unknown;
}>, execution: unknown, dependencies: unknown, providers: ReadonlyMap<string, InstalledProvider>) {
  const selected = providers.get(moon.clientProgramInferProviderId(execution));
  if (selected === undefined) {
    throw Object.assign(new Error('InstalledInferModelProviderUnavailable'),
      {code: 'InstalledInferModelProviderUnavailable'});
  }
  return checked(moon.clientProgramAdmitModelProvider(selected.provider,
    execution, dependencies, selected.validatePrompt));
}

// Bind the actual Host-selected provider to its nonsecret installation and
// configuration originals. MoonBit owns their canonical admission and all
// resulting identities; callback text and display names are not revisions.
export function admitInstalledModelProviderBinding(moon: BindingRuntime, providerId: string,
  physical: Pick<InstalledProvider, 'bindingOriginals'> | undefined, constructOriginal?: ConstructBinding) {
  const originals = physical?.bindingOriginals;
  if (originals === undefined) {
    throw Object.assign(new Error('InstalledModelProviderBindingUnavailable'),
      {code: 'InstalledModelProviderBindingUnavailable'});
  }
  if (typeof moon.clientProgramModelProviderBinding !== 'function') {
    throw Object.assign(new Error('InstalledModelProviderBindingRuntimeUnavailable'),
      {code: 'InstalledModelProviderBindingRuntimeUnavailable'});
  }
  const value = constructOriginal === undefined
    ? checked(moon.clientProgramModelProviderBinding(providerId,
      originals.installationRevision.wire, originals.configurationContract.wire,
      originals.configuration.wire))
    : constructOriginal(providerId, originals.installationRevision.wire,
      originals.configurationContract.wire, originals.configuration.wire);
  return retainAdmittedProviderBinding(moon, providerId, originals, value);
}

export function installedModelEnvironment(moon: Parameters<typeof composeInstalledCheckEnvironment>[0],
  baseWire: string, currentWire: string, installation: ModelInstallation | undefined) {
  if (installation === undefined) return currentWire;
  checkInstallation(installation);
  // Both full documents are independently admitted by the common checker;
  // selectors and capacities retain the existing conflict checks.
  return composeInstalledCheckEnvironment(moon, baseWire, currentWire,
    installation.environmentWire);
}

// Normal submit uses its original prepared owner. The metadata lookup does
// not admit a body: MoonBit checks canonical bytes, self-CID, exact Task and
// ceilings. Returning this contract does not admit prompt/retry/egress policy.
export function readInstalledModelExecution(moon: ExecutionRuntime, prepared: unknown,
  installation: ModelInstallation | undefined, occurrence?: unknown, beforeRead?: BeforeRead) {
  if (beforeRead !== undefined) {
    const original = originalModelMaterialArrays(installation);
    const step = occurrence === undefined ? moon.clientProgramSelectedInferStep(prepared)
      : (runtimeField(moon.clientProgramInferOccurrenceCoordinates(occurrence), 2) as number);
    if (step === undefined) return undefined;
    if (original.emptyOriginal === true) {
      const error = Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
        {code: 'InstalledInferModelExecutionUnavailable'});
      modelMetadataRefusals.set(error, {prepared, installation, occurrence});
      throw error;
    }
    const taskCid = occurrence === undefined ? moon.clientProgramInferModelTaskCid(prepared, step)
      : moon.clientProgramInferOccurrenceModelTaskCid(occurrence);
    const entry = original.executions.find(item => item.modelTaskCid === taskCid);
    if (entry === undefined) {
      throw Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
        {code: 'InstalledInferModelExecutionUnavailable'});
    }
    const wire = entry.bodyWire, cid = entry.cid;
    const read = occurrence === undefined ? moon.clientProgramReadInferModelExecution
      : moon.clientProgramReadComposedInferModelExecution;
    const funded = beforeRead(1, () => wire, original.executions.length + original.bodies.length);
    const witness = funded === undefined && original.ordinaryOriginal && originalModelMaterialIntrinsics()
      ? {prepared, installation, occurrence, beforeRead} : undefined;
    checkInstallation(installation!);
    return Object.freeze({step, execution: checkedModelMetadata(Reflect.apply(read, moon,
      occurrence === undefined ? [prepared, step, wire, cid] : [occurrence, wire, cid]), witness)});
  }
  return readInstalledModelExecutionLegacy(moon, prepared, installation, occurrence);
}

function readInstalledModelExecutionLegacy(moon: ExecutionRuntime, prepared: unknown,
  installation: ModelInstallation | undefined, occurrence: unknown) {
  const step = occurrence === undefined
    ? moon.clientProgramSelectedInferStep(prepared)
    : (runtimeField(moon.clientProgramInferOccurrenceCoordinates(occurrence), 2) as number);
  if (step === undefined) return undefined;
  const taskCid = occurrence === undefined
    ? moon.clientProgramInferModelTaskCid(prepared, step)
    : moon.clientProgramInferOccurrenceModelTaskCid(occurrence);
  const entry = installation === undefined ? undefined :
    checkInstallation(installation).find(item => item.modelTaskCid === taskCid);
  if (entry === undefined) {
    throw Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
      {code: 'InstalledInferModelExecutionUnavailable'});
  }
  return Object.freeze({step, execution: checked(occurrence === undefined
    ? moon.clientProgramReadInferModelExecution(prepared, step, entry.bodyWire,
      entry.cid)
    : moon.clientProgramReadComposedInferModelExecution(occurrence,
      entry.bodyWire, entry.cid))});
}

// Only the actual normal Mock factory's frozen DATA envelope enters the
// funded Request path. This captures original arrays, not another registry,
// contract validator, canonical reader or Provider/Account permission.
function originalModelMaterialArrays(installation: unknown) {
  if (installation === null || typeof installation !== 'object' || !Object.isFrozen(installation)) {
    throw new TypeError('InstalledModelMaterialOriginalUnavailable');
  }
  const executions = Object.getOwnPropertyDescriptor(installation, 'executionContracts');
  const bodies = Object.getOwnPropertyDescriptor(installation, 'dependencyBodies');
  if (!executions || !Object.hasOwn(executions, 'value') ||
      !bodies || !Object.hasOwn(bodies, 'value') ||
      !Array.isArray(executions.value) || !Array.isArray(bodies.value) ||
      !Object.isFrozen(executions.value) || !Object.isFrozen(bodies.value)) {
    throw new TypeError('InstalledModelMaterialOriginalUnavailable');
  }
  const ownString = (entry: unknown, key: string) => {
    if (entry === null || typeof entry !== 'object' || !Object.isFrozen(entry)) {
      throw new TypeError('InstalledModelMaterialOriginalUnavailable');
    }
    const field = Object.getOwnPropertyDescriptor(entry, key);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
      throw new TypeError('InstalledModelMaterialOriginalUnavailable');
    }
  };
  const validate = (entries: readonly unknown[], fields: readonly string[]) => {
    const ordinaryArray = !nodeTypes.isProxy(entries) &&
      Object.getPrototypeOf(entries) === Array.prototype &&
      Reflect.ownKeys(entries).length === entries.length + 1 && originalModelMaterialIntrinsics();
    let ordinary = ordinaryArray;
    const entryFields = (entry: unknown) => {
      const plain = entry !== null && typeof entry === 'object' && !nodeTypes.isProxy(entry) &&
        [Object.prototype, null].includes(Object.getPrototypeOf(entry));
      ordinary &&= plain && Reflect.ownKeys(entry).length === fields.length;
      for (const key of fields) ownString(entry, key);
    };
    if (ordinaryArray) {
      // Inspect each original field once. Accessors retain their old reader
      // behavior but cannot supply a callback-free native-result witness.
      for (let index = 0; index < entries.length; index++) {
        const field = Object.getOwnPropertyDescriptor(entries, String(index));
        const own = field !== undefined && Object.hasOwn(field, 'value');
        ordinary &&= own;
        entryFields(own ? field.value : entries[index]);
      }
    } else for (const entry of entries) entryFields(entry);
    return ordinary;
  };
  const ordinaryExecutions = validate(executions.value, ['modelTaskCid', 'bodyWire', 'cid']);
  const ordinaryBodies = validate(bodies.value, ['bodyWire', 'cid']);
  const environment = Object.getOwnPropertyDescriptor(installation, 'environmentWire');
  const ordinaryOriginal = !nodeTypes.isProxy(installation) &&
    [Object.prototype, null].includes(Object.getPrototypeOf(installation)) &&
    Reflect.ownKeys(installation).length === 3 && typeof environment?.value === 'string' &&
    ordinaryExecutions && ordinaryBodies;
  return {executions: executions.value as readonly ExecutionBody[], bodies: bodies.value as readonly DependencyBody[], ordinaryOriginal,
    emptyOriginal: ordinaryOriginal && executions.value.length === 0};
}


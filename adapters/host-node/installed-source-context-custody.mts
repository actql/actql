import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {retainInstalledHostInitializationFailure as retainHostFailure} from './installed-host-cleanup.mjs';
import type {createInstalledSourceMaterialAccounting} from './installed-source-material-accounting.mjs';

type Accounting = ReturnType<typeof createInstalledSourceMaterialAccounting>;
type Material = NonNullable<ReturnType<Accounting['sourceMaterial']>>;
type ConfigurationReader = NonNullable<Material['configurationReader']>;
type CleanupInputs = NonNullable<Parameters<typeof retainHostFailure>[1]>;
type Role = 'source' | 'effect';
type Installation = Readonly<{registration?: string; revision?: string; effect?: unknown}>;
type HostOriginal = Parameters<Accounting['sourceMaterial']>[0] & Readonly<{
  selected: WeakMap<Installation, string>;
  current(): void;
  admitAcquisitionContracts?: unknown;
  acquisitionContractsCapacity?: unknown;
}>;
type Snapshot = Readonly<{source_ref: string; read_mode: string; source_view_contract_cid: string}>;
type PublishedEnvironment = Readonly<{body: Readonly<{
  schema_snapshots: readonly Snapshot[];
  connector_catalogs: readonly Readonly<{connector_id: string; source_views: readonly Readonly<{contract_cid: string}>[]}>[];
}>}>;
type SourceContext = Readonly<{preparePublishedEnvironment(wire: string): Readonly<{body: object}>}>;
type Prepared = Readonly<{declaration?: unknown; declared?: unknown; environment?: unknown; mappings?: unknown; commands?: unknown}>;
type SourceScope = Material['contexts'][number] & {
  connectorId?: string;
  active: boolean;
  role: Role;
  prepared?: Prepared;
  source?: CleanupInputs['sourceProfile'];
  acquisitionContractsAttempted?: boolean;
};
type RetainedContext = Readonly<{original: HostOriginal; material: Material; scope: SourceScope}>;
type BoundConstruction = {
  failed?: boolean; closed?: boolean;
  adapter?: CleanupInputs['sourceProfile']; site?: CleanupInputs['sourceProfile'];
  reader?: CleanupInputs['sourceReader']; authorization?: CleanupInputs['authorization'];
};
type ContextPorts<Context extends SourceContext, Original extends HostOriginal> = Pick<Accounting,
  'sourceMaterial' | 'reserveSource' | 'reconcileSource' | 'requireSynchronousSourceConstruction' | 'retainSourceFailure'> &
  Readonly<{
    fail(code: string): never;
    installations: Pick<WeakMap<object, Original>, 'get'>;
    sourceContexts: Pick<WeakMap<object, RetainedContext>, 'get'>;
    boundConstructions: Pick<WeakMap<object, BoundConstruction>, 'get'>;
    createInstalledSourceContext(original: Original, material: Material, installation: Installation,
      connectorId: string | undefined, baseEnvironmentWire: string, role: Role, services: object): Context;
    retainInstalledHostInitializationFailure: typeof retainHostFailure;
    resolveInstalledRowEffectConstruction(source: unknown, adapter: unknown): unknown;
  }>;

export function createInstalledSourceContextCustody<Context extends SourceContext, Original extends HostOriginal>({fail: reject, installations, sourceContexts, boundConstructions,
  sourceMaterial, createInstalledSourceContext, retainInstalledHostInitializationFailure,
  reserveSource, reconcileSource, requireSynchronousSourceConstruction, retainSourceFailure,
  resolveInstalledRowEffectConstruction}: ContextPorts<Context, Original>) {
  const fail: (code: string) => never = reject;

  function requireSourceConstructor(services: object, installation: Installation,
    fields: Readonly<{sourceInitialization?: PropertyDescriptor}>, prepared = false) {
    const original = installations.get(services)!;
    const field = fields.sourceInitialization;
    if (field === undefined && original.initialPreparation === undefined && original.material === undefined) {
      return installation;
    }
    if (!field || !Object.hasOwn(field, 'value')) fail('InstalledSourceInitializationUnavailable');
    const context = field.value as Context, selected = sourceContexts.get(context);
    if (selected?.original !== original || selected.material.phase !== 'working' ||
        !selected.scope.active || selected.scope.installation !== installation ||
        prepared && (selected.scope.prepared === undefined ||
          selected.scope.role === 'effect' && selected.scope.prepared.mappings === undefined && selected.scope.prepared.commands === undefined)) {
      fail('InstalledSourceInitializationUnavailable');
    }
    return context;
  }

  // Provider construction consumes only this original context, never a public
  // numerical capacity. Its declaration, native projection and Environment are
  // retained together by the same Source successor through Request borrowing.
  function beginInstalledSourceInitialization(services: object, installation: Installation, connectorId: unknown,
    baseEnvironmentWire: unknown, role: string = 'source') {
    const original = installations.get(services);
    if (original === undefined) fail('ForeignInstalledHostServices');
    const material = sourceMaterial(original);
    if (material === undefined) return undefined;
    if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
    if (original.selected.get(installation) === undefined || typeof connectorId !== 'string' ||
        typeof baseEnvironmentWire !== 'string' || !['source', 'effect'].includes(role) ||
        role === 'effect' && installation.effect === undefined) fail('ForeignInstalledSourceInitialization');
    return createInstalledSourceContext(original, material, installation, connectorId, baseEnvironmentWire, role as Role, services);
  }

  // The existing builtin publishes its complete Environment, rather than a Row
  // declaration. Retain the SAME pending Source context before its checked
  // constructor; select the connector only from that admitted original Catalog.
  function beginInstalledPublishedSourceInitialization(services: object, installation: Installation, sourceRef: unknown,
    wire: unknown, baseEnvironmentWire: unknown) {
    const original = installations.get(services);
    if (original === undefined) fail('ForeignInstalledHostServices');
    const material = sourceMaterial(original);
    if (material === undefined) return undefined;
    if (material.phase !== 'working' || original.selected.get(installation) === undefined ||
        typeof sourceRef !== 'string' || typeof wire !== 'string' || typeof baseEnvironmentWire !== 'string') {
      fail('ForeignInstalledSourceInitialization');
    }
    const context = createInstalledSourceContext(original, material, installation, undefined, baseEnvironmentWire, 'source', services);
    try {
      const environment = context.preparePublishedEnvironment(wire) as PublishedEnvironment;
      // Catalog views carry their checked contract identity, not a source_ref.
      // Join the SAME admitted snapshot selector to that exact catalog member;
      // never infer a connector by parsing or repairing the URI-like spelling.
      let snapshot: Snapshot | undefined;
      for (const candidate of environment.body.schema_snapshots) {
        if (candidate.source_ref !== sourceRef || candidate.read_mode !== 'snapshot') continue;
        if (snapshot !== undefined) fail('InstalledSourceBindingAmbiguous');
        snapshot = candidate;
      }
      if (snapshot === undefined) fail('InstalledSourceProgramMismatch');
      let selected;
      for (const catalog of environment.body.connector_catalogs) {
        if (!catalog.source_views.some(view => view.contract_cid === snapshot!.source_view_contract_cid)) continue;
        if (selected !== undefined) fail('InstalledSourceBindingAmbiguous');
        selected = catalog.connector_id;
      }
      if (typeof selected !== 'string' || selected.length === 0) fail('InstalledSourceProgramMismatch');
      const retained = sourceContexts.get(context)!;
      if (!retained.scope.active || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
      retained.scope.connectorId = selected;
      return context;
    } catch (cause) {
      finishInstalledSourceInitialization(context, undefined, cause, true);
      throw cause;
    }
  }

  async function retainBoundInstalledSourceFailure(context: object, cause: unknown, adapter?: unknown) {
    const owned = boundConstructions.get(context);
    const registered = sourceContexts.get(context)?.scope.source;
    if (owned === undefined) return retainInstalledHostInitializationFailure(cause, {sourceProfile: registered});
    owned.failed = true;
    // The adapter's existing close owns its Reader and Site after successful
    // construction; before then the same acquired originals remain here.
    // The module's returned value is not custody evidence. A mistaken foreign
    // return must not close a sibling; a correctly registered own adapter must
    // still retire even when the module returns something else.
    const acquired = owned.adapter ?? registered;
    return retainInstalledHostInitializationFailure(cause, acquired !== undefined
      ? {sourceProfile: acquired}
      : {sourceReader: owned.reader, sourceProfile: owned.site,
        ...(owned.site === undefined ? {authorization: owned.authorization} : {})});
  }

  function assertInstalledSourceConstruction(context: object, declaration: unknown, declared: unknown, environment: unknown,
    providerReader?: unknown, mappings?: unknown, commands?: unknown) {
    const retained = sourceContexts.get(context), prepared = retained?.scope.prepared;
    if (retained === undefined || prepared === undefined || !retained.scope.active || retained.material.phase !== 'working' ||
        prepared?.declaration !== declaration || prepared.declared !== declared || prepared.environment !== environment) {
      fail('ForeignInstalledSourceConstruction');
    }
    const empty = (value: unknown) => Array.isArray(value) && !nodeTypes.isProxy(value) &&
      Object.getOwnPropertyDescriptor(value, 'length')?.value === 0;
    // The constructor has two existing alternatives. An omitted family's
    // default empty Array is not a second original; any added/nonoriginal
    // members still refuse before adapter construction or another callback.
    if (mappings !== undefined && prepared.mappings !== mappings &&
        !(prepared.mappings === undefined && prepared.commands === commands && empty(mappings))) fail('ForeignInstalledSourceConstruction');
    if (commands !== undefined && prepared.commands !== commands &&
        !(prepared.commands === undefined && prepared.mappings === mappings && empty(commands))) fail('ForeignInstalledSourceConstruction');
    if (providerReader !== undefined) {
      if (retained.scope.reader !== providerReader || retained.scope.readerDemand === undefined) {
        fail('ForeignInstalledSourceReaderDemand');
      }
      return retained.scope.readerDemand;
    }
  }

  // Normal static protocol input uses the existing SAME Source file reader.
  // Its original stat/before-read/before-decode/close path owns every Buffer and
  // String before the native admission constructor can receive these inputs.
  async function readInstalledSourceAcquisitionContract(context: object, path: unknown): Promise<string> {
    const retained = sourceContexts.get(context);
    if (retained === undefined || retained.material.phase !== 'working' ||
        !retained.scope.active || retained.scope.prepared === undefined || retained.scope.source !== undefined) {
      fail('ForeignInstalledSourceInitialization');
    }
    const {original,material,scope} = retained;
    if (material.busy) fail('InstalledSourceInitializationReentry');
    const reader = material.configurationReader;
    const method = reader && Object.getOwnPropertyDescriptor(reader,'readOriginalText');
    if (!method || !Object.hasOwn(method,'value') || typeof method.value !== 'function') {
      fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    const value = await Reflect.apply(method.value as ConfigurationReader['readOriginalText'],reader,[path]);
    original.current();
    if (material.phase !== 'working' || !scope.active || scope.source !== undefined) fail('ForeignInstalledSourceInitialization');
    return value;
  }

  // Retain the existing admitted protocol holder on the SAME Source successor.
  // No Request needs to parse these unchanged installation bodies again. The
  // numeric extents describe this constructor's input/output/failed-child overlap;
  // only the original initial capacity can admit them, before the Core call.
  function prepareInstalledSourceAcquisitionContracts(context: object, query: unknown, evidence: unknown) {
    const retained = sourceContexts.get(context);
    if (retained === undefined || retained.material.phase !== 'working' ||
        !retained.scope.active || retained.scope.prepared === undefined || retained.scope.source !== undefined) {
      fail('ForeignInstalledSourceInitialization');
    }
    const {original, material, scope} = retained;
    if (material.busy) fail('InstalledSourceInitializationReentry');
    if (scope.acquisitionContractsAttempted || scope.acquisitionContracts !== undefined) fail('InstalledSourceAcquisitionContractsAlreadyPrepared');
    if (typeof query !== 'string' || typeof evidence !== 'string') fail('InvalidInstalledSourceAcquisitionContracts');
    if (typeof original.admitAcquisitionContracts !== 'function' || typeof original.acquisitionContractsCapacity !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
    scope.acquisitionContractsAttempted = true;
    const prepared = scope.prepared;
    let quantity;
    material.busy = true;
    try {quantity = requireSynchronousSourceConstruction(material,
      Reflect.apply(original.acquisitionContractsCapacity, original.moon, [query.length, evidence.length]));}
    finally {material.busy = false;}
    if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) fail('InstalledSourceAcquisitionContractsConstructionUnavailable');
    // The SAME original native parser/canonical/hash owner supplies its actual
    // constructor peak. Keep the full peak through Source retirement, including
    // a failed reserve or native call; do not turn escaped byte counts into a
    // second number of generic ValueNodeSlots and quote the same trees twice.
    material.providers.push(quantity);
    reserveSource(original, material);
    if (material.phase !== 'working' || !scope.active || scope.prepared !== prepared || scope.source !== undefined) fail('ForeignInstalledSourceInitialization');
    let contracts;
    material.busy = true;
    try {contracts = checked(requireSynchronousSourceConstruction(material,
      Reflect.apply(original.admitAcquisitionContracts, original.moon, [query, evidence])));}
    finally {material.busy = false;}
    if (contracts === undefined || contracts === null) fail('InstalledSourceAcquisitionContractsUnavailable');
    // Retain before any subsequent current/reconcile callback can fail.
    scope.acquisitionContracts = contracts;
    material.inputs.push(query, evidence, contracts);
    original.current();
    if (material.phase !== 'working' || !scope.active || scope.source !== undefined) fail('ForeignInstalledSourceInitialization');
    reconcileSource(original, material);
    return contracts;
  }

  function retainInstalledSourceConstruction(context: object, source: CleanupInputs['sourceProfile'], declaration: unknown,
    declared: unknown, environment: unknown) {
    assertInstalledSourceConstruction(context, declaration, declared, environment);
    const retained = sourceContexts.get(context)!;
    if (retained.scope.source !== undefined) fail('InstalledSourceAlreadyConstructed');
    retained.scope.source = source;
  }

  function closeInstalledSourceConstruction(context: object, source: unknown) {
    const retained = sourceContexts.get(context);
    if (retained === undefined || retained.scope.source !== source) fail('ForeignInstalledSourceConstruction');
    retained.scope.closed = true;
    const owned = boundConstructions.get(context);
    if (owned !== undefined) {
      owned.site = owned.authorization = owned.reader = owned.adapter = undefined;
      owned.closed = true;
    }
  }

  function finishInstalledSourceInitialization(context: object | undefined, adapter: unknown, cause?: unknown, failed = false) {
    if (context === undefined) return;
    const retained = sourceContexts.get(context);
    if (retained === undefined || !retained.scope.active) fail('ForeignInstalledSourceInitialization');
    const selected = retained.scope.role === 'effect'
      ? resolveInstalledRowEffectConstruction(retained.scope.source, adapter) : adapter;
    if (!failed && (retained.scope.source === undefined || retained.scope.source !== selected)) {
      fail('InstalledSourceConstructorUnavailable');
    }
    if (failed) retainSourceFailure(retained.material, cause);
    retained.scope.finishedSuccessfully = !failed;
    retained.scope.active = false; retained.material.constructors--;
  }

  function retainInstalledHostServiceInstallation(services: object | undefined, installation: Installation, runtimeBundleCid: string | undefined) {
    if (services === undefined) return;
    const original = installations.get(services);
    if (original === undefined) fail('ForeignInstalledHostServices');
    original.current();
    if (!installation || typeof installation !== 'object' || !Object.isFrozen(installation) ||
        !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '')) {
      fail('InvalidInstalledHostServiceInstallation');
    }
    const previous = original.selected.get(installation);
    if (previous !== undefined && previous !== runtimeBundleCid) fail(
      'InstalledHostServiceRuntimeChanged');
    original.selected.set(installation, runtimeBundleCid!);
  }

  return {requireSourceConstructor, beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization,
    retainBoundInstalledSourceFailure, assertInstalledSourceConstruction, readInstalledSourceAcquisitionContract,
    prepareInstalledSourceAcquisitionContracts, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
    finishInstalledSourceInitialization, retainInstalledHostServiceInstallation};
}

// Snapshot only the existing required Source service methods. The connector
// chooses its own unavailable error and retains its explicit legacy branch.
// This view issues no service, installation, capacity or cleanup observation.
export function captureInstalledSourceServices(receiver: unknown, unavailable: unknown) {
  if (typeof unavailable !== 'function') throw new TypeError('InvalidInstalledSourceServiceErrorFactory');
  const refuse: () => never = () => {throw Reflect.apply(unavailable, undefined, []);};
  if (receiver === null || !['object', 'function'].includes(typeof receiver) || nodeTypes.isProxy(receiver)) refuse();
  const methods: Record<string, (...args: unknown[]) => unknown> = Object.create(null);
  for (const name of ['sourceReaderImplementationProfile', 'sourceReaderImplementation', 'openRowSite', 'createSourceReader']) {
    const field = Object.getOwnPropertyDescriptor(receiver as object, name);
    if (field === undefined || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') refuse();
    methods[name] = field.value;
  }
  Object.freeze(methods);
  return Object.freeze(function invokeInstalledSourceService(name: unknown, ...args: unknown[]) {
    if (typeof name !== 'string' || !Object.hasOwn(methods, name)) refuse();
    return Reflect.apply(methods[name], receiver, args);
  });
}

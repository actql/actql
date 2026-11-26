import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createFixtureFileSupplier} from './fixture-file-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime} from '../host-node/installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from '../host-node/installed-project-connections.mjs';
import {loadDeclaredProjectCatalog, inspectDeclaredProjectCatalog} from './declared-project-catalog.mjs';
import {assertDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import {composeInstalledSourceEnvironment} from '../host-node/installed-funded-environment.mjs';
import {contentCid} from '../host-node/local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from '../host-node/installed-host-cleanup.mjs';
import {retireNodeInferOriginalRead} from '../host-node/infer-operation.mjs';
import {declaredProjectWritableRuntimeConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';

import type {createDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import type {selectInstalledProjectProfile} from '../host-node/installed-project-profile.mjs';

type Catalog = Awaited<ReturnType<typeof loadDeclaredProjectCatalog>>;
type CatalogInspection = Awaited<ReturnType<typeof inspectDeclaredProjectCatalog>>;
type CatalogSource = Catalog['sources'][number];
type Inventory = ReturnType<typeof createDeclaredFileInstallationInventory>;
type Project = Parameters<typeof loadInstalledProjectConnections>[1];
type ProjectOriginal = ReturnType<typeof installedProjectOriginalsForRuntime>;
type Connections = Awaited<ReturnType<typeof loadInstalledProjectConnections>>;
type ConnectionOriginal = ReturnType<Connections['originalsForRuntime']>;
type Profile = ReturnType<typeof selectInstalledProjectProfile>;
type CatalogLoader<View extends CatalogInspection = Catalog> =
  (...args: Parameters<typeof loadDeclaredProjectCatalog>) => Promise<View>;
type ProjectRuntime = Parameters<CatalogLoader>[0] & NonNullable<Parameters<typeof loadInstalledProjectConnections>[0]>;
type PreparationOptions = Readonly<{assertCurrent?: () => unknown; openFile?: unknown; installationInventory?: Inventory}>;
type Available = object & Readonly<{then?: never; file?: Readonly<{close(): unknown}>}>;
type Phase = Parameters<typeof declaredProjectWritableRuntimeConstructionGeometry>[2];
type Frame<View extends CatalogInspection = Catalog> = Readonly<{
  physicalKind: 'declared-json-document'; project: ProjectOriginal; configuration: unknown; selection: unknown;
  connections: ConnectionOriginal; dataFile: string; dataPath: string; catalog: View;
  sources: View['sources']; writables: View['writables'];
}>;
type Preparation<View extends CatalogInspection = Catalog> = Readonly<{
  originalsForRuntime(runtime: unknown): Frame<View>;
  constructWritableRuntime<Value extends Available>(runtime: unknown, phase: Phase,
    source: View['sources'][number] | undefined, projectImplementation: () => Value): Promise<Value>;
  retire(runtime: unknown): void;
}>;
type Plan = Readonly<{compiled: unknown; runDefinition: unknown; queryTimePreparation?: unknown}>;
type Occurrence = Readonly<{stage: number; input: number; task: number}>;
type Selection = Readonly<{graph: unknown; occurrence: unknown}>;
type Control = Parameters<typeof retireNodeInferOriginalRead>[0]['control'] & Readonly<{
  prepareCheckedClientInferOriginalRead(compiled: unknown, definition: unknown, graph: unknown, scope: unknown, budget: Budget): unknown;
}>;
type Budget = Readonly<{readRetainedBytes: bigint; readExecutionBytes: bigint; modelRetainedBytes: bigint; modelExecutionBytes: bigint}>;
type Model = {
  control?: Control; compiled?: unknown; runDefinition?: unknown; graph?: unknown; occurrence?: unknown; compilation?: unknown;
  selection?: Selection; component?: Readonly<{bindOriginal?: unknown}>; queryTimePreparation?: unknown; scope?: unknown;
  budget?: Budget; publicationCapacity?: () => unknown; releaseAliases?(this: Model): void;
  closed?: boolean; scopeFinished?: boolean; taken?: boolean; readAttempted?: boolean;
  read?: unknown; readFailure?: unknown; sourceLedgerAttempted?: boolean; sourceLedgerFailure?: unknown;
  sourceLedger?: unknown; hostAttempted?: boolean;
};
type Physical = CatalogSource['physical'][number];
type FileBinding = CatalogSource['fileBindings'][number];
type Read = {
  raw?: object; source: number; occurrence?: Occurrence; request?: unknown;
  close?: () => unknown; bytes?: () => Buffer | PromiseLike<Buffer>; value?: object;
  closed: boolean; keyed?: boolean; physicalClosed?: boolean;
  observedBytes?: Buffer; document?: unknown; projections?: Map<Physical, unknown>;
};
type Run = {
  prepared?: object; request?: unknown; runtime?: object; preparationKind?: string;
  value?: unknown; original?: unknown; admission?: unknown; requestOwned?: boolean; preparationFunded?: boolean;
  model?: Model; managed?: HostRun; closed?: boolean; reads?: (Read | undefined)[]; failure?: unknown;
  effectful?: boolean; retired?: boolean; aliasesReleased?: boolean; retiringModel?: boolean; retiringContent?: boolean;
  retiringMockSources?: boolean; mockSourceReads?: (Read | undefined)[]; mockKeyedReads?: Read[];
  releaseMockSourceAliases?(this: Run, prepared: object, request: unknown): void;
};
// The Host-owned Run lends the same identity and closure cells. The
// Connector's local wrapper alone initially owns its independent read array.
type HostRun = Omit<Run, 'model'> & {model?: unknown};
type ManagedSourceFacts = Readonly<{preparedProgram: object; requestIdentity: unknown; prepareInvocation?: unknown; effectful?: unknown}>;
type AcquireCapacity = Readonly<{managedRun: unknown; wholeInput?: boolean; capacity: unknown; transferBytes: bigint; executionBytes: bigint}>;
type SavedCapture = Readonly<{capture: Readonly<{source(): unknown}>}>;
type EnvironmentArgs = Parameters<typeof composeInstalledSourceEnvironment>;
type CorePlan = [registry: unknown, values: string, fragment: string | undefined, ordered: string | undefined];
type LedgerArgs = [value: unknown, prepared: unknown, request: unknown,
  capacities: readonly unknown[], transfers: readonly bigint[], executions: readonly bigint[]];
type KeyedRead = [value: unknown, keyed: unknown, request: unknown, declaration: unknown];
type ReadProfile = [identity: string, name: string, version: string, mediaType: string,
  contentUtf8: string, path: string | undefined, itemsPath: readonly string[], keyPath: readonly string[]];
type ProducerMoon = EnvironmentArgs[1] & Parameters<typeof createFixtureFileSupplier>[0]['moon'] & Readonly<{
  clientProgramInstalledManagedRunCheck(value: unknown, prepared: unknown, request: unknown): unknown;
  clientProgramAcquisitionCount(prepared: unknown): number;
  clientProgramEffectAcquisitionCount(prepared: unknown): number;
  clientProgramInstalledManagedWholeSourcesLedger?(...args: LedgerArgs): unknown;
  clientProgramInstalledManagedRunPrepareLedger(...args: [...LedgerArgs, ...CorePlan]): unknown;
  clientProgramOpenInstalledManagedSourceFreeComposedInferHost(value: unknown, prepared: unknown, request: unknown,
    ...args: [...CorePlan, providers: unknown]): unknown;
  clientProgramOpenInstalledManagedCaptureHost(value: unknown, prepared: unknown, request: unknown, sources: readonly unknown[]): unknown;
  clientProgramInstalledManagedRunRetire(value: unknown): unknown;
  clientProgramNodeManagedRunCleanup(admission: unknown): unknown;
  clientProgramInstalledKeyedSourceReadRetire(read: unknown): unknown;
  clientProgramInstalledSourceReadRetire(read: unknown): unknown;
  clientProgramResourceReferenceIssuer(admit: (kind: string, wire: string) => boolean, current: () => boolean): unknown;
  clientProgramRelationAdmitDocument(bytes: Uint8Array, maximum: number, nodes: number, depth: number, rows: number, work: number): unknown;
  clientProgramRelationProjectTargetDocument(document: unknown, declaration: unknown, resource: string,
    items: readonly string[], key: readonly string[], identity: string | undefined,
    preparedKey: unknown, writable: readonly string[]): unknown;
  clientProgramRowSourceFileReadProfileMatches?(declaration: unknown, ref: string, physical: unknown,
    resource: string, ...fields: ReadProfile): boolean;
  clientProgramInstalledManagedRunSourceReadAt(value: unknown, stage: number, input: number, task: number): object | undefined;
  clientProgramInstalledManagedEffectKeyedSourceRead(...args: [...KeyedRead, number, number, number]): unknown;
  clientProgramInstalledManagedModelKeyedSourceRead(...args: [...KeyedRead, number, number, number]): unknown;
  clientProgramInstalledManagedKeyedSourceRead(...args: KeyedRead): unknown;
  clientProgramRelationAcceptChargedInputDocument(run: unknown, charge: unknown, acquisition: unknown, document: unknown, work: number): unknown;
  clientProgramRelationAcceptChargedDocument(run: unknown, charge: unknown, acquisition: unknown, document: unknown, work: number): unknown;
}>;
type Authorization = Readonly<{context: Readonly<{contextCid: string}>; assertAccountCurrent?: (decision: unknown) => unknown}>;
type SourceManaged = Readonly<{
  assertCurrent(): unknown;
  prepareRead(owner: object, declaration: unknown, run: unknown, occurrence: Occurrence): object;
  prepareKeyedRead?(owner: object, declaration: unknown, run: unknown, request: unknown): object;
}>;
type SourceInstallOptions = Readonly<{
  moon: ProducerMoon; mockPreparation: Preparation; sourceManaged: SourceManaged;
  baseEnvironmentWire: EnvironmentArgs[2]; installationServices: EnvironmentArgs[0];
  authorizationFor(connection: string): Authorization | PromiseLike<Authorization>;
  readAsset: (input: unknown) => unknown;
  prepareManagedModelRun?: (prepared: object, request: unknown, model: Model) => HostRun;
  prepareManagedSourceRun: (facts: ManagedSourceFacts) => HostRun;
  effectManagedRun?: (prepared: object, request: unknown) => HostRun;
}>;
type Declared = Readonly<{views: readonly Readonly<{
  resource: string; source_ref: string; view_cid: string; carrier_schema_cid: string;
}>[]}>;
type DispatchDecision = Readonly<{
  action?: string; boundary?: string; tuple?: Readonly<{connection?: string; resource?: string; operation?: string}>;
  contextCid?: string;
}>;
type GrantOptions = Readonly<{
  operation: string; decision: DispatchDecision; resource: string; runInvocationCid: string; dispatchRequestCid: string; maxUses: number;
}>;
type RowRun = Readonly<{
  originalRead?: object; originalKeyedRead?: object; inputKind?: string; run?: unknown; acquisition?: unknown;
}>;
type ReadOptions = Readonly<{rowRun: RowRun; signal?: AbortSignal; verifyRead(): unknown}>;
type Supplier = ReturnType<typeof createFixtureFileSupplier<RowRun>>;
type ListingPage = Parameters<Supplier['readListing']>[0];
type ContentPage = Parameters<Supplier['readContent']>[0];
type Pages = ReadOptions & Partial<ListingPage> & Partial<ContentPage> &
  Readonly<{resource: string; chargePage(bytes: Uint8Array): unknown}>;
type ReadPreparation = Readonly<{
  checkedOwner: object; effectful: boolean; declaration: unknown; occurrence: Occurrence; managedRun?: unknown; originalRead?: object;
}>;
type KeyedPreparation = Readonly<{
  checkedOwner: object; keyedAcquisition: unknown; request: unknown; declaration: unknown; managedRun?: unknown; originalRead?: object;
  rowLimits: Readonly<{maxPageBytes: number; maxTextBytes: number; maxWork: number}>;
}>;
type SourceFacts = Readonly<{preparedEffect?: object; preparedProgram?: object; requestIdentity?: unknown; managedRun?: unknown}>;
type SourceAdapter = Readonly<{
  close(): unknown; environmentWire: string; connectorBindings: readonly unknown[];
  admitsSource(ref: string): boolean;
  prepare(facts: SourceFacts): object | PromiseLike<object>;
  ledgerCapacity(prepared: object): Readonly<Record<string, unknown>>;
}>;
type QueryAlias = Readonly<{name: string; sourceRef: string; sourceViewContractCid: string; schemaContractCid: string; request?: object}>;
type InstalledSource = SourceAdapter & Readonly<{queryAliases: readonly QueryAlias[]; requiresRunContentCapture?: boolean}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const mockRealization = 'installed-multi-acquired';
const canonical = (value: unknown) => canonicalJson(value, {dataKeys: true});
const exactCid = (value: unknown) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

// The exact request Site subject of this same fixed Mock installation, before
// authorization-dependent adapters are built. The returned label grants no
// Source or operation; the installer below uses this same retained constant.
export function installedMockRequestRealization(preparation: Pick<Preparation, 'originalsForRuntime'>, runtime: unknown) {
  if (preparation.originalsForRuntime(runtime).sources.length < 1) fail('ForeignInstalledMockPreparation');
  return mockRealization;
}

// Original installation preparation under the separately admitted Source
// phase, before any fixture acquisition. The bundled declarations are not
// inferred from rows, a Task, pathname or the original connection's secrets.
// This view supplies no read decision, physical child, Run or capacity.
function capturedPreparationOptions(options: unknown): PreparationOptions {
  if (options === null || typeof options !== 'object' || Array.isArray(options) ||
      nodeTypes.isProxy(options)) fail('ForeignDeclaredFileInstallation');
  const captured: Record<string, unknown> = {};
  for (const name of ['assertCurrent', 'openFile', 'installationInventory']) {
    const field = Object.getOwnPropertyDescriptor(options, name);
    if (field !== undefined && !Object.hasOwn(field, 'value')) fail('ForeignDeclaredFileInstallation');
    captured[name] = field?.value;
  }
  return Object.freeze(captured) as PreparationOptions;
}

export async function prepareInstalledProjectMock(moon: ProjectRuntime, project: Project, profile: Profile, options: PreparationOptions = {}) {
  options = capturedPreparationOptions(options);
  assertDeclaredFileInstallationInventory(options.installationInventory, moon,
    installedProjectOriginalsForRuntime(project, moon));
  return prepareProjectMockDeclarations(moon, project, profile, options, loadDeclaredProjectCatalog);
}

// Explicit metadata inspection. It cannot produce issued installation members.
export async function inspectProjectMockDeclarations(moon: ProjectRuntime, project: Project, profile: Profile, options: PreparationOptions = {}) {
  options = capturedPreparationOptions(options);
  if (options.installationInventory !== undefined) fail('ForeignDeclaredFileInstallation');
  return prepareProjectMockDeclarations(moon, project, profile, options, inspectDeclaredProjectCatalog);
}

async function prepareProjectMockDeclarations<View extends CatalogInspection>(
  moon: ProjectRuntime, project: Project | undefined, profile: Profile | undefined,
  {assertCurrent, openFile, installationInventory}: PreparationOptions, loadCatalog: CatalogLoader<View>,
): Promise<Preparation<View>> {
  let projectOriginal: ProjectOriginal | undefined = installedProjectOriginalsForRuntime(project, moon);
  if (typeof assertCurrent !== 'function' || typeof project!.directory !== 'string' ||
      !project!.directory || typeof profile?.originalsForRuntime !== 'function' ||
      typeof profile?.mockLocatorsForRuntime !== 'function') {
    fail('InvalidInstalledMockPreparation');
  }
  let countConnections = moon?.clientProjectConnectionsCount;
  if (typeof countConnections !== 'function') fail('InstalledProjectRuntimeUnavailable');
  let profilePorts: Readonly<{originals: Profile['originalsForRuntime'];
    locators: Profile['mockLocatorsForRuntime']}> | undefined = Object.freeze({
    originals: profile.originalsForRuntime, locators: profile.mockLocatorsForRuntime});
  const select = <Name extends keyof NonNullable<typeof profilePorts>>(name: Name) =>
    Reflect.apply(profilePorts![name], profile, [moon]) as ReturnType<NonNullable<typeof profilePorts>[Name]>;
  let selection: ReturnType<Profile['originalsForRuntime']> | undefined = select('originals');
  function current() {
    assertCurrent!();
    const observed = select('originals');
    if (installedProjectOriginalsForRuntime(project, moon) !== projectOriginal ||
        selection!.configuration !== projectOriginal!.configuration ||
        observed.configuration !== selection!.configuration ||
        observed.selection !== selection!.selection || observed.selected !== 'mock' ||
        selection!.selected !== 'mock') fail('ForeignInstalledMockPreparation');
  }
  current();
  const locators = select('locators');
  if (typeof locators.dataFile !== 'string' || !locators.dataFile ||
      !locators.dataFile.isWellFormed() || locators.dataFile.length > 65536) {
    fail('InstalledMockDataUnavailable');
  }
  // This reads only the explicitly selected connections declaration. The
  // original metadata reader owns its same FD, UTF8 bounds and close carrier;
  // no entry's credential resolver, env variable or network is consulted.
  let connections: Connections | undefined = await loadInstalledProjectConnections(moon, project!,
    {assertCurrent: current, installationInventory, ...(openFile === undefined ? {} : {openFile})});
  current();
  let connectionOriginal: ConnectionOriginal | undefined = connections.originalsForRuntime(moon);
  if (connectionOriginal.project !== projectOriginal ||
      connectionOriginal.connections === undefined) fail('InstalledMockConnectionsUnavailable');
  const count = Reflect.apply(countConnections, moon, [connectionOriginal.connections]);
  if (!Number.isSafeInteger(count) || count < 0 || count > 128) {
    fail('InstalledMockConnectionCountUnavailable');
  }
  let catalog: View | undefined = await loadCatalog(moon, {directory: project!.directory as string,
    catalogFile: locators.catalogFile, dataFile: locators.dataFile, connectionOriginal,
    connections: connectionOriginal.connections,
    assertCurrent: current, openFile, installationInventory});
  let sources: View['sources'] | undefined = catalog.sources;
  let writables: View['writables'] | undefined = catalog.writables;
  current();
  let originals: Frame<View> | undefined = Object.freeze({physicalKind: 'declared-json-document',
    project: projectOriginal!, selection: selection.selection,
    configuration: selection.configuration, connections: connectionOriginal,
    dataFile: locators.dataFile, dataPath: resolve(project!.directory as string, locators.dataFile),
    sources, writables, catalog});
  let retired = false, view: Preparation<View>;
  function same(runtime: unknown, receiver: unknown) {
    if (runtime !== moon || receiver !== view) fail('ForeignInstalledMockPreparation');
  }
  view = Object.freeze({
    originalsForRuntime(runtime: unknown) {
      same(runtime, this);
      if (retired) fail('InstalledMockPreparationRetired');
      current();
      if (connections!.originalsForRuntime(moon) !== connectionOriginal) {
        fail('ForeignInstalledMockPreparation');
      }
      return originals!;
    },
    async constructWritableRuntime<Value extends Available>(runtime: unknown, phase: Phase,
      source: View['sources'][number] | undefined, projectImplementation: () => Value) {
      same(runtime, this);
      if (retired || typeof projectImplementation !== 'function' || installationInventory === undefined) {
        fail('InstalledMockImplementationConstructionUnavailable');
      }
      current();
      let value: Value | undefined;
      try {
      const result = installationInventory.prepareMetadataInput(Object.freeze({
        capacity() {
          const {retained, workspace} = declaredProjectWritableRuntimeConstructionGeometry(sources!, writables!, phase, source);
          return checked(moon.clientProgramInstalledSourceConstructionCapacity!(
            retained.nodes, retained.text, retained.wire, workspace.nodes, workspace.text, workspace.wire));
        }, project() {
          // Retain the actual physical owner BEFORE the reader's completion or
          // following current fence can fail. Never recreate it for cleanup.
          value = projectImplementation();
          return value;
        },
      }));
      current();
      return result;
      } catch (cause) {
        if (value?.file !== undefined) {
          throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: {close: value.file.close}});
        }
        throw cause;
      }
    },
    retire(runtime: unknown) {
      same(runtime, this);
      if (retired) return;
      // Managed references only, after the actual Source parent's close. This
      // cannot settle its FD, backing bytes, RowRuns or external cleanup ACKs.
      retired = true;
      originals = sources = writables = catalog = connections = connectionOriginal = undefined;
      projectOriginal = selection = project = profile = profilePorts = countConnections = undefined;
      assertCurrent = openFile = undefined;
      installationInventory = undefined;
    },
  });
  return view;
}

// Physical installation of the same already retained Mock declarations. The
// ordinary Host supplies its existing Account gates and the actual selected
// Source/managed-Compute original; neither the profile label nor this factory
// issues a permission, a runtime parent, or a replacement Run.
export async function installPreparedProjectMockSources({moon, mockPreparation,
  sourceManaged, baseEnvironmentWire, authorizationFor, readAsset, prepareManagedModelRun, prepareManagedSourceRun, effectManagedRun, installationServices}: SourceInstallOptions) {
  if (typeof authorizationFor !== 'function' || typeof readAsset !== 'function' ||
      typeof prepareManagedSourceRun !== 'function' ||
      typeof sourceManaged?.assertCurrent !== 'function' ||
      typeof sourceManaged?.prepareRead !== 'function') fail('NodeManagedRunAdmissionUnavailable');
  const bundle = mockPreparation.originalsForRuntime(moon);
  if (bundle.sources.length < 1) fail('InstalledMockCatalogueUnavailable');
  if (bundle.sources.some(source => source.sourceMember === undefined ||
      source.sourcePrepared === undefined)) fail('DeclaredFileInstallationUnavailable');
  let closing = false;
  const prepareRequestModel = prepareManagedModelRun;
  const prepareRequestSource = prepareManagedSourceRun;
  const records = new Map<object, Run>(), originalReads = new WeakMap<object, {run: HostRun; read: Read}>();
  // Weak provenance for Source and Effect Runs already owned by this Host.
  const effectRuns = new WeakMap<object, WeakRef<HostRun>>(), effectReads = new Set<Read>(), keyedReads = new Set<Read>();
  const sources: InstalledSource[] = [], closedSources = new Set<InstalledSource>();
  const current = () => {
    if (closing) fail('InstalledMockSourceClosed');
    sourceManaged.assertCurrent();
    if (mockPreparation.originalsForRuntime(moon) !== bundle) fail('ForeignInstalledMockPreparation');
  };
  const sameRun = (prepared: object | undefined) => {
    current();
    const record = records.get(prepared!) ?? effectRuns.get(prepared!)?.deref();
    if (record === undefined || record.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
    if (record.preparationKind === 'effect-plan') {
      if (typeof effectManagedRun !== 'function' ||
          effectManagedRun(prepared!, record.request) !== record) fail('ForeignInstalledModelPreparation');
      return record;
    }
    checked(moon.clientProgramInstalledManagedRunCheck(record.value, prepared, record.request));
    return record;
  };
  function prepareManagedRun(facts: ManagedSourceFacts) {
    if (arguments.length !== 1 || facts?.preparedProgram === undefined ||
        facts.requestIdentity === undefined || facts.effectful !== undefined) {
      fail('InvalidInstalledManagedRunRequest');
    }
    const {preparedProgram: prepared, requestIdentity: request, prepareInvocation} = facts;
    current();
    if (typeof prepareRequestSource !== 'function') fail('NodeManagedRunAdmissionUnavailable');
    // The Host retains partial construction and the adopted original before
    // this callback returns. This weak index adds no Root or retirement owner.
    const record: HostRun = Reflect.apply(prepareRequestSource, undefined,
      [Object.freeze({preparedProgram: prepared, requestIdentity: request, prepareInvocation})]);
    if (record?.prepared !== prepared || record.request !== request ||
        record.runtime !== moon || record.closed || record.value === undefined) {
      fail('ForeignInstalledSourcePreparation');
    }
    if (Object.hasOwn(record, 'failure')) throw record.failure;
    effectRuns.set(prepared, new WeakRef(record));
    const value = record.value;
    current();
    if (Object.hasOwn(record, 'failure')) throw record.failure;
    if (effectRuns.get(prepared)?.deref() !== record || record.prepared !== prepared ||
        record.request !== request || record.runtime !== moon || record.closed || record.value !== value) {
      fail('ForeignInstalledSourcePreparation');
    }
    return value;
  }
  function bindManagedSerializationReadRun(run: HostRun) {
    current();
    const prepared = run.prepared, request = run.request, value = run.value;
    if (run.preparationKind !== 'serialization-plan' || prepared === undefined ||
        request === undefined || value === undefined || run.runtime !== moon || run.closed ||
        Object.hasOwn(run, 'failure') || records.has(prepared)) fail('ForeignInstalledSourcePreparation');
    checked(moon.clientProgramInstalledManagedRunCheck(value, prepared, request));
    current();
    const prior = effectRuns.get(prepared)?.deref();
    if ((prior !== undefined && prior !== run) || run.prepared !== prepared || run.request !== request ||
        run.value !== value || run.closed || Object.hasOwn(run, 'failure')) fail('ForeignInstalledSourcePreparation');
    effectRuns.set(prepared, new WeakRef(run));
  }
  function prepareManagedMockModelRun(prepared: object, request: unknown, control: Control, plan: Plan,
    selection: Selection, publicationCapacity: () => unknown) {
    current();
    let record = records.get(prepared);
    if (record !== undefined) {
      if (record.failure !== undefined) throw record.failure;
      if (!record.requestOwned || record.request !== request || record.model?.compiled !== plan.compiled ||
          record.model?.runDefinition !== plan.runDefinition || record.model?.graph !== selection.graph ||
          record.model?.control !== control || record.model.closed) fail('ForeignInstalledModelPreparation');
      sameRun(prepared);
      return record.value;
    }
    if (typeof prepareRequestModel !== 'function') fail('InstalledMockModelOperationalAdmissionUnavailable');
    if (records.size === 4096) fail('InstalledMockRunLimit');
    const model: Model = {control, compiled: plan.compiled, runDefinition: plan.runDefinition,
      graph: selection.graph, occurrence: selection.occurrence, selection, component: undefined,
      queryTimePreparation: plan.queryTimePreparation,
      scope: undefined, publicationCapacity, releaseAliases() {
        if (this !== model) fail('ForeignInstalledModelPreparation');
        if (record!.aliasesReleased) return;
        if (model.scope !== undefined && model.scopeFinished !== true || model.read !== undefined ||
            record!.reads!.some(read => read !== undefined && !read.closed)) fail('InstalledMockModelCleanupPending');
        records.delete(record!.prepared!);
        for (const key of Object.keys(model)) model[key as keyof Model] = undefined;
        model.closed = true;
        record!.prepared = record!.request = record!.original = record!.value = record!.model = record!.managed = record!.failure = undefined;
        record!.reads!.length = 0; record!.aliasesReleased = true; record!.retired = true;
      }};
    record = {prepared, request, model, requestOwned: true, effectful: false, original: undefined,
      value: undefined, reads: [], failure: undefined};
    records.set(prepared, record);
    try {
      // The original Host owns module/Scope/partial failure on this Request.
      // Local retains this SAME model carrier before either can be issued.
      const run: HostRun = Reflect.apply(prepareRequestModel, undefined, [prepared, request, model]);
      // The mutable Host record owns the real Run and cuts its heavyweight
      // fields at retirement. Do not copy its opaque Run into another owner.
      record.managed = run;
      record.original = run.original; record.value = run.value; record.preparationFunded = true;
      sameRun(prepared);
      return record.value;
    } catch (cause) {record.failure = cause; throw cause;}
  }
  function modelPreparation(prepared: object, plan: Plan) {
    const run = sameRun(prepared), model = run.model as Model | undefined;
    if (model === undefined || model.compiled !== plan.compiled || model.runDefinition !== plan.runDefinition ||
        model.scope === undefined) fail('ForeignInstalledModelPreparation');
    const publicationCapacity = () => {
      sameRun(prepared);
      if (model.closed || typeof model.publicationCapacity !== 'function') fail('HostResultPublicationUnavailable');
      return model.publicationCapacity();
    };
    const managed = run.managed, scope = model.scope, selection = model.selection,
      component = model.component, budget = model.budget, graph = model.graph,
      control = model.control, publication = model.publicationCapacity;
    const publicationCurrent = () => {
      if (managed !== undefined && Object.hasOwn(managed, 'failure')) throw managed.failure;
      if (closing || run.retired || model.closed || model.scopeFinished || !run.requestOwned ||
          run.model !== model || run.managed !== managed || managed === undefined || managed.closed ||
          managed.retiringModel || managed.retiringContent || managed.model !== model || managed.runtime !== moon ||
          managed.prepared !== prepared || managed.request !== run.request || managed.value !== run.value ||
          run.value === undefined || model.compiled !== plan.compiled || model.runDefinition !== plan.runDefinition ||
          model.scope !== scope || model.control !== control || model.publicationCapacity !== publication ||
          model.selection !== selection || selection?.graph !== graph ||
          model.graph !== graph || model.component !== component || model.budget !== budget) {
        fail('ForeignInstalledModelPreparation');
      }
    };
    return Object.freeze({control: model.control, compiled: model.compiled, selection: model.selection,
      component: model.component, managedPublication: managed,
      assertRuntimeCurrent() {
        // Closed/failed originals refuse before retained installation hooks.
        publicationCurrent();
        if (sameRun(prepared) !== run) fail('ForeignInstalledModelPreparation');
        publicationCurrent();
      },
      runDefinition: model.runDefinition, scope: model.scope, publicationCapacity,
      readRetainedBytes: model.budget!.readRetainedBytes, readExecutionBytes: model.budget!.readExecutionBytes,
      modelRetainedBytes: model.budget!.modelRetainedBytes, modelExecutionBytes: model.budget!.modelExecutionBytes,
      prepareAcquiredLedger(capacities: readonly AcquireCapacity[], registry: unknown, values: string, fragment?: string, ordered?: string) {
        sameRun(prepared);
        if (!run.requestOwned || model.closed || model.scopeFinished || model.taken || model.readAttempted ||
            !Array.isArray(capacities) || capacities.length !== moon.clientProgramAcquisitionCount(prepared) ||
            capacities.length < 1 || capacities.length > 2 ||
            capacities.some(value => value?.managedRun !== run.value)) fail('InvalidInstalledMockModelPreparation');
        if (model.sourceLedgerAttempted) {
          if (Object.hasOwn(model, 'sourceLedgerFailure')) throw model.sourceLedgerFailure;
          fail('InstalledModelSourceLedgerAlreadyBorrowed');
        }
        const original = run.value, request = run.request;
        model.sourceLedgerAttempted = true;
        try {
          const whole = capacities.some(value => value.wholeInput === true);
          if (whole && (capacities.some(value => value.wholeInput !== true) ||
              typeof moon.clientProgramInstalledManagedWholeSourcesLedger !== 'function')) {
            fail('InvalidInstalledMockModelPreparation');
          }
          const ledger = checked(whole
            ? moon.clientProgramInstalledManagedWholeSourcesLedger!(original, prepared, request,
              capacities.map(value => value.capacity), capacities.map(value => value.transferBytes),
              capacities.map(value => value.executionBytes))
            : moon.clientProgramInstalledManagedRunPrepareLedger(original,
              prepared, request, capacities.map(value => value.capacity),
              capacities.map(value => value.transferBytes), capacities.map(value => value.executionBytes),
              registry, values, fragment, ordered));
          if (sameRun(prepared) !== run || run.model !== model || run.value !== original ||
              run.request !== request || model.closed || model.scopeFinished) fail('ForeignInstalledModelPreparation');
          model.sourceLedger = ledger;
          return ledger;
        } catch (cause) {model.sourceLedgerFailure = cause; throw cause;}
      },
      retain() {
        if (model.closed || model.taken || model.readAttempted) fail('ForeignInstalledModelPreparation');
        model.taken = true;
      },
      openSourceFreeHost(registry: unknown, values: string, fragment: string | undefined, ordered: string | undefined, providers: unknown) {
        sameRun(prepared);
        if (run.effectful || run.retired || model.closed || !model.taken || model.hostAttempted ||
            moon.clientProgramAcquisitionCount(prepared) !== 0) {
          fail('ForeignInstalledModelPreparation');
        }
        // The checked Source-free driver and Model component borrow this
        // original Run Ledger. No captured Source or second parent is made.
        model.hostAttempted = true;
        return checked(moon.clientProgramOpenInstalledManagedSourceFreeComposedInferHost(
          run.value, prepared, run.request, registry, values, fragment, ordered, providers));
      },
      ...(moon.clientProgramAcquisitionCount(prepared) === 0 ? {} : {openCapturedHost(captures: readonly SavedCapture[]) {
        sameRun(prepared);
        if (!run.requestOwned || run.effectful || run.retired || model.closed || !model.taken ||
            model.hostAttempted || !Array.isArray(captures) || captures.length !== 2 ||
            moon.clientProgramAcquisitionCount(prepared) !== captures.length ||
            typeof model.component?.bindOriginal !== 'function') fail('InstalledComposedInferHostUnavailable');
        model.hostAttempted = true;
        return checked(moon.clientProgramOpenInstalledManagedCaptureHost(run.value, prepared, run.request,
          captures.map(value => value.capture.source())));
      }}),
      prepareRead() {
        // The Scope predates all Sources. Its descriptor/read snapshots the
        // same Ledger only when Local hands the actual prefix inputs to the
        // Model component: earlier Source/Compute mutations must not make a
        // previously issued claim stale, nor may they reset a spent claim.
        if (model.closed) fail('ForeignInstalledModelPreparation');
        if (model.readAttempted && model.readFailure !== undefined) throw model.readFailure;
        if (!model.taken || model.readAttempted) fail('ForeignInstalledModelPreparation');
        model.readAttempted = true;
        try {
          sameRun(prepared);
          model.read = model.control!.prepareCheckedClientInferOriginalRead(model.compiled,
            model.runDefinition, model.graph, model.scope, model.budget!);
          return Object.freeze({control: model.control, compiled: model.compiled,
            runDefinition: model.runDefinition, scope: model.scope, read: model.read, publicationCapacity,
            readRetainedBytes: model.budget!.readRetainedBytes, readExecutionBytes: model.budget!.readExecutionBytes,
            modelRetainedBytes: model.budget!.modelRetainedBytes, modelExecutionBytes: model.budget!.modelExecutionBytes});
        } catch (error) {model.readFailure = error; throw error;}
      },
      async retire() {
        if (model.closed || run.retired) return true;
        // Source capture can still be borrowed by the Local DAG. Its own
        // retirement/FD checks, not Model completion, decide when each read
        // is closed. The same scope then checks the whole original census.
        for (const read of run.reads!) await closeRead(read);
        retireModelRead(model);
        if (model.control!.finishCheckedClientInferOriginalReadScope(model.compiled,
          model.runDefinition, model.graph, model.scope, true) !== true) return false;
        model.scopeFinished = true;
        if (run.requestOwned) {
          // Physical child/Scope cleanup is complete. Existing Host registry
          // retirement still owns payload severing, borrows and parent stop.
          model.closed = true;
          return true;
        }
        retireRunRecord(run);
        return true;
      }});
  }
  function retireModelRead(model: Model) {
    if (model.read === undefined) return;
    retireNodeInferOriginalRead(model as Parameters<typeof retireNodeInferOriginalRead>[0]);
    model.read = undefined;
  }
  function retireRunRecord(record: HostRun) {
    if (record.retired) return;
    if (record.requestOwned) {
      if (!(record.model as Model | undefined)?.closed) fail('InstalledMockModelCleanupPending');
      return;
    }
    if (record.value !== undefined) checked(moon.clientProgramInstalledManagedRunRetire(record.value));
    else if (record.admission !== undefined) checked(moon.clientProgramNodeManagedRunCleanup(record.admission));
    record.retired = true;
  }
  // Called only by the same Host Run after its native retirement succeeds (or
  // the existing payload-sever witness confirms it). This releases aliases,
  // never a physical child, native read or consumed occurrence. The separate
  // physical-close ACK for every original child must already be retained.
  function releaseEffectSourceAliases(this: Run, prepared: object, request: unknown) {
    const run = this, direct = run.mockSourceReads;
    const reads = [...(direct ?? []), ...(run.mockKeyedReads ?? [])];
    if (effectRuns.get(prepared)?.deref() !== run || run.prepared !== prepared ||
        run.request !== request || run.closed ||
        run.releaseMockSourceAliases !== releaseEffectSourceAliases || !Array.isArray(direct)) {
      fail('InstalledSourcePreparationMismatch');
    }
    // Check the whole same-Run inventory before cutting any sibling's document
    // correspondence. Pending/failed close keeps every original for its retry.
    for (const read of reads) if (read !== undefined) {
      if (!read.physicalClosed || !read.closed && !effectReads.has(read) && !keyedReads.has(read) ||
          read.value !== undefined && originalReads.get(read.value)?.run !== run) {
        fail('InstalledMockSourceCleanupPending');
      }
    }
    for (const read of reads) if (read !== undefined) {
      if (read.value !== undefined) originalReads.delete(read.value);
      effectReads.delete(read); keyedReads.delete(read);
      read.raw = read.close = read.bytes = read.observedBytes = read.document = read.projections = read.value = undefined;
      read.closed = true;
    }
    effectRuns.delete(prepared);
    run.mockSourceReads = run.mockKeyedReads = run.releaseMockSourceAliases = undefined;
  }
  async function closeSource(index: number) {
    for (const read of keyedReads) if (read.source === index) {
      await closeRead(read); keyedReads.delete(read);
    }
    for (const read of effectReads) if (read.source === index) {
      await closeRead(read);
      effectReads.delete(read);
    }
    for (const record of records.values()) {
      for (const read of record.reads!) if (read?.source === index) await closeRead(read);
    }
  }
  async function closeRead(read: Read | undefined) {
    if (read === undefined || read.closed) return;
    // A completed Promise or logical retirement cannot acknowledge the
    // physical child. Preserve this read and every projection until its ACK.
    await closePhysicalRead(read);
    if (read.value !== undefined) checked((read.keyed
      ? moon.clientProgramInstalledKeyedSourceReadRetire : moon.clientProgramInstalledSourceReadRetire)(read.value));
    read.closed = true;
    read.raw = read.close = read.bytes = read.observedBytes = read.document = read.projections = undefined;
  }
  async function closePhysicalRead(read: Read) {
    if (read.physicalClosed) return;
    const observed = await Reflect.apply(read.close!, read.raw, []);
    const pending = observed !== null && typeof observed === 'object'
      ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
    if (!pending || !Object.hasOwn(pending, 'value') || pending.value !== false) {
      fail('InstalledMockSourceCleanupPending');
    }
    read.physicalClosed = true;
  }
  const close = async () => {
    closing = true;
    const failures = [];
    for (const source of sources) {
      if (closedSources.has(source)) continue;
      try {await source.close(); closedSources.add(source);} catch (error) {failures.push(error);}
    }
    if (failures.length === 0) for (const record of records.values()) {
      try {
        if (record.requestOwned) {
          const model = record.model!;
          if (model.taken && !model.closed) fail('InstalledMockModelCleanupPending');
          retireModelRead(model);
          if (model.scope !== undefined && model.scopeFinished !== true) {
            if (model.control!.finishCheckedClientInferOriginalReadScope(model.compiled,
              model.runDefinition, model.graph, model.scope, true) !== true) fail('InstalledMockModelCleanupPending');
            model.scopeFinished = true;
          }
          model.closed = true;
        }
        if (record.model?.read !== undefined) {
          // A handed-off component owns its real cleanup. Host close cannot
          // acknowledge it just because both Source FileHandles have closed.
          if (record.model.taken) fail('InstalledMockModelCleanupPending');
          retireModelRead(record.model);
        }
        retireRunRecord(record);
      } catch (error) {failures.push(error);}
    }
    if (failures.length) throw new AggregateError(failures, 'InstalledMockSourceCleanupPending');
    // Retire only our managed references, after every original Source close
    // and the same Run's cleanup have succeeded. A failed sibling or Model
    // cleanup retains this whole record for its original retry; clearing it
    // is not an FD/native acknowledgement or a promise about GC/RSS.
    for (const record of records.values()) {
      // The same Host Run continuation cuts Request-owned aliases only after
      // its actual Core payload-sever witness; close is not that witness.
      if (record.requestOwned) continue;
      if (record.model !== undefined) {
        const model = record.model;
        model.closed = true;
        model.control = model.compiled = model.compilation = model.runDefinition = model.graph = undefined;
        model.publicationCapacity = undefined;
        model.occurrence = model.scope = model.budget = model.readFailure = undefined;
      }
      record.prepared = record.request = record.original = record.admission = record.value = undefined;
      record.model = record.failure = undefined;
      record.reads!.length = 0;
    }
    records.clear();
  };
  try {
    for (const [index, original] of bundle.sources.entries()) {
      current();
      const entry = original.catalogue, declaration = original.declaration;
      const preparedSource = original.sourcePrepared;
      if (typeof original.sourceMember?.load !== 'function' ||
          preparedSource?.declaration !== declaration || preparedSource!.wire !== original.wire) {
        fail('InstalledSourceInitializationUnavailable');
      }
      const {declared, environment} = preparedSource as unknown as Readonly<{declared: Declared; environment: Readonly<{wire: string}>}>;
      const authorization = await authorizationFor(entry.connection);
      current();
      const preparedReads = new WeakMap<object, HostRun>();
      const knownResources = new Map<string, {binding: FileBinding; identity: string}>();
      const referenceIssuer = original.fileBindings.length === 0 ? undefined
        : moon.clientProgramResourceReferenceIssuer((kind, wire) => kind === 'file' && knownResources.has(wire),
          () => {try {current(); return true;} catch {return false;}});
      async function readOriginal(options: ReadOptions) {
        const originalRead = options.rowRun.originalRead ?? options.rowRun.originalKeyedRead;
        const held = originalReads.get(originalRead!);
        if (held === undefined) fail('InstalledSourcePreparationMismatch');
        const run = sameRun(held.run.prepared), read = held.read;
        if (run !== held.run || read.source !== index || read.value !== originalRead || read.closed) {
          fail('InstalledSourcePreparationMismatch');
        }
        options.signal?.throwIfAborted(); await options.verifyRead();
        options.signal?.throwIfAborted(); sameRun(run.prepared);
        const bytes: Buffer = await Reflect.apply(read.bytes!, read.raw, []);
        options.signal?.throwIfAborted(); sameRun(run.prepared);
        await options.verifyRead(); options.signal?.throwIfAborted(); sameRun(run.prepared);
        const siblings = [...(run.mockSourceReads ?? run.reads!), ...(run.mockKeyedReads ?? [])];
        for (const sibling of siblings) if (sibling?.observedBytes !== undefined &&
            !bytes.equals(sibling.observedBytes)) fail('InstalledMockSourceChanged');
        read.observedBytes = bytes;
        return bytes;
      }
      function projectOriginal(physical: Physical, bytes: Uint8Array, options: ReadOptions) {
        const held = originalReads.get((options.rowRun.originalRead ?? options.rowRun.originalKeyedRead)!);
        if (held === undefined || held.read.source !== index || held.read.observedBytes !== bytes ||
            held.read.document !== undefined || held.read.closed) fail('InstalledSourcePreparationMismatch');
        sameRun(held.run.prepared);
        const document = checked(moon.clientProgramRelationAdmitDocument(bytes, 1048576, 4096, 32, 100, 16777216));
        // Retain the SAME raw backing and every bounded projection under the
        // managed read before another projection/current check can refuse.
        held.read.document = document;
        const projections = held.read.projections = new Map<Physical, unknown>();
        for (const source of bundle.sources) for (const model of source.physical) {
          projections.set(model, checked(moon.clientProgramRelationProjectTargetDocument(document,
            model.declaration, model.resource, model.itemsPath, model.keyPath,
            typeof model.primaryIdentity === 'string' ? model.primaryIdentity : undefined,
            model.preparedKey, model.writableFields)));
        }
        sameRun(held.run.prepared);
        const selected = projections.get(physical);
        if (selected === undefined) fail('InstalledMockPhysicalBindingUnavailable');
        return selected;
      }
      const fileSuppliers = new Map(original.fileBindings.map(binding => {
        const physical = original.physical.find(value => value.resource === binding.data_resource);
        const contentView = declared.views.find(view => view.resource === binding.content_resource);
        const matches = moon.clientProgramRowSourceFileReadProfileMatches;
        if (physical === undefined || typeof physical.primaryIdentity !== 'string' ||
            contentView === undefined || typeof matches !== 'function' ||
            Reflect.apply(matches, moon, [declaration, contentView.source_ref,
              physical.declaration, physical.resource, binding.identity_field,
              binding.name_field, binding.version_field, binding.media_type_field,
              binding.content_utf8_field, binding.path_field,
              physical.itemsPath, physical.keyPath]) !== true) {
          fail('InstalledMockPhysicalBindingUnavailable');
        }
        const supplier = createFixtureFileSupplier<RowRun>({moon,
          physical: physical as Physical & Readonly<{primaryIdentity: string}>,
          fields: {identity: binding.identity_field, name: binding.name_field, version: binding.version_field,
            mediaType: binding.media_type_field, contentUtf8: binding.content_utf8_field,
            ...(binding.path_field === undefined ? {} : {path: binding.path_field})},
          limits: {maxBytes: 1048576, maxNodes: 4096, maxDepth: 32, maxRows: 100,
            maxWork: 16777216, maxPageBytes: 1048576, maxContentBytes: 1048576},
          assertCurrent: current, readOriginalBytes: readOriginal,
          projectOriginalDocument: (bytes, options) => projectOriginal(physical, bytes, options),
          issueResource(identity) {
            current();
            const resource = Object.freeze({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
              provider_namespace: entry.provider, resource_kind: 'file', provider_identity_cid: original.scopeCid,
              authority_scope_cid: authorization.context.contextCid, boundary_cid: original.scopeCid,
              identity_cid: exactCid({scope: original.scopeCid, collection: binding.data_resource, identity})});
            const key = canonical(resource);
            if (!knownResources.has(key) && knownResources.size >= 100) fail('InstalledMockResourceInventoryLimit');
            knownResources.set(key, {binding, identity}); return resource;
          },
          resolveResource(resource) {
            current(); const held = knownResources.get(canonical(resource));
            return held?.binding === binding ? held.identity : undefined;
          }});
        return [binding, supplier] as const;
      }));
      const adapter = await original.sourceMember.load({moon, declaration, declared,
        environmentWire: environment.wire, connectorId: entry.connectorId,
        connectorRegistration: entry.registration, connectorRevision: entry.revision,
        bindingCid: contentCid({connection: entry.connection, dataPath: bundle.dataPath,
          declaration: original.wire}), authorization, readOperation: 'read',
        site: Object.freeze({connection: entry.connection,
          async close() {await closeSource(index); knownResources.clear();},
          issueReadGrant({operation, decision, resource, runInvocationCid, dispatchRequestCid, maxUses}: GrantOptions) {
            current();
            if (operation !== 'read' || !declared.views.some(view => view.resource === resource) ||
                !/^sha256:[0-9a-f]{64}$/u.test(runInvocationCid) ||
                !/^sha256:[0-9a-f]{64}$/u.test(dispatchRequestCid) || maxUses !== 1 ||
                decision?.action !== 'dispatch' || decision.boundary !== 'acquisition' ||
                decision.tuple?.connection !== entry.connection || decision.tuple?.resource !== resource ||
                decision.tuple?.operation !== 'read' || decision.contextCid !== authorization.context.contextCid ||
                typeof authorization.assertAccountCurrent !== 'function') fail('InstalledMockReadNotAuthorized');
            Reflect.apply(authorization.assertAccountCurrent, authorization, [decision]); current();
            return Object.freeze({runInvocationCid, dispatchRequestCid});
          }}),
        physicalTarget: (resource: string, fields: readonly string[]) => ({connection: entry.connection,
          resource, fields: [...fields], dataPath: bundle.dataPath}),
        readAsset, referenceIssuer,
        limits: {maxPages: 1, maxPageBytes: 1048576, maxPageRows: 100, maxCaptureRows: 100},
        // Match the existing RowRun page decoder's depth envelope. A wider
        // requested limit is rejected before even the original Mock read.
        originalPageLimits: {maxNodes: 4096, maxDepth: 32},
        prepareSourceRead({checkedOwner, effectful, declaration: selected, occurrence, managedRun, originalRead}: ReadPreparation) {
          const run = sameRun(checkedOwner);
          if (run.closed || run.retiringMockSources) fail('InstalledMockSourceCleanupPending');
          const count = effectful ? moon.clientProgramEffectAcquisitionCount(checkedOwner)
            : moon.clientProgramAcquisitionCount(checkedOwner);
          const shared = effectRuns.get(checkedOwner)?.deref() === run;
          const planned = shared || run.requestOwned;
          const reads = shared ? run.mockSourceReads ??= [] : run.reads!;
          if (effectful !== (run.preparationKind === 'effect-plan' || run.effectful === true) || selected !== declaration ||
              !(['stage', 'input', 'task'] as const).every(name => Number.isSafeInteger(occurrence[name]) && occurrence[name] >= 0) ||
              reads.length >= count || reads.some(read => read !== undefined &&
                (['stage', 'input', 'task'] as const).every(name => read.occurrence![name] === occurrence[name])) ||
              planned && (managedRun !== run.value || originalRead === undefined)) fail('InstalledSourcePreparationMismatch');
          if (shared) {
            if (run.releaseMockSourceAliases !== undefined &&
                run.releaseMockSourceAliases !== releaseEffectSourceAliases) fail('InstalledSourcePreparationMismatch');
            run.releaseMockSourceAliases = releaseEffectSourceAliases;
          }
          const raw = sourceManaged.prepareRead(checkedOwner, declaration,
            shared || run.requestOwned ? run.value : run.original, occurrence);
          const read: Read = {raw, source: index, occurrence: Object.freeze({...occurrence}),
            close: undefined, bytes: undefined, value: undefined, closed: false};
          reads.push(read);
          if (shared) effectReads.add(read);
          read.close = Object.getOwnPropertyDescriptor(raw, 'close')?.value;
          read.bytes = Object.getOwnPropertyDescriptor(raw, 'readOriginalBytes')?.value;
          if (typeof read.close !== 'function' || typeof read.bytes !== 'function') {
            fail('InstalledMockSourceUnavailable');
          }
          sourceManaged.assertCurrent();
          read.value = planned ? originalRead : checked(moon.clientProgramInstalledManagedRunSourceReadAt(
            run.value, occurrence.stage, occurrence.input, occurrence.task)) as object;
          originalReads.set(read.value!, {run, read});
          return read.value;
        },
        async closeSourceRead(value: object) {
          const held = originalReads.get(value);
          if (held === undefined || held.read.source !== index) fail('InstalledSourcePreparationMismatch');
          // Close the physical/raw child before Row completion. Core capture
          // and the same native read keep their separate retirement duties.
          await closePhysicalRead(held.read);
          return Object.freeze({pending: false});
        },
        prepareKeyedSourceRead({checkedOwner, keyedAcquisition, request, declaration: selected, managedRun, originalRead, rowLimits}: KeyedPreparation) {
          const run = sameRun(checkedOwner);
          if (selected !== declaration || run.closed || run.retiringMockSources ||
              managedRun !== undefined && managedRun !== run.value ||
              typeof sourceManaged.prepareKeyedRead !== 'function') fail('InstalledSourcePreparationMismatch');
          const reads = run.mockKeyedReads ??= [];
          if (reads.some(read => read.request === request)) fail('InstalledSourcePreparationMismatch');
          const raw = sourceManaged.prepareKeyedRead(checkedOwner, declaration, run.value, request);
          const read: Read = {raw, source: index, request, keyed: true, close: undefined, bytes: undefined,
            value: undefined, closed: false};
          reads.push(read); keyedReads.add(read);
          read.close = Object.getOwnPropertyDescriptor(raw, 'close')?.value;
          read.bytes = Object.getOwnPropertyDescriptor(raw, 'readOriginalBytes')?.value;
          if (typeof read.close !== 'function' || typeof read.bytes !== 'function') fail('InstalledMockSourceUnavailable');
          sameRun(checkedOwner);
          read.value = originalRead ?? checked(run.preparationKind === 'effect-plan'
            ? (run.model === undefined
              ? moon.clientProgramInstalledManagedEffectKeyedSourceRead
              : moon.clientProgramInstalledManagedModelKeyedSourceRead)(run.value,
              keyedAcquisition, request, declaration,
              rowLimits.maxPageBytes, rowLimits.maxTextBytes, rowLimits.maxWork)
            : moon.clientProgramInstalledManagedKeyedSourceRead(run.value, keyedAcquisition, request, declaration)) as object;
          originalReads.set(read.value!, {run, read}); return read.value;
        },
        async closeKeyedSourceRead(value: object) {
          const held = originalReads.get(value);
          if (held === undefined || held.read.source !== index || !held.read.keyed) fail('InstalledSourcePreparationMismatch');
          await closePhysicalRead(held.read);
          return Object.freeze({pending: false});
        },
        async readPages(options: Pages) {
          const {resource, rowRun, chargePage} = options;
          const fileBinding = original.fileBindings.find(binding =>
            binding.listing_resource === resource || binding.content_resource === resource);
          if (fileBinding !== undefined) {
            const supplier = fileSuppliers.get(fileBinding)!;
            return resource === fileBinding.listing_resource
              ? supplier.readListing(options as ListingPage)
              : supplier.readContent(options as ContentPage);
          }
          const bytes = await readOriginal(options);
          const charge = chargePage(bytes);
          const physical = original.physical.find(value => value.resource === resource);
          if (physical === undefined || physical.declaration !== declaration) fail('InstalledMockPhysicalBindingUnavailable');
          const selected = projectOriginal(physical, bytes, options);
          checked(rowRun.inputKind === 'whole-input'
            ? moon.clientProgramRelationAcceptChargedInputDocument(rowRun.run, charge,
              rowRun.acquisition, selected, 16777216)
            : moon.clientProgramRelationAcceptChargedDocument(rowRun.run, charge,
              rowRun.acquisition, selected, 16777216));
          current();
        }}) as SourceAdapter;
      const queryAliases = Object.freeze(entry.queryAliases.map(alias => {
        const view = declared.views.find(view => view.resource === alias.resource);
        if (view === undefined) fail('InstalledMockCatalogueUnavailable');
        return Object.freeze({name: alias.name, sourceRef: view.source_ref,
          sourceViewContractCid: view.view_cid,
          schemaContractCid: view.carrier_schema_cid,
          ...(Object.hasOwn(alias, 'request') ? {request: alias.request} : {})});
      }));
      sources.push(Object.freeze({...adapter, queryAliases,
        ...(original.fileBindings.length === 0 ? {} : {requiresRunContentCapture: true}),
        async prepare(facts: SourceFacts) {
          const owner = facts.preparedEffect ?? facts.preparedProgram;
          if (facts.preparedEffect !== undefined) {
            if (typeof effectManagedRun !== 'function') fail('InstalledEffectPlanUnavailable');
            const selected = effectManagedRun(owner!, facts.requestIdentity);
            if (selected.value !== facts.managedRun) fail('ForeignInstalledModelPreparation');
            effectRuns.set(owner!, new WeakRef(selected));
          }
          const run = sameRun(owner);
          // The SAME adopted Plan retains its original Query/acquisition.
          // Let the existing Core borrower select it instead of preparing a
          // second requirement from the physical source description.
          const forwarded = run.requestOwned || effectRuns.get(owner!)?.deref() === run ? Object.freeze({...facts,
            managedRun: run.value, requestIdentity: run.request}) : facts;
          const prepared = await adapter.prepare(forwarded);
          if (sameRun(owner) !== run) fail('ForeignInstalledModelPreparation');
          preparedReads.set(prepared, run);
          return prepared;
        },
        ledgerCapacity(prepared: object) {
          const run = preparedReads.get(prepared);
          if (run === undefined || run !== sameRun(run.prepared)) fail('InstalledSourcePreparationMismatch');
          return Object.freeze({...adapter.ledgerCapacity(prepared), managedRun: run.value});
        }}));
    }
    let environmentOriginal: ReturnType<typeof composeInstalledSourceEnvironment> | undefined;
    for (const source of sources) environmentOriginal = composeInstalledSourceEnvironment(installationServices, moon,
      baseEnvironmentWire, environmentOriginal, source.environmentWire);
    const environmentWire = environmentOriginal!.wire;
    current();
    return Object.freeze({realizationKey: mockRealization, environmentWire, environmentOriginal,
      fileReadDeclarations: bundle.catalog.fileReadDeclarations,
      sources: Object.freeze(sources),
      connectorBindings: Object.freeze(sources.flatMap(source => source.connectorBindings)),
      queryAliases: Object.freeze(sources.flatMap(source => source.queryAliases)),
      admitsSource: (ref: string) => sources.some(source => source.admitsSource(ref)),
      prepareManagedRun, bindManagedSerializationReadRun, prepareManagedMockModelRun, modelPreparation, close});
  } catch (error) {
    throw await retainInstalledHostInitializationFailure(error,
      {sourceProfile: {close}});
  }
}

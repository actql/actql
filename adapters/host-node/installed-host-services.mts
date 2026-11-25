import {createAccountConstruction} from './account-construction.mjs';
import {composeInstalledSourceEnvironment, releaseRetiredInstalledEnvironmentComposition, bindInstalledEnvironmentConstruction,
  assertInstalledEnvironmentPublicationOriginal} from './installed-funded-environment.mjs';
// Standard installed Host service owner. This public cut retains the exact
// original Source implementation/Site association; numerical DATA is neither
// a Run admission nor permission. Other service facets extend this SAME owner.
import {openInstalledRowSite, installedRowCredentialOperationSite, rowSourceCheckEnvironment,
  rowSourceMapping, createInstalledRowSource, installRowSourceAuthorization}
  from './installed-row-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {createInstalledRowEffect, resolveInstalledRowEffectConstruction} from './installed-row-effect.mjs';
import {createInstalledTableSource, installedTableReadSite} from './installed-table-source.mjs';
import {createInstalledTableEffect} from './installed-table-effect.mjs';
import {installDuckDBSourceProfile, createInstalledDuckDBSource} from './installed-duckdb-source.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {captureConfigurationReaders} from './source-profile-json.mjs';
import {runtimeField, runtimeTag, runtimeIsBoxedSome, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {createInstalledCredentialSourceReader, installedJsonSourceReaderLimitNames,
  installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {types as nodeTypes} from 'node:util';
import {createInstalledSourcePhysicalConstruction} from './installed-source-physical-construction.mjs';
import {createInstalledSourceMaterialAccounting} from './installed-source-material-accounting.mjs';
import {createInstalledSourceContextCustody, captureInstalledSourceServices} from './installed-source-context-custody.mjs';
import {createInstalledSourceContextFactory} from './installed-source-context-construction.mjs';
import type {RowSourceMappingRuntime} from './installed-row-source-mapping.mjs';
import type {installRowSourceAuthorization as installAuthorization} from './installed-row-source-authorization.mjs';

type Accounting = ReturnType<typeof createInstalledSourceMaterialAccounting>;
type Material = NonNullable<ReturnType<Accounting['sourceMaterial']>>;
type Physical = ReturnType<typeof createInstalledSourcePhysicalConstruction<HostOriginal, Material>>;
type ContextFactory = ReturnType<typeof createInstalledSourceContextFactory>;
type Context = ReturnType<ContextFactory>;
type ContextPorts = Parameters<typeof createInstalledSourceContextFactory>[0];
type CustodyPorts = Parameters<typeof createInstalledSourceContextCustody>[0];
type ContextRecord = NonNullable<ReturnType<ContextPorts['sourceContexts']['get']>>;
type ContextScope = ContextRecord['scope'];
type Holdings = Parameters<typeof retainInstalledHostInitializationFailure>[1];
type CoreMethod = (...args: unknown[]) => unknown;
type AccountOptions = Parameters<typeof createAccountConstruction>[0];
type DuckDBOptions = Parameters<typeof createInstalledDuckDBSource>;
type Runtime = ContextRecord['original']['moon'] & AccountOptions['moon'] &
  DuckDBOptions[1] & NonNullable<Parameters<typeof installDuckDBSourceProfile>[1]['runtime']> &
  Readonly<Record<string, unknown>> & RowSourceMappingRuntime & {
    clientProgramRowSourceDeclarationJson: CoreMethod;
    clientProgramRowSourceUpdateMappingConstructionCapacity?: CoreMethod;
    clientProgramPrepareInstalledAccountRead(capacity: unknown, input: unknown): ReturnType<AccountOptions['prepareRead']>;
  };
type CredentialLimits = Readonly<{maxBindings: number; maxSecretBytes: number}>;
type HostScope = ContextScope & {
  reader?: Holdings['sourceReader']; readerDemand?: unknown;
  credentialSelecting?: boolean; credentialLimits?: CredentialLimits;
};
type HostOriginal = Omit<ContextRecord['original'], 'moon'> & {
  moon: Runtime; root: string; principalId: string; selected: WeakMap<object, string>;
  siteInstallations: WeakMap<object, object>; accountCurrent?: () => undefined;
  accountConstruction?: ReturnType<typeof createAccountConstruction>;
  admitAcquisitionContracts?: unknown; acquisitionContractsCapacity?: unknown;
  sites: WeakMap<object, EffectSelection | undefined>; implementations: WeakMap<object, EffectSelection>;
  sourceImplementations: WeakMap<object, ImplementationSelection>; sourceProfiles: WeakMap<object, ProfileSelection>;
};
type EffectSelection = {constructing?: boolean; sealed?: boolean};
type Bound = {
  site?: Holdings['sourceProfile']; authorization?: Holdings['authorization']; reader?: Holdings['sourceReader'];
  adapter?: Holdings['sourceProfile'] & Readonly<{tableReadTargets?: Awaited<ReturnType<typeof createInstalledTableSource>>['tableReadTargets']}>; bridge?: unknown;
  constructing: boolean; attempted: boolean; siteAttempted?: boolean; failed?: boolean; closed?: boolean;
};
type SiteSelection = Readonly<{site: NonNullable<Bound['site']>; authorization: NonNullable<Bound['authorization']>}>;
type ProfileLimits = Readonly<Record<string, number>>;
type ReaderLimits = Readonly<Record<typeof installedJsonSourceReaderLimitNames[number] | 'maxSecretBytes', number>>;
type ProfileSelection = Readonly<{runtimeBundleCid: string; metadata: number; origin: number; value: ProfileLimits}>;
type ReaderImplementation = Readonly<{capacity: unknown; limits: ReaderLimits; runAcquisitionLimits: CredentialLimits}>;
type RequestConstruction = Readonly<{capacity: unknown; maxRequestBytes: number}>;
type Sequence = Readonly<{children?: readonly object[]}>;
type SequenceConstruction = Readonly<{capacity: unknown; sequence?: Sequence; sequences?: Readonly<Record<string, Sequence>>;
  maxQueryBytes?: number; maxRequestBytes?: number}>;
type ImplementationSelection = Readonly<{
  value: ReaderImplementation; runtimeBundleCid: string; columns: number; requestConstruction?: RequestConstruction;
  readSequenceConstruction?: SequenceConstruction; preservingResponse: boolean; cursorProgress?: true | 'codec-identities';
}>;
type HostServices = Readonly<{
  sourceReaderImplementationProfile(options: unknown): ProfileLimits;
  sourceReaderImplementation(options: unknown): ReaderImplementation;
  createSourceReader(options: unknown): ReturnType<typeof createInstalledCredentialSourceReader>;
  openRowSite(options: unknown): Promise<SiteSelection>;
}>;
type HostServicesInput = Readonly<{
  root: unknown; principalId: unknown; moon: Runtime; assertCurrent: unknown;
  accountCurrent?: () => undefined; receiver?: unknown; initialPreparation?: unknown;
}>;
type RowFactory = (input: Readonly<Record<string, unknown>>) => Promise<NonNullable<Bound['adapter']>>;
type TableSourceInputs = Parameters<typeof createInstalledTableSource>[0];
type TableEffectInputs = Parameters<typeof createInstalledTableEffect>[0];
type TableSiteInputs = Parameters<typeof installedTableReadSite>[0];
type TableInput = Pick<TableSourceInputs, 'limits'> & Readonly<{
  targets: readonly Readonly<{resource: string; schemaWire: string; selector: Readonly<{schema_cid: string}>}>[];
}>;
type TableBridge = object & Readonly<{frameLimits?: Readonly<{maxBytes: number}>}>;
type BoundConstruction = Pick<Context,
  'prepareDeclaration' | 'prepareNativeDeclaration' | 'prepareNativeInput' | 'preparePublishedEnvironment' |
  'prepareAuthoredDeclaration' | 'prepareBorrowedDeclaration' | 'prepareMappings' | 'prepareNativeMappings' |
  'prepareDeclaredCommands' | 'prepareAuthoredCommands' | 'prepareDerivedDeclaredCommands' | 'prepareReadTarget' |
  'prepareReadTargetWithMappings' | 'prepareEffectDriverConstruction'> &
  Pick<HostServices, 'sourceReaderImplementationProfile' | 'sourceReaderImplementation' | 'openRowSite' | 'createSourceReader'> &
  Readonly<{
    configurationReader: ReturnType<typeof captureConfigurationReaders>;
    prepareProviderEffect(provider: object, mappings: unknown): ReturnType<Context['prepareProviderEffect']>;
    openSpecializedSite(options: unknown): Promise<SiteSelection>;
    createDuckDBSource(): ReturnType<typeof createInstalledDuckDBSource>;
    createTableSource(options: unknown): ReturnType<typeof createInstalledTableSource>;
    createTableEffect(options: unknown): ReturnType<typeof createInstalledTableEffect>;
    createRowSource(options: unknown): ReturnType<RowFactory>;
    createRowEffect(options: unknown): ReturnType<RowFactory>;
  }>;

const sourceNativeThen = Promise.prototype.then;
const installations = new WeakMap<object, HostOriginal>();
const sourceContexts = new WeakMap<object, Readonly<{original: HostOriginal; material: Material; scope: HostScope}>>();
const boundConstructions = new WeakMap<object, Bound>();
const fail: (code: string) => never = code => {throw Object.assign(new TypeError(code), {code});};

const {sourceMaterial, sourceCall, reserveSource, reconcileSource,
  retainSourceFailure, requireSynchronousSourceConstruction, sourceProjectionMethods, freezeSourceProjection,
  retainCompletedSourceNativeConstruction, prepareSourceNativeInput, reserveSourceJsonConstruction,
  retainCompletedSourceJson, prepareModelTaskInput, installedSourceConfigurationReader, withInstalledSourceLoading,
  installedSourceEnvironmentConstructionReader, reserveInstalledSourceEnvironment, reserveInstalledSourceRuntimeIdentity,
  completeInstalledSourceInitialization, borrowInstalledSourceInitialization, isInstalledSourceInitializationRetired,
  retireInstalledSourceInitialization} =
  createInstalledSourceMaterialAccounting({fail, sourceNativeThen, installations, bindInstalledEnvironmentConstruction,
    assertInstalledEnvironmentPublicationOriginal, releaseRetiredInstalledEnvironmentComposition});
export {installedSourceConfigurationReader, withInstalledSourceLoading, installedSourceEnvironmentConstructionReader,
  reserveInstalledSourceEnvironment, reserveInstalledSourceRuntimeIdentity, completeInstalledSourceInitialization,
  borrowInstalledSourceInitialization, isInstalledSourceInitializationRetired, retireInstalledSourceInitialization};

const {reserveInstalledTableConstruction, installedTableReaderConstruction,
  reserveInstalledDuckDBConstruction} = createInstalledSourcePhysicalConstruction<HostOriginal, Material>({fail, sourceCall, reserveSource});

const createInstalledSourceContext = createInstalledSourceContextFactory({fail, sourceContexts,
  composeInstalledSourceEnvironment, installedSourceConfigurationReader, reserveSource, reconcileSource,
  freezeSourceProjection, sourceProjectionMethods, requireSynchronousSourceConstruction,
  prepareSourceNativeInput, retainCompletedSourceNativeConstruction, rowSourceCheckEnvironment, rowSourceMapping});

const {requireSourceConstructor, beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization,
  retainBoundInstalledSourceFailure, assertInstalledSourceConstruction, readInstalledSourceAcquisitionContract,
  prepareInstalledSourceAcquisitionContracts, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
  finishInstalledSourceInitialization, retainInstalledHostServiceInstallation} =
  createInstalledSourceContextCustody<Context, HostOriginal>({fail, installations,
    sourceContexts: sourceContexts as CustodyPorts['sourceContexts'], boundConstructions, sourceMaterial,
    createInstalledSourceContext, retainInstalledHostInitializationFailure, reserveSource, reconcileSource,
    requireSynchronousSourceConstruction, retainSourceFailure, resolveInstalledRowEffectConstruction});
export {beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization,
  retainBoundInstalledSourceFailure, assertInstalledSourceConstruction, readInstalledSourceAcquisitionContract,
  prepareInstalledSourceAcquisitionContracts, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
  finishInstalledSourceInitialization, retainInstalledHostServiceInstallation, captureInstalledSourceServices};

// The ordinary loader owns this one bound factory. Connector code supplies
// domain inputs, never the initialization token or registration/retirement order.
// Keep partial acquisitions in the existing initialization failure carrier.
export function bindInstalledSourceConstruction(services: HostServices, context: Context,
  checkedProfile: unknown, profileConstruction: Parameters<Physical['reserveInstalledTableConstruction']>[3]): BoundConstruction {
  const retained = sourceContexts.get(context), original = installations.get(services)!;
  if (retained === undefined || retained.original !== original) fail('ForeignInstalledSourceConstruction');
  if (boundConstructions.has(context)) fail('InstalledSourceConstructionAlreadyBound');
  const {scope, material} = retained;
  const owned: Bound = {site: undefined, authorization: undefined, reader: undefined, adapter: undefined,
    constructing: false, attempted: false};
  boundConstructions.set(context, owned);
  const current = () => {
    if (!scope.active || material.phase !== 'working' || owned.failed || owned.closed) fail('InstalledSourceInitializationClosed');
    original.current();
    if (!scope.active || material.phase !== 'working' || owned.failed || owned.closed) fail('InstalledSourceInitializationClosed');
  };
  const domain = (options: unknown, reserved: readonly string[] = []): Readonly<Record<string, unknown>> => {
    if (options === null || typeof options !== 'object' || nodeTypes.isProxy(options)) fail('InvalidInstalledSourceConstruction');
    const fields = Object.getOwnPropertyDescriptors(options);
    for (const name of Reflect.ownKeys(fields)) {
      if (typeof name !== 'string' || !Object.hasOwn(fields[name], 'value') || reserved.includes(name)) {
        fail('InvalidInstalledSourceConstruction');
      }
    }
    return Object.fromEntries(Object.entries(fields).map(([name, field]) => [name, field.value]));
  };
  const identity = (options: unknown) => ({...domain(options, ['installation', 'sourceInitialization']),
    installation: scope.installation, sourceInitialization: context});
  const prepare = <Name extends keyof Context,>(name: Name) => (...args: Parameters<Context[Name]>) => {
    current();
    const value = Reflect.apply(context[name] as CoreMethod, context, args) as ReturnType<Context[Name]>;
    current();
    return value;
  };
  async function construct(options: unknown, role: ContextScope['role'], factory: RowFactory) {
    current();
    if (scope.role !== role || owned.attempted || owned.constructing || scope.prepared === undefined ||
        owned.site === undefined || owned.authorization === undefined ||
        scope.prepared.environment === undefined) fail('InstalledSourceConstructionUnavailable');
    const selected = domain(options, ['moon', 'sourceInitialization', 'declaration', 'declared', 'environment',
      'environmentWire', 'site', 'authorization', 'connectorId', 'connectorRegistration', 'connectorRevision']);
    const prepared = scope.prepared;
    const {projectSite, ...input} = selected;
    if (projectSite !== undefined && (typeof projectSite !== 'function' || nodeTypes.isProxy(projectSite) ||
        nodeTypes.isAsyncFunction(projectSite))) fail('InvalidInstalledSiteProjection');
    owned.attempted = true; owned.constructing = true;
    try {
      let site = owned.site;
      if (projectSite !== undefined) {
        // A grant projection changes domain method names, never physical
        // custody. Capture the owned Site's actual close before provider code.
        const originalSite = owned.site;
        const close = Object.getOwnPropertyDescriptor(originalSite, 'close');
        if (!close || !Object.hasOwn(close, 'value') || typeof close.value !== 'function') {
          fail('InvalidInstalledSiteProjection');
        }
        const projected = requireSynchronousSourceConstruction(material,
          Reflect.apply(projectSite, undefined, [originalSite]));
        material.inputs.push(projected);
        const fields = domain(projected, ['close', 'then']);
        site = Object.freeze({...fields, close: () => Reflect.apply(close.value, originalSite, [])});
      }
      material.inputs.push(site);
      current();
      // No connector callback runs between acquisition and retaining the actual
      // adapter. The constructor itself retains partial physical failures.
      const adapter = await factory({...input, moon: original.moon, sourceInitialization: context,
        ...prepared, environmentWire: prepared.environment!.wire,
        connectorId: scope.connectorId, connectorRegistration: scope.installation.registration,
        connectorRevision: scope.installation.revision, site, authorization: owned.authorization});
      owned.adapter = adapter;
      current();
      if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
      return adapter;
    } finally {owned.constructing = false;}
  }
  const bound: BoundConstruction = Object.freeze({
    configurationReader: captureConfigurationReaders(installedSourceConfigurationReader(services), undefined,
      () => fail('InstalledConfigurationReaderUnavailable')),
    prepareDeclaration: prepare('prepareDeclaration'),
    prepareNativeDeclaration: prepare('prepareNativeDeclaration'),
    prepareNativeInput: prepare('prepareNativeInput'),
    preparePublishedEnvironment: prepare('preparePublishedEnvironment'),
    prepareProviderEffect(provider: object, mappings: unknown) {
      current();
      if (owned.site === undefined) fail('InstalledSourceSiteUnavailable');
      const value = context.prepareProviderEffect(owned.site, provider, mappings);
      current(); return value;
    },
    prepareAuthoredDeclaration: prepare('prepareAuthoredDeclaration'),
    prepareBorrowedDeclaration: prepare('prepareBorrowedDeclaration'),
    prepareMappings: prepare('prepareMappings'),
    prepareNativeMappings: prepare('prepareNativeMappings'),
    prepareDeclaredCommands: prepare('prepareDeclaredCommands'),
    prepareAuthoredCommands: prepare('prepareAuthoredCommands'),
    prepareDerivedDeclaredCommands: prepare('prepareDerivedDeclaredCommands'),
    prepareReadTarget: prepare('prepareReadTarget'),
    prepareReadTargetWithMappings: prepare('prepareReadTargetWithMappings'),
    prepareEffectDriverConstruction: prepare('prepareEffectDriverConstruction'),
    sourceReaderImplementationProfile(options: unknown) {
      current(); return services.sourceReaderImplementationProfile(identity(options));
    },
    sourceReaderImplementation(options: unknown) {
      current(); return services.sourceReaderImplementation(identity(options));
    },
    async openSpecializedSite(options: unknown) {
      current();
      if (owned.site !== undefined || owned.siteAttempted) fail('InstalledSourceSiteAlreadyConstructed');
      const selected = domain(options);
      const {authorizationConstructor, siteConstructor, siteArgument, accountConfiguration, siteOptions = {}} = selected;
      if (typeof authorizationConstructor !== 'function' || typeof siteConstructor !== 'function' ||
          nodeTypes.isProxy(authorizationConstructor) || nodeTypes.isProxy(siteConstructor)) fail('InvalidInstalledSpecializedSite');
      const input = domain(siteOptions, ['authorization','commonMoon','runtimeBundleCid','configurationReader','ownAuthorization']);
      owned.siteAttempted = true;
      const authorization = await Reflect.apply(authorizationConstructor, undefined, [{accountConfiguration,
        root: original.root, principalId: original.principalId, gateOptions: {runtime: original.moon, accountConstruction: installedAccountConstruction(services)}}]);
      owned.authorization = authorization;
      current();
      const site = await Reflect.apply(siteConstructor, undefined, [siteArgument, {...input, authorization,
        commonMoon: original.moon, runtimeBundleCid: original.selected.get(scope.installation),
        configurationReader: bound.configurationReader, ownAuthorization: true}]);
      owned.site = site;
      // Bind this SAME specialized original to its bound constructor just as
      // openRowSite does. Credential custody still validates the Site issuer;
      // this private association supplies no grant or physical acknowledgement.
      original.siteInstallations.set(site, context);
      current();
      return Object.freeze({site, authorization});
    },
    async openRowSite(options: unknown) {
      current();
      if (owned.site !== undefined || owned.siteAttempted) fail('InstalledSourceSiteAlreadyConstructed');
      const selected = domain(options);
      const profile = selected.profile;
      // The bound owner captures immutable installation DATA; a provider need
      // not remember to freeze a fresh domain profile before the Site call.
      const fields = domain(profile);
      const capturedProfile = Object.isFrozen(profile) ? profile : Object.freeze(fields);
      material.inputs.push(profile, capturedProfile);
      owned.siteAttempted = true;
      const opened = await services.openRowSite(identity({...selected, profile: capturedProfile}));
      // The actual shared Site constructor owns its Authorization even when
      // its own current check fails. Retain both before this facade reenters.
      owned.site = opened.site; owned.authorization = opened.authorization;
      current();
      return opened;
    },
    createSourceReader(options: unknown) {
      current();
      if (owned.reader !== undefined) fail('InstalledSourceReaderAlreadyConstructed');
      const selected = domain(options, ['site']);
      const reader = services.createSourceReader(identity({...selected, site: owned.site}));
      owned.reader = reader;
      current();
      return reader;
    },
    async createDuckDBSource() {
      current();
      if (scope.role !== 'source' || !scope.publishedEnvironment || scope.prepared?.environment === undefined ||
          typeof scope.connectorId !== 'string' || owned.attempted || owned.constructing) {
        fail('InstalledSourceConstructionUnavailable');
      }
      const prepared = scope.prepared;
      owned.attempted = true; owned.constructing = true;
      try {
        reserveInstalledDuckDBConstruction(original, material, checkedProfile as Parameters<Physical['reserveInstalledDuckDBConstruction']>[2],
          prepared.environment as unknown as Parameters<Physical['reserveInstalledDuckDBConstruction']>[3]);
        current();
        const profile = await installDuckDBSourceProfile(checkedProfile, {
          root: original.root, principalId: original.principalId, runtime: original.moon,
          retainAuthorization(authorization) {
            // Retain before the installed profile can return or fail.
            owned.authorization = authorization;
            material.inputs.push(authorization);
          },
        });
        material.inputs.push(profile);
        current();
        // This known constructor registers its SAME adapter before returning;
        // connector DATA cannot supply a factory or register an arbitrary value.
        const adapter = await createInstalledDuckDBSource(profile, original.moon, {
          root: original.root, principalId: original.principalId,
          sourceInitialization: context, environment: prepared.environment as NonNullable<DuckDBOptions[2]['environment']>,
          installation: scope.installation,
        });
        owned.adapter = adapter;
        current();
        if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
        return adapter;
      } finally {owned.constructing = false;}
    },
    async createTableSource(options: unknown) {
      current();
      if (scope.role !== 'source' || owned.attempted || scope.prepared !== undefined) {
        fail('InstalledSourceConstructionUnavailable');
      }
      const selected = domain(options, ['moon', 'sourceInitialization', 'environment', 'environmentWire',
        'declaration', 'declared', 'site', 'authorization', 'connectorId', 'connectorRegistration',
        'connectorRevision', 'baseEnvironmentWire']);
      const {accountConfiguration, createBridge, ...input} = selected;
      if (typeof createBridge !== 'function' || nodeTypes.isProxy(createBridge) ||
          nodeTypes.isAsyncFunction(createBridge)) fail('InvalidInstalledTableBridgeConstructor');
      owned.attempted = true; owned.constructing = true;
      try {
        reserveInstalledTableConstruction(original, material, checkedProfile, profileConstruction);
        const bridge = requireSynchronousSourceConstruction(material, Reflect.apply(createBridge, undefined, []));
        owned.bridge = bridge; material.inputs.push(bridge);
        if (!bridge || typeof bridge !== 'object' || nodeTypes.isProxy(bridge) ||
            'then' in bridge) fail('InvalidInstalledTableBridge');
        current();
        // Full installation construction remains retained above. A selected
        // Reader only sends ONE first selector; later reply-derived payloads
        // grow through that SAME RowRun before their actual allocation.
        const readerProfileCapacity = installedTableReaderConstruction(original, material,
          checkedProfile as Parameters<Physical['installedTableReaderConstruction']>[2],
          profileConstruction!, bridge);
        const prepared = context.prepareDeclaration((input as TableInput).targets.map(target => ({
          resource: target.resource, resource_kind: 'table', schema_wire: target.schemaWire,
          schema_cid: target.selector.schema_cid,
        })));
        current();
        const authorization = await (installRowSourceAuthorization as typeof installAuthorization)({accountConfiguration,
          root: original.root, principalId: original.principalId,
          connectorRegistration: scope.installation.registration, gateOptions: {runtime: original.moon, accountConstruction: installedAccountConstruction(services)}});
        owned.authorization = authorization;
        current();
        const site = installedTableReadSite({connection: input.connection as TableSiteInputs['connection'], authorization,
          principalId: original.principalId, ownAuthorization: true,
          targets: () => owned.adapter?.tableReadTargets ?? []});
        owned.site = site;
        current();
        const capacityMethod = original.moon.clientProgramInstalledTableSourceReaderCapacity;
        if (typeof capacityMethod !== 'function' || nodeTypes.isAsyncFunction(capacityMethod)) {
          fail('InstalledTableSourceReaderUnavailable');
        }
        const columns = Math.max(...(prepared.declared as unknown as {views: readonly {fields: readonly unknown[]}[]}).views.map(view => view.fields.length));
        const originalReaderCapacity = Reflect.apply(capacityMethod, original.moon, [columns, readerProfileCapacity]);
        // Preserve the original native reference Option for the existing typed
        // Source composition. Its canonical binding alone exposes the value;
        // Host never reconstructs a Some, tuple or scalar capacity.
        const readerCapacity = runtimeUnboxedReferenceOption(originalReaderCapacity);
        if (readerCapacity === undefined || readerCapacity === null || typeof readerCapacity !== 'object') {
          fail('InstalledTableSourceReaderUnavailable');
        }
        material.providers.push(originalReaderCapacity);
        reserveSource(original, material);
        current();
        const bindReader = (reader: NonNullable<Bound['reader']>) => {
          current();
          if (owned.reader !== undefined || scope.reader !== undefined ||
              (bridge as TableBridge).frameLimits === undefined || !Object.isFrozen((bridge as TableBridge).frameLimits)) {
            fail('InstalledTableSourceReaderUnavailable');
          }
          owned.reader = scope.reader = reader;
          // Two actual commands, each with its ready and reply frame. Page
          // count remains the original row-page profile; protocol transfer is
          // the actual four original bounded bodies, not re-encoded rows.
          scope.readerDemand = Object.freeze({nested:false,responses:4,
            queryPages:(input as TableInput).limits.maxPages,maxResponseBytes:(input as TableInput).limits.maxPageBytes,
            maxNodes:400000,maxDepth:32,maxRows:(input as TableInput).limits.maxPageRows,
            maxTotalRows:(input as TableInput).limits.maxCaptureRows,
            transferBytes:4n*BigInt((bridge as TableBridge).frameLimits!.maxBytes)});
        };
        const adapter = await createInstalledTableSource({...input as Pick<TableSourceInputs, 'targets' | 'limits' | 'publicationBindingCid'>,
          bridge: bridge as TableSourceInputs['bridge'], site, authorization,
          readerCapacity, bindReader,
          moon: original.moon as Runtime & TableSourceInputs['moon'], sourceInitialization: context, ...prepared,
          baseEnvironmentWire: scope.baseEnvironmentWire!,
          connectorId: scope.connectorId!, connectorRegistration: scope.installation.registration!,
          connectorRevision: scope.installation.revision!});
        owned.adapter = adapter;
        current();
        if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
        return adapter;
      } finally {owned.constructing = false;}
    },
    async createTableEffect(options: unknown) {
      current();
      if (scope.role !== 'effect' || scope.publishedEnvironment !== true || owned.attempted ||
          scope.prepared?.environment === undefined) fail('InstalledSourceConstructionUnavailable');
      const selected = domain(options, ['moon', 'sourceInitialization', 'environment', 'environmentWire',
        'authorization', 'connectorId', 'connectorRegistration', 'connectorRevision', 'runtimeBundleCid']);
      const {accountConfiguration, createBridge, ...input} = selected;
      if (typeof createBridge !== 'function' || nodeTypes.isProxy(createBridge) ||
          nodeTypes.isAsyncFunction(createBridge)) fail('InvalidInstalledTableBridgeConstructor');
      const prepared = scope.prepared;
      owned.attempted = true; owned.constructing = true;
      try {
        reserveInstalledTableConstruction(original, material, checkedProfile, profileConstruction);
        const bridge = requireSynchronousSourceConstruction(material, Reflect.apply(createBridge, undefined, []));
        owned.bridge = bridge; material.inputs.push(bridge);
        if (!bridge || typeof bridge !== 'object' || nodeTypes.isProxy(bridge) ||
            'then' in bridge) fail('InvalidInstalledTableBridge');
        current();
        const authorization = await (installRowSourceAuthorization as typeof installAuthorization)({accountConfiguration,
          root: original.root, principalId: original.principalId,
          connectorRegistration: scope.installation.registration, gateOptions: {runtime: original.moon, accountConstruction: installedAccountConstruction(services)}});
        owned.authorization = authorization;
        current();
        const adapter = await createInstalledTableEffect({
          ...input as Pick<TableEffectInputs, 'connection' | 'bindingCid' | 'catalogCid' | 'targets' | 'ledgerRoot' | 'limits'>,
          bridge: bridge as TableEffectInputs['bridge'], moon: original.moon as Runtime & TableEffectInputs['moon'],
          sourceInitialization: context, environment: prepared.environment as TableEffectInputs['environment'],
          environmentWire: prepared.environment!.wire, authorization,
          connectorId: scope.connectorId!, connectorRegistration: scope.installation.registration!,
          connectorRevision: scope.installation.revision!,
          runtimeBundleCid: original.selected.get(scope.installation)!});
        owned.adapter = adapter;
        current();
        if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
        return adapter;
      } finally {owned.constructing = false;}
    },
    createRowSource: (options: unknown) => construct(options, 'source', createInstalledRowSource as RowFactory),
    createRowEffect: (options: unknown) => construct(options, 'effect', createInstalledRowEffect as unknown as RowFactory),
  });
  return bound;
}

export function createInstalledHostServices({root, principalId, moon, assertCurrent, accountCurrent, receiver, initialPreparation}: HostServicesInput): HostServices {
  if (typeof root !== 'string' || !root || typeof principalId !== 'string' || !principalId ||
      !moon || typeof moon !== 'object' || typeof assertCurrent !== 'function') fail('InvalidInstalledHostServices');
  const selected = new WeakMap<object, string>(), sites = new WeakMap<object, EffectSelection | undefined>(),
    siteInstallations = new WeakMap<object, object>();
  const implementations = new WeakMap<object, EffectSelection>(), sourceImplementations = new WeakMap<object, ImplementationSelection>(),
    sourceProfiles = new WeakMap<object, ProfileSelection>();
  const publicationOnly = false;
  const sourcePolicy = moon.clientProgramInstalledSourceReaderPolicy;
  const sourceProfile = moon.clientProgramInstalledJsonSourceReaderProfile;
  const sourceCapacity = moon.clientProgramInstalledJsonSourceReaderCapacity;
  const cursorSourceCapacity = moon.clientProgramInstalledJsonCursorSourceReaderCapacity;
  const cursorSourceRequestCapacity = moon.clientProgramInstalledJsonCursorSourceReaderCapacityWithRequest;
  const identityCursorSourceRequestCapacity = moon.clientProgramInstalledJsonIdentityCursorSourceReaderCapacityWithRequest;
  const sourceRequestCapacity = moon.clientProgramInstalledJsonSourceReaderCapacityWithRequest;
  const preservingSourceRequestCapacity = moon.clientProgramInstalledPreservingJsonSourceReaderCapacityWithRequest;
  const current = () => {
    if (Reflect.apply(assertCurrent, receiver, []) !== undefined) fail('InstalledHostServiceCurrentCheckNotSynchronous');
  };
  current();
  const services: HostServices = Object.freeze({
    sourceReaderImplementationProfile(options: unknown) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      if (Reflect.ownKeys(fields).length !== (Object.hasOwn(fields, 'sourceInitialization') ? 4 : 3) || ['installation', 'metadataResponses', 'originUnits'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation, fields);
      const metadata = fields.metadataResponses.value, origin = fields.originUnits.value;
      if (![metadata, origin].every(value => Number.isSafeInteger(value) && value >= 0 && value < 2147483647)) {
        fail('InvalidInstalledSourceReaderSelection');
      }
      const previous = sourceProfiles.get(selection);
      if (previous !== undefined) {
        if (previous.runtimeBundleCid !== runtimeBundleCid || previous.metadata !== metadata || previous.origin !== origin) {
          fail('InstalledSourceReaderSelectionChanged');
        }
        return previous.value;
      }
      if (sourceImplementations.has(selection)) fail('InstalledSourceReaderProfileSelectedLate');
      if (typeof sourceProfile !== 'function') fail('InstalledSourceReaderProfileUnavailable');
      const returned = Reflect.apply(sourceProfile, moon, [metadata, origin]);
      const values = runtimeIsBoxedSome(returned) ? runtimeField(returned, 0) : undefined;
      if (!Array.isArray(values) || values.length !== installedJsonSourceReaderProfileLimitNames.length ||
          values.some(value => !Number.isSafeInteger(value) || value < 1 || value >= 2147483647)) {
        fail('InvalidInstalledSourceReaderProfile');
      }
      const value = Object.freeze(Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map(
        (name, index) => [name, values[index]])));
      current(); sourceProfiles.set(selection, Object.freeze({runtimeBundleCid, metadata, origin, value}));
      return value;
    },
    sourceReaderImplementation(options: unknown) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) {
        fail('InvalidInstalledSourceReaderSelection');
      }
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      if (Reflect.ownKeys(fields).length !== (Object.hasOwn(fields, 'sourceInitialization') ? 4 : 3) +
          (Object.hasOwn(fields, 'requestConstruction') ? 1 : 0) +
          (Object.hasOwn(fields, 'preservingRequestConstruction') ? 1 : 0) +
          (Object.hasOwn(fields, 'cursorProgress') ? 1 : 0) +
          (Object.hasOwn(fields, 'readSequenceConstruction') ? 1 : 0) ||
          Object.hasOwn(fields, 'requestConstruction') && Object.hasOwn(fields, 'preservingRequestConstruction') || ['installation', 'limits', 'columnCount'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      if (nodeTypes.isProxy(fields.limits.value ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation, fields);
      const columns = fields.columnCount.value;
      const preservingResponse = Object.hasOwn(fields, 'preservingRequestConstruction');
      // Trusted Source construction selects its actual representation. Program
      // DATA and Account policy do not choose a cheaper quote or another mode.
      let cursorProgress: true | 'codec-identities' | undefined;
      if (Object.hasOwn(fields, 'cursorProgress')) {
        if (!Object.hasOwn(fields.cursorProgress, 'value') ||
            (fields.cursorProgress.value !== true && fields.cursorProgress.value !== 'codec-identities') ||
            preservingResponse || Object.hasOwn(fields, 'readSequenceConstruction') ||
            (fields.cursorProgress.value === 'codec-identities' && !Object.hasOwn(fields, 'requestConstruction'))) {
          fail('InvalidInstalledSourceReaderSelection');
        }
        cursorProgress = fields.cursorProgress.value;
      }
      let requestConstruction: RequestConstruction | undefined;
      if (Object.hasOwn(fields, 'requestConstruction') || preservingResponse) {
        const field = preservingResponse ? fields.preservingRequestConstruction : fields.requestConstruction;
        if (!Object.hasOwn(field, 'value') || !field.value || nodeTypes.isProxy(field.value) ||
            !Object.isFrozen(field.value)) fail('InvalidInstalledSourceRequestConstruction');
        const original = Object.getOwnPropertyDescriptors(field.value);
        if (Reflect.ownKeys(original).length !== 2 ||
            !Object.hasOwn(original.capacity ?? {}, 'value') ||
            !Object.hasOwn(original.maxRequestBytes ?? {}, 'value') ||
            !Number.isSafeInteger(original.maxRequestBytes.value) ||
            original.maxRequestBytes.value < 1 || original.maxRequestBytes.value > 2147483647) {
          fail('InvalidInstalledSourceRequestConstruction');
        }
        requestConstruction = field.value;
      }
      // The selected Source supplies its SAME complete Core quote and original
      // occurrence declaration. This is retained construction DATA, not a grant,
      // owner, profile knob or a recipe selected again by registration here.
      let readSequenceConstruction: SequenceConstruction | undefined;
      if (Object.hasOwn(fields, 'readSequenceConstruction')) {
        const field = fields.readSequenceConstruction;
        if (!Object.hasOwn(field, 'value') || field.value === null || typeof field.value !== 'object' ||
            nodeTypes.isProxy(field.value) || !Object.isFrozen(field.value)) fail('InvalidInstalledSourceSequenceConstruction');
        const original = Object.getOwnPropertyDescriptors(field.value);
        const names = Reflect.ownKeys(original);
        if (names.some(name => !['capacity', 'originalLimits', 'sequence', 'sequences', 'maxRequestBytes', 'maxQueryBytes'].includes(name as string)) ||
            names.some(name => !Object.hasOwn(original[name as string], 'value')) ||
            !Object.hasOwn(original, 'capacity') || !Object.hasOwn(original, 'originalLimits') ||
            Object.hasOwn(original, 'sequence') === Object.hasOwn(original, 'sequences') ||
            original.capacity.value === undefined || original.capacity.value === null ||
            original.originalLimits.value === null || typeof original.originalLimits.value !== 'object' ||
            nodeTypes.isProxy(original.originalLimits.value) || !Object.isFrozen(original.originalLimits.value)) {
          fail('InvalidInstalledSourceSequenceConstruction');
        }
        const occurrences = (original.sequence ?? original.sequences).value;
        if (occurrences === null || typeof occurrences !== 'object' || nodeTypes.isProxy(occurrences) ||
            !Object.isFrozen(occurrences) || original.maxRequestBytes !== undefined &&
            (!Number.isSafeInteger(original.maxRequestBytes.value) || original.maxRequestBytes.value < 1 ||
              original.maxRequestBytes.value > 2147483647) || original.maxQueryBytes !== undefined &&
            (!Number.isSafeInteger(original.maxQueryBytes.value) || original.maxQueryBytes.value < 1 ||
              original.maxQueryBytes.value > 2147483647)) fail('InvalidInstalledSourceSequenceConstruction');
        readSequenceConstruction = field.value;
      }
      const profile = sourceProfiles.get(selection);
      const supplied = Object.getOwnPropertyDescriptors(fields.limits.value ?? {});
      // A scalar method/body allowance cannot replace the original request
      // constructor or a complete selected sequence. The retired query/property
      // projection never admitted its 21-field quote through the real 16-field
      // JSON constructor, and its managed-read entry was refused as unfunded.
      if (Object.hasOwn(supplied, 'maxRequestBytes') || Object.hasOwn(supplied, 'maxQueryBytes')) fail('InstalledSourceReaderRequestCapacityUnavailable');
      if (requestConstruction !== undefined && readSequenceConstruction !== undefined) {
        fail('InstalledSourceReaderRequestConstructionChanged');
      }
      const names = [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'] as const;
      if (names.some(name => !Object.hasOwn(supplied[name] ?? {}, 'value') ||
          !Number.isSafeInteger(supplied[name].value) || supplied[name].value < 1 || supplied[name].value > 2147483647)) {
        fail('InvalidInstalledSourceReaderLimits');
      }
      if (profile !== undefined && (profile.runtimeBundleCid !== runtimeBundleCid ||
          columns > profile.value.maxColumns || names.some(name =>
            supplied[name].value > profile.value[name]))) {
        fail('InstalledSourceReaderImplementationBoundsExceeded');
      }
      const selectedRequestCapacity = cursorProgress === 'codec-identities' ? identityCursorSourceRequestCapacity
        : cursorProgress ? cursorSourceRequestCapacity
        : preservingResponse ? preservingSourceRequestCapacity : sourceRequestCapacity;
      const selectedPageCapacity = cursorProgress ? cursorSourceCapacity : sourceCapacity;
      if (typeof sourcePolicy !== 'function' || readSequenceConstruction === undefined &&
          typeof (requestConstruction === undefined ? selectedPageCapacity : selectedRequestCapacity) !== 'function') fail('InstalledSourceReaderRuntimeUnavailable');
      const policy = Reflect.apply(sourcePolicy, moon, []);
      // The Values cells-per-row default is not Source schema eligibility.
      // Source columns retain their declared bounds and typed RowRun capacity;
      // this bridge still requires the original Core Int representation.
      if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
        !Number.isSafeInteger(value) || value < 1 || value > 2147483647) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > 2147483647 ||
        supplied.maxSecretBytes.value > policy[0]) fail('InstalledSourceReaderPolicyUnavailable');
      const limits = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value]))) as ReaderLimits;
      const previous = sourceImplementations.get(selection);
      if (previous !== undefined) {
        if (previous.requestConstruction !== requestConstruction || previous.preservingResponse !== preservingResponse ||
            previous.cursorProgress !== cursorProgress ||
            previous.readSequenceConstruction !== readSequenceConstruction ||
            previous.runtimeBundleCid !== runtimeBundleCid || previous.columns !== columns ||
            names.some(name => previous.value.limits[name] !== limits[name])) fail('InstalledSourceReaderSelectionChanged');
        return previous.value;
      }
      const capacity = readSequenceConstruction !== undefined ? readSequenceConstruction.capacity
        : Reflect.apply((requestConstruction === undefined ? selectedPageCapacity : selectedRequestCapacity) as CoreMethod, moon,
          [installedJsonSourceReaderLimitNames.map(name => limits[name]), columns, limits.maxSecretBytes,
            ...(requestConstruction === undefined ? [] : [requestConstruction.capacity])]);
      if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
      const value = Object.freeze({capacity, limits, runAcquisitionLimits: Object.freeze({
        maxBindings: policy[1], maxSecretBytes: limits.maxSecretBytes})});
      current(); sourceImplementations.set(selection, Object.freeze({runtimeBundleCid, columns, readSequenceConstruction, requestConstruction, preservingResponse, cursorProgress, value}));
      return value;
    },
    createSourceReader(options: unknown) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      const standard = Object.hasOwn(fields, 'preparePageReader');
      const managedSequence = Object.hasOwn(fields, 'prepareReadSequence');
      if (standard === managedSequence) fail('InvalidInstalledSourceReaderSelection');
      const readerField = managedSequence ? 'prepareReadSequence' : 'preparePageReader';
      if (Reflect.ownKeys(fields).length !== (standard ? 5 : 4) + (Object.hasOwn(fields, 'sourceInitialization') ? 1 : 0) ||
          ['installation', 'implementation', 'site', readerField, ...(standard ? ['operation'] : [])].some(name =>
            !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value;
      const selection = requireSourceConstructor(services, installation, fields, true);
      const implementation = sourceImplementations.get(selection);
      if (implementation === undefined || implementation.value !== fields.implementation.value ||
          implementation.runtimeBundleCid !== selected.get(installation) ||
          siteInstallations.get(fields.site.value) !== selection) fail('ForeignInstalledSourceReaderSelection');
      // The normal JSON page recipe does not back a retained query/property
      // sequence. Keep this entry refused until that same Source recipe owns
      // constructor, prefix, output and failed-child overlap before use.
      if (managedSequence && implementation.readSequenceConstruction === undefined) fail('InstalledSourceReaderReadChildCapacityUnavailable');
      if (implementation.requestConstruction !== undefined && !standard) fail('InstalledSourceReaderStandardSelectionRequired');
      if (implementation.readSequenceConstruction !== undefined && !managedSequence) fail('InstalledSourceReaderSequenceSelectionRequired');
      const originalSite = installedRowCredentialOperationSite(fields.site.value.credential);
      const limits = implementation.value.limits, sequence = implementation.readSequenceConstruction;
      const maxQueryBytes = sequence !== undefined && Object.hasOwn(sequence, 'maxQueryBytes')
        ? sequence.maxQueryBytes : undefined;
      const constructor = sourceContexts.get(selection);
      if (constructor?.scope.reader !== undefined) fail('InstalledSourceReaderAlreadyConstructed');
      // Optional separately bound Resources are declared by this SAME complete
      // native sequence recipe. Names bound construction; only each original
      // Site-issued decision/grant authorizes the actual child.
      let resourceChildren: string[] | undefined;
      const sequences = sequence?.sequences === undefined ? [sequence?.sequence]
        : Object.values(sequence.sequences);
      for (const originalSequence of sequences) {
        for (const child of originalSequence?.children ?? []) {
          const resource = Object.getOwnPropertyDescriptor(child, 'resource');
          if (resource === undefined) continue;
          if (!Object.hasOwn(resource, 'value') || typeof resource.value !== 'string' || resource.value.length === 0) {
            fail('InvalidInstalledSourceResourceChildren');
          }
          resourceChildren ??= [];
          if (!resourceChildren.includes(resource.value)) resourceChildren.push(resource.value);
        }
      }
      if (resourceChildren !== undefined) Object.freeze(resourceChildren);
      const factory = createInstalledCredentialSourceReader({capacity: implementation.value.capacity,
        originalSite, [readerField]: fields[readerField].value, assertCurrent: current,
        ...(resourceChildren === undefined ? {} : {resourceChildren}),
        maxResponses: limits.maxPages,
        ...(standard ? {operation: fields.operation.value,
          ...(implementation.requestConstruction === undefined ? {} : {maxRequestBytes:implementation.requestConstruction.maxRequestBytes}),
          maxResponseBytes: limits.maxResponseBytes, maxTotalResponseBytes: limits.maxTotalResponseBytes,
          maxSecretBytes: limits.maxSecretBytes} : {}),
        ...(managedSequence ? {maxResponseBytes: limits.maxResponseBytes,
          ...(maxQueryBytes === undefined ? {} : {maxQueryBytes}),
          ...(sequence?.maxRequestBytes !== undefined ? {maxRequestBytes:sequence.maxRequestBytes}
            : {}),
          maxTotalResponseBytes: limits.maxTotalResponseBytes} : {})});
      if (constructor !== undefined) {
        const all = BigInt(limits.maxPages) * BigInt(limits.maxResponseBytes);
        const prefix = BigInt(limits.maxTotalResponseBytes) + BigInt(limits.maxResponseBytes);
        constructor.scope.reader = factory;
        constructor.scope.readerDemand = Object.freeze({nested: false,
          ...(sequence?.sequence === undefined ? {} : {sequence:sequence.sequence}),
          ...(sequence?.sequences === undefined ? {} : {sequences:sequence.sequences}),
          responses: limits.maxPages, queryPages: limits.maxPages,
          propertyPages: undefined, propertyOccurrences: undefined,
          maxResponseBytes: limits.maxResponseBytes, maxNodes: limits.maxNodes, maxDepth: limits.maxDepth,
          maxRows: limits.maxRows, maxTotalRows: limits.maxTotalRows,
          transferUnitBytes: BigInt(limits.maxResponseBytes),
          transferBytes: sequence === undefined || all < prefix ? all : prefix});
      }
      return factory;
    },
    openRowSite(options: unknown) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationPhysicalUnavailable');
      const presentation = Object.getOwnPropertyDescriptor(options ?? {}, 'secretPresentation');
      if (presentation !== undefined && !Object.hasOwn(presentation, 'value')) {
        fail('InvalidRowSourceSecretPresentation');
      }
      const installation = Object.getOwnPropertyDescriptor(options ?? {}, 'installation')?.value;
      const runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation,
        Object.getOwnPropertyDescriptors(options ?? {}), true);
      // An Effect has no Source reader from which to forward these limits.
      // Select the SAME Core implementation policy once on its original
      // constructor. These are rejection bounds only: the adopted Run's
      // operation extent must still back every actual binding/secret before
      // construction, and Account/claim still authorize each physical use.
      const constructor = sourceContexts.get(selection);
      let effectCredentialLimits;
      if (constructor?.scope.role === 'effect') {
        const {scope} = constructor;
        if (Object.hasOwn(options as object, 'runAcquisitionLimits') || scope.credentialSelecting) {
          fail('InstalledEffectCredentialSelectionUnavailable');
        }
        if (scope.credentialLimits === undefined) {
          if (typeof sourcePolicy !== 'function') fail('InstalledEffectCredentialPolicyUnavailable');
          scope.credentialSelecting = true;
          try {
            const policy = Reflect.apply(sourcePolicy, moon, []);
            if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
              !Number.isSafeInteger(value) || value < 1 || value > 2147483647)) {
              fail('InstalledEffectCredentialPolicyUnavailable');
            }
            // This is a local original/lifetime fence after the selected
            // callback, not a second current or semantic policy admission.
            if (requireSourceConstructor(services, installation,
              Object.getOwnPropertyDescriptors(options), true) !== selection) {
              fail('InstalledEffectCredentialSelectionUnavailable');
            }
            scope.credentialLimits = Object.freeze({maxBindings: policy[1], maxSecretBytes: policy[0]});
          } finally {scope.credentialSelecting = false;}
        }
        effectCredentialLimits = scope.credentialLimits;
      }
      // The caller supplies provider configuration only. It cannot replace the
      // original Host/runtime/current association with equal or copied DATA.
      const implementation = implementations.get(installation);
      if (implementation?.constructing) fail('InstalledEffectDefinitionSelectionReentry');
      if (implementation !== undefined) implementation.sealed = true;
      return openInstalledRowSite({...options as object,
        ...(effectCredentialLimits === undefined ? {} : {runAcquisitionLimits: effectCredentialLimits}),
        root, principalId, commonMoon: moon, runtimeBundleCid, assertCurrent: current,
        accountConstruction: installedAccountConstruction(services),
        configurationReader: installedSourceConfigurationReader(services)} as
          Parameters<typeof openInstalledRowSite>[0]).then((original: SiteSelection) => {
          sites.set(original.site, implementation);
          siteInstallations.set(original.site, selection);
        return original;
      });
    },
  });
  const restoreDeclaration = moon.clientProgramRowSourceRestoreRelationDeclaration;
  const restoreAuthoredDeclaration = moon.clientProgramRowSourceRestoreDeclaration;
  const declarationJson = moon.clientProgramRowSourceDeclarationJson;
  const admitAcquisitionContracts = moon.clientProgramRowSourceAdmitAcquisitionContracts;
  const acquisitionContractsCapacity = moon.clientProgramRowSourceAcquisitionContractsConstructionCapacity;
  const prepareMapping = moon.clientProgramRowSourcePrepareMapping;
  const prepareFileCreateMapping = moon.clientProgramRowSourcePrepareFileCreateMapping;
  const prepareUpdateMapping = moon.clientProgramRowSourcePrepareUpdateMapping;
  const prepareDeleteMapping = moon.clientProgramRowSourcePrepareDeleteMapping;
  const prepareUpdateMappingCapacity = moon.clientProgramRowSourceUpdateMappingConstructionCapacity;
  installations.set(services, {selected, current, sites, siteInstallations, implementations,
    sourceImplementations, sourceProfiles, moon, root, principalId, initialPreparation, accountCurrent, restoreDeclaration, restoreAuthoredDeclaration, declarationJson,
    admitAcquisitionContracts, acquisitionContractsCapacity, prepareMapping, prepareFileCreateMapping, prepareUpdateMapping, prepareDeleteMapping,
    prepareUpdateMappingCapacity});
  return services;
}

// Private Account facet on the SAME initial/continued Host material. A
// nominal/control scope is insufficient; this entrance requires the actual
// selected Core capacity retained by this installed service.
export function installedAccountConstruction(services: object) {
  const original = installations.get(services);
  // Standalone legacy installers have no original numeric carrier. Ordinary
  // Host construction always supplies its actual initialization preparation.
  if (original !== undefined && original.initialPreparation === undefined) return undefined;
  if (original === undefined || typeof original.accountCurrent !== 'function') fail('AccountConstructionUnavailable');
  original.accountCurrent();
  const material = sourceMaterial(original);
  if (material === undefined || material.capacity === undefined || material.input === undefined) fail('AccountConstructionUnavailable');
  return original.accountConstruction ??= createAccountConstruction({moon: original.moon,
    current: original.accountCurrent,
    prepareRead: () => original.moon.clientProgramPrepareInstalledAccountRead(material.capacity, material.input)});
}

export async function closeInstalledAccountConstruction(services: object) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  return original.accountConstruction === undefined || await original.accountConstruction.close();
}

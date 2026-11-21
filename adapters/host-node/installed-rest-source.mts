// The standard author facade composes existing installation and reader
// owners. Provider declarations supply DATA; no reader lifecycle is here.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
// @ts-expect-error TS7016: remove after installed-host-services has an authored TypeScript entry.
import {captureInstalledSourceServices} from './installed-host-services.mjs';
// @ts-expect-error TS7016: remove after installed-row-source has an authored TypeScript entry.
import {createInstalledRowSource} from './installed-row-source.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createRestSourceMetadata} from './rest-source-metadata.mjs';
import {restSourcePageReader} from './rest-source-page.mjs';
import {captureRestSourceRead, restSourceReadConstructionUnits,
  restSourceRequestConstructionUnits} from './rest-source-request.mjs';
import {captureRestReadOriginals, restReadOriginalControlUnits, restReadTransportConstructionUnits}
  from './rest-read-original.mjs';
import {installedJsonSourceReaderLimitNames} from './installed-credential-source-reader.mjs';
import type {InstalledRowSource, RestSourceInstallationDefinition} from '../../packages/local-node/connector-installation.js';
import type {DeclaredRestPublication} from './rest-source-metadata.mjs';
import type {RestSourceProjection} from './rest-source-page.mjs';
import type {RestReadOriginal} from './rest-read-original.mjs';
import type {RestConstructionUnits, RestSourceRead} from './rest-source-request.mjs';

type DefinitionSource = RestSourceInstallationDefinition['sources'][number];
type Pagination = DefinitionSource['pagination'] & Readonly<{parameter?: string}>;
type PageOptions = Parameters<typeof restSourcePageReader>[0];
type RuntimeOptions = Readonly<{
  moon?: object; installation?: unknown; sourceInitialization?: unknown; runtimeBundleCid?: unknown;
  resolveSecret?: unknown; configurationReader?: unknown; installationServices?: unknown;
}>;
type Declared = DeclaredRestPublication & Readonly<{views: readonly Readonly<{resource: string; fields: readonly string[]}>[]}>;
type Prepared = Readonly<{declaration: unknown; declared: Declared; environment: Readonly<{wire: string}>}>;
type HostPolicy = Readonly<Record<typeof installedJsonSourceReaderLimitNames[number] |
  'maxDeclarationBytes' | 'maxDeclarationNodes' | 'maxSecretBytes', number>>;
type PhysicalTarget = (resource: string, fields: unknown, originalPath?: string) => Readonly<{
  connectorRegistration: string; connectorRevision: string; catalogCid: string; originalStringsCid: string;
  origin: string; path: string; resource: string; fields: readonly string[];
}>;
type TargetMaterial = Readonly<{targets: readonly ReturnType<PhysicalTarget>[];
  requests: readonly (RestSourceRead | RestReadOriginal)[]}>;
type ReadOriginals = ReturnType<typeof captureRestReadOriginals>;
type SiteClosure = NonNullable<Parameters<typeof retainInstalledHostInitializationFailure>[1]['sourceProfile']>;
type ProviderReader = Readonly<{capacity: unknown}>;
type Services = {
  (method: 'sourceReaderImplementationProfile', options: Readonly<Record<string, unknown>>): HostPolicy;
  (method: 'sourceReaderImplementation', options: Readonly<Record<string, unknown>>):
    Readonly<{capacity: unknown; runAcquisitionLimits: unknown}>;
  (method: 'openRowSite', options: Readonly<Record<string, unknown>>): Promise<Readonly<{
    site: SiteClosure; authorization: Readonly<{context: Readonly<{contextCid: string}>}>;
  }>>;
  (method: 'createSourceReader', options: Readonly<Record<string, unknown>>): ProviderReader;
};

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const cid = (value: unknown) => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const bounds = Object.freeze({maxPageRows: 'maxRows', maxPageBytes: 'maxResponseBytes',
  maxPages: 'maxPages', maxRows: 'maxTotalRows', maxNodes: 'maxNodes', maxDepth: 'maxDepth',
  maxCursorBytes: 'maxCursorBytes'} as const);

// Select the existing Source constructor before configuration awaits. Its
// original native capacity recipe owns proportional DATA, not callback counts.
function capturePhysicalTargetConstruction(sourceInitialization: unknown, moon: object) {
  const method = Object.getOwnPropertyDescriptor(sourceInitialization as object, 'prepareReadTarget');
  const capacity = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSourceConstructionCapacity');
  if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function' ||
      !capacity || !Object.hasOwn(capacity, 'value') || typeof capacity.value !== 'function') {
    fail('RestSourceInitializationUnavailable');
  }
  return (sources: readonly DefinitionSource[], declared: Declared, physicalTarget: PhysicalTarget): TargetMaterial => {
    // One array, one eight-field target object per resource and its original
    // ordered field values. String payloads are borrowed immutable originals.
    let slots = 1n;
    const requests = [0n, 0n, 0n, 0n, 0n, 0n];
    for (const source of sources) {
      const view = declared.views.find(view => view.resource === source.resource);
      if (view === undefined) fail('RestSourceReadTargetMismatch');
      slots += 9n + BigInt(view.fields.length);
      const units = restSourceReadConstructionUnits(source.read!, (source.pagination as Pagination).parameter);
      for (let index = 0; index < units.length; index++) requests[index] += units[index];
    }
    // Internal two-field wrapper and request vector. Public target DATA stays
    // byte-for-byte the original eight-field shape. The SAME one initializer
    // retains both outputs before any page constructor can borrow the request.
    // The additional Core request-row projector is captured once per source:
    // one closure with method+namespace captures and one result-record field
    // (4 value slots), retained alongside the original request snapshot.
    const wrapper = 4n + 5n * BigInt(sources.length);
    return Reflect.apply(method.value, sourceInitialization, [Object.freeze({
      capacity() {
        return checked(Reflect.apply(capacity.value, moon, requests.map((units, index) =>
          units + (index === 0 ? slots + wrapper : index === 3
            // New method-entry pair3 + map result vector entry1 remain in
            // constructor workspace alongside the retained closure/field.
            ? slots + wrapper + 4n * BigInt(sources.length) : 0n))));
      },
      project() {
        return Object.freeze({targets: Object.freeze(sources.map(source => physicalTarget(source.resource,
          declared.views.find(view => view.resource === source.resource)!.fields))),
        requests: Object.freeze(sources.map(source => captureRestSourceRead(
          {method: 'GET', ...source.read}, (source.pagination as Pagination).parameter)))});
      },
    })]);
  };
}

// The same initializer also retains the original Core parser/Bytes for the
// shipped readWire representation. Legacy row-only DATA keeps its existing
// projector above; Program/Account DATA cannot select a budget or Reader mode.
function captureCoreTargetConstruction(sourceInitialization: unknown, moon: object, originals: ReadOriginals) {
  const method = Object.getOwnPropertyDescriptor(sourceInitialization as object, 'prepareReadTarget');
  if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') {
    fail('RestSourceInitializationUnavailable');
  }
  return (sources: readonly DefinitionSource[], declared: Declared, physicalTarget: PhysicalTarget, policy: HostPolicy): TargetMaterial => {
    const units = restReadOriginalControlUnits(sources.length);
    let targets = 1n;
    for (const source of sources) {
      const view = declared.views.find(view => view.resource === source.resource);
      if (view === undefined) fail('RestSourceReadTargetMismatch');
      targets += 10n + BigInt(view.fields.length);
    }
    units[0] += targets;
    // Keep own-values vectors for each eight-field target and each fields
    // Array, plus pending/growth references, alongside the retained target.
    units[3] += 3n * targets;
    return Reflect.apply(method.value, sourceInitialization, [Object.freeze({
      capacity() {return originals.composeConstruction(units, sources.length, index => {
        const source = sources[index];
        return originals.quote(source.readWire!, (source.pagination as Pagination).parameter, policy);
      });},
      project() {
        const requests = Object.freeze(sources.map(source => originals.project(
          source.readWire!, (source.pagination as Pagination).parameter, policy)));
        return Object.freeze({targets: Object.freeze(sources.map((source, index) => physicalTarget(
          source.resource, declared.views.find(view => view.resource === source.resource)!.fields,
          requests[index].path))), requests});
      },
    })]);
  };
}

export function createInstalledRestSource(definition: RestSourceInstallationDefinition,
  {decodePage}: Readonly<{decodePage?: PageOptions['decodePage']}> = {}) {
  const metadata = createRestSourceMetadata(definition), original = metadata.definition;
  const nativeReads = original.sources.some(source => Object.hasOwn(source, 'readWire'));
  if (nativeReads && original.sources.some(source => typeof source.readWire !== 'string' ||
      Object.hasOwn(source, 'read'))) fail('RestSourceReadDeclarationMismatch');
  if (decodePage !== undefined && typeof decodePage !== 'function') fail('InvalidRestSourceTransform');
  const operation = `${original.registration}:rest:read`;
  function captureDeclarationPreparation(sourceInitialization: unknown) {
    if (sourceInitialization === null || typeof sourceInitialization !== 'object' ||
        types.isProxy(sourceInitialization)) fail('RestSourceInitializationUnavailable');
    const method = Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareAuthoredDeclaration');
    if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') {
      fail('RestSourceInitializationUnavailable');
    }
    const wire = metadata.authoredDeclarationWire();
    return function prepareOriginalDeclaration() {
      const prepared = Reflect.apply(method.value, sourceInitialization, [wire]);
      if (prepared === null || typeof prepared !== 'object' || types.isProxy(prepared)) {
        fail('RestSourcePreparedDeclarationUnavailable');
      }
      const fields = Object.getOwnPropertyDescriptors(prepared);
      if (['declaration', 'declared', 'environment'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value') || fields[name].value === undefined)) {
        fail('RestSourcePreparedDeclarationUnavailable');
      }
      return prepared as Prepared;
    };
  }
  async function publish(profile: unknown, options: RuntimeOptions = {}) {
    const prepare = captureDeclarationPreparation(options.sourceInitialization);
    const input = await metadata.readInputs(profile, {configurationReader: options.configurationReader});
    const {declared} = prepare();
    return metadata.reportPrepared(input, declared);
  }
  async function load(profile: unknown, options: RuntimeOptions = {}): Promise<InstalledRowSource> {
    // Select original service methods before any configuration await. The
    // service owns normal implementation selection, Site and typed capacity.
    const services = captureInstalledSourceServices(options.installationServices,
      () => fail('RestSourceInstallationServicesUnavailable')) as Services;
    const {moon, installation, sourceInitialization, runtimeBundleCid, resolveSecret} = options;
    const prepare = captureDeclarationPreparation(sourceInitialization);
    const originals = nativeReads ? captureRestReadOriginals(moon) : undefined;
    const preparePhysicalTargets = nativeReads
      ? captureCoreTargetConstruction(sourceInitialization, moon!, originals!)
      : capturePhysicalTargetConstruction(sourceInitialization, moon!);
    const requestCapacity = Object.getOwnPropertyDescriptor(moon!, 'clientProgramInstalledSourceConstructionCapacity')!.value;
    if (typeof resolveSecret !== 'function') fail('RestSourceCredentialMaterialUnavailable');
    const input = await metadata.readInputs(profile, {configurationReader: options.configurationReader});
    const {declaration, declared, environment} = prepare();
    const policy = services('sourceReaderImplementationProfile', {installation, sourceInitialization,
      metadataResponses: 0, originUnits: original.origin.length});
    // Author limits constrain this connector's semantics, not its physical
    // funding. The same selected Host profile must cover them in full.
    for (const source of original.sources) {
      for (const [authorName, hostName] of Object.entries(bounds)) {
        const value = source.limits[authorName as keyof typeof bounds];
        if (!Number.isSafeInteger(value) || value <= 0 || value > policy[hostName]) {
          fail('RestSourceImplementationBoundsExceeded');
        }
      }
    }
    // Both constructors select the same already-validated Source demand.
    // Other codec/workspace rejection bounds remain the selected Host policy.
    const limits = Object.freeze({maxPages: Math.max(...original.sources.map(source => source.limits.maxPages)),
      maxPageBytes: Math.max(...original.sources.map(source => source.limits.maxPageBytes)),
      maxPageRows: Math.max(...original.sources.map(source => source.limits.maxPageRows)),
      maxCaptureRows: Math.max(...original.sources.map(source => source.limits.maxRows))});
    const pageBounds = Object.freeze({maxNodes: Math.max(...original.sources.map(source => source.limits.maxNodes)),
      maxDepth: Math.max(...original.sources.map(source => source.limits.maxDepth)),
      maxCursorBytes: Math.max(...original.sources.map(source => source.limits.maxCursorBytes))});
    const implementationLimits = Object.freeze({...Object.fromEntries(
      ([...installedJsonSourceReaderLimitNames, 'maxSecretBytes'] as const).map(name => [name, policy[name]])),
      maxPages: limits.maxPages, maxResponseBytes: limits.maxPageBytes,
      maxRows: limits.maxPageRows, maxTotalRows: limits.maxCaptureRows, ...pageBounds});
    const physicalTarget: PhysicalTarget = (resource, fields, originalPath) => {
      const source = original.sources.find(source => source.resource === resource);
      const view = declared.views.find(view => view.resource === resource);
      if (source === undefined || view === undefined || !Array.isArray(fields) ||
          // The constructor passes this SAME Common-checked original fields
          // Array. Other callers (including approval targets) still receive
          // the full duplicate/membership checks; no request Bool selects it.
          !(originalPath !== undefined && fields === view.fields) &&
          (new Set(fields).size !== fields.length || fields.some(field => !view.fields.includes(field)))) {
        fail('RestSourceReadTargetMismatch');
      }
      return Object.freeze({connectorRegistration: original.registration, connectorRevision: original.revision,
        catalogCid: declared.catalog_cid, originalStringsCid: input.originalStringsCid,
        origin: original.origin, path: nativeReads
          ? originalPath ?? material!.requests[original.sources.indexOf(source)].path : source.read!.path, resource, fields: Object.freeze([...fields])});
    };
    let material: TargetMaterial | undefined;
    if (nativeReads) material = preparePhysicalTargets(original.sources, declared, physicalTarget, policy);
    const requestUnits: [...RestConstructionUnits] = [0n, 0n, 0n, 0n, 0n, 0n];
    for (const source of original.sources) {
      const units = nativeReads ? restReadTransportConstructionUnits(material!.requests[original.sources.indexOf(source)] as RestReadOriginal)
        : restSourceRequestConstructionUnits(source.read!, (source.pagination as Pagination).parameter);
      // Only one page request is entered at a time on the existing Reader.
      // All static Source snapshots are retained separately by the initializer.
      for (let index = 0; index < units.length; index++) {
        if (units[index] > requestUnits[index]) requestUnits[index] = units[index];
      }
    }
    // Replaces the old three-argument fetch projection, not decode. Two new
    // primitive args, their call-vector copies, the typed Option and inner
    // Result overlap add6 workspace slots; all are charged before acquisition.
    requestUnits[3] += 6n;
    const requestConstruction = Object.freeze({
      capacity: nativeReads ? originals!.requestCapacity(requestUnits, material!.requests as readonly RestReadOriginal[])
        : checked(Reflect.apply(requestCapacity, moon, requestUnits)),
      maxRequestBytes: policy.maxTargetBytes});
    const implementation = services('sourceReaderImplementation', {installation, sourceInitialization, limits: implementationLimits,
      columnCount: Math.max(...declared.views.map(view => view.fields.length)), cursorProgress: true,
      requestConstruction});
    const connection = `${original.registration}:${input.installed.connectorId}`;
    const opened = await services('openRowSite', {installation, sourceInitialization,
      accountConfiguration: input.installed.accountConfigurationWire, connection,
      profile: Object.freeze({...input.site, resourceOrigin: original.origin}), resolveSecret,
      ...(input.ca === undefined ? {} : {ca: input.ca}),
      responseHeaders: [], runAcquisitionLimits: implementation.runAcquisitionLimits,
      admitsApprovalTarget(value: unknown, resource: string) {
        return value !== null && typeof value === 'object' && Array.isArray((value as {fields?: unknown}).fields) &&
          canonicalJson(value) === canonicalJson(physicalTarget(resource, (value as {fields?: unknown}).fields));
      }});
    const {site, authorization} = opened;
    let providerReader: ProviderReader | undefined;
    try {
      if (!nativeReads) material = (preparePhysicalTargets as ReturnType<typeof capturePhysicalTargetConstruction>)(original.sources, declared, physicalTarget);
      const pages = new Map(original.sources.map((source, index) =>
        [source.resource, restSourcePageReader({moon, source, decodePage, request: material!.requests[index]})]));
      // One original Host factory for the complete installation. Selecting a
      // pure resource adapter creates no second retirement/cleanup wrapper.
      providerReader = services('createSourceReader', {installation, sourceInitialization, implementation, site, operation,
        preparePageReader(input: Readonly<{resource: string}>, applySynchronousProjection: RestSourceProjection) {
          const selected = pages.get(input.resource);
          if (selected === undefined) fail('RestSourceReadTargetMismatch');
          return selected(input, applySynchronousProjection);
        }});
      if (providerReader.capacity !== implementation.capacity) fail('RestSourceReaderImplementationMismatch');
      return await createInstalledRowSource({moon, declaration, declared, environment, sourceInitialization,
        environmentWire: environment.wire,
        connectorId: input.installed.connectorId, connectorRegistration: original.registration,
        connectorRevision: original.revision, site, authorization, readOperation: operation,
        physicalTarget: material!.targets,
        bindingCid: cid({connectorId: input.installed.connectorId, connectorRegistration: original.registration,
          connectorRevision: original.revision, originalStringsCid: input.originalStringsCid,
          catalogCid: declared.catalog_cid, runtimeBundleCid, contextCid: authorization.context.contextCid}),
        limits,
        providerReader});
    } catch (cause) {
      throw await retainInstalledHostInitializationFailure(cause,
        {sourceReader: providerReader, sourceProfile: site});
    }
  }
  return Object.freeze({checkProfile: metadata.checkProfile, identityParts: metadata.identityParts,
    publish, load});
}

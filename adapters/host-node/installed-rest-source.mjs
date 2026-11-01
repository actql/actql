// The standard author facade composes existing installation and reader
// owners. Provider declarations supply DATA; no reader lifecycle is here.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {captureInstalledSourceServices} from './installed-host-services.mjs';
import {createInstalledRowSource} from './installed-row-source.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createRestSourceMetadata} from './rest-source-metadata.mjs';
import {restSourcePageReader} from './rest-source-page.mjs';
import {installedJsonSourceReaderLimitNames} from './installed-credential-source-reader.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const cid = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const bounds = Object.freeze({maxPageRows: 'maxRows', maxPageBytes: 'maxResponseBytes',
  maxPages: 'maxPages', maxRows: 'maxTotalRows', maxNodes: 'maxNodes', maxDepth: 'maxDepth',
  maxCursorBytes: 'maxCursorBytes'});

// Select the existing Source constructor before configuration awaits. Its
// original native capacity recipe owns proportional DATA, not callback counts.
function capturePhysicalTargetConstruction(sourceInitialization, moon) {
  const method = Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareReadTarget');
  const capacity = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSourceConstructionCapacity');
  if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function' ||
      !capacity || !Object.hasOwn(capacity, 'value') || typeof capacity.value !== 'function') {
    fail('RestSourceInitializationUnavailable');
  }
  return (sources, declared, physicalTarget) => {
    // One array, one eight-field target object per resource and its original
    // ordered field values. String payloads are borrowed immutable originals.
    let slots = 1n;
    for (const source of sources) {
      const view = declared.views.find(view => view.resource === source.resource);
      if (view === undefined) fail('RestSourceReadTargetMismatch');
      slots += 9n + BigInt(view.fields.length);
    }
    return Reflect.apply(method.value, sourceInitialization, [Object.freeze({
      capacity() {
        return checked(Reflect.apply(capacity.value, moon, [slots, 0n, 0n, slots, 0n, 0n]));
      },
      project() {
        return Object.freeze(sources.map(source => physicalTarget(source.resource,
          declared.views.find(view => view.resource === source.resource).fields)));
      },
    })]);
  };
}

export function createInstalledRestSource(definition, {decodePage} = {}) {
  const metadata = createRestSourceMetadata(definition), original = metadata.definition;
  if (decodePage !== undefined && typeof decodePage !== 'function') fail('InvalidRestSourceTransform');
  const operation = `${original.registration}:rest:read`;
  function captureDeclarationPreparation(sourceInitialization) {
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
      return prepared;
    };
  }
  async function publish(profile, options = {}) {
    const prepare = captureDeclarationPreparation(options.sourceInitialization);
    const input = await metadata.readInputs(profile, {configurationReader: options.configurationReader});
    const {declared} = prepare();
    return metadata.reportPrepared(input, declared);
  }
  async function load(profile, options = {}) {
    // Select original service methods before any configuration await. The
    // service owns normal implementation selection, Site and typed capacity.
    const services = captureInstalledSourceServices(options.installationServices,
      () => fail('RestSourceInstallationServicesUnavailable'));
    const {moon, installation, sourceInitialization, runtimeBundleCid, resolveSecret} = options;
    const prepare = captureDeclarationPreparation(sourceInitialization);
    const preparePhysicalTargets = capturePhysicalTargetConstruction(sourceInitialization, moon);
    if (typeof resolveSecret !== 'function') fail('RestSourceCredentialMaterialUnavailable');
    const input = await metadata.readInputs(profile, {configurationReader: options.configurationReader});
    const {declaration, declared, environment} = prepare();
    const policy = services('sourceReaderImplementationProfile', {installation, sourceInitialization,
      metadataResponses: 0, originUnits: original.origin.length});
    // Author limits constrain this connector's semantics, not its physical
    // funding. The same selected Host profile must cover them in full.
    for (const source of original.sources) {
      for (const [authorName, hostName] of Object.entries(bounds)) {
        const value = source.limits[authorName];
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
      [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'].map(name => [name, policy[name]])),
      maxPages: limits.maxPages, maxResponseBytes: limits.maxPageBytes,
      maxRows: limits.maxPageRows, maxTotalRows: limits.maxCaptureRows, ...pageBounds});
    const implementation = services('sourceReaderImplementation', {installation, sourceInitialization, limits: implementationLimits,
      columnCount: Math.max(...declared.views.map(view => view.fields.length))});
    const targets = new Map(original.sources.map(source => [source.resource, source]));
    const physicalTarget = (resource, fields) => {
      const source = targets.get(resource), view = declared.views.find(view => view.resource === resource);
      if (source === undefined || view === undefined || !Array.isArray(fields) ||
          new Set(fields).size !== fields.length || fields.some(field => !view.fields.includes(field))) {
        fail('RestSourceReadTargetMismatch');
      }
      return Object.freeze({connectorRegistration: original.registration, connectorRevision: original.revision,
        catalogCid: declared.catalog_cid, originalStringsCid: input.originalStringsCid,
        origin: original.origin, path: source.read.path, resource, fields: Object.freeze([...fields])});
    };
    const connection = `${original.registration}:${input.installed.connectorId}`;
    const opened = await services('openRowSite', {installation, sourceInitialization,
      accountConfiguration: input.installed.accountConfigurationWire, connection,
      profile: Object.freeze({...input.site, resourceOrigin: original.origin}), resolveSecret,
      ...(input.ca === undefined ? {} : {ca: input.ca}),
      responseHeaders: [], runAcquisitionLimits: implementation.runAcquisitionLimits,
      admitsApprovalTarget(value, resource) {
        return value !== null && typeof value === 'object' && Array.isArray(value.fields) &&
          canonicalJson(value) === canonicalJson(physicalTarget(resource, value.fields));
      }});
    const {site, authorization} = opened;
    let providerReader;
    try {
      const pages = new Map(original.sources.map(source =>
        [source.resource, restSourcePageReader({moon, source, decodePage})]));
      // One original Host factory for the complete installation. Selecting a
      // pure resource adapter creates no second retirement/cleanup wrapper.
      providerReader = services('createSourceReader', {installation, sourceInitialization, implementation, site, operation,
        preparePageReader(input, applySynchronousProjection) {
          const selected = pages.get(input.resource);
          if (selected === undefined) fail('RestSourceReadTargetMismatch');
          return selected(input, applySynchronousProjection);
        }});
      if (providerReader.capacity !== implementation.capacity) fail('RestSourceReaderImplementationMismatch');
      return await createInstalledRowSource({moon, declaration, declared, environment, sourceInitialization,
        environmentWire: environment.wire,
        connectorId: input.installed.connectorId, connectorRegistration: original.registration,
        connectorRevision: original.revision, site, authorization, readOperation: operation,
        physicalTarget: preparePhysicalTargets(original.sources, declared, physicalTarget),
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

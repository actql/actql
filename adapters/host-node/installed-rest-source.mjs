// The standard author facade composes existing installation and reader
// owners. Provider declarations supply DATA; no reader lifecycle is here.
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {captureInstalledSourceServices} from './installed-host-services.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createRestSourceMetadata} from './rest-source-metadata.mjs';
import {restSourcePageReader} from './rest-source-page.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const cid = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const bounds = Object.freeze({maxPageRows: 'maxRows', maxPageBytes: 'maxResponseBytes',
  maxPages: 'maxPages', maxRows: 'maxTotalRows', maxNodes: 'maxNodes', maxDepth: 'maxDepth',
  maxCursorBytes: 'maxCursorBytes'});

export function createInstalledRestSource(definition, {decodePage} = {}) {
  const metadata = createRestSourceMetadata(definition), original = metadata.definition;
  if (decodePage !== undefined && typeof decodePage !== 'function') fail('InvalidRestSourceTransform');
  const operation = `${original.registration}:rest:read`;
  async function load(profile, options = {}) {
    // Select original service methods before any configuration await. The
    // service owns normal implementation selection, Site and typed capacity.
    const services = captureInstalledSourceServices(options.installationServices,
      () => fail('RestSourceInstallationServicesUnavailable'));
    const {moon, installation, baseEnvironmentWire, runtimeBundleCid, resolveSecret} = options;
    if (typeof resolveSecret !== 'function') fail('RestSourceCredentialMaterialUnavailable');
    const input = await metadata.readInputs(profile, {configurationReader: options.configurationReader});
    const {declaration, declared} = metadata.restore(input.installed, moon);
    const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
    const policy = services('sourceReaderImplementationProfile', {installation,
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
    const implementation = services('sourceReaderImplementation', {installation, limits: policy,
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
    const opened = await services('openRowSite', {installation,
      accountConfiguration: input.installed.accountConfigurationWire, connection,
      profile: Object.freeze({...input.site, resourceOrigin: original.origin}), resolveSecret,
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
      providerReader = services('createSourceReader', {installation, implementation, site, operation,
        preparePageReader(input, applySynchronousProjection) {
          const selected = pages.get(input.resource);
          if (selected === undefined) fail('RestSourceReadTargetMismatch');
          return selected(input, applySynchronousProjection);
        }});
      if (providerReader.capacity !== implementation.capacity) fail('RestSourceReaderImplementationMismatch');
      return await createInstalledRowSource({moon, declaration, declared, environmentWire: environment.wire,
        connectorId: input.installed.connectorId, connectorRegistration: original.registration,
        connectorRevision: original.revision, site, authorization, readOperation: operation, physicalTarget,
        bindingCid: cid({connectorId: input.installed.connectorId, connectorRegistration: original.registration,
          connectorRevision: original.revision, originalStringsCid: input.originalStringsCid,
          catalogCid: declared.catalog_cid, runtimeBundleCid, contextCid: authorization.context.contextCid}),
        limits: {maxPages: Math.max(...original.sources.map(source => source.limits.maxPages)),
          maxPageBytes: Math.max(...original.sources.map(source => source.limits.maxPageBytes)),
          maxPageRows: Math.max(...original.sources.map(source => source.limits.maxPageRows)),
          maxCaptureRows: Math.max(...original.sources.map(source => source.limits.maxRows))},
        providerReader});
    } catch (cause) {
      throw await retainInstalledHostInitializationFailure(cause,
        {sourceReader: providerReader, sourceProfile: site});
    }
  }
  return Object.freeze({checkProfile: metadata.checkProfile, identityParts: metadata.identityParts,
    publish: metadata.publish, load});
}

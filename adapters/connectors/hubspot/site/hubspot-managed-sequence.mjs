// HubSpot protocol DATA on the existing generic Reader's original response
// borrow. Physical sends, charge-before-decode, current and cleanup stay there.
import {checked} from '../../../host-common/runtime-result.mjs';
import {projectHubSpotAccountIdentity, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from './hubspot-account-read.mjs';
import {HUBSPOT_OBJECT_LIST_OPERATION, HUBSPOT_PROPERTIES_READ_OPERATION} from './hubspot-object-read.mjs';
const fail = code => {throw Object.assign(new Error(code), {code});};
const segment = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);
const names = ['hubspotRecheckAccountIdentityJson', 'hubspotProjectProperties',
  'hubspotRecheckPropertyCatalog', 'hubspotPropertyCatalogObjectType',
  'hubspotProjectObjectPage', 'hubspotObjectPageRowsWire', 'hubspotObjectPageMetadataJson',
  'hubspotPreparePropertyResponseSource', 'hubspotPropertyResponseSourceGeometryData',
  'hubspotConsumePropertyResponseSource', 'hubspotRetirePropertyResponseSource'];

export function prepareHubSpotManagedSequence({moon, originalPortalId, originalCatalog,
  objectType, properties, limits, authorizeMetadata, responseCapacity}) {
  if (names.some(name => typeof moon?.[name] !== 'function') ||
      typeof authorizeMetadata !== 'function' || typeof responseCapacity !== 'function' ||
      !Array.isArray(properties) || new Set(properties).size !== properties.length ||
      properties.some(name => typeof name !== 'string' || !name || name === 'id' || name.includes(',')) ||
      properties.length > limits.maxColumns || objectType === '.' || objectType === '..' ||
      typeof objectType !== 'string' || !objectType || objectType.length > limits.maxNameUnits ||
      properties.reduce((n, name) => n + name.length, 0) > limits.maxNameUnits ||
      moon.hubspotPropertyCatalogObjectType(originalCatalog) !== objectType) fail('InvalidHubSpotManagedSequence');
  const provider = Object.freeze(Object.fromEntries(names.map(name => [name, moon[name]])));
  const selected = Object.freeze(properties.slice());
  const bodies = [], ids = new Set(), cursors = new Set();
  const base = `/crm/v3/objects/${segment(objectType)}`;
  const schemaPath = `/crm/v3/properties/${segment(objectType)}`;
  let started = false, retired = false, requestCount = 0, pages = 0, rowCount = 0, sequence;
  let propertySource, propertyGeometry = Object.freeze([]);
  const current = () => {if (retired) fail('HubSpotManagedSequenceClosed');};
  const request = (path, query = []) => Object.freeze({method: 'GET', path, query,
    headers: Object.freeze([Object.freeze(['accept', 'application/json'])]), responseHeaders: Object.freeze([])});
  sequence = Object.freeze({
    responseCapacity(bytes, body, path, receivedBytes, responseCount) {
      if (this !== sequence) fail('ForeignHubSpotManagedSequence');current();
      if (responseCount !== bodies.length + 1 || bytes !== body.byteLength ||
          bytes > limits.maxResponseBytes) fail('ForeignHubSpotManagedResponse');
      bodies.push(bytes);
      if (bodies.reduce((total, value) => total + BigInt(value), 0n) !== receivedBytes) {
        fail('ForeignHubSpotManagedResponse');
      }
      if (bodies.length === 2) {
        if (propertySource !== undefined || path !== schemaPath) fail('ForeignHubSpotManagedResponse');
        // Keep the Result itself. A Source refusal must not leapfrog the
        // original accepted/status check in project(response) below.
        propertySource = provider.hubspotPreparePropertyResponseSource(body, path, objectType,
          limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, limits.maxProperties, limits.maxNameUnits);
        propertyGeometry = Object.freeze([...provider.hubspotPropertyResponseSourceGeometryData(propertySource)]);
      }
      // The same generic Reader retained and charged this body first. The
      // quote includes every earlier/failed constructor until real retirement.
      return responseCapacity(Object.freeze(bodies.slice()), receivedBytes, propertyGeometry);
    },
    async read(context) {
      if (this !== sequence || started) fail('ForeignHubSpotManagedSequence');current();started = true;
      const receive = async (operation, path, query, project) => {
        current();context.signal.throwIfAborted();
        if (requestCount >= limits.maxRequests) fail('HubSpotReadRequestLimit');
        const index = requestCount++;
        const supplied = operation === HUBSPOT_OBJECT_LIST_OPERATION ? undefined
          : await authorizeMetadata(operation, index, context.signal);
        current();context.signal.throwIfAborted();
        return await context.readChild({operation, prepare() {
          current();return Object.freeze({original: Object.freeze({}),
            ...(supplied === undefined ? {} : supplied), request: request(path, query),
            project(response) {
              current();if (!response.accepted || response.statusCode !== 200) fail('HubSpotReadRejected');
              return project(response.body);
            }});
        }});
      };
      const recheckProperties = async () => {
        await receive(HUBSPOT_PROPERTIES_READ_OPERATION, schemaPath, [], body => {
          const catalog = propertySource !== undefined && requestCount === 2
            ? checked(provider.hubspotConsumePropertyResponseSource(propertySource, schemaPath, body))
            : checked(provider.hubspotProjectProperties(body, objectType,
              limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, limits.maxProperties, limits.maxNameUnits));
          checked(provider.hubspotRecheckPropertyCatalog(originalCatalog, catalog, limits.maxProperties));
        });
        await context.consumeObservation();current();
      };
      await receive(HUBSPOT_ACCOUNT_DETAILS_OPERATION, '/account-info/v3/details', [], body =>
        projectHubSpotAccountIdentity({moon: provider, body, originalPortalId, limits}));
      await context.consumeObservation();current();
      await recheckProperties();
      let after;
      do {
        if (pages >= limits.maxPages) fail('HubSpotReadPageLimit');
        const pageRows = Math.min(limits.perPage, limits.maxRows - rowCount);
        if (pageRows <= 0) fail('HubSpotReadRowLimit');
        const query = [['archived', 'false'], ['limit', String(pageRows)], ['properties', selected.join(',')]];
        if (after !== undefined) query.push(['after', after]);
        const page = await receive(HUBSPOT_OBJECT_LIST_OPERATION, base, query, body => {
          const original = checked(provider.hubspotProjectObjectPage(body, originalCatalog, selected,
            limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, pageRows, limits.maxColumns,
            limits.maxCursorUnits, limits.maxValueNodes, limits.maxValueTextBytes));
          const metadata = JSON.parse(provider.hubspotObjectPageMetadataJson(original));
          const wire = checked(provider.hubspotObjectPageRowsWire(original, limits.maxRowsWireBytes,
            limits.maxRowsWireNodes, limits.maxRowsWireDepth));
          const rows = JSON.parse(wire);
          for (const row of rows) {if (ids.has(row.id)) fail('HubSpotReadDuplicateRecord');ids.add(row.id);}
          return Object.freeze({metadata, rows});
        });
        if (rowCount + page.metadata.rowCount > limits.maxRows) fail('HubSpotReadRowLimit');
        await context.consumePage(page.rows);current();
        pages++;rowCount += page.metadata.rowCount;after = page.metadata.nextAfter ?? undefined;
        if (after !== undefined) {
          if (cursors.has(after)) fail('HubSpotReadCursorCycle');cursors.add(after);
          if (rowCount >= limits.maxRows) fail('HubSpotReadRowLimit');
        }
      } while (after !== undefined);
      await recheckProperties();current();context.signal.throwIfAborted();
    },
    retire() {
      if (this !== sequence) fail('ForeignHubSpotManagedSequence');
      if (retired) return true;
      if (propertySource !== undefined) provider.hubspotRetirePropertyResponseSource(propertySource);
      propertySource = undefined;propertyGeometry = undefined;retired = true;
      bodies.length = 0;ids.clear();cursors.clear();return true;
    },
  });
  return sequence;
}

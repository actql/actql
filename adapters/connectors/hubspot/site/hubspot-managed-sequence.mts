// HubSpot protocol DATA on the existing generic Reader's original response
// borrow. Physical sends, charge-before-decode, current and cleanup stay there.
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {projectHubSpotAccountIdentity, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from './hubspot-account-read.mjs';
import {HUBSPOT_OBJECT_LIST_OPERATION, HUBSPOT_PROPERTIES_READ_OPERATION} from './hubspot-object-read.mjs';
import type {readHubSpotObjects} from './hubspot-object-read.mjs';
import type {HubSpotResponse} from './hubspot-account-read.mjs';

type ObjectRead = Parameters<typeof readHubSpotObjects>[0];
type Native = ObjectRead['moon'] & Readonly<{
  hubspotPreparePropertyResponseSource(bytes: Uint8Array, path: string, objectType: string,
    maxBytes: number, maxNodes: number, maxDepth: number, maxProperties: number, maxNameUnits: number): unknown;
  hubspotPropertyResponseSourceGeometryData(original: unknown): readonly number[];
  hubspotConsumePropertyResponseSource(original: unknown, path: string, bytes: Uint8Array): unknown;
  hubspotRetirePropertyResponseSource(original: unknown): void;
}>;
type MetadataOperation = typeof HUBSPOT_ACCOUNT_DETAILS_OPERATION | typeof HUBSPOT_PROPERTIES_READ_OPERATION;
type Operation = MetadataOperation | typeof HUBSPOT_OBJECT_LIST_OPERATION;
type SuppliedAuthorization = Readonly<{originalAuthorization: unknown; authorization: unknown; verifyCurrent?(): unknown}>;
type Options = Pick<ObjectRead, 'originalPortalId' | 'originalCatalog' | 'objectType' | 'properties' | 'limits'> &
  Readonly<{moon: Native; authorizeMetadata?(operation: MetadataOperation, index: number, signal: AbortSignal):
    SuppliedAuthorization | PromiseLike<SuppliedAuthorization>;
  responseCapacity(bodies: readonly number[], receivedBytes: bigint, geometry: readonly number[] | undefined): unknown}>;
type Query = readonly (readonly [string, string])[];
type Request = Readonly<{method: string; path: string; query: Query;
  headers: readonly (readonly string[])[]; responseHeaders: readonly string[]}>;
type Response = Pick<HubSpotResponse, 'accepted' | 'statusCode' | 'body'>;
type ReadChild<Value> = Readonly<{operation: Operation; prepare():
  Readonly<{original: object; request: Request; project(response: Response): Value}> &
  Partial<SuppliedAuthorization>}>;
type Row = Readonly<Record<string, unknown> & {id: string}>;
type Context = Readonly<{signal: AbortSignal; readChild<Value>(options: ReadChild<Value>): Promise<Value>;
  consumeObservation(): Promise<void>; consumePage(rows: readonly Row[]): Promise<void>}>;
type Sequence = Readonly<{responseCapacity(bytes: number, body: Uint8Array, path: string, receivedBytes: bigint,
  responseCount: number): unknown; read(context: Context): Promise<void>; retire(): boolean}>;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const segment = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);
const names = ['hubspotRecheckAccountIdentityJson', 'hubspotProjectProperties',
  'hubspotRecheckPropertyCatalog', 'hubspotPropertyCatalogObjectType',
  'hubspotProjectObjectPage', 'hubspotObjectPageRowsWire', 'hubspotObjectPageProgress',
  'hubspotPreparePropertyResponseSource', 'hubspotPropertyResponseSourceGeometryData',
  'hubspotConsumePropertyResponseSource', 'hubspotRetirePropertyResponseSource'] as const;

export function prepareHubSpotManagedSequence({moon, originalPortalId, originalCatalog,
  objectType, properties, limits, authorizeMetadata, responseCapacity}: Options) {
  if (names.some(name => typeof moon?.[name] !== 'function') ||
      authorizeMetadata !== undefined && typeof authorizeMetadata !== 'function' || typeof responseCapacity !== 'function' ||
      !Array.isArray(properties) || new Set(properties).size !== properties.length ||
      properties.some(name => typeof name !== 'string' || !name || name === 'id' || name.includes(',')) ||
      properties.length > limits.maxColumns || objectType === '.' || objectType === '..' ||
      typeof objectType !== 'string' || !objectType || objectType.length > limits.maxNameUnits ||
      properties.reduce((n, name) => n + name.length, 0) > limits.maxNameUnits ||
      moon.hubspotPropertyCatalogObjectType(originalCatalog) !== objectType) fail('InvalidHubSpotManagedSequence');
  const provider = Object.freeze(Object.fromEntries(names.map(name => [name, moon[name]]))) as Native;
  const selected = Object.freeze(properties.slice());
  const bodies: number[] = [], ids = new Set<string>(), cursors = new Set<string>();
  const base = `/crm/v3/objects/${segment(objectType)}`;
  const schemaPath = `/crm/v3/properties/${segment(objectType)}`;
  let started = false, retired = false, requestCount = 0, pages = 0, rowCount = 0, sequence: Sequence;
  let propertySource: unknown, propertyGeometry: readonly number[] | undefined = Object.freeze([]);
  const current = () => {if (retired) fail('HubSpotManagedSequenceClosed');};
  const request = (path: string, query: Query = []) => Object.freeze({method: 'GET', path, query,
    headers: Object.freeze([Object.freeze(['accept', 'application/json'])]), responseHeaders: Object.freeze([])});
  sequence = Object.freeze({
    responseCapacity(bytes: number, body: Uint8Array, path: string, receivedBytes: bigint, responseCount: number) {
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
    async read(context: Context) {
      if (this !== sequence || started) fail('ForeignHubSpotManagedSequence');current();started = true;
      const receive = async <Value,>(operation: Operation, path: string, query: Query, project: (body: Uint8Array) => Value) => {
        current();context.signal.throwIfAborted();
        if (requestCount >= limits.maxRequests) fail('HubSpotReadRequestLimit');
        const index = requestCount++;
        const supplied = operation === HUBSPOT_OBJECT_LIST_OPERATION || authorizeMetadata === undefined ? undefined
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
      let after: string | undefined;
      do {
        if (pages >= limits.maxPages) fail('HubSpotReadPageLimit');
        const pageRows = Math.min(limits.perPage, limits.maxRows - rowCount);
        if (pageRows <= 0) fail('HubSpotReadRowLimit');
        const query: [string, string][] = [['archived', 'false'], ['limit', String(pageRows)], ['properties', selected.join(',')]];
        if (after !== undefined) query.push(['after', after]);
        const page = await receive(HUBSPOT_OBJECT_LIST_OPERATION, base, query, body => {
          const original = checked(provider.hubspotProjectObjectPage(body, originalCatalog, selected,
            limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, pageRows, limits.maxColumns,
            limits.maxCursorUnits, limits.maxValueNodes, limits.maxValueTextBytes));
          const progress = provider.hubspotObjectPageProgress(original);
          const wire = checked(provider.hubspotObjectPageRowsWire(original, limits.maxRowsWireBytes,
            limits.maxRowsWireNodes, limits.maxRowsWireDepth)) as string;
          const rows = JSON.parse(wire) as readonly Row[];
          for (const row of rows) {if (ids.has(row.id)) fail('HubSpotReadDuplicateRecord');ids.add(row.id);}
          return Object.freeze({count: runtimeField(progress, 0) as number, nextAfter: runtimeField(progress, 1) as string, rows});
        });
        if (rowCount + page.count > limits.maxRows) fail('HubSpotReadRowLimit');
        await context.consumePage(page.rows);current();
        pages++;rowCount += page.count;after = page.nextAfter === '' ? undefined : page.nextAfter;
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

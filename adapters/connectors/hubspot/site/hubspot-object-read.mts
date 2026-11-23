// Sequence one original accounted acquisition. Provider meaning stays in the
// compiled HubSpot projection; authority, nominal uses and physical cleanup
// remain with the existing Host/Credential/RowRun owners.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {observeHubSpotAccount, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from './hubspot-account-read.mjs';
import type {HubSpotInvocation, HubSpotObservationCause, HubSpotResourceCall, HubSpotResourceInput, HubSpotResponse}
  from './hubspot-account-read.mjs';

type Native = Readonly<{
  hubspotRecheckAccountIdentityJson(bytes: Uint8Array, originalPortalId: string, maxBytes: number, maxNodes: number,
    maxDepth: number): string;
  hubspotProjectProperties(bytes: Uint8Array, originalObjectType: string, maxBytes: number, maxNodes: number,
    maxDepth: number, maxProperties: number, maxNameUnits: number): unknown;
  hubspotRecheckPropertyCatalog(original: unknown, current: unknown, maxProperties: number): unknown;
  hubspotPropertyCatalogObjectType(catalog: unknown): string;
  hubspotProjectObjectPage(bytes: Uint8Array, catalog: unknown, names: readonly string[], maxBytes: number,
    maxNodes: number, maxDepth: number, maxRows: number, maxColumns: number,
    maxCursorUnits: number, maxValueNodes: number, maxValueTextBytes: number): unknown;
  hubspotObjectPageRowsWire(page: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  hubspotObjectPageMetadataJson(page: unknown): string;
}>;
type Limits = Readonly<Record<(typeof limitFields)[number], number>>;
type Callbacks = Readonly<{authorizationFor(original: Readonly<{operation: string; index: number; objectType: string}>): unknown;
  current(operation: string): unknown; chargeResponse(body: HubSpotResponse['body']): unknown;
  consumeObservation(charge: unknown): unknown; callResource: HubSpotResourceCall;
  consumePage(rows: readonly Row[], original: Readonly<{charge: unknown}>): unknown}>;
type Options = Omit<Callbacks, 'callResource'> & Readonly<{moon: Native; originalPortalId: string;
  originalCatalog: unknown; initialAuthorization: unknown; credential: {binding?: unknown}; limits: Limits;
  signal?: AbortSignal; callResource?: HubSpotResourceCall; objectType: string; properties: readonly string[]}>;
type Row = Readonly<Record<string, unknown> & {id: string}>;
type PageMetadata = Readonly<{rowCount: number; nextAfter: string | null}>;

export const HUBSPOT_PROPERTIES_READ_OPERATION = 'hubspot:properties:read';
export const HUBSPOT_OBJECT_LIST_OPERATION = 'hubspot:objects:list';
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const exports = ['hubspotRecheckAccountIdentityJson', 'hubspotProjectProperties',
  'hubspotRecheckPropertyCatalog', 'hubspotPropertyCatalogObjectType',
  'hubspotProjectObjectPage', 'hubspotObjectPageRowsWire', 'hubspotObjectPageMetadataJson'] as const;
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxPages', 'maxRows', 'maxRequests', 'perPage', 'maxColumns',
  'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes',
  'maxRowsWireNodes', 'maxRowsWireDepth'] as const;
const segment = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);

// Private original responses are retained even when later current checks,
// projection, admission or final schema verification fail. This is not a retry
// decision, a Source completion, or an ACK of persistence/physical retirement.
export class HubSpotObjectReadFailure extends Error {
  declare readonly code: unknown;
  declare readonly observations: readonly HubSpotResponse[];

  constructor(cause: HubSpotObservationCause, observations: readonly HubSpotResponse[]) {
    super(typeof cause?.message === 'string' ? cause.message : 'HubSpotObjectReadFailed', {cause});
    this.name = typeof cause?.name === 'string' ? cause.name : 'Error';
    this.code = cause?.code ?? 'HubSpotObjectReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// authorizationFor returns the already authorized original nominal use for
// each explicitly registered operation; it must not derive identity/schema
// permission from a data-read grant. current(operation) rechecks that operation
// through the trusted installed Host before/after awaits and before sending.
// No operation grants, finish/capture, binding close, or fallback are created.
export async function readHubSpotObjects({moon, originalPortalId, originalCatalog,
  objectType, properties, initialAuthorization, credential, authorizationFor,
  limits, current, chargeResponse, consumeObservation, consumePage, signal,
  callResource = callHttpsCredentialResource}: Options) {
  if (exports.some(name => typeof moon?.[name] !== 'function') ||
      typeof objectType !== 'string' || !objectType.length ||
      objectType === '.' || objectType === '..' ||
      !Array.isArray(properties) || properties.some(name => typeof name !== 'string' ||
        !name.length || name === 'id' || name.includes(',')) ||
      new Set(properties).size !== properties.length ||
      !limitFields.every(key => positive(limits?.[key])) ||
      properties.length > limits.maxColumns || objectType.length > limits.maxNameUnits ||
      properties.reduce((total, name) => total + name.length, 0) > limits.maxNameUnits ||
      [authorizationFor, current, chargeResponse, consumeObservation, consumePage, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidHubSpotObjectRead');
  const provider = Object.freeze(Object.fromEntries(exports.map(name => [name, moon[name]]))) as Native;
  if (provider.hubspotPropertyCatalogObjectType(originalCatalog) !== objectType) {
    fail('ForeignHubSpotObjectCatalog');
  }
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse,
      consumeObservation, consumePage, callResource}}) as HubSpotInvocation<Limits, Callbacks>;
  if ((context.scope as {operation?: unknown}).operation !== HUBSPOT_ACCOUNT_DETAILS_OPERATION) fail('ForeignHubSpotAccountOperation');
  const selected = Object.freeze(properties.slice());
  const bound = context.limits;
  const base = `/crm/v3/objects/${segment(objectType)}`;
  const schemaPath = `/crm/v3/properties/${segment(objectType)}`;
  const observations: HubSpotResponse[] = [], cursors = new Set<string>(), ids = new Set<string>();
  let requests = 0, pages = 0, rowCount = 0;
  const verify = async (operation: string) => {
    signal?.throwIfAborted();
    await context.callbacks.current(operation);
    signal?.throwIfAborted();
  };
  const slot = () => {
    if (requests >= bound.maxRequests) fail('HubSpotReadRequestLimit');
    return requests++;
  };
  const authorization = async (operation: string) => {
    await verify(operation);
    const next = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation, index: slot(), objectType})));
    if ((next.scope as {operation?: unknown}).operation !== operation || !invocationBindingsMatch(next.scope, context.scope)) {
      fail('ForeignHubSpotReadAuthorization');
    }
    await verify(operation);
    return next;
  };
  const receive = async (operation: string, path: string, query: readonly (readonly [string, string])[]) => {
    const auth = await authorization(operation);
    const response = await invokeScopedCredentialOperation({authorization: auth,
      credential: context.credential,
      callResource: (options: HubSpotResourceInput) => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(operation)}),
      operation, method: 'GET', path, query, headers: [['accept', 'application/json']],
      responseHeaders: [], maxResponseBytes: bound.maxResponseBytes, signal}) as HubSpotResponse;
    observations.push(response);
    // Complete received bytes are charged even when HTTP/current later refuses.
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify(operation);
    if (!response.accepted || response.statusCode !== 200) fail('HubSpotReadRejected');
    return {response, charge};
  };
  const recheckProperties = async () => {
    const {response, charge} = await receive(HUBSPOT_PROPERTIES_READ_OPERATION, schemaPath, []);
    const catalog = checked(provider.hubspotProjectProperties(response.body, objectType,
      bound.maxResponseBytes, bound.maxNodes, bound.maxDepth,
      bound.maxProperties, bound.maxNameUnits));
    checked(provider.hubspotRecheckPropertyCatalog(originalCatalog, catalog, bound.maxProperties));
    await context.callbacks.consumeObservation(charge);
    await verify(HUBSPOT_PROPERTIES_READ_OPERATION);
  };
  try {
    slot();
    const account = await observeHubSpotAccount({moon: provider, originalPortalId,
      authorization: context.authorization, credential: context.credential,
      limits: {maxResponseBytes: bound.maxResponseBytes,
        maxNodes: bound.maxNodes, maxDepth: bound.maxDepth},
      current: () => verify(HUBSPOT_ACCOUNT_DETAILS_OPERATION),
      chargeResponse: context.callbacks.chargeResponse,
      consumeObservation: context.callbacks.consumeObservation,
      signal, callResource: context.callbacks.callResource});
    observations.push(account.response);
    await recheckProperties();
    let after: string | undefined;
    do {
      if (pages >= bound.maxPages) fail('HubSpotReadPageLimit');
      const pageRows = Math.min(bound.perPage, bound.maxRows - rowCount);
      if (pageRows <= 0) fail('HubSpotReadRowLimit');
      const query: [string, string][] = [['archived', 'false'], ['limit', String(pageRows)],
        ['properties', selected.join(',')]];
      if (after !== undefined) query.push(['after', after]);
      const {response, charge} = await receive(HUBSPOT_OBJECT_LIST_OPERATION, base, query);
      const page = checked(provider.hubspotProjectObjectPage(response.body,
        originalCatalog, selected, bound.maxResponseBytes, bound.maxNodes,
        bound.maxDepth, pageRows,
        bound.maxColumns, bound.maxCursorUnits, bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.hubspotObjectPageMetadataJson(page)) as PageMetadata;
      if (rowCount + metadata.rowCount > bound.maxRows) fail('HubSpotReadRowLimit');
      const rows = JSON.parse(checked(provider.hubspotObjectPageRowsWire(page,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)) as string) as readonly Row[];
      for (const row of rows) {
        if (ids.has(row.id)) fail('HubSpotReadDuplicateRecord');
        ids.add(row.id);
      }
      await context.callbacks.consumePage(rows, Object.freeze({charge}));
      await verify(HUBSPOT_OBJECT_LIST_OPERATION);
      pages++; rowCount += metadata.rowCount;
      after = metadata.nextAfter ?? undefined;
      if (after !== undefined) {
        if (cursors.has(after)) fail('HubSpotReadCursorCycle');
        cursors.add(after);
        if (rowCount >= bound.maxRows) fail('HubSpotReadRowLimit');
      }
    } while (after !== undefined);
    // Keep admission distinct from the original Host's final Source capture.
    await recheckProperties();
    await verify(HUBSPOT_OBJECT_LIST_OPERATION);
    return Object.freeze({pages, rowCount, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    if ((cause as HubSpotObservationCause)?.observation && !observations.includes((cause as HubSpotObservationCause)!.observation!)) {
      observations.push((cause as HubSpotObservationCause)!.observation!);
    }
    throw new HubSpotObjectReadFailure(cause as HubSpotObservationCause, observations);
  }
}

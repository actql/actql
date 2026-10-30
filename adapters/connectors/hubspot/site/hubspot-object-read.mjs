// Sequence one original accounted acquisition. Provider meaning stays in the
// compiled HubSpot projection; authority, nominal uses and physical cleanup
// remain with the existing Host/Credential/RowRun owners.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {observeHubSpotAccount, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from './hubspot-account-read.mjs';

export const HUBSPOT_PROPERTIES_READ_OPERATION = 'hubspot:properties:read';
export const HUBSPOT_OBJECT_LIST_OPERATION = 'hubspot:objects:list';
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const fail = code => { throw Object.assign(new Error(code), {code}); };
const exports = ['hubspotRecheckAccountIdentityJson', 'hubspotProjectProperties',
  'hubspotRecheckPropertyCatalog', 'hubspotPropertyCatalogObjectType',
  'hubspotProjectObjectPage', 'hubspotObjectPageRowsWire', 'hubspotObjectPageMetadataJson'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxPages', 'maxRows', 'maxRequests', 'perPage', 'maxColumns',
  'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes',
  'maxRowsWireNodes', 'maxRowsWireDepth'];
const segment = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);

// Private original responses are retained even when later current checks,
// projection, admission or final schema verification fail. This is not a retry
// decision, a Source completion, or an ACK of persistence/physical retirement.
export class HubSpotObjectReadFailure extends Error {
  constructor(cause, observations) {
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
  callResource = callHttpsCredentialResource}) {
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
  const provider = Object.freeze(Object.fromEntries(exports.map(name => [name, moon[name]])));
  if (provider.hubspotPropertyCatalogObjectType(originalCatalog) !== objectType) {
    fail('ForeignHubSpotObjectCatalog');
  }
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse,
      consumeObservation, consumePage, callResource}});
  if (context.scope.operation !== HUBSPOT_ACCOUNT_DETAILS_OPERATION) fail('ForeignHubSpotAccountOperation');
  const selected = Object.freeze(properties.slice());
  const bound = context.limits;
  const base = `/crm/v3/objects/${segment(objectType)}`;
  const schemaPath = `/crm/v3/properties/${segment(objectType)}`;
  const observations = [], cursors = new Set(), ids = new Set();
  let requests = 0, pages = 0, rowCount = 0;
  const verify = async operation => {
    signal?.throwIfAborted();
    await context.callbacks.current(operation);
    signal?.throwIfAborted();
  };
  const slot = () => {
    if (requests >= bound.maxRequests) fail('HubSpotReadRequestLimit');
    return requests++;
  };
  const authorization = async operation => {
    await verify(operation);
    const next = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation, index: slot(), objectType})));
    if (next.scope.operation !== operation || !invocationBindingsMatch(next.scope, context.scope)) {
      fail('ForeignHubSpotReadAuthorization');
    }
    await verify(operation);
    return next;
  };
  const receive = async (operation, path, query) => {
    const auth = await authorization(operation);
    const response = await invokeScopedCredentialOperation({authorization: auth,
      credential: context.credential,
      callResource: options => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(operation)}),
      operation, method: 'GET', path, query, headers: [['accept', 'application/json']],
      responseHeaders: [], maxResponseBytes: bound.maxResponseBytes, signal});
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
    let after;
    do {
      if (pages >= bound.maxPages) fail('HubSpotReadPageLimit');
      const pageRows = Math.min(bound.perPage, bound.maxRows - rowCount);
      if (pageRows <= 0) fail('HubSpotReadRowLimit');
      const query = [['archived', 'false'], ['limit', String(pageRows)],
        ['properties', selected.join(',')]];
      if (after !== undefined) query.push(['after', after]);
      const {response, charge} = await receive(HUBSPOT_OBJECT_LIST_OPERATION, base, query);
      const page = checked(provider.hubspotProjectObjectPage(response.body,
        originalCatalog, selected, bound.maxResponseBytes, bound.maxNodes,
        bound.maxDepth, pageRows,
        bound.maxColumns, bound.maxCursorUnits, bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.hubspotObjectPageMetadataJson(page));
      if (rowCount + metadata.rowCount > bound.maxRows) fail('HubSpotReadRowLimit');
      const rows = JSON.parse(checked(provider.hubspotObjectPageRowsWire(page,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
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
    if (cause?.observation && !observations.includes(cause.observation)) {
      observations.push(cause.observation);
    }
    throw new HubSpotObjectReadFailure(cause, observations);
  }
}

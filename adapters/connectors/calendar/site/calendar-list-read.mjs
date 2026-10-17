// Calendar API sequencing only. Catalog meaning stays with the compiled
// provider, and Account/credential/RowRun/current/cleanup retain their owners.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';

export const CALENDAR_LIST_OPERATION = 'calendar:calendars:list';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const providerExports = ['calendarProjectCalendarList', 'calendarListRowsWire', 'calendarListMetadataJson'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxPages', 'maxRows',
  'maxRequests', 'perPage', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const columns = new Set(['id', 'summary', 'time_zone', 'access_role']);
const selectedFields = 'kind,items(id,summary,timeZone,accessRole,deleted),nextPageToken';

// Keep original received responses and the unchanged cause even if charging,
// projection/current checks or page delivery fail. This is not a completion or
// physical-release ACK, and does not infer whether a failed send happened.
export class CalendarListReadFailure extends Error {
  constructor(cause, observations) {
    super('CalendarListReadFailed', {cause});
    this.code = 'CalendarListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

export async function readCalendarList({moon, names, initialAuthorization,
  credential, authorizationFor, limits, current, chargeResponse, consumePage,
  signal, callResource = callHttpsCredentialResource}) {
  if (providerExports.some(name => typeof moon?.[name] !== 'function') ||
      !Array.isArray(names) || names.some(name => !columns.has(name)) ||
      new Set(names).size !== names.length ||
      !limitFields.every(key => positive(limits?.[key])) || limits.perPage > 250 ||
      limits.maxPages > limits.maxRequests ||
      [authorizationFor, current, chargeResponse, consumePage, callResource].some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidCalendarListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => [name, moon[name]])));
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse, consumePage, callResource}});
  if (context.scope.operation !== CALENDAR_LIST_OPERATION) fail('ForeignCalendarListOperation');
  // The original Source key is observed even when the query projects it away.
  // Projection cannot hide a duplicate calendar from whole-read validation.
  const selected = Object.freeze(['id', ...names.filter(name => name !== 'id')]);
  const bound = context.limits, observations = [], cursors = new Set(), ids = new Set();
  let pages = 0, requests = 0, rowCount = 0, token;
  const verify = async () => {
    signal?.throwIfAborted();
    await context.callbacks.current(CALENDAR_LIST_OPERATION);
    signal?.throwIfAborted();
  };
  try {
    do {
      await verify();
      if (pages >= bound.maxPages) fail('CalendarListPageLimit');
      if (requests >= bound.maxRequests) fail('CalendarListRequestLimit');
      if (rowCount >= bound.maxRows) fail('CalendarListRowLimit');
      const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
        Object.freeze({operation: CALENDAR_LIST_OPERATION, index: requests++})));
      if (authorization.scope.operation !== CALENDAR_LIST_OPERATION ||
          !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignCalendarListAuthorization');
      await verify();
      const query = [['maxResults', String(Math.min(bound.perPage, bound.maxRows - rowCount))],
        ['showHidden', 'true'], ['showDeleted', 'false'], ['fields', selectedFields]];
      if (token !== undefined) query.push(['pageToken', token]);
      const response = await invokeScopedCredentialOperation({authorization,
        credential: context.credential,
        callResource: options => context.callbacks.callResource({...options, currentBeforeSend: verify}),
        operation: CALENDAR_LIST_OPERATION, method: 'GET',
        path: '/calendar/v3/users/me/calendarList', query,
        headers: [['accept', 'application/json']], responseHeaders: [],
        maxResponseBytes: bound.maxResponseBytes, signal});
      observations.push(response);
      // Count every complete response before checking status/current/type.
      const charge = await context.callbacks.chargeResponse(response.body);
      await verify();
      if (!response.accepted || response.statusCode !== 200) fail('CalendarListReadRejected');
      const page = checked(provider.calendarProjectCalendarList(response.body,
        bound.maxResponseBytes, bound.maxNodes, bound.maxDepth,
        Math.min(bound.perPage, bound.maxRows - rowCount), bound.maxCursorUnits,
        bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.calendarListMetadataJson(page));
      // Metadata is the sealed provider's projection of the entire page, not
      // a transport-owned parser or the selected (possibly keyless) columns.
      if (rowCount + metadata.rowCount > bound.maxRows) fail('CalendarListRowLimit');
      for (const id of metadata.ids) {
        if (ids.has(id)) fail('CalendarListDuplicateRecord');
        ids.add(id);
      }
      token = metadata.nextPageToken ?? undefined;
      if (token !== undefined && cursors.has(token)) fail('CalendarListCursorCycle');
      if (token !== undefined) cursors.add(token);
      const rows = JSON.parse(checked(provider.calendarListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
      await context.callbacks.consumePage(rows, Object.freeze({charge}));
      await verify();
      pages++; rowCount += metadata.rowCount;
    } while (token !== undefined);
    await verify();
    // Only the original RowRun caller may finish/capture, after this returns.
    return Object.freeze({pages, rowCount, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    throw new CalendarListReadFailure(cause, observations);
  }
}

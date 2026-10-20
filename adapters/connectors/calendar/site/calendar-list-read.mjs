// Calendar API sequencing only. Catalog meaning stays with the compiled
// provider, and Account/credential/RowRun/current/cleanup retain their owners.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';

export const CALENDAR_LIST_OPERATION = 'calendar:calendars:list';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const providerExports = ['calendarProjectCalendarList', 'calendarListRowsWire', 'calendarListMetadataJson', 'calendarListColumnNames'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxPages', 'maxRows',
  'maxRequests', 'perPage', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
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

function prepareCalendarListRead({moon, names, initialAuthorization,
  credential, authorizationFor, limits, current, chargeResponse, consumePage,
  signal, callResource = callHttpsCredentialResource}) {
  if (!Array.isArray(names) ||
      new Set(names).size !== names.length ||
      [authorizationFor, current, chargeResponse, consumePage, callResource].some(value => typeof value !== 'function') ||
      !credential || typeof credential !== 'object' ||
      !limits || typeof limits !== 'object') fail('InvalidCalendarListRead');
  // Read trusted external properties once, then validate and use only that
  // original snapshot. Validation must not re-read a changing provider/limit.
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => [name, moon?.[name]])));
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse, consumePage, callResource}});
  if (providerExports.some(name => typeof provider[name] !== 'function') ||
      !limitFields.every(key => positive(context.limits[key])) || context.limits.perPage > 250 ||
      context.limits.maxPages > context.limits.maxRequests ||
      !context.credential.binding || typeof context.credential.binding !== 'object') fail('InvalidCalendarListRead');
  const declaredColumns = provider.calendarListColumnNames();
  if (names.some(name => !declaredColumns.includes(name))) fail('InvalidCalendarListRead');
  if (context.scope.operation !== CALENDAR_LIST_OPERATION) fail('ForeignCalendarListOperation');
  // The existing RowRun admits the complete declared row. Retain all four
  // checked cells even when a query projects columns away; ordinary Relation
  // projection follows capture. Never hide a key or required cell here.
  const selected = Object.freeze(declaredColumns.slice());
  return Object.freeze({provider, context, selected, signal});
}

async function executeCalendarListRead({provider, context, selected, signal}, received) {
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
      received?.(response);
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

export async function readCalendarList(options) {
  return executeCalendarListRead(prepareCalendarListRead(options));
}

const readers = new WeakMap();
function originalReader(value) {
  const state = readers.get(value);
  if (!state) fail('ForeignCalendarListReader');
  return state;
}

// A private physical-reader handle, not a new execution/cleanup authority.
// Acquire and retain it before binding the original RowRun response observer.
// Factory failure leaves the caller's already-acquired resources with it.
export function createCalendarListReader(options) {
  const original = prepareCalendarListRead(options);
  const stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal
    : AbortSignal.any([original.signal, stop.signal]);
  const prepared = Object.freeze({...original, signal});
  const state = {prepared, stop, phase: 'ready', receivedResponses: 0,
    receivedBodyBytes: 0n};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('CalendarListReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeCalendarListRead(state.prepared, response => {
          state.receivedResponses++;
          state.receivedBodyBytes += BigInt(response.body.byteLength);
        });
        state.phase = 'succeeded';
        return result;
      } catch (cause) {
        state.phase = 'failed';
        throw cause;
      }
    },
    requestStop(reason) {
      const state = originalReader(this);
      // Request cancellation only. Neither stop nor promise settlement owns
      // credential close, original observation release or RowRun settlement.
      state.stop.abort(reason);
    },
    observe() {
      const state = originalReader(this);
      return Object.freeze({phase: state.phase,
        stopRequested: state.prepared.signal.aborted,
        receivedResponses: state.receivedResponses,
        receivedBodyBytes: state.receivedBodyBytes,
        observationCustody: state.receivedResponses === 0 ? 'not-observed' : 'retained',
        // This reader borrows its original credential binding. Only that
        // binding's actual owner can close/acknowledge its native duties;
        // retained JS observations do not require a GC/RSS cleanup receipt.
        cleanupConfirmed: false});
    },
  });
  readers.set(handle, state);
  return handle;
}

// Calendar request sequencing only. Catalog meaning, original authorization,
// Credential use, RowRun reservation and physical custody retain their owners.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';

export const CALENDAR_FREE_BUSY_OPERATION = 'calendar:free_busy:query';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const exports = ['calendarFreeBusyRequestWire', 'calendarProjectFreeBusy',
  'calendarFreeBusyMatchesQuery', 'calendarFreeBusyMetadataJson',
  'calendarFreeBusyRowsWire', 'calendarFreeBusyColumnNames'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxCalendars',
  'maxRows', 'maxRequestBytes', 'maxBodyBytes', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];

export class CalendarFreeBusyReadFailure extends Error {
  constructor(cause, observations) {
    super('CalendarFreeBusyReadFailed', {cause});
    this.code = 'CalendarFreeBusyReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

function prepare({moon, query, names, initialAuthorization, credential,
  authorizationFor, current, chargeResponse, consumePage, limits, signal,
  callResource = callHttpsCredentialResource}) {
  if (!Array.isArray(names) || new Set(names).size !== names.length ||
      [authorizationFor, current, chargeResponse, consumePage, callResource].some(fn => typeof fn !== 'function')) {
    fail('InvalidCalendarFreeBusyRead');
  }
  // One synchronous snapshot. Later getters or changes during credential
  // resolution cannot replace the original implementation or request recipe.
  const provider = Object.freeze(Object.fromEntries(exports.map(name => [name, moon?.[name]])));
  if (exports.some(name => typeof provider[name] !== 'function')) fail('InvalidCalendarFreeBusyRead');
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse, consumePage, callResource}});
  if (!limitFields.every(name => positive(context.limits[name])) ||
      context.limits.maxCalendars > 50 || !context.credential.binding ||
      typeof context.credential.binding !== 'object') fail('InvalidCalendarFreeBusyRead');
  if (context.scope.operation !== CALENDAR_FREE_BUSY_OPERATION) fail('ForeignCalendarFreeBusyOperation');
  const columns = provider.calendarFreeBusyColumnNames();
  if (names.some(name => !columns.includes(name))) fail('InvalidCalendarFreeBusyRead');
  const requestBody = provider.calendarFreeBusyRequestWire(query);
  if (typeof requestBody !== 'string' || Buffer.byteLength(requestBody) > context.limits.maxBodyBytes) {
    fail('CalendarFreeBusyRequestLimit');
  }
  return Object.freeze({provider, query, context, requestBody,
    columns: Object.freeze(columns.slice()), signal});
}

async function execute(original, received) {
  const {provider, query, context, requestBody, columns, signal} = original;
  const limits = context.limits, observations = [];
  const verify = async () => {
    signal?.throwIfAborted();
    await context.callbacks.current(CALENDAR_FREE_BUSY_OPERATION);
    signal?.throwIfAborted();
  };
  try {
    await verify();
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: CALENDAR_FREE_BUSY_OPERATION, index: 0})));
    if (authorization.scope.operation !== CALENDAR_FREE_BUSY_OPERATION ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignCalendarFreeBusyAuthorization');
    await verify();
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential,
      callResource: options => context.callbacks.callResource({...options, currentBeforeSend: verify}),
      operation: CALENDAR_FREE_BUSY_OPERATION, method: 'POST', path: '/calendar/v3/freeBusy',
      // The existing Credential String-body port owns JSON content-type and
      // framing; a provider cannot insert that reserved request header.
      query: [], headers: [['accept', 'application/json']],
      body: requestBody, responseHeaders: [],
      maxRequestBytes: limits.maxRequestBytes, maxResponseBytes: limits.maxResponseBytes, signal});
    observations.push(response);
    received?.(response);
    // Keep and charge the complete received body before status, current or
    // projection failure. Neither failure nor zero rows proves no prior send.
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify();
    if (!response.accepted || response.statusCode !== 200) fail('CalendarFreeBusyReadRejected');
    const page = checked(provider.calendarProjectFreeBusy(response.body, query,
      limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, limits.maxCalendars,
      limits.maxRows, limits.maxBodyBytes, limits.maxValueNodes, limits.maxValueTextBytes));
    if (!provider.calendarFreeBusyMatchesQuery(page, query)) fail('ForeignCalendarFreeBusyQuery');
    const metadata = JSON.parse(provider.calendarFreeBusyMetadataJson(page));
    const rows = JSON.parse(checked(provider.calendarFreeBusyRowsWire(page, columns,
      limits.maxRowsWireBytes, limits.maxRowsWireNodes, limits.maxRowsWireDepth)));
    await context.callbacks.consumePage(rows, Object.freeze({charge}));
    await verify();
    return Object.freeze({pages: 1, rowCount: metadata.rowCount,
      observations: Object.freeze(observations.slice())});
  } catch (cause) {
    throw new CalendarFreeBusyReadFailure(cause, observations);
  }
}

export async function readCalendarFreeBusy(options) {
  return execute(prepare(options));
}

const readers = new WeakMap();
function originalReader(value) {
  const state = readers.get(value);
  if (!state) fail('ForeignCalendarFreeBusyReader');
  return state;
}

// Same private physical-reader interface as calendar-list. A normal caller
// must install the original cleanup observer before read; no caller can turn
// retained raw aliases, Promise completion or cancellation into a release ACK.
export function createCalendarFreeBusyReader(options) {
  const prepared = prepare(options), stop = new AbortController();
  const signal = prepared.signal === undefined ? stop.signal
    : AbortSignal.any([prepared.signal, stop.signal]);
  const original = Object.freeze({...prepared, signal});
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('CalendarFreeBusyReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await execute(state.original, response => {
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
    requestStop(reason) {originalReader(this).stop.abort(reason);},
    observe() {
      const state = originalReader(this);
      return Object.freeze({phase: state.phase, stopRequested: state.original.signal.aborted,
        receivedResponses: state.receivedResponses, receivedBodyBytes: state.receivedBodyBytes,
        observationCustody: state.receivedResponses === 0 ? 'not-observed' : 'retained',
        cleanupConfirmed: false});
    },
  });
  readers.set(handle, {original, stop, phase: 'ready', receivedResponses: 0, receivedBodyBytes: 0n});
  return handle;
}

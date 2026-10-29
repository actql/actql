// Calendar FreeBusy query and checked page meaning only. The shared Host
// reader owns authorization, current, accounting, cancellation and cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';

export const CALENDAR_FREE_BUSY_OPERATION = 'calendar:free_busy:query';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const providerExports = ['calendarFreeBusyRequestWire', 'calendarProjectFreeBusy',
  'calendarFreeBusyMatchesQuery', 'calendarFreeBusyMetadataJson',
  'calendarFreeBusyRowsWire', 'calendarFreeBusyColumnNames'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxCalendars',
  'maxRows', 'maxRequestBytes', 'maxBodyBytes', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];

export class CalendarFreeBusyReadFailure extends Error {
  constructor(cause) {
    super('CalendarFreeBusyReadFailed', {cause});
    this.code = 'CalendarFreeBusyReadFailed';
  }
}

export function prepareCalendarFreeBusyPages({moon, query, names, limits}, applySynchronousProjection) {
  if (!Array.isArray(names) || new Set(names).size !== names.length ||
      !limits || typeof limits !== 'object' || typeof applySynchronousProjection !== 'function') {
    fail('InvalidCalendarFreeBusyRead');
  }
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidCalendarFreeBusyRead');
    return [name, (...args) => applySynchronousProjection(original, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  if (!limitFields.every(name => positive(bound[name])) || bound.maxCalendars > 50) {
    fail('InvalidCalendarFreeBusyRead');
  }
  // Capture every declared column, even when the user selected a subset.
  const columns = provider.calendarFreeBusyColumnNames();
  if (names.some(name => !columns.includes(name))) fail('InvalidCalendarFreeBusyRead');
  const selected = Object.freeze(columns.slice());
  const requestBody = provider.calendarFreeBusyRequestWire(query);
  if (typeof requestBody !== 'string' || Buffer.byteLength(requestBody) > bound.maxBodyBytes ||
      Buffer.byteLength(requestBody) > bound.maxRequestBytes) fail('CalendarFreeBusyRequestLimit');
  return Object.freeze({
    fetchPage({pageIndex}) {
      if (pageIndex !== 0) fail('CalendarFreeBusyPageLimit');
      // Credential owns JSON content-type and framing; no reserved header.
      return {method:'POST',path:'/calendar/v3/freeBusy',query:[],
        headers:[['accept','application/json']],body:requestBody,responseHeaders:[]};
    },
    decodePage(response) {
      if (!response.accepted || response.statusCode !== 200) fail('CalendarFreeBusyReadRejected');
      const page = checked(provider.calendarProjectFreeBusy(response.body, query,
        bound.maxResponseBytes, bound.maxNodes, bound.maxDepth, bound.maxCalendars,
        bound.maxRows, bound.maxBodyBytes, bound.maxValueNodes, bound.maxValueTextBytes));
      if (provider.calendarFreeBusyMatchesQuery(page, query) !== true) fail('ForeignCalendarFreeBusyQuery');
      const metadata = JSON.parse(provider.calendarFreeBusyMetadataJson(page));
      const rows = JSON.parse(checked(provider.calendarFreeBusyRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
      if (rows.length !== metadata.rowCount) fail('ForeignCalendarFreeBusyQuery');
      return {rows,done:true};
    },
    onError(cause) {return new CalendarFreeBusyReadFailure(cause);},
  });
}

// Calendar request and checked page meaning only. The shared Host reader owns
// authentication, accounting, current checks, cancellation and physical cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';

export const CALENDAR_LIST_OPERATION = 'calendar:calendars:list';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const providerExports = ['calendarProjectCalendarList', 'calendarListRowsWire', 'calendarListMetadataJson', 'calendarListColumnNames'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxPages', 'maxRows',
  'maxRequests', 'perPage', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const selectedFields = 'kind,items(id,summary,timeZone,accessRole,deleted),nextPageToken';

export class CalendarListReadFailure extends Error {
  constructor(cause) {
    super('CalendarListReadFailed', {cause});
    this.code = 'CalendarListReadFailed';
  }
}

export function prepareCalendarListPages({moon, names, limits}) {
  if (!Array.isArray(names) || new Set(names).size !== names.length ||
      !limits || typeof limits !== 'object') fail('InvalidCalendarListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidCalendarListRead');
    return [name, (...args) => Reflect.apply(original, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  if (!limitFields.every(key => positive(bound[key])) || bound.perPage > 250 ||
      bound.maxPages > bound.maxRequests) fail('InvalidCalendarListRead');
  const declared = provider.calendarListColumnNames();
  if (names.some(name => !declared.includes(name))) fail('InvalidCalendarListRead');
  // RowRun captures every declared cell, including an unselected identity.
  const selected = Object.freeze(declared.slice()), cursors = new Set(), ids = new Set();
  let token;
  return Object.freeze({
    fetchPage({pageIndex, rowCount}) {
      if (pageIndex >= bound.maxPages) fail('CalendarListPageLimit');
      if (pageIndex >= bound.maxRequests) fail('CalendarListRequestLimit');
      if (rowCount >= bound.maxRows) fail('CalendarListRowLimit');
      const query = [['maxResults', String(Math.min(bound.perPage, bound.maxRows - rowCount))],
        ['showHidden', 'true'], ['showDeleted', 'false'], ['fields', selectedFields]];
      if (token !== undefined) query.push(['pageToken', token]);
      return {method: 'GET', path: '/calendar/v3/users/me/calendarList', query,
        headers: [['accept','application/json']], responseHeaders: []};
    },
    decodePage(response, {pageIndex, rowCount}) {
      if (!response.accepted || response.statusCode !== 200) fail('CalendarListReadRejected');
      const page = checked(provider.calendarProjectCalendarList(response.body,
        bound.maxResponseBytes, bound.maxNodes, bound.maxDepth,
        Math.min(bound.perPage, bound.maxRows - rowCount), bound.maxCursorUnits,
        bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.calendarListMetadataJson(page));
      if (rowCount + metadata.rowCount > bound.maxRows) fail('CalendarListRowLimit');
      for (const id of metadata.ids) {
        if (ids.has(id)) fail('CalendarListDuplicateRecord');
        ids.add(id);
      }
      token = metadata.nextPageToken ?? undefined;
      if (token !== undefined) {
        if (cursors.has(token)) fail('CalendarListCursorCycle');
        cursors.add(token);
        // Refuse an incomplete Source before handing rows to the Host.
        if (pageIndex + 1 >= bound.maxPages) fail('CalendarListPageLimit');
        if (pageIndex + 1 >= bound.maxRequests) fail('CalendarListRequestLimit');
        if (rowCount + metadata.rowCount >= bound.maxRows) fail('CalendarListRowLimit');
      }
      const rows = JSON.parse(checked(provider.calendarListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
      return {rows, done: token === undefined};
    },
    onError(cause) {return new CalendarListReadFailure(cause);},
  });
}

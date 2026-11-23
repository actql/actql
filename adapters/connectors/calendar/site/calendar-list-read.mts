// Calendar request and checked page meaning only. The shared Host reader owns
// authentication, accounting, current checks, cancellation and physical cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';

export const CALENDAR_LIST_OPERATION = 'calendar:calendars:list';
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const providerExports = ['calendarProjectCalendarList', 'calendarListRowsWire', 'calendarListMetadataJson', 'calendarListColumnNames'] as const;
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxPages', 'maxRows',
  'maxRequests', 'perPage', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'] as const;
const selectedFields = 'kind,items(id,summary,timeZone,accessRole,deleted),nextPageToken';

export type CalendarListLimits = Readonly<Record<typeof limitFields[number], number>>;

// The four exports belong to the original compiled Calendar namespace. The
// checked page stays opaque and is passed back to that same namespace.
export type CalendarListBindings = Readonly<{
  calendarProjectCalendarList(body: ArrayBufferView, maxBytes: number, maxNodes: number,
    maxDepth: number, maxRows: number, maxCursorUnits: number,
    maxValueNodes: number, maxValueTextBytes: number): unknown;
  calendarListRowsWire(page: unknown, names: readonly string[], maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  calendarListMetadataJson(page: unknown): string;
  calendarListColumnNames(): string[];
}>;
type ListInput = Readonly<{moon: Partial<CalendarListBindings> | undefined;
  names: readonly string[]; limits: CalendarListLimits}>;
export type CalendarListProjection = <Result>(method: (...args: never[]) => Result,
  receiver: unknown, args: readonly unknown[]) => Result;
type Progress = Readonly<{pageIndex: number; rowCount: number}>;
type Response = Readonly<{accepted: boolean; statusCode: number; body: ArrayBufferView}>;
type Metadata = Readonly<{rowCount: number; ids: readonly string[]; nextPageToken: string | null}>;
type CalendarRow = Readonly<{access_role: string; id: string; summary: string; time_zone: string}>;

export class CalendarListReadFailure extends Error {
  declare readonly code: 'CalendarListReadFailed';

  constructor(cause: unknown) {
    super('CalendarListReadFailed', {cause});
    this.code = 'CalendarListReadFailed';
  }
}

export function prepareCalendarListPages({moon, names, limits}: ListInput, applySynchronousProjection: CalendarListProjection) {
  if (!Array.isArray(names) || new Set(names).size !== names.length ||
      !limits || typeof limits !== 'object') fail('InvalidCalendarListRead');
  if (typeof applySynchronousProjection !== 'function') fail('InvalidCalendarListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidCalendarListRead');
    return [name, (...args: unknown[]) => applySynchronousProjection(original, moon, args)];
  }))) as CalendarListBindings;
  const bound = Object.freeze({...limits});
  if (!limitFields.every(key => positive(bound[key])) || bound.perPage > 250 ||
      bound.maxPages > bound.maxRequests) fail('InvalidCalendarListRead');
  const declared = provider.calendarListColumnNames();
  if (names.some(name => !declared.includes(name))) fail('InvalidCalendarListRead');
  // RowRun captures every declared cell, including an unselected identity.
  const selected = Object.freeze(declared.slice()), cursors = new Set<string>(), ids = new Set<string>();
  let token: string | undefined;
  return Object.freeze({
    fetchPage({pageIndex, rowCount}: Progress) {
      if (pageIndex >= bound.maxPages) fail('CalendarListPageLimit');
      if (pageIndex >= bound.maxRequests) fail('CalendarListRequestLimit');
      if (rowCount >= bound.maxRows) fail('CalendarListRowLimit');
      const query = [['maxResults', String(Math.min(bound.perPage, bound.maxRows - rowCount))],
        ['showHidden', 'true'], ['showDeleted', 'false'], ['fields', selectedFields]];
      if (token !== undefined) query.push(['pageToken', token]);
      return {method: 'GET', path: '/calendar/v3/users/me/calendarList', query,
        headers: [['accept','application/json']], responseHeaders: []};
    },
    decodePage(response: Response, {pageIndex, rowCount}: Progress) {
      if (!response.accepted || response.statusCode !== 200) fail('CalendarListReadRejected');
      const page = checked(provider.calendarProjectCalendarList(response.body,
        bound.maxResponseBytes, bound.maxNodes, bound.maxDepth,
        Math.min(bound.perPage, bound.maxRows - rowCount), bound.maxCursorUnits,
        bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.calendarListMetadataJson(page)) as Metadata;
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
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)) as string) as readonly CalendarRow[];
      return {rows, done: token === undefined};
    },
    onError(cause: unknown) {return new CalendarListReadFailure(cause);},
  });
}

// Provider request/cursor/projection only. The existing shared managed reader
// owns authorization, currentness, accounting, cancellation and physical close.
import {checked} from '../../../host-common/runtime-result.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';
import type {CalendarListProjection as SynchronousProjection} from './calendar-list-read.mjs';

export const CALENDAR_EVENTS_OPERATION='calendar:events:list';
const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const positive=(value: number)=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const count=(value: unknown): value is number=>Number.isSafeInteger(value)&&(value as number)>=0&&(value as number)<2147483647;
const segment=(value: string)=>encodeURIComponent(value).replace(/[!'()*]/gu,
  unit=>'%'+unit.charCodeAt(0).toString(16).toUpperCase());
const methods=['calendarEventsQueryWire','calendarProjectEvents','calendarEventsMatchesQuery',
  'calendarEventsMetadataWire','calendarEventsRowsWire','calendarEventsColumnNames'] as const;
const positiveLimits=['maxResponseBytes','maxNodes','maxDepth','maxPages','maxRows','maxRequests',
  'perPage','maxIdentityBytes','maxCursorBytes','maxQueryBytes','maxTargetBytes',
  'maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;

type EventsLimits = Readonly<Record<typeof positiveLimits[number] | 'maxAttendees' | 'maxResolutionWork', number>>;
type WireBounds = [maxBytes: number, maxNodes: number, maxDepth: number];
type EventBounds = [...WireBounds, maxRows: number, maxIdentityBytes: number, maxCursorBytes: number,
  maxAttendees: number, maxValueNodes: number, maxValueTextBytes: number, maxResolutionWork: number];

// Opaque Profile, query and page originals go back to the same Common namespace.
type EventBindings = Readonly<{
  calendarEventsProfileFromEnvironment(environment: unknown): unknown;
  calendarEventsQueryFromRequestWire(wire: string, profile: unknown, ...bounds: EventBounds): unknown;
  calendarEventsQueryWire(query: unknown, ...bounds: WireBounds): unknown;
  calendarProjectEvents(body: ArrayBufferView, query: unknown, ...bounds: EventBounds): unknown;
  calendarEventsMatchesQuery(page: unknown, query: unknown): boolean;
  calendarEventsMetadataWire(page: unknown, ...bounds: WireBounds): unknown;
  calendarEventsRowsWire(page: unknown, columns: readonly string[], ...bounds: WireBounds): unknown;
  calendarEventsColumnNames(): string[];
}>;
type EventInput = Readonly<{moon: Partial<EventBindings> | undefined; names: readonly string[]; limits: EventsLimits}>;
type EventRequest = Record<'calendar_id' | 'time_max' | 'time_min' | 'time_zone', string>;
type Frame = Readonly<{pageIndex: number; rowCount: number}> | null | undefined;
type Response = Readonly<{accepted: boolean; statusCode: number; body: ArrayBufferView}>;
type Metadata = Readonly<{rowCount?: unknown; ids?: unknown; nextPageToken?: unknown; calendarId?: unknown}> | null;

export class CalendarEventsReadFailure extends Error{
  declare readonly code: 'CalendarEventsReadFailed';

  constructor(cause: unknown){super('CalendarEventsReadFailed',{cause});this.code='CalendarEventsReadFailed';}
}

// Adapter for the existing managed reader's original requestWire input. The
// selected environment must arrive from its original checking/installation
// owner. Its Profile and all opaque query/page operations stay in that SAME
// Common runtime. This port neither admits JSON nor transports a foreign Map.
export function prepareCalendarEventsRequestPages({moon,requestWire,environment,names,limits}:
  EventInput & Readonly<{requestWire: unknown; environment: unknown}>,applySynchronousProjection: SynchronousProjection){
  if(typeof requestWire!=='string'||!requestWire.isWellFormed()||environment===undefined||environment===null||
      !limits||typeof limits!=='object'||typeof applySynchronousProjection!=='function')fail('InvalidCalendarEventsRead');
  const bound=Object.freeze({...limits});
  if(!positiveLimits.every(name=>positive(bound[name]))||bound.perPage>2500||
      !count(bound.maxAttendees)||!count(bound.maxResolutionWork))fail('InvalidCalendarEventsRead');
  if(Buffer.byteLength(requestWire)>bound.maxQueryBytes)fail('CalendarEventsRequestLimit');
  const prepare=moon?.calendarEventsQueryFromRequestWire;
  const select=moon?.calendarEventsProfileFromEnvironment;
  if(typeof prepare!=='function'||typeof select!=='function')fail('InvalidCalendarEventsRead');
  const profile=checked(applySynchronousProjection(select,moon,[environment]));
  const query=checked(applySynchronousProjection(prepare,moon,[requestWire,profile,
    bound.maxQueryBytes,bound.maxNodes,bound.maxDepth,bound.maxRows,
    bound.maxIdentityBytes,bound.maxCursorBytes,bound.maxAttendees,
    bound.maxValueNodes,bound.maxValueTextBytes,bound.maxResolutionWork]));
  return prepareCalendarEventsPages({moon,query,names,limits:bound},applySynchronousProjection);
}

export function prepareCalendarEventsPages({moon,query,names,limits}:
  EventInput & Readonly<{query: unknown}>,applySynchronousProjection: SynchronousProjection){
  if(!Array.isArray(names)||new Set(names).size!==names.length||!limits||typeof limits!=='object'||
      typeof applySynchronousProjection!=='function'||query===undefined)fail('InvalidCalendarEventsRead');
  const provider=Object.freeze(Object.fromEntries(methods.map(name=>{
    const original=moon?.[name];
    if(typeof original!=='function')fail('InvalidCalendarEventsRead');
    return[name,(...args: unknown[])=>applySynchronousProjection(original,moon,args)];
  }))) as Pick<EventBindings, typeof methods[number]>;
  const bound=Object.freeze({...limits});
  if(!positiveLimits.every(name=>positive(bound[name]))||bound.perPage>2500||
      !count(bound.maxAttendees)||!count(bound.maxResolutionWork))fail('InvalidCalendarEventsRead');
  const columns=provider.calendarEventsColumnNames();
  if(!Array.isArray(columns)||columns.some(name=>typeof name!=='string')||
      new Set(columns).size!==columns.length||names.some(name=>!columns.includes(name)))fail('InvalidCalendarEventsRead');
  const selected=Object.freeze(columns.slice());
  const wire=checked(provider.calendarEventsQueryWire(query,bound.maxQueryBytes,bound.maxNodes,bound.maxDepth));
  if(typeof wire!=='string'||Buffer.byteLength(wire)>bound.maxQueryBytes)fail('CalendarEventsRequestLimit');
  let request: EventRequest;
  try{request=JSON.parse(wire) as EventRequest;}catch{fail('InvalidCalendarEventsRequest');}
  if(request===null||typeof request!=='object'||Array.isArray(request)||
      Object.keys(request).sort().join('\0')!=='calendar_id\0time_max\0time_min\0time_zone'||
      Object.values(request).some(value=>typeof value!=='string'||!value.length||!value.isWellFormed())){
    fail('InvalidCalendarEventsRequest');
  }
  const path='/calendar/v3/calendars/'+segment(request.calendar_id)+'/events';
  const original=Object.freeze({...request}),ids=new Set<string>(),cursors=new Set<string>();
  let token: unknown;
  const frame=(value: Frame)=>{
    if(!value||!count(value.pageIndex)||!count(value.rowCount))fail('InvalidCalendarEventsFrame');
    if(value.pageIndex>=bound.maxPages)fail('CalendarEventsPageLimit');
    if(value.pageIndex>=bound.maxRequests)fail('CalendarEventsRequestLimit');
    if(value.rowCount>bound.maxRows)fail('CalendarEventsRowLimit');
    return value;
  };
  return Object.freeze({
    fetchPage(value: Frame){
      const {rowCount}=frame(value);
      if(rowCount===bound.maxRows)fail('CalendarEventsRowLimit');
      const parameters=[['maxResults',String(Math.min(bound.perPage,bound.maxRows-rowCount))],
        ['singleEvents','true'],['showDeleted','true'],['timeMin',original.time_min],
        ['timeMax',original.time_max],['timeZone',original.time_zone]];
      if(token!==undefined)parameters.push(['pageToken',token as string]);
      if(Buffer.byteLength(requestTarget(path,parameters))>bound.maxTargetBytes)fail('CalendarEventsTargetLimit');
      // No maxAttendees or field-mask truncation is selected. A future checked
      // projection must carry its matching Source schema through the owner.
      return{method:'GET',path,query:parameters,headers:[['accept','application/json']],responseHeaders:[]};
    },
    decodePage(response: Response,value: Frame){
      const {pageIndex,rowCount}=frame(value);
      if(!response.accepted||response.statusCode!==200)fail('CalendarEventsReadRejected');
      const page=checked(provider.calendarProjectEvents(response.body,query,
        bound.maxResponseBytes,bound.maxNodes,bound.maxDepth,
        Math.min(bound.perPage,bound.maxRows-rowCount),bound.maxIdentityBytes,bound.maxCursorBytes,
        bound.maxAttendees,bound.maxValueNodes,bound.maxValueTextBytes,bound.maxResolutionWork));
      if(provider.calendarEventsMatchesQuery(page,query)!==true)fail('ForeignCalendarEventsQuery');
      const metadataWire=checked(provider.calendarEventsMetadataWire(page,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth));
      if(typeof metadataWire!=='string'||Buffer.byteLength(metadataWire)>bound.maxRowsWireBytes)fail('CalendarEventsMetadataLimit');
      const metadata=JSON.parse(metadataWire) as Metadata;
      if(!metadata||typeof metadata!=='object'||!Object.hasOwn(metadata,'nextPageToken')||
          !count(metadata.rowCount)||!Array.isArray(metadata.ids)||metadata.ids.length!==metadata.rowCount||
          metadata.calendarId!==original.calendar_id||
          metadata.rowCount>Math.min(bound.perPage,bound.maxRows-rowCount))fail('CalendarEventsRowLimit');
      for(const id of metadata.ids){
        if(typeof id!=='string'||!id.length||!id.isWellFormed()||Buffer.byteLength(id)>bound.maxIdentityBytes)fail('InvalidCalendarEventsIdentity');
        if(ids.has(id))fail('CalendarEventsDuplicateRecord');
        ids.add(id);
      }
      token=metadata.nextPageToken===null?undefined:metadata.nextPageToken;
      if(token!==undefined){
        if(typeof token!=='string'||!token.length||!token.isWellFormed()||Buffer.byteLength(token)>bound.maxCursorBytes)fail('InvalidCalendarEventsCursor');
        if(cursors.has(token))fail('CalendarEventsCursorCycle');
        cursors.add(token);
        if(pageIndex+1>=bound.maxPages)fail('CalendarEventsPageLimit');
        if(pageIndex+1>=bound.maxRequests)fail('CalendarEventsRequestLimit');
        if(rowCount+metadata.rowCount>=bound.maxRows)fail('CalendarEventsRowLimit');
      }
      const rowsWire=checked(provider.calendarEventsRowsWire(page,selected,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth));
      if(typeof rowsWire!=='string'||Buffer.byteLength(rowsWire)>bound.maxRowsWireBytes)fail('CalendarEventsRowsLimit');
      return{rowsWire,rowCount:metadata.rowCount,done:token===undefined};
    },
    onError(cause: unknown){return new CalendarEventsReadFailure(cause);},
  });
}

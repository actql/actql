// Pure vendor request/response callbacks for the existing shared reader.
// Source/Account/credentials, actual attempts/bytes, cancellation, raw response
// custody and physical retirement remain with that original reader and caller.
import {checked} from '../../../host-common/runtime-result.mjs';
import type {CalendarListProjection as SynchronousProjection} from './calendar-list-read.mjs';

export const CALENDAR_FREE_BUSY_PAGES_OPERATION='calendar:free_busy:query';
const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const positive=(value: number)=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const count=(value: unknown): value is number=>Number.isSafeInteger(value)&&(value as number)>=0&&(value as number)<2147483647;
const limitFields=['maxResponseBytes','maxNodes','maxDepth','maxCalendars','maxRows',
  'maxRequestBytes','maxBodyBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;
const methods=['calendarPrepareFreeBusyRequest','calendarFreeBusyRequestWire',
  'calendarProjectFreeBusy','calendarFreeBusyMatchesQuery','calendarFreeBusyMetadataJson',
  'calendarFreeBusyRowsWire','calendarFreeBusyColumnNames'] as const;

export type FreeBusyLimits = Readonly<Record<typeof limitFields[number], number>>;
type ProjectionBounds = [maxBytes: number, maxNodes: number, maxDepth: number, maxCalendars: number,
  maxRows: number, maxRequestBytes: number, maxValueNodes: number, maxValueTextBytes: number];
export type FreeBusyBindings = Readonly<{
  calendarFreeBusyRequestWire(query: unknown): string;
  calendarProjectFreeBusy(body: ArrayBufferView, query: unknown, ...bounds: ProjectionBounds): unknown;
  calendarFreeBusyMatchesQuery(page: unknown, query: unknown): boolean;
  calendarFreeBusyMetadataJson(page: unknown): string;
  calendarFreeBusyRowsWire(page: unknown, columns: readonly string[], maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  calendarFreeBusyColumnNames(): string[];
}>;
type RequestBindings = FreeBusyBindings & Readonly<{
  calendarPrepareFreeBusyRequest(wire: string, ...bounds: ProjectionBounds): unknown;
}>;
type PageInput = Readonly<{moon: Partial<RequestBindings> | undefined; requestWire: unknown;
  names: readonly string[]; limits: FreeBusyLimits}>;
type Frame = Readonly<{pageIndex: number; rowCount: number}> | null | undefined;
type Response = Readonly<{accepted: boolean; statusCode: number; body: ArrayBufferView}>;
type Metadata = Readonly<{rowCount?: unknown; responseSha256?: unknown}> | null;

export class CalendarFreeBusyPagesFailure extends Error{
  declare readonly code: 'CalendarFreeBusyPagesFailed';

  constructor(cause: unknown){super('CalendarFreeBusyPagesFailed',{cause});this.code='CalendarFreeBusyPagesFailed';}
}

export function prepareCalendarFreeBusyRequestPages({moon,requestWire,names,limits}: PageInput,applySynchronousProjection: SynchronousProjection){
  if(typeof requestWire!=='string'||!requestWire.isWellFormed()||!Array.isArray(names)||
      new Set(names).size!==names.length||!limits||typeof limits!=='object'||
      typeof applySynchronousProjection!=='function')fail('InvalidCalendarFreeBusyPages');
  const bound=Object.freeze({...limits});
  if(!limitFields.every(name=>positive(bound[name]))||bound.maxCalendars>50)fail('InvalidCalendarFreeBusyPages');
  if(Buffer.byteLength(requestWire)>bound.maxBodyBytes)fail('CalendarFreeBusyRequestLimit');
  const provider=Object.freeze(Object.fromEntries(methods.map(name=>{
    const original=moon?.[name];if(typeof original!=='function')fail('InvalidCalendarFreeBusyPages');
    return[name,(...args: unknown[])=>applySynchronousProjection(original,moon,args)];
  }))) as RequestBindings;
  const query=checked(provider.calendarPrepareFreeBusyRequest(requestWire,bound.maxResponseBytes,
    bound.maxNodes,bound.maxDepth,bound.maxCalendars,bound.maxRows,bound.maxBodyBytes,
    bound.maxValueNodes,bound.maxValueTextBytes));
  const columns=provider.calendarFreeBusyColumnNames();
  if(!Array.isArray(columns)||columns.some(name=>typeof name!=='string')||
      new Set(columns).size!==columns.length||names.some(name=>!columns.includes(name)))fail('InvalidCalendarFreeBusyPages');
  const selected=Object.freeze(columns.slice());
  const body=provider.calendarFreeBusyRequestWire(query);
  if(typeof body!=='string'||!body.isWellFormed()||
      Buffer.byteLength(body)>Math.min(bound.maxBodyBytes,bound.maxRequestBytes))fail('CalendarFreeBusyRequestLimit');
  const frame=(value: Frame)=>{
    if(!value||value.pageIndex!==0||value.rowCount!==0)fail('InvalidCalendarFreeBusyFrame');
  };
  return Object.freeze({
    fetchPage(value: Frame){
      frame(value);
      // The existing Credential String-body port owns content-type/framing.
      return{method:'POST',path:'/calendar/v3/freeBusy',query:[],
        headers:[['accept','application/json']],responseHeaders:[],body};
    },
    decodePage(response: Response,value: Frame){
      frame(value);
      if(!response.accepted||response.statusCode!==200)fail('CalendarFreeBusyReadRejected');
      const page=checked(provider.calendarProjectFreeBusy(response.body,query,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,bound.maxCalendars,bound.maxRows,bound.maxBodyBytes,
        bound.maxValueNodes,bound.maxValueTextBytes));
      if(provider.calendarFreeBusyMatchesQuery(page,query)!==true)fail('ForeignCalendarFreeBusyQuery');
      const wire=provider.calendarFreeBusyMetadataJson(page);
      if(typeof wire!=='string'||Buffer.byteLength(wire)>bound.maxRowsWireBytes)fail('CalendarFreeBusyMetadataLimit');
      const metadata=JSON.parse(wire) as Metadata;
      if(!metadata||!count(metadata.rowCount)||metadata.rowCount>bound.maxRows||
          typeof metadata.responseSha256!=='string'||!/^[0-9a-f]{64}$/u.test(metadata.responseSha256))fail('InvalidCalendarFreeBusyMetadata');
      // Always capture all declared columns before downstream selection.
      const rowsWire=checked(provider.calendarFreeBusyRowsWire(page,selected,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth));
      if(typeof rowsWire!=='string'||Buffer.byteLength(rowsWire)>bound.maxRowsWireBytes)fail('CalendarFreeBusyRowsLimit');
      return{rowsWire,rowCount:metadata.rowCount,done:true};
    },
    onError(cause: unknown){return new CalendarFreeBusyPagesFailure(cause);},
  });
}

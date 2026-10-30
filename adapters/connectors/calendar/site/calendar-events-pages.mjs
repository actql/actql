// Provider request/cursor/projection only. The existing shared managed reader
// owns authorization, currentness, accounting, cancellation and physical close.
import {checked} from '../../../host-common/runtime-result.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const CALENDAR_EVENTS_OPERATION='calendar:events:list';
const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const count=value=>Number.isSafeInteger(value)&&value>=0&&value<2147483647;
const segment=value=>encodeURIComponent(value).replace(/[!'()*]/gu,
  unit=>'%'+unit.charCodeAt(0).toString(16).toUpperCase());
const methods=['calendarEventsQueryWire','calendarProjectEvents','calendarEventsMatchesQuery',
  'calendarEventsMetadataWire','calendarEventsRowsWire','calendarEventsColumnNames'];
const positiveLimits=['maxResponseBytes','maxNodes','maxDepth','maxPages','maxRows','maxRequests',
  'perPage','maxIdentityBytes','maxCursorBytes','maxQueryBytes','maxTargetBytes',
  'maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

export class CalendarEventsReadFailure extends Error{
  constructor(cause){super('CalendarEventsReadFailed',{cause});this.code='CalendarEventsReadFailed';}
}

export function prepareCalendarEventsPages({moon,query,names,limits},applySynchronousProjection){
  if(!Array.isArray(names)||new Set(names).size!==names.length||!limits||typeof limits!=='object'||
      typeof applySynchronousProjection!=='function'||query===undefined)fail('InvalidCalendarEventsRead');
  const provider=Object.freeze(Object.fromEntries(methods.map(name=>{
    const original=moon?.[name];
    if(typeof original!=='function')fail('InvalidCalendarEventsRead');
    return[name,(...args)=>applySynchronousProjection(original,moon,args)];
  })));
  const bound=Object.freeze({...limits});
  if(!positiveLimits.every(name=>positive(bound[name]))||bound.perPage>2500||
      !count(bound.maxAttendees)||!count(bound.maxResolutionWork))fail('InvalidCalendarEventsRead');
  const columns=provider.calendarEventsColumnNames();
  if(!Array.isArray(columns)||columns.some(name=>typeof name!=='string')||
      new Set(columns).size!==columns.length||names.some(name=>!columns.includes(name)))fail('InvalidCalendarEventsRead');
  const selected=Object.freeze(columns.slice());
  const wire=checked(provider.calendarEventsQueryWire(query,bound.maxQueryBytes,bound.maxNodes,bound.maxDepth));
  if(typeof wire!=='string'||Buffer.byteLength(wire)>bound.maxQueryBytes)fail('CalendarEventsRequestLimit');
  let request;
  try{request=JSON.parse(wire);}catch{fail('InvalidCalendarEventsRequest');}
  if(request===null||typeof request!=='object'||Array.isArray(request)||
      Object.keys(request).sort().join('\0')!=='calendar_id\0time_max\0time_min\0time_zone'||
      Object.values(request).some(value=>typeof value!=='string'||!value.length||!value.isWellFormed())){
    fail('InvalidCalendarEventsRequest');
  }
  const path='/calendar/v3/calendars/'+segment(request.calendar_id)+'/events';
  const original=Object.freeze({...request}),ids=new Set(),cursors=new Set();
  let token;
  const frame=value=>{
    if(!value||!count(value.pageIndex)||!count(value.rowCount))fail('InvalidCalendarEventsFrame');
    if(value.pageIndex>=bound.maxPages)fail('CalendarEventsPageLimit');
    if(value.pageIndex>=bound.maxRequests)fail('CalendarEventsRequestLimit');
    if(value.rowCount>bound.maxRows)fail('CalendarEventsRowLimit');
    return value;
  };
  return Object.freeze({
    fetchPage(value){
      const {rowCount}=frame(value);
      if(rowCount===bound.maxRows)fail('CalendarEventsRowLimit');
      const parameters=[['maxResults',String(Math.min(bound.perPage,bound.maxRows-rowCount))],
        ['singleEvents','true'],['showDeleted','true'],['timeMin',original.time_min],
        ['timeMax',original.time_max],['timeZone',original.time_zone]];
      if(token!==undefined)parameters.push(['pageToken',token]);
      if(Buffer.byteLength(requestTarget(path,parameters))>bound.maxTargetBytes)fail('CalendarEventsTargetLimit');
      // No maxAttendees or field-mask truncation is selected. A future checked
      // projection must carry its matching Source schema through the owner.
      return{method:'GET',path,query:parameters,headers:[['accept','application/json']],responseHeaders:[]};
    },
    decodePage(response,value){
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
      const metadata=JSON.parse(metadataWire);
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
    onError(cause){return new CalendarEventsReadFailure(cause);},
  });
}

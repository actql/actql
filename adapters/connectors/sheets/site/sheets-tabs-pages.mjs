// Pure request/response callbacks. The original shared Reader owns Source
// authority, credential/current, send, body charging, cancellation and close.
import {checked} from '../../../host-common/runtime-result.mjs';
export const SHEETS_TABS_PAGES_OPERATION='sheets:grid:read';
const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const fields='spreadsheetId,sheets(properties(sheetId,title,index,sheetType,gridProperties(rowCount,columnCount)))';
const limitFields=['maxResponseBytes','maxNodes','maxDepth','maxRows','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];
export class SheetsTabsPagesFailure extends Error{
  constructor(cause){super('SheetsTabsPagesFailed',{cause});this.code='SheetsTabsPagesFailed';}
}
export function prepareSheetsTabsPages({moon,spreadsheetId,names,limits},applySynchronousProjection){
  if(typeof spreadsheetId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/u.test(spreadsheetId)||
      !Array.isArray(names)||new Set(names).size!==names.length||!limits||typeof limits!=='object'||
      typeof applySynchronousProjection!=='function')fail('InvalidSheetsTabsPages');
  const bound=Object.freeze({...limits});
  if(!limitFields.every(name=>positive(bound[name])))fail('InvalidSheetsTabsPages');
  const provider=Object.freeze(Object.fromEntries(['sheetsProjectTabs','sheetsTabsRowsWire','sheetsTabsRowCount','sheetsTabsColumnNames'].map(name=>{
    const original=moon?.[name];if(typeof original!=='function')fail('InvalidSheetsTabsPages');
    return[name,(...args)=>applySynchronousProjection(original,moon,args)];
  })));
  const columns=provider.sheetsTabsColumnNames();
  if(!Array.isArray(columns)||columns.some(name=>typeof name!=='string')||new Set(columns).size!==columns.length||
      names.some(name=>!columns.includes(name)))fail('InvalidSheetsTabsPages');
  const allColumns=Object.freeze([...columns]);
  const frame=value=>{if(!value||value.pageIndex!==0||value.rowCount!==0)fail('InvalidSheetsTabsFrame');};
  return Object.freeze({
    fetchPage(value){frame(value);return{method:'GET',path:'/v4/spreadsheets/'+spreadsheetId,
      query:[['fields',fields]],headers:[['accept','application/json']],responseHeaders:[]};},
    decodePage(response,value){
      frame(value);
      if(!response.accepted||response.statusCode!==200)fail('SheetsTabsReadRejected');
      const page=checked(provider.sheetsProjectTabs(response.body,spreadsheetId,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,bound.maxRows,bound.maxValueNodes,bound.maxValueTextBytes));
      const rowCount=provider.sheetsTabsRowCount(page);
      if(!Number.isSafeInteger(rowCount)||rowCount<0||rowCount>bound.maxRows)fail('InvalidSheetsTabsPage');
      const rowsWire=checked(provider.sheetsTabsRowsWire(page,allColumns,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth));
      if(typeof rowsWire!=='string'||Buffer.byteLength(rowsWire)>bound.maxRowsWireBytes)fail('SheetsTabsRowsLimit');
      return{rowsWire,rowCount,done:true};
    },
    onError(cause){return new SheetsTabsPagesFailure(cause);},
  });
}

// Pure request/response callbacks. The original shared Reader owns Source
// authority, credential/current, send, body charging, cancellation and close.
import {checked} from '../../../host-common/runtime-result.mjs';
type Limits = Readonly<Record<typeof limitFields[number], number>>;
type Frame = Readonly<{pageIndex: number; rowCount: number}>;
type Response = Readonly<{accepted: boolean; statusCode: number; body: Buffer}>;
type Projection = (method: (...args: never[]) => unknown, receiver: unknown, args: unknown[]) => unknown;
type Provider = Readonly<{
  sheetsProjectTabs(body: Buffer, spreadsheetId: string, bytes: number, nodes: number, depth: number,
    rows: number, valueNodes: number, valueTextBytes: number): unknown;
  sheetsTabsRowsWire(page: unknown, columns: readonly string[], bytes: number, nodes: number, depth: number): unknown;
  sheetsTabsRowCount(page: unknown): number;
  sheetsTabsColumnNames(): readonly string[];
}>;
type Options = Readonly<{moon: Provider; spreadsheetId: string; names: readonly string[]; limits: Limits}>;

export const SHEETS_TABS_PAGES_OPERATION='sheets:grid:read';
const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const positive=(value: number)=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const fields='spreadsheetId,sheets(properties(sheetId,title,index,sheetType,gridProperties(rowCount,columnCount)))';
const limitFields=['maxResponseBytes','maxNodes','maxDepth','maxRows','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;
export class SheetsTabsPagesFailure extends Error{
  declare readonly code: 'SheetsTabsPagesFailed';
  constructor(cause: unknown){super('SheetsTabsPagesFailed',{cause});this.code='SheetsTabsPagesFailed';}
}
export function prepareSheetsTabsPages({moon,spreadsheetId,names,limits}: Options,applySynchronousProjection: Projection){
  if(typeof spreadsheetId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/u.test(spreadsheetId)||
      !Array.isArray(names)||new Set(names).size!==names.length||!limits||typeof limits!=='object'||
      typeof applySynchronousProjection!=='function')fail('InvalidSheetsTabsPages');
  const bound=Object.freeze({...limits});
  if(!limitFields.every(name=>positive(bound[name])))fail('InvalidSheetsTabsPages');
  const provider=Object.freeze(Object.fromEntries((['sheetsProjectTabs','sheetsTabsRowsWire','sheetsTabsRowCount','sheetsTabsColumnNames'] as const).map(name=>{
    const original=moon?.[name];if(typeof original!=='function')fail('InvalidSheetsTabsPages');
    return[name,(...args: unknown[])=>applySynchronousProjection(original,moon,args)];
  }))) as unknown as Provider;
  const columns=provider.sheetsTabsColumnNames();
  if(!Array.isArray(columns)||columns.some(name=>typeof name!=='string')||new Set(columns).size!==columns.length||
      names.some(name=>!columns.includes(name)))fail('InvalidSheetsTabsPages');
  const allColumns=Object.freeze([...columns]);
  const frame=(value: Frame)=>{if(!value||value.pageIndex!==0||value.rowCount!==0)fail('InvalidSheetsTabsFrame');};
  return Object.freeze({
    fetchPage(value: Frame){frame(value);return{method:'GET',path:'/v4/spreadsheets/'+spreadsheetId,
      query:[['fields',fields]],headers:[['accept','application/json']],responseHeaders:[]};},
    decodePage(response: Response,value: Frame){
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
    onError(cause: unknown){return new SheetsTabsPagesFailure(cause);},
  });
}

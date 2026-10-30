// Pure Sheets request and typed-page callbacks. The shared Reader owns
// credential/current checks, physical sends, charging, cancellation and close.
const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const rangeFields=['sheetId','startRow','endRow','startColumn','endColumn'];
const limitFields=['maxRequestBytes','maxResponseBytes','maxNodes','maxDepth','maxCells','maxRows'];
const fields='spreadsheetId,sheets(properties(sheetId),data(startRow,startColumn,rowData(values(effectiveValue,userEnteredValue))))';
export const SHEETS_GRID_PAGES_OPERATION='sheets:grid:read';
export class SheetsGridPagesFailure extends Error{
  constructor(cause){super('SheetsGridPagesFailed',{cause});this.code='SheetsGridPagesFailed';}
}

export function prepareSheetsGridPages({moon,spreadsheetId,columns,range,names,limits},applySynchronousProjection){
  if(typeof spreadsheetId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/u.test(spreadsheetId)||
      !Array.isArray(columns)||columns.length===0||columns.length>64||
      !range||typeof range!=='object'||Object.keys(range).sort().join('\0')!==[...rangeFields].sort().join('\0')||
      !Array.isArray(names)||new Set(names).size!==names.length||
      !limits||typeof limits!=='object'||typeof applySynchronousProjection!=='function')fail('InvalidSheetsGridPages');
  const bound=Object.freeze({...limits});
  if(!limitFields.every(name=>positive(bound[name]))||bound.maxRows>100||
      !rangeFields.every(name=>Number.isSafeInteger(range[name])&&!Object.is(range[name],-0)&&range[name]>=0&&range[name]<=2147483647)||
      range.endRow-range.startRow>bound.maxRows)fail('InvalidSheetsGridPages');
  const schema=columns.map(column=>{
    if(!column||typeof column!=='object'||Array.isArray(column)||
        Object.keys(column).sort().join('\0')!=='name\0nullable\0type'||
        typeof column.name!=='string'||typeof column.type!=='string'||typeof column.nullable!=='boolean')fail('InvalidSheetsGridPages');
    return Object.freeze({name:column.name,type:column.type,nullable:column.nullable});
  });
  const declared=schema.map(column=>column.name);
  if(names.some(name=>!declared.includes(name)))fail('InvalidSheetsGridPages');
  const schemaWire=JSON.stringify(schema),coordinates=Object.freeze(rangeFields.map(name=>range[name]));
  const codec=Object.freeze(Object.fromEntries(['sheetsGridRequestJson','sheetsGridPageJson'].map(name=>{
    const original=moon?.[name];if(typeof original!=='function')fail('InvalidSheetsGridPages');
    return[name,(...args)=>applySynchronousProjection(original,moon,args)];
  })));
  const decoded=wire=>{
    if(typeof wire!=='string')fail('InvalidSheetsGridProjection');
    const result=JSON.parse(wire);
    if(result?.refused!==undefined)throw Object.assign(new Error('SheetsContractRefused'),{code:'SheetsContractRefused',cause:result.refused});
    return result;
  };
  const codecLimits=bytes=>[bytes,bound.maxNodes,bound.maxDepth,bound.maxCells];
  const body=decoded(codec.sheetsGridRequestJson(schemaWire,...coordinates,...codecLimits(bound.maxRequestBytes))).body;
  if(typeof body!=='string'||!body.isWellFormed()||Buffer.byteLength(body)>bound.maxRequestBytes)fail('SheetsGridRequestLimit');
  const frame=value=>{if(!value||value.pageIndex!==0||value.rowCount!==0)fail('InvalidSheetsGridFrame');};
  return Object.freeze({
    fetchPage(value){frame(value);return{method:'POST',
      path:`/v4/spreadsheets/${spreadsheetId}:getByDataFilter`,query:[['fields',fields]],
      headers:[['accept','application/json']],responseHeaders:[],body};},
    decodePage(response,value){
      frame(value);
      if(!response.accepted||response.statusCode!==200)fail('SheetsReadRejected');
      const {page}=decoded(codec.sheetsGridPageJson(response.body,spreadsheetId,schemaWire,
        ...coordinates,...codecLimits(bound.maxResponseBytes)));
      if(!page||!Array.isArray(page.rows)||!Number.isSafeInteger(page.excludedBlankRows)||page.excludedBlankRows<0)fail('InvalidSheetsGridProjection');
      if(page.rows.length>bound.maxRows)fail('SheetsReadRowLimit');
      // All declared cells are admitted before downstream column selection.
      return{rows:page.rows,done:true};
    },
    onError(cause){return new SheetsGridPagesFailure(cause);},
  });
}

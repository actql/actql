// Actual portable Sheets codecs with pure provider callbacks. No credential,
// physical send, charge, RowRun, Account, normal installation or Saved scope.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareSheetsGridPages} from '../site/sheets-grid-pages.mjs';
import {prepareSheetsTargetRequest,projectSheetsTarget} from '../site/sheets-exchange.mjs';
import {isEffectPreparationRefusal} from '../../../host-common/effect-preparation-result.mjs';
import {columns,expectedRows,sheetsRoutes,errorGridRows} from './sheets-api.fixture.mjs';
const moon=await import(process.env.ACTQL_TEST_SHEETS_PROVIDER_MODULE??
  new URL('../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js',import.meta.url).href);
const range={sheetId:0,startRow:0,endRow:4,startColumn:0,endColumn:3};
const limits={maxRequestBytes:300000,maxResponseBytes:2000000,maxNodes:200000,maxDepth:32,maxCells:6400,maxRows:100};
const frame={pageIndex:0,rowCount:0};
const prepare=()=>prepareSheetsGridPages({moon,spreadsheetId:'book',columns,range,names:['text'],limits},(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
const route=state=>sheetsRoutes(state).find(item=>item.pathname.endsWith(':getByDataFilter'));
function response(state,body){return{accepted:true,statusCode:200,body:Buffer.from(JSON.stringify(route(state).handle({body}).body))};}

test('actual Sheets callback codec retains full grid duplicate rows blanks formula result and exact literal text',()=>{
  const p=prepare(),request=p.fetchPage(frame);
  const expected={dataFilters:[{gridRange:{sheetId:0,startRowIndex:0,endRowIndex:4,startColumnIndex:0,endColumnIndex:3}}],includeGridData:true};
  assert.deepEqual(JSON.parse(request.body),expected);
  assert.deepEqual(p.decodePage(response({},request.body),frame),{rows:expectedRows,done:true});
});

test('actual Sheets callback codec refuses cell errors foreign spreadsheet and excess row extent before page delivery',()=>{
  const p=prepare(),request=p.fetchPage(frame);
  assert.throws(()=>p.decodePage(response({gridRows:errorGridRows},request.body),frame),error=>error.code==='SheetsContractRefused'&&error.cause.kind==='CellError');
  const original=response({},request.body);
  assert.throws(()=>p.decodePage({...original,body:Buffer.from(original.body.toString().replace('"book"','"foreign"'))},frame),error=>error.code==='SheetsContractRefused'&&error.cause.kind==='ForeignSpreadsheet');
  const exceeded=response({gridRows:Array(5).fill({values:[{effectiveValue:{stringValue:'one'}}]})},request.body);
  assert.throws(()=>p.decodePage(exceeded,frame),{code:'SheetsContractRefused'});
});

test('actual Sheets metadata projection preserves original target refusal separately from transport rejection',()=>{
  const request=prepareSheetsTargetRequest('book');assert.equal(request.method,'GET');
  assert.equal(Object.hasOwn(request,'body'),false);
  assert.equal(new URL(request.path,'https://fixture.invalid').searchParams.get('fields'),
    'spreadsheetId,sheets(properties(sheetId,sheetType,gridProperties(rowCount,columnCount)))');
  const body=Buffer.from(JSON.stringify(sheetsRoutes({}).find(route=>route.method==='GET').handle().body));
  const selected={moon,spreadsheetId:'book',columns,range,appendSheetId:7};
  assert.equal(projectSheetsTarget({...selected,response:{accepted:true,statusCode:200,body}}),undefined);
  assert.throws(()=>projectSheetsTarget({...selected,response:{accepted:false,statusCode:200,body}}),
    error=>error.code==='SheetsTargetUnverified'&&!isEffectPreparationRefusal(error));
  const foreign=Buffer.from(body.toString().replace('"book"','"foreign"'));
  assert.throws(()=>projectSheetsTarget({...selected,response:{accepted:true,statusCode:200,body:foreign}}),
    error=>error.code==='SheetsContractRefused'&&error.cause.kind==='ForeignSpreadsheet'&&isEffectPreparationRefusal(error));
});

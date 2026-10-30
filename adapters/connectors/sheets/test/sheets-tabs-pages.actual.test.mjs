// Actual standalone portable provider + pure callbacks, not a Source issuance,
// physical read/ACK, Account, installed Host or separate-process Saved case.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareSheetsTabsPages} from '../site/sheets-tabs-pages.mjs';
const moon=await import(process.env.ACTQL_TEST_SHEETS_PROVIDER_MODULE??
  new URL('../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js',import.meta.url).href);
const limits={maxResponseBytes:8192,maxNodes:512,maxDepth:16,maxRows:4,maxValueNodes:100,maxValueTextBytes:4096,
  maxRowsWireBytes:8192,maxRowsWireNodes:100,maxRowsWireDepth:8};
const body=Buffer.from('{"spreadsheetId":"book","sheets":[{"properties":{"sheetId":0,"title":"é\\r\\n😀","index":0,"gridProperties":{"rowCount":100,"columnCount":3}}},{"properties":{"sheetId":7,"title":"Chart","index":1,"sheetType":"OBJECT"}}]}');
const frame={pageIndex:0,rowCount:0};
test('actual Sheets tabs ABI and callbacks retain all typed columns tab identity exact title and nongrid null counts',()=>{
  const p=prepareSheetsTabsPages({moon,spreadsheetId:'book',names:['title'],limits},(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
  const request=p.fetchPage(frame);assert.equal(request.method,'GET');assert.equal(Object.hasOwn(request,'body'),false);
  const result=p.decodePage({accepted:true,statusCode:200,body},frame);
  assert.equal(result.done,true);assert.equal(result.rowCount,2);
  assert.deepEqual(JSON.parse(result.rowsWire),[
    {id:'0',title:'é\r\n😀',index:'0',row_count:'100',column_count:'3'},
    {id:'7',title:'Chart',index:'1',row_count:null,column_count:null}]);
  const schema=JSON.parse(checked(moon.sheetsTabsSchemaWire(4096,100,8)));
  assert.deepEqual(schema.id,{nullable:false,type:'int64'});assert.deepEqual(schema.row_count,{nullable:true,type:'int64'});
  assert.throws(()=>p.decodePage({accepted:true,statusCode:200,body:Buffer.from(body.toString().replace('"book"','"foreign"'))},frame),{code:'MoonBitHostFailure'});
});

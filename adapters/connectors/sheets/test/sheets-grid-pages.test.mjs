import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareSheetsGridPages} from '../site/sheets-grid-pages.mjs';
const columns=[{name:'id',type:'string',nullable:false},{name:'value',type:'number',nullable:true}];
const range={sheetId:7,startRow:1,endRow:4,startColumn:0,endColumn:2};
const limits={maxRequestBytes:4096,maxResponseBytes:8192,maxNodes:256,maxDepth:16,maxCells:6,maxRows:3};
const frame={pageIndex:0,rowCount:0};
function fixture(){
  const calls=[],body='{"original":"body"}',bytes=Buffer.from('same response');
  const rows=[{id:'one',value:0},{id:'one',value:null}];
  const moon={sheetsGridRequestJson(...args){assert.equal(this,moon);calls.push(['request',...args]);return JSON.stringify({body});},
    sheetsGridPageJson(...args){assert.equal(this,moon);calls.push(['page',...args]);return JSON.stringify({page:{rows,excludedBlankRows:1}});}};
  const options={moon,spreadsheetId:'book',columns:structuredClone(columns),range:{...range},names:['id'],limits:{...limits}};
  const provider=prepareSheetsGridPages(options,(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
  return{provider,options,calls,body,bytes,rows,moon};
}

test('Sheets pure grid callbacks capture original codec receiver configuration and complete columns',()=>{
  const f=fixture();
  f.options.columns[0].name='changed';f.options.range.sheetId=99;f.options.limits.maxResponseBytes=1;
  f.moon.sheetsGridPageJson=()=>assert.fail('original method is retained');
  const request=f.provider.fetchPage(frame);
  assert.equal(request.method,'POST');assert.equal(request.path,'/v4/spreadsheets/book:getByDataFilter');
  assert.equal(request.body,f.body);assert.deepEqual(request.headers,[['accept','application/json']]);
  assert.equal(request.query[0][0],'fields');assert.match(request.query[0][1],/effectiveValue,userEnteredValue/);
  const page=f.provider.decodePage({accepted:true,statusCode:200,body:f.bytes},frame);
  assert.deepEqual(page,{rows:f.rows,done:true});
  assert.equal(f.calls[1][1],f.bytes);assert.equal(f.calls[1][2],'book');
  assert.deepEqual(JSON.parse(f.calls[1][3]),columns);
  assert.deepEqual(f.calls[1].slice(4),[7,1,4,0,2,8192,256,16,6]);
});

test('Sheets pure grid callbacks reject foreign selection repeated frames bad response and codec refusal',()=>{
  const f=fixture();
  assert.throws(()=>prepareSheetsGridPages({...f.options,names:['foreign']},Reflect.apply),{code:'InvalidSheetsGridPages'});
  assert.throws(()=>f.provider.fetchPage({pageIndex:1,rowCount:0}),{code:'InvalidSheetsGridFrame'});
  assert.throws(()=>f.provider.decodePage({accepted:false,statusCode:403,body:f.bytes},frame),{code:'SheetsReadRejected'});
  assert.equal(f.calls.length,1,'rejected response never enters codec');
  const cause=new Error('original callback failure');assert.equal(f.provider.onError(cause).cause,cause);
  const moon={sheetsGridRequestJson:()=>'{"body":"one"}',sheetsGridPageJson:()=>'{"refused":{"kind":"CellError"}}'};
  const refused=prepareSheetsGridPages({...f.options,moon},(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
  assert.throws(()=>refused.decodePage({accepted:true,statusCode:200,body:f.bytes},frame),error=>error.code==='SheetsContractRefused'&&error.cause.kind==='CellError');
});

test('Sheets grid callbacks retain finite response and row bounds before delivery',()=>{
  const f=fixture();
  for(const change of [{maxRows:101},{maxRows:0},{maxCells:0},{maxRequestBytes:1}]){
    assert.throws(()=>prepareSheetsGridPages({...f.options,limits:{...limits,...change}},(fn,receiver,args)=>Reflect.apply(fn,receiver,args)));
  }
  const moon={sheetsGridRequestJson:()=>'{"body":"one"}',sheetsGridPageJson:()=>JSON.stringify({page:{rows:Array(4).fill({id:'one'}),excludedBlankRows:0}})};
  const p=prepareSheetsGridPages({...f.options,moon},(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
  assert.throws(()=>p.decodePage({accepted:true,statusCode:200,body:f.bytes},frame),{code:'SheetsReadRowLimit'});
});

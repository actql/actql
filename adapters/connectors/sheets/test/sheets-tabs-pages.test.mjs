import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareSheetsTabsPages} from '../site/sheets-tabs-pages.mjs';
const limits={maxResponseBytes:8192,maxNodes:512,maxDepth:16,maxRows:4,maxValueNodes:100,maxValueTextBytes:4096,
  maxRowsWireBytes:8192,maxRowsWireNodes:100,maxRowsWireDepth:8};
const frame={pageIndex:0,rowCount:0};

test('Sheets tab callbacks capture same codec receiver complete columns limits and original body',()=>{
  const page={},body=Buffer.from('same body'),seen=[];
  const moon={sheetsTabsColumnNames(){assert.equal(this,moon);return['id','title','index','row_count','column_count'];},
    sheetsProjectTabs(...args){assert.equal(this,moon);seen.push(args);return[page,undefined];},
    sheetsTabsRowCount(value){assert.equal(this,moon);assert.equal(value,page);return 1;},
    sheetsTabsRowsWire(value,names,...bounds){assert.equal(this,moon);assert.equal(value,page);
      assert.deepEqual(names,['id','title','index','row_count','column_count']);
      assert.deepEqual(bounds,[8192,100,8]);return['[{"id":"0","title":"one","index":"0","row_count":"1","column_count":"2"}]',undefined];}};
  // Explicit Result port below uses the existing runtime's successful Result
  // carrier only; actual compiler Result ABI is checked by the separate case.
  const originalProject=moon.sheetsProjectTabs,originalRows=moon.sheetsTabsRowsWire;
  const good=value=>({$tag:1,0:value});
  moon.sheetsProjectTabs=function(...args){return good(Reflect.apply(originalProject,this,args)[0]);};
  moon.sheetsTabsRowsWire=function(...args){return good(Reflect.apply(originalRows,this,args)[0]);};
  const selected={...limits};
  const callbacks=prepareSheetsTabsPages({moon,spreadsheetId:'book',names:['title'],limits:selected},(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
  moon.sheetsProjectTabs=()=>assert.fail('original method is retained');selected.maxRows=1;
  const request=callbacks.fetchPage(frame);assert.equal(request.method,'GET');assert.equal(request.path,'/v4/spreadsheets/book');
  assert.equal(Object.hasOwn(request,'body'),false);assert.match(request.query[0][1],/sheetType,gridProperties/);
  assert.equal(callbacks.decodePage({accepted:true,statusCode:200,body},frame).rowCount,1);
  assert.equal(seen[0][0],body);assert.equal(seen[0][1],'book');assert.equal(seen[0][5],4);
  const original=new Error('same failure');assert.equal(callbacks.onError(original).cause,original);
});

test('Sheets tab callbacks refuse invalid selection frames responses and limits before page decode',()=>{
  let decoded=0;
  const moon={sheetsTabsColumnNames:()=>['id'],sheetsProjectTabs(){decoded++;},sheetsTabsRowCount(){},sheetsTabsRowsWire(){}};
  const make=options=>prepareSheetsTabsPages({moon,spreadsheetId:'book',names:['id'],limits,...options},(fn,receiver,args)=>Reflect.apply(fn,receiver,args));
  assert.throws(()=>make({names:['foreign']}),{code:'InvalidSheetsTabsPages'});
  assert.throws(()=>make({limits:{...limits,maxRows:0}}),{code:'InvalidSheetsTabsPages'});
  const p=make();
  assert.throws(()=>p.fetchPage({pageIndex:1,rowCount:0}),{code:'InvalidSheetsTabsFrame'});
  assert.throws(()=>p.decodePage({accepted:false,statusCode:403},frame),{code:'SheetsTabsReadRejected'});
  assert.equal(decoded,0);
});

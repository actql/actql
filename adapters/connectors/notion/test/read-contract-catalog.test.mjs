import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const metadata=[16384,1024,20,8,8,128,128];
const bounds=[...metadata,256,16,4096,16,10000];
const dbWire='{"object":"database","id":"db","data_sources":[{"id":"s","name":"tasks"}]}';
const properties={
  amount:{id:'n%3Ax',name:'amount',type:'number',number:{format:'dollar'}},
  state:{id:'s',name:'state',type:'formula',formula:{expression:'arbitrary vendor expression'}},
  when:{id:'d',name:'when',type:'date',date:{}},
};
const contracts={
  'n%3Ax':[{column:'amount',projection:'value',contract:{type:'decimal',nullable:false,precision:20,scale:2}}],
  s:[{column:'state',projection:'value',contract:{type:'string',nullable:false,enum:['low','medium']}}],
  d:[{column:'when',projection:'start',contract:{type:'timestamp',nullable:false}}],
};
const declarationWire=JSON.stringify({id:'db',read_contracts:contracts});
const read=(wire=declarationWire,b=bounds)=>checked(provider.notionReadDatabaseDeclaration(Buffer.from(wire),...b));
const db=()=>checked(provider.notionProjectDatabase(Buffer.from(dbWire),...metadata));
const source=(database=db())=>checked(provider.notionProjectDataSource(database,0,Buffer.from(JSON.stringify({
  object:'data_source',id:'s',parent:{type:'database_id',database_id:'db'},properties,
})),...metadata));
const bind=(d,s,b=bounds)=>checked(provider.notionBindDataSourceReadContracts(d,s,...b));
const page=(s,amount='9007199254740993.25',state={type:'string',string:'low'},date={start:'2026-01-01T09:00:00.000+09:00',end:null,time_zone:null})=>{
  const row={object:'page',id:'p',parent:{type:'data_source_id',data_source_id:'s'},properties:{
    amount:{id:'n%3Ax',type:'number',number:'EXACT_TOKEN'},
    state:{id:'s',type:'formula',formula:state},when:{id:'d',type:'date',date},
  }};
  const wire=JSON.stringify({object:'list',type:'page_or_data_source',page_or_data_source:{},results:[row],has_more:false,next_cursor:null}).replace('"EXACT_TOKEN"',amount);
  return checked(provider.notionProjectQueryPage(s,Buffer.from(wire),...metadata,100,128));
};
const cell=(b,p,column,work=10000,output=128)=>checked(provider.notionPropertyReadCellJson(b,p,0,column,128,16,4096,work,output,32,8));
const refuses=fn=>assert.throws(fn,{code:'MoonBitHostFailure'});

test('actual checked Notion cells preserve original decimal lexeme enum and exact physical instant',()=>{
  const d=read(),s=source(),b=bind(d,s),p=page(s);
  assert.equal(cell(b,p,0),'"9007199254740993.25"');
  assert.equal(cell(b,p,1),'"low"');
  assert.equal(cell(b,p,2),'"2026-01-01T00:00:00.000Z"');
  const schema=checked(provider.notionDataSourceReadSchemaJson(b,4096,128,16));
  assert.match(schema,/"precision":20/u);
  assert.match(schema,/"enum":\["low","medium"\]/u);
  assert.equal(provider.notionDataSourceReadMatches(b,d,s),true);
  assert.equal(provider.notionDataSourceReadMatches(b,read(),s),false);
  assert.equal(provider.notionDataSourceReadMatches(b,d,source()),false);
  refuses(()=>cell(b,page(source()),0));
});

test('actual Notion scalar admission refuses rounded native relabels changed discriminants and dropped date ranges',()=>{
  const d=read(),s=source(),b=bind(d,s);
  for(const token of ['"9007199254740993.25"','9007199254740993.251','null','false'])refuses(()=>cell(b,page(s,token),0));
  refuses(()=>cell(b,page(s,'1',{type:'string',string:'high'}),1));
  refuses(()=>cell(b,page(s,'1',{type:'number',number:1}),1));
  for(const date of [
    {start:'2026-01-01T00:00:00.000-00:00',end:null,time_zone:null},
    {start:'2026-01-01T00:00:00.0001Z',end:null,time_zone:null},
    {start:'2026-01-01T00:00:00.000Z',end:'2026-01-02T00:00:00.000Z',time_zone:null},
    {start:'2026-01-01T00:00:00.000',end:null,time_zone:'Asia/Tokyo'},
  ])refuses(()=>cell(b,page(s,'1',{type:'string',string:'low'},date),2));
});

test('actual declaration keeps singleton selection explicit and checks unused complete contracts',()=>{
  const database=db(),d=read('"db"');
  assert.equal(checked(provider.notionReadSourceIndex(d,database)),0);
  const multiple=checked(provider.notionProjectDatabase(Buffer.from(dbWire.replace(']}',',{"id":"other","name":"tasks"}]}')),...metadata));
  refuses(()=>checked(provider.notionReadSourceIndex(d,multiple)));
  const explicit=read('{"id":"db","data_source_id":"other"}');
  assert.equal(checked(provider.notionReadSourceIndex(explicit,multiple)),1);
  for(const mutate of [
    x=>{x.read_contracts['n%3Ax'][0].contract={type:'number',nullable:false};},
    x=>{x.read_contracts.unknown=[{column:'unused',projection:'value',contract:{type:'nonsense'}}];},
    x=>{x.read_contracts['n%3Ax'][0].contract.precision=0;},
    x=>{x.data_source_id=null;},
  ]){
    const x=JSON.parse(declarationWire);mutate(x);
    refuses(()=>bind(read(JSON.stringify(x)),source()));
  }
});

test('actual scalar schema and cell output remain bounded and fail closed',()=>{
  const d=read(),s=source(),b=bind(d,s),p=page(s);
  refuses(()=>cell(b,p,0,1));
  refuses(()=>cell(b,p,0,10000,1));
  refuses(()=>checked(provider.notionPropertyReadCellJson(b,p,1,0,128,16,4096,10000,128,32,8)));
  refuses(()=>checked(provider.notionDataSourceReadSchemaJson(b,1,128,16)));
  refuses(()=>read(declarationWire,[...bounds.slice(0,-1),1]));
});

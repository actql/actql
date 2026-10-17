import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const limits=[8192,512,16,100,64,64,400,4096];
const wire=(results=[],has_more=false,next_cursor=null)=>JSON.stringify({object:'list',type:'user',user:{},results,has_more,next_cursor});
const project=(body,bounds=limits)=>checked(provider.notionProjectUserList(
  typeof body==='string'?Buffer.from(body):body,...bounds));
const rows=(page,names=provider.notionUserListColumnNames())=>JSON.parse(checked(
  provider.notionUserListRowsWire(page,names,8192,100,8)));
const metadata=page=>JSON.parse(checked(provider.notionUserListMetadataJson(page,4096,20,8)));

test('Notion actual Catalog exports keep original person bot and nullable partial values',()=>{
  const page=project(wire([
    {object:'user',id:'3c90c3cc-0d44-4b50-8888-8dd25736052a',type:'person',name:'観測 é',person:{email:'a@example.test'}},
    {object:'user',id:'9188c6a5-7381-452f-b3dc-d4865aa89bdf',type:'bot',name:null,bot:{},person:{email:'not a person'}},
  ],true,'original+/= é'));
  assert.deepEqual(rows(page),[
    {id:'3c90c3cc-0d44-4b50-8888-8dd25736052a',name:'観測 é',type:'person',email:'a@example.test'},
    {id:'9188c6a5-7381-452f-b3dc-d4865aa89bdf',name:null,type:'bot',email:null},
  ]);
  assert.deepEqual(metadata(page),{rowCount:2,nextCursor:'original+/= é'});
  assert.deepEqual(provider.notionUserListColumnNames(),['id','name','type','email']);
  const copy=provider.notionUserListIds(page);copy[0]='not original';
  assert.equal(provider.notionUserListIds(page)[0],'3c90c3cc-0d44-4b50-8888-8dd25736052a');
});

test('Notion actual absent permission-derived fields stay nullable without inferred person kind',()=>{
  const page=project(wire([{object:'user',id:'original',person:{email:'no kind proof'}}]));
  assert.deepEqual(rows(page,['email','type','name']),[{email:null,type:null,name:null}]);
  const person=project(wire([{object:'user',id:'original',type:'person',person:{}}]));
  assert.deepEqual(rows(person,['email']),[{email:null}]);
  for(const row of [{object:'user',id:'original',type:'person',person:{email:false}},
    {object:'user',id:'original',type:'person'},
    {object:'user',id:'original',type:'bot',bot:false}]){
    assert.throws(()=>project(wire([row])),{code:'MoonBitHostFailure'});
  }
});

test('Notion actual inconsistent continuation and errors cannot become an empty Source',()=>{
  for(const body of [wire([],true,null),wire([],false,'unused'),wire([],true,''),
    JSON.stringify({object:'error',status:403,code:'restricted_resource'}),
    '{"object":"list","type":"user","user":{},"results":[],"has_more":false}',
    '{"object":"list","type":"user","user":{},"results":[],"has_more":false,"next_cursor":null,"has_more":false}']){
    assert.throws(()=>project(body),{code:'MoonBitHostFailure'});
  }
  assert.deepEqual(metadata(project(wire())),{rowCount:0,nextCursor:null});
  assert.deepEqual(metadata(project(wire([],true,'next'))),{rowCount:0,nextCursor:'next'});
  assert.throws(()=>project(wire([{object:'user',id:'same'},{object:'user',id:'same'}])),{code:'MoonBitHostFailure'});
});

test('Notion actual raw cursor identity and selected-output limits reject without truncation',()=>{
  const body=wire([{object:'user',id:'original',type:'person',person:{email:'checked even before selection'}}]);
  for(const [index,value]of [[0,Buffer.byteLength(body)-1],[1,1],[3,0],[5,1],[6,3],[7,1]]){
    const bound=[...limits];bound[index]=value;
    assert.throws(()=>project(body,bound),{code:'MoonBitHostFailure'});
  }
  const bound=[...limits];bound[4]=1;
  assert.throws(()=>project(wire([],true,'é'),bound),{code:'MoonBitHostFailure'});
  assert.throws(()=>project(Buffer.from([0xff,0x80])),{code:'MoonBitHostFailure'});
  const page=project(body);
  assert.throws(()=>checked(provider.notionUserListMetadataJson(page,1,20,8)),{code:'MoonBitHostFailure'});
  assert.throws(()=>checked(provider.notionUserListRowsWire(page,['id'],1,100,8)),{code:'MoonBitHostFailure'});
  assert.throws(()=>checked(provider.notionUserListRowsWire(page,['id','id'],8192,100,8)),{code:'MoonBitHostFailure'});
  assert.throws(()=>checked(provider.notionUserListRowsWire(page,['grant'],8192,100,8)),{code:'MoonBitHostFailure'});
});

test('Notion actual schema preserves exact public columns and nullability independently of names',()=>{
  assert.deepEqual(JSON.parse(checked(provider.notionUserListSchemaWire(4096,100,8))),{
    email:{nullable:true,type:'string'},id:{nullable:false,type:'string'},
    name:{nullable:true,type:'string'},type:{nullable:true,type:'string'},
  });
  const columns=provider.notionUserListColumnNames();columns.push('grant');
  assert.deepEqual(provider.notionUserListColumnNames(),['id','name','type','email']);
  assert.throws(()=>checked(provider.notionUserListSchemaWire(1,100,8)),{code:'MoonBitHostFailure'});
});

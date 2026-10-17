import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/slack/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const bounds=[8192,512,16,10,64,100,4096];
const project=(value,limits=bounds)=>checked(provider.slackProjectUserList(
  typeof value==='string'?Buffer.from(value):value,...limits));
const rows=(page,names=provider.slackUserListColumnNames())=>JSON.parse(checked(
  provider.slackUserListRowsWire(page,names,8192,100,8)));

test('Slack actual Node exports preserve profile values identity and explicit cursor metadata',()=>{
  const page=project(JSON.stringify({ok:true,members:[{id:'U1',name:'original',real_name:'legacy',
    profile:{real_name:'観測 é',display_name:'',email:'a@example.test'},tz:'Asia/Tokyo',
    is_bot:false,deleted:true,unselected:{bounded:'vendor data'}}],
    response_metadata:{next_cursor:'a+/= é'}}));
  assert.deepEqual(rows(page),[{id:'U1',name:'original',real_name:'観測 é',display_name:'',
    email:'a@example.test',tz:'Asia/Tokyo',is_bot:false,deleted:true}]);
  assert.deepEqual(JSON.parse(provider.slackUserListMetadataJson(page)),{rowCount:1,nextCursor:'a+/= é'});
  assert.deepEqual(JSON.parse(provider.slackUserListRelationFactsWire()),{relation_keys:{candidate_keys:[['id']]}});
  const schema=JSON.parse(checked(provider.slackUserListSchemaWire(2048,100,8)));
  assert.deepEqual(schema.id,{type:'string',nullable:false});
  assert.deepEqual(schema.deleted,{type:'boolean',nullable:true});
  assert.equal(schema.email.nullable,true);
});

test('Slack actual Node nullable absence does not make a name scope or false boolean',()=>{
  const page=project('{"ok":true,"members":[{"id":"U1","real_name":"not profile"}]}');
  assert.deepEqual(rows(page,['real_name','email','is_bot','deleted']),[
    {real_name:null,email:null,is_bot:null,deleted:null}]);
  assert.deepEqual(JSON.parse(provider.slackUserListMetadataJson(page)),{rowCount:1,nextCursor:null});
  assert.throws(()=>checked(provider.slackUserListRowsWire(page,['id','id'],100,20,8)),
    {code:'MoonBitHostFailure'});
});

test('Slack actual Node errors malformed continuation and duplicate IDs refuse the whole page',()=>{
  for(const body of ['{"ok":false,"members":[]}','{"ok":true}',
    '{"ok":true,"members":[],"error":"ratelimited"}',
    '{"ok":true,"members":[],"response_metadata":null}',
    '{"ok":true,"members":[],"response_metadata":{"next_cursor":false}}',
    '{"ok":true,"members":[],"response_metadata":{"next_cursor":[]}}',
    '{"ok":true,"members":[{"id":"U1"},{"id":"U1"}]}',
    '{"ok":true,"members":[{"id":"U1","profile":{"email":true}}]}',
    '{"ok":true,"members":[],"ok":true}'])assert.throws(()=>project(body),{code:'MoonBitHostFailure'});
});

test('Slack actual Node byte cursor cell and output bounds never truncate or coerce',()=>{
  const body='{"ok":true,"members":[{"id":"U1"}]}';
  for(const [index,value] of [[0,1],[1,1],[5,7],[6,1]]){
    const limits=[...bounds];limits[index]=value;
    assert.throws(()=>project(body,limits),{code:'MoonBitHostFailure'});
  }
  const limits=[...bounds];limits[4]=1;
  assert.throws(()=>project('{"ok":true,"members":[],"response_metadata":{"next_cursor":"é"}}',limits),
    {code:'MoonBitHostFailure'});
  assert.throws(()=>project(Buffer.from([0xff,0x80])),{code:'MoonBitHostFailure'});
  const page=project(body);
  assert.throws(()=>checked(provider.slackUserListRowsWire(page,['id'],1,100,8)),{code:'MoonBitHostFailure'});
});

test('Slack actual Node documented null continuation is terminal without dropping member rows',()=>{
  const page=project('{"ok":true,"members":[{"id":"U1","name":"original"}],"response_metadata":{"next_cursor":null}}');
  assert.deepEqual(JSON.parse(provider.slackUserListMetadataJson(page)),{rowCount:1,nextCursor:null});
  assert.deepEqual(rows(page,['id','name']),[{id:'U1',name:'original'}]);
  for(const metadata of [{},{next_cursor:''},{next_cursor:null}]){
    const terminal=project(JSON.stringify({ok:true,members:[],response_metadata:metadata}));
    assert.deepEqual(JSON.parse(provider.slackUserListMetadataJson(terminal)),{rowCount:0,nextCursor:null});
  }
});
